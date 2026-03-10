import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:system_tray/system_tray.dart';

import 'notification_service.dart';

/// Service for Linux-specific functionality
class LinuxService {
  final SystemTray _systemTray = SystemTray();
  final AppWindow _appWindow = AppWindow();
  final NotificationService _notificationService = NotificationService();

  bool _isInitialized = false;
  bool _minimizeToTray = true;

  // Singleton instance
  static final LinuxService _instance = LinuxService._internal();

  factory LinuxService() {
    return _instance;
  }

  LinuxService._internal();

  /// Initialize the Linux service
  Future<void> initialize({
    required bool minimizeToTray,
    String? appTitle,
  }) async {
    if (!Platform.isLinux || _isInitialized) return;

    try {
      _minimizeToTray = minimizeToTray;

      // Initialize notification service
      try {
        await _notificationService.initialize();
        developer.log('Notification service initialized', name: 'LinuxService');
      } catch (e) {
        developer.log('Error initializing notification service: $e', name: 'LinuxService');
      }

      // Initialize system tray
      await _initSystemTray(appTitle ?? 'GalleVR');

      _isInitialized = true;
      developer.log('Linux service initialized', name: 'LinuxService');
    } catch (e) {
      developer.log('Error initializing Linux service: $e', name: 'LinuxService');
    }
  }

  Future<void> _initSystemTray(String appTitle) async {
    try {
      final iconPath = 'assets/images/app_icon_32.png';

      developer.log('Initializing system tray with icon: $iconPath', name: 'LinuxService');

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
            developer.log('Exiting application from system tray', name: 'LinuxService');
            exitApplication();
          },
        ),
      ]);

      await _systemTray.setContextMenu(menu);

      // Handle system tray events
      _systemTray.registerSystemTrayEventHandler((eventName) {
        developer.log('System tray event: $eventName', name: 'LinuxService');
        if (eventName == kSystemTrayEventClick) {
          _systemTray.popUpContextMenu();
        } else if (eventName == kSystemTrayEventRightClick) {
          _systemTray.popUpContextMenu();
        } else if (eventName == kSystemTrayEventDoubleClick) {
          showWindow();
        }
      });

      developer.log('System tray initialized', name: 'LinuxService');
    } catch (e) {
      developer.log('Error initializing system tray: $e', name: 'LinuxService');
    }
  }

  void updateMinimizeToTray(bool minimizeToTray) {
    _minimizeToTray = minimizeToTray;
  }

  Future<bool> handleWindowClose({bool forceExit = false}) async {
    if (!Platform.isLinux || !_isInitialized) return false;

    if (forceExit) {
      await exitApplication();
      return false;
    }

    if (_minimizeToTray) {
      try {
        await hideWindow(showNotification: true);
        return true;
      } catch (e) {
        developer.log('Error minimizing to tray: $e', name: 'LinuxService');
        return false;
      }
    }

    return false;
  }

  Future<void> exitApplication() async {
    developer.log('Exiting application', name: 'LinuxService');
    try {
      await FlutterForegroundTask.stopService();
    } catch (e) {
      developer.log('Error stopping foreground tasks: $e', name: 'LinuxService');
    }
    exit(0);
  }

  Future<void> showWindow() async {
    if (!Platform.isLinux || !_isInitialized) return;
    _appWindow.show();
  }

  Future<void> hideWindow({bool showNotification = false}) async {
    if (!Platform.isLinux || !_isInitialized) return;
    _appWindow.hide();
    if (showNotification) {
      await _notificationService.showMinimizedNotification();
    }
  }

  Future<void> showStartMinimizedNotification() async {
    await _notificationService.showStartMinimizedNotification();
  }

  void dispose() {}
}