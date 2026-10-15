import 'dart:async';
import '../image/image_cache_service.dart';
import 'dart:developer' as developer;
import 'dart:ffi';
import 'dart:io';

import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:system_tray/system_tray.dart';
import 'package:win32_registry/win32_registry.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/foundation.dart';

import 'notification_service.dart';

class WindowsService {
  static const String _startupRegistryPath =
      r'Software\Microsoft\Windows\CurrentVersion\Run';
  static const String _appRegistryKey = 'GalleVR';

  static const String _windowChannelName = 'gallevr/window';

  final SystemTray _systemTray = SystemTray();
  final AppWindow _appWindow = AppWindow();
  final NotificationService _notificationService = NotificationService();
  final MethodChannel _windowChannel = const MethodChannel(_windowChannelName);

  bool _isInitialized = false;
  bool _minimizeToTray = true;

  /// True while the window is hidden, so the widget tree can be torn down.
  final ValueNotifier<bool> isHidden = ValueNotifier<bool>(false);

  /// Called on close when minimize to tray is off.
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
  }) async {
    if (!Platform.isWindows || _isInitialized) return;

    try {
      _minimizeToTray = minimizeToTray;

      if (Platform.isWindows) {
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
      }

      await _initSystemTray(appTitle ?? 'GalleVR');

      await _windowChannel.invokeMethod('updateMinimizeToTray', minimizeToTray);

      _isInitialized = true;
      developer.log('Windows service initialized', name: 'WindowsService');
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

      await _systemTray.setToolTip('GalleVR is running');

      _systemTray.registerSystemTrayEventHandler((eventName) {
        developer.log('System tray event: $eventName', name: 'WindowsService');
        if (eventName == kSystemTrayEventClick) {
          // Left click shows the app on Windows, the context menu on macOS.
          if (Platform.isWindows) {
            showWindow();
          } else {
            _systemTray.popUpContextMenu();
          }
        } else if (eventName == kSystemTrayEventRightClick) {
          // Right click shows the context menu on Windows, the app on macOS.
          if (Platform.isWindows) {
            _systemTray.popUpContextMenu();
          } else {
            showWindow();
          }
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

  /// Returns true when the window was minimized to tray instead of closed.
  Future<bool> handleWindowClose({bool forceExit = false}) async {
    if (!Platform.isWindows || !_isInitialized) return false;

    // exit pls
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
        developer.log(
          'Cleaning up system tray before exit',
          name: 'WindowsService',
        );

        _appWindow.hide();

        await _systemTray
            .setToolTip('')
            .timeout(const Duration(milliseconds: 100), onTimeout: () => false);
        await _systemTray
            .setTitle('')
            .timeout(const Duration(milliseconds: 100), onTimeout: () => false);

        final emptyMenu = Menu();
        await emptyMenu
            .buildFrom([])
            .timeout(const Duration(milliseconds: 100), onTimeout: () => false);
        await _systemTray
            .setContextMenu(emptyMenu)
            .timeout(const Duration(milliseconds: 100), onTimeout: () => false);

        await Future.delayed(const Duration(milliseconds: 50));

        developer.log('System tray cleanup completed', name: 'WindowsService');
      } catch (e) {
        developer.log(
          'Error during system tray cleanup: $e',
          name: 'WindowsService',
        );
      }
    }

    try {
      if (Platform.isAndroid || Platform.isIOS) {
        developer.log('Stopping any foreground tasks', name: 'WindowsService');
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
    if (!Platform.isWindows || !_isInitialized) return;

    try {
      developer.log('Restoring application window...', name: 'WindowsService');

      ImageCacheService.applyMemoryLimits();

      isHidden.value = false;

      await Future.delayed(const Duration(milliseconds: 50));

      _appWindow.show();
    } catch (e) {
      developer.log('Error showing window: $e', name: 'WindowsService');
    }
  }

  Future<void> hideWindow({bool showNotification = false}) async {
    if (!Platform.isWindows || !_isInitialized) return;

    try {
      developer.log('Hiding application window', name: 'WindowsService');
      isHidden.value = true;

      await Future.delayed(const Duration(milliseconds: 100));

      _appWindow.hide();

      await trimMemory();

      await _systemTray.setToolTip('GalleVR is running in the background');

      if (showNotification) {
        await _showMinimizedNotification();
      }
    } catch (e) {
      developer.log('Error hiding window: $e', name: 'WindowsService');
    }
  }

  /// Releases cached memory while the window is hidden.
  Future<void> trimMemory() async {
    if (!Platform.isWindows) return;

    try {
      PaintingBinding.instance.imageCache.maximumSize = 0;
      PaintingBinding.instance.imageCache.maximumSizeBytes = 0;
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();

      PaintingBinding.instance.handleMemoryPressure();

      developer.log(
        'Purged UI image caches and signaled low-memory pressure.',
        name: 'WindowsService',
      );
    } catch (e) {
      developer.log('Failed to purge caches: $e', name: 'WindowsService');
    }

    await Future.delayed(const Duration(milliseconds: 500));

    try {
      _emptyWorkingSet();
      developer.log(
        'Successfully emptied working set.',
        name: 'WindowsService',
      );
    } catch (e) {
      developer.log(
        'EmptyWorkingSet invocation failed: $e',
        name: 'WindowsService',
      );
    }
  }

  Future<void> _showMinimizedNotification() async {
    if (!Platform.isWindows) {
      await _systemTray.setToolTip('GalleVR is running in the background');
      return;
    }

    await _notificationService.showMinimizedNotification();
    await _systemTray.setToolTip('GalleVR is running in the background');
  }

  Future<void> showStartMinimizedNotification() async {
    if (!Platform.isWindows) {
      await _systemTray.setToolTip('GalleVR is running in the background');
      return;
    }

    await _notificationService.showStartMinimizedNotification();
    await _systemTray.setToolTip('GalleVR is running in the background');
  }

  void dispose() {
    if (!Platform.isWindows || !_isInitialized) return;

    try {
      developer.log(
        'System tray will be cleaned up when app exits',
        name: 'WindowsService',
      );
      developer.log('Windows service disposed', name: 'WindowsService');
    } catch (e) {
      developer.log(
        'Error disposing Windows service: $e',
        name: 'WindowsService',
      );
    }
  }

  void _setupWindowEventChannel() {
    _windowChannel.setMethodCallHandler((call) async {
      developer.log(
        'Received window event: ${call.method}',
        name: 'WindowsService',
      );

      if (call.method == 'onWindowHidden' && !isHidden.value) {
        developer.log(
          'Executing central hideWindow pipeline from native intercept...',
          name: 'WindowsService',
        );
        await hideWindow(showNotification: true);
      }

      if (call.method == 'onWindowCloseRequest') {
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
      }

      if (call.method == 'onWindowMinimized' && !isHidden.value) {
        developer.log(
          'Window minimized: Virtualizing UI tree and executing memory purge...',
          name: 'WindowsService',
        );
        isHidden.value = true;
        await trimMemory();
      }

      if (call.method == 'onWindowRestored' && isHidden.value) {
        developer.log(
          'Window restored: Restoring UI tree and re-establishing image caches...',
          name: 'WindowsService',
        );
        ImageCacheService.applyMemoryLimits();
        isHidden.value = false;
      }

      return null;
    });

    developer.log(
      'Window event channel listener bound successfully',
      name: 'WindowsService',
    );
  }

  void _emptyWorkingSet() {
    final psapi = DynamicLibrary.open('psapi.dll');
    final emptyWorkingSet = psapi
        .lookupFunction<Int32 Function(IntPtr), int Function(int)>(
          'EmptyWorkingSet',
        );
    emptyWorkingSet(-1);
  }
}
