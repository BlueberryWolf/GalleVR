import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:system_tray/system_tray.dart';
import 'package:win32_registry/win32_registry.dart';

import 'notification_service.dart';

/// Service for Windows-specific functionality
class WindowsService {
  static const String _startupRegistryPath =
      r'Software\Microsoft\Windows\CurrentVersion\Run';
  static const String _appRegistryKey = 'GalleVR';

  final SystemTray _systemTray = SystemTray();
  final AppWindow _appWindow = AppWindow();
  final NotificationService _notificationService = NotificationService();

  bool _isInitialized = false;
  bool _minimizeToTray = true;

  // Singleton instance
  static final WindowsService _instance = WindowsService._internal();

  // Factory constructor to return the singleton instance
  factory WindowsService() {
    return _instance;
  }

  // Private constructor
  WindowsService._internal();

  /// Initialize the Windows service
  Future<void> initialize({
    required bool minimizeToTray,
    String? appTitle,
  }) async {
    if (!Platform.isWindows || _isInitialized) return;

    try {
      _minimizeToTray = minimizeToTray;

      // Initialize notification service for Windows
      if (Platform.isWindows) {
        try {
          await _notificationService.initialize();
          developer.log('Notification service initialized', name: 'WindowsService');
        } catch (e) {
          developer.log('Error initializing notification service: $e', name: 'WindowsService');
        }
      }

      // Initialize system tray
      await _initSystemTray(appTitle ?? 'GalleVR');

      _isInitialized = true;
      developer.log('Windows service initialized', name: 'WindowsService');
    } catch (e) {
      developer.log('Error initializing Windows service: $e',
          name: 'WindowsService');
    }
  }

  /// Initialize the system tray
  Future<void> _initSystemTray(String appTitle) async {
    try {
      // Set up system tray icon and menu
      final iconPath = Platform.isWindows
          ? 'assets/images/app_icon.ico'
          : 'assets/images/app_icon.png';

      developer.log('Initializing system tray with icon: $iconPath', name: 'WindowsService');

      await _systemTray.initSystemTray(
        title: appTitle,
        iconPath: iconPath,
      );

      // Create system tray menu
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
            // Clean up before exiting
            developer.log('Exiting application from system tray', name: 'WindowsService');
            exitApplication();
          },
        ),
      ]);

      // Set system tray menu
      await _systemTray.setContextMenu(menu);

      // Set tooltip to indicate the app is running
      await _systemTray.setToolTip('GalleVR is running');

      // Handle system tray events
      _systemTray.registerSystemTrayEventHandler((eventName) {
        developer.log('System tray event: $eventName', name: 'WindowsService');
        if (eventName == kSystemTrayEventClick) {
          // Left click shows the app on Windows, context menu on macOS
          if (Platform.isWindows) {
            showWindow();
          } else {
            _systemTray.popUpContextMenu();
          }
        } else if (eventName == kSystemTrayEventRightClick) {
          // Right click shows the context menu on Windows, app on macOS
          if (Platform.isWindows) {
            _systemTray.popUpContextMenu();
          } else {
            showWindow();
          }
        } else if (eventName == kSystemTrayEventDoubleClick) {
          // Double click shows the app
          showWindow();
        }
      });

      developer.log('System tray initialized', name: 'WindowsService');
    } catch (e) {
      developer.log('Error initializing system tray: $e',
          name: 'WindowsService');
    }
  }

  /// Update the minimize to tray setting
  void updateMinimizeToTray(bool minimizeToTray) {
    _minimizeToTray = minimizeToTray;
  }

  /// Handle window close event
  /// Returns true if the app should be minimized to tray instead of closed
  Future<bool> handleWindowClose({bool forceExit = false}) async {
    if (!Platform.isWindows || !_isInitialized) return false;

    // exit pls
    if (forceExit) {
      developer.log('Force exiting application from handleWindowClose', name: 'WindowsService');
      await exitApplication();
      return false;
    }

    if (_minimizeToTray) {
      try {
        developer.log('Minimizing to system tray instead of closing', name: 'WindowsService');

        await hideWindow(showNotification: true);

        return true;
      } catch (e) {
        developer.log('Error minimizing to tray: $e', name: 'WindowsService');
        return false;
      }
    }

    return false;
  }

  /// Exit the application completely
  Future<void> exitApplication() async {
    developer.log('Exiting application', name: 'WindowsService');

    if (_isInitialized) {
      try {
        // Try to clean up system tray resources before exiting
        developer.log('Cleaning up system tray before exit', name: 'WindowsService');

        // Hide the window first
        _appWindow.hide();

        await _systemTray.setToolTip('');
        await _systemTray.setTitle('');

        final emptyMenu = Menu();
        await emptyMenu.buildFrom([]);
        await _systemTray.setContextMenu(emptyMenu);

        await Future.delayed(Duration(milliseconds: 100));

        developer.log('System tray cleanup completed', name: 'WindowsService');
      } catch (e) {
        developer.log('Error during system tray cleanup: $e', name: 'WindowsService');
      }
    }

    try {
      // Try to stop any foreground tasks that might be running
      developer.log('Stopping any foreground tasks', name: 'WindowsService');
      await FlutterForegroundTask.stopService();
    } catch (e) {
      developer.log('Error stopping foreground tasks: $e', name: 'WindowsService');
    }

    // Force exit the application using a more aggressive approach
    developer.log('Force terminating process', name: 'WindowsService');

    // Use exit code 0 for normal exit
    exit(0);
  }

  /// Check if the app is set to start with Windows
  Future<bool> isStartWithWindowsEnabled() async {
    if (!Platform.isWindows) return false;

    try {
      final key = Registry.openPath(
        RegistryHive.currentUser,
        path: _startupRegistryPath,
      );

      // Check if our app key exists in the startup registry
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
      developer.log('Error checking startup registry: $e',
          name: 'WindowsService');
      return false;
    }
  }

  /// Set whether the app should start with Windows
  Future<bool> setStartWithWindows(bool enabled) async {
    if (!Platform.isWindows) return false;

    try {
      final key = Registry.openPath(
        RegistryHive.currentUser,
        path: _startupRegistryPath,
        desiredAccessRights: AccessRights.allAccess,
      );

      if (enabled) {
        // Get the executable path
        final exePath = Platform.resolvedExecutable;

        // Add the --start-minimized flag to the startup command
        final startupCommand = '$exePath --start-minimized';

        // Add the app to startup registry with the start minimized flag
        key.createValue(RegistryValue.string(_appRegistryKey, startupCommand));
        developer.log('Added app to Windows startup with minimized flag', name: 'WindowsService');
      } else {
        // Remove the app from startup registry
        for (final value in key.values) {
          if (value.name == _appRegistryKey) {
            key.deleteValue(_appRegistryKey);
            developer.log('Removed app from Windows startup',
                name: 'WindowsService');
            break;
          }
        }
      }

      key.close();
      return true;
    } catch (e) {
      developer.log('Error setting startup registry: $e',
          name: 'WindowsService');
      return false;
    }
  }

  /// Show the application window
  Future<void> showWindow() async {
    if (!Platform.isWindows || !_isInitialized) return;

    try {
      developer.log('Showing application window', name: 'WindowsService');
      _appWindow.show();
    } catch (e) {
      developer.log('Error showing window: $e', name: 'WindowsService');
    }
  }

  /// Hide the application window
  Future<void> hideWindow({bool showNotification = false}) async {
    if (!Platform.isWindows || !_isInitialized) return;

    try {
      developer.log('Hiding application window', name: 'WindowsService');
      _appWindow.hide();

      // Update the tooltip to inform the user that the app is still running
      await _systemTray.setToolTip('GalleVR is running in the background');

      // Show a notification if requested
      if (showNotification) {
        await _showMinimizedNotification();
      }
    } catch (e) {
      developer.log('Error hiding window: $e', name: 'WindowsService');
    }
  }

  /// Show a notification that the app is minimized to tray
  Future<void> _showMinimizedNotification() async {
    if (!Platform.isWindows) {
      await _systemTray.setToolTip('GalleVR is running in the background');
      return;
    }

    await _notificationService.showMinimizedNotification();
    await _systemTray.setToolTip('GalleVR is running in the background');
  }

  /// Show a notification that the app started minimized
  Future<void> showStartMinimizedNotification() async {
    if (!Platform.isWindows) {
      await _systemTray.setToolTip('GalleVR is running in the background');
      return;
    }

    await _notificationService.showStartMinimizedNotification();
    await _systemTray.setToolTip('GalleVR is running in the background');
  }

  /// Dispose the Windows service
  void dispose() {
    if (!Platform.isWindows || !_isInitialized) return;

    try {
      developer.log('System tray will be cleaned up when app exits', name: 'WindowsService');
      developer.log('Windows service disposed', name: 'WindowsService');
    } catch (e) {
      developer.log('Error disposing Windows service: $e',
          name: 'WindowsService');
    }
  }
}



