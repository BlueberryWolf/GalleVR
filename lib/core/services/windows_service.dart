import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:system_tray/system_tray.dart';
import 'package:win32_registry/win32_registry.dart';

import '../../daemon/daemon_ipc.dart';
import '../../data/database/app_database.dart';
import 'memory_manager.dart';
import 'notification_service.dart';

class WindowsService {
  static const String _startupRegistryPath =
      r'Software\Microsoft\Windows\CurrentVersion\Run';
  static const String _appRegistryKey = 'GalleVR';

  static const String _windowChannelName = 'gallevr/window';

  final SystemTray _systemTray = SystemTray();
  final NotificationService _notificationService = NotificationService();
  final MethodChannel _windowChannel = const MethodChannel(_windowChannelName);

  bool _isInitialized = false;
  bool _minimizeToTray = true;
  bool _daemonManaged = false;

  final ValueNotifier<bool> isHidden = ValueNotifier<bool>(false);

  Future<void> Function()? onCloseRequest;

  static final WindowsService _instance = WindowsService._internal();

  factory WindowsService() {
    return _instance;
  }

  WindowsService._internal() {
    _setupWindowEventChannel();
  }

  Future<void> initialize({
    required bool minimizeToTray,
    String? appTitle,
    bool daemonManaged = false,
  }) async {
    if (!Platform.isWindows || _isInitialized) return;

    try {
      _minimizeToTray = minimizeToTray;
      _daemonManaged = daemonManaged;

      if (!_daemonManaged) {
        try {
          await _notificationService.initialize();
          developer.log(
            'Notification service initialized',
            name: 'WindowsService',
          );
        } catch (e) {
          developer.log(
            'Error initializing notification service: $e',
            name: 'WindowsService',
          );
        }

        await _initSystemTray(appTitle ?? 'GalleVR');
      } else {
        await _windowChannel.invokeMethod('setDaemonMode', true);
      }

      await _windowChannel.invokeMethod('updateMinimizeToTray', minimizeToTray);

      _isInitialized = true;
      developer.log(
        'Windows service initialized (daemonManaged=$_daemonManaged)',
        name: 'WindowsService',
      );
    } catch (e) {
      developer.log(
        'Error initializing Windows service: $e',
        name: 'WindowsService',
      );
    }
  }

  Future<void> _initSystemTray(String appTitle) async {
    try {
      final iconPath =
          Platform.isWindows
              ? 'assets/images/app_icon.ico'
              : 'assets/images/app_icon.png';

      developer.log(
        'Initializing system tray with icon: $iconPath',
        name: 'WindowsService',
      );

      await _systemTray.initSystemTray(title: appTitle, iconPath: iconPath);

      final menu = Menu();
      await menu.buildFrom([
        MenuItemLabel(
          label: 'Open GalleVR',
          onClicked: (menuItem) => showWindow(),
        ),
        MenuItemLabel(
          label: 'Hide GalleVR',
          onClicked: (menuItem) => hideWindow(showNotification: true),
        ),
        MenuSeparator(),
        MenuItemLabel(
          label: 'Exit',
          onClicked: (menuItem) {
            developer.log(
              'Exiting application from system tray',
              name: 'WindowsService',
            );
            exitApplication();
          },
        ),
      ]);

      await _systemTray.setContextMenu(menu);

      await _systemTray.setToolTip(
        isHidden.value
            ? 'GalleVR is running in the background'
            : 'GalleVR is running',
      );

      _systemTray.registerSystemTrayEventHandler((eventName) {
        developer.log('System tray event: $eventName', name: 'WindowsService');
        if (eventName == kSystemTrayEventClick) {
          showWindow();
        } else if (eventName == kSystemTrayEventRightClick) {
          _systemTray.popUpContextMenu();
        } else if (eventName == kSystemTrayEventDoubleClick) {
          showWindow();
        }
      });

      developer.log('System tray initialized', name: 'WindowsService');
    } catch (e) {
      developer.log(
        'Error initializing system tray: $e',
        name: 'WindowsService',
      );
    }
  }

  void updateMinimizeToTray(bool minimizeToTray) {
    _minimizeToTray = minimizeToTray;
    _windowChannel.invokeMethod('updateMinimizeToTray', minimizeToTray);
  }

  Future<bool> handleWindowClose({bool forceExit = false}) async {
    if (!Platform.isWindows || !_isInitialized) return false;

    if (forceExit) {
      developer.log(
        'Force exiting application from handleWindowClose',
        name: 'WindowsService',
      );
      await exitApplication();
      return false;
    }

    if (_minimizeToTray) {
      try {
        developer.log(
          'Minimizing to system tray instead of closing',
          name: 'WindowsService',
        );

        await hideWindow(showNotification: true);

        return true;
      } catch (e) {
        developer.log('Error minimizing to tray: $e', name: 'WindowsService');
        return false;
      }
    }

    return false;
  }

  Future<void> exitApplication() async {
    developer.log('Exiting application', name: 'WindowsService');

    try {
      await _windowChannel
          .invokeMethod('savePlacement')
          .timeout(const Duration(milliseconds: 200));
    } catch (e) {
      developer.log(
        'Error saving window placement: $e',
        name: 'WindowsService',
      );
    }

    if (_isInitialized) {
      try {
        await _windowChannel
            .invokeMethod('hideWindow')
            .timeout(const Duration(milliseconds: 100));

        if (_daemonManaged) {
          await DaemonClient().shutdownDaemon();
        } else {
          developer.log(
            'Cleaning up system tray before exit',
            name: 'WindowsService',
          );
          await _systemTray
              .destroy()
              .timeout(const Duration(milliseconds: 150), onTimeout: () => null);
          developer.log('System tray cleanup completed', name: 'WindowsService');
        }
      } catch (e) {
        developer.log(
          'Error during shutdown cleanup: $e',
          name: 'WindowsService',
        );
      }
    }

    try {
      await AppDatabase().close();
    } catch (_) {}

    try {
      if (Platform.isAndroid || Platform.isIOS) {
        await FlutterForegroundTask.stopService().timeout(
          const Duration(milliseconds: 100),
        );
      }
    } catch (e) {
      developer.log(
        'Error stopping foreground tasks: $e',
        name: 'WindowsService',
      );
    }

    developer.log('Force terminating process', name: 'WindowsService');

    exit(0);
  }

  Future<void> exitUiOnly() async {
    try {
      await _windowChannel
          .invokeMethod('savePlacement')
          .timeout(const Duration(milliseconds: 150));
    } catch (_) {}
    try {
      await AppDatabase().close();
    } catch (_) {}
    DaemonClient().disconnect();
    exit(0);
  }

  Future<bool> isStartWithWindowsEnabled() async {
    if (!Platform.isWindows) return false;

    try {
      final key = Registry.openPath(
        RegistryHive.currentUser,
        path: _startupRegistryPath,
      );

      bool exists = false;
      for (final value in key.values) {
        if (value.name == _appRegistryKey) {
          exists = true;
          break;
        }
      }

      key.close();
      return exists;
    } catch (e) {
      developer.log(
        'Error checking startup registry: $e',
        name: 'WindowsService',
      );
      return false;
    }
  }

  Future<bool> setStartWithWindows(bool enabled) async {
    if (!Platform.isWindows) return false;

    try {
      final key = Registry.openPath(
        RegistryHive.currentUser,
        path: _startupRegistryPath,
        desiredAccessRights: AccessRights.allAccess,
      );

      if (enabled) {
        final exePath = Platform.resolvedExecutable;

        final startupCommand = '$exePath --start-minimized';

        key.createValue(RegistryValue.string(_appRegistryKey, startupCommand));
        developer.log(
          'Added app to Windows startup with minimized flag',
          name: 'WindowsService',
        );
      } else {
        for (final value in key.values) {
          if (value.name == _appRegistryKey) {
            key.deleteValue(_appRegistryKey);
            developer.log(
              'Removed app from Windows startup',
              name: 'WindowsService',
            );
            break;
          }
        }
      }

      key.close();
      return true;
    } catch (e) {
      developer.log(
        'Error setting startup registry: $e',
        name: 'WindowsService',
      );
      return false;
    }
  }

  Future<void> showWindow() async {
    if (!Platform.isWindows) return;

    try {
      developer.log('Restoring application window...', name: 'WindowsService');

      MemoryManager.restoreUiResources();
      isHidden.value = false;

      await _windowChannel.invokeMethod('showWindow');
      if (_isInitialized && !_daemonManaged) {
        await _systemTray.setToolTip('GalleVR is running');
      }
    } catch (e) {
      developer.log('Error showing window: $e', name: 'WindowsService');
    }
  }

  Future<void> hideWindow({
    bool showNotification = false,
    bool alreadyHiddenNatively = false,
  }) async {
    if (!Platform.isWindows) return;

    try {
      developer.log('Hiding application window', name: 'WindowsService');
      isHidden.value = true;

      if (_daemonManaged && DaemonClient().isConnected) {
        if (!alreadyHiddenNatively) {
          try {
            await _windowChannel
                .invokeMethod('savePlacement')
                .timeout(const Duration(milliseconds: 150));
          } catch (_) {}
        }
        if (showNotification) {
          await DaemonClient().showTrayBalloon(
            'GalleVR Minimized',
            'GalleVR is running in the background. Click the tray icon to reopen.',
          );
        }
        await AppDatabase().close();
        DaemonClient().disconnect();
        exit(0);
      }

      if (!alreadyHiddenNatively) {
        await _windowChannel.invokeMethod('hideWindow');
      }

      await trimMemory();

      if (_isInitialized && !_daemonManaged) {
        await _systemTray.setToolTip('GalleVR is running in the background');
      }

      if (showNotification) {
        await _showMinimizedNotification();
      }
    } catch (e) {
      developer.log('Error hiding window: $e', name: 'WindowsService');
    }
  }

  Future<void> trimMemory() async {
    if (!Platform.isWindows) return;

    await MemoryManager.purgeUiResources();

    try {
      await _windowChannel.invokeMethod('trimMemory');
    } catch (e) {
      developer.log('Native memory trim failed: $e', name: 'WindowsService');
    }
  }

  Future<void> _showMinimizedNotification() async {
    await _notificationService.showMinimizedNotification();
    if (_isInitialized) {
      await _systemTray.setToolTip('GalleVR is running in the background');
    }
  }

  Future<void> showStartMinimizedNotification() async {
    await _notificationService.showStartMinimizedNotification();
    if (_isInitialized) {
      await _systemTray.setToolTip('GalleVR is running in the background');
    }
  }

  void dispose() {
    if (!Platform.isWindows || !_isInitialized) return;
    developer.log('Windows service disposed', name: 'WindowsService');
  }

  void _setupWindowEventChannel() {
    _windowChannel.setMethodCallHandler((call) async {
      developer.log(
        'Received window event: ${call.method}',
        name: 'WindowsService',
      );

      if (call.method == 'onWindowHidden') {
        await hideWindow(
          showNotification: true,
          alreadyHiddenNatively: true,
        );
      } else if (call.method == 'onWindowCloseRequest') {
        try {
          if (onCloseRequest != null) {
            await onCloseRequest!().timeout(const Duration(milliseconds: 300));
          }
        } catch (e) {
          developer.log(
            'Error during close request cleanup: $e',
            name: 'WindowsService',
          );
        } finally {
          await exitApplication();
        }
      } else if (call.method == 'onWindowMinimized') {
        isHidden.value = true;
        await trimMemory();
      } else if (call.method == 'onWindowRestored') {
        MemoryManager.restoreUiResources();
        isHidden.value = false;
        if (_isInitialized && !_daemonManaged) {
          _systemTray.setToolTip('GalleVR is running');
        }
      }

      return null;
    });

    developer.log(
      'Window event channel listener bound successfully',
      name: 'WindowsService',
    );
  }
}
