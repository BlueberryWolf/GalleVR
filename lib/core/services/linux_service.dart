import 'dart:async';
import 'dart:developer' as developer;
import 'dart:ffi';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:system_tray/system_tray.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/foundation.dart';

import 'notification_service.dart';

/// Service for Linux-specific functionality
class LinuxService {
  static const String _windowChannelName = 'gallevr/window';
  final MethodChannel _windowChannel = const MethodChannel(_windowChannelName);

  final SystemTray _systemTray = SystemTray();
  final AppWindow _appWindow = AppWindow();
  final NotificationService _notificationService = NotificationService();

  bool _isInitialized = false;
  bool _minimizeToTray = true;

  // State broadcaster indicating if the UI window is hidden
  final ValueNotifier<bool> isHidden = ValueNotifier<bool>(false);

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
        developer.log(
          'Error initializing notification service: $e',
          name: 'LinuxService',
        );
      }

      // Initialize system tray
      await _initSystemTray(appTitle ?? 'GalleVR');

      // Set up window event channel handler
      _setupWindowEventChannel();

      _isInitialized = true;
      developer.log('Linux service initialized', name: 'LinuxService');
    } catch (e) {
      developer.log(
        'Error initializing Linux service: $e',
        name: 'LinuxService',
      );
    }
  }

  Future<void> _initSystemTray(String appTitle) async {
    try {
      final iconPath = 'assets/images/app_icon_32.png';

      developer.log(
        'Initializing system tray with icon: $iconPath',
        name: 'LinuxService',
      );

      await _systemTray.initSystemTray(title: appTitle, iconPath: iconPath);

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
            developer.log(
              'Exiting application from system tray',
              name: 'LinuxService',
            );
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
      developer.log(
        'Error stopping foreground tasks: $e',
        name: 'LinuxService',
      );
    }
    exit(0);
  }

  Future<void> showWindow() async {
    if (!Platform.isLinux || !_isInitialized) return;
    _appWindow.show();
    isHidden.value = false;

    PaintingBinding.instance.imageCache.maximumSize = 1000;
    PaintingBinding.instance.imageCache.maximumSizeBytes = 100 << 20; // 100 MB
  }

  Future<void> hideWindow({bool showNotification = false}) async {
    if (!Platform.isLinux || !_isInitialized) return;

    isHidden.value = true;
    await Future.delayed(const Duration(milliseconds: 100));

    _appWindow.hide();

    try {
      PaintingBinding.instance.imageCache.maximumSize = 0;
      PaintingBinding.instance.imageCache.maximumSizeBytes = 0;
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
      PaintingBinding.instance.handleMemoryPressure();
      developer.log(
        'Purged UI image cache and triggered low-memory reclamation',
        name: 'LinuxService',
      );
    } catch (memErr) {
      developer.log('Error purging memory: $memErr', name: 'LinuxService');
    }

    try {
      _trimHeap();
    } catch (trimErr) {
      developer.log('Heap trim skipped: $trimErr', name: 'LinuxService');
    }

    if (showNotification) {
      await _notificationService.showMinimizedNotification();
    }
  }

  Future<void> showStartMinimizedNotification() async {
    await _notificationService.showStartMinimizedNotification();
  }

  void dispose() {}

  void _setupWindowEventChannel() {
    _windowChannel.setMethodCallHandler((call) async {
      developer.log(
        'Received window event: ${call.method}',
        name: 'LinuxService',
      );

      if (call.method == 'onWindowHidden' && !isHidden.value) {
        developer.log(
          'Executing central hideWindow pipeline from native intercept...',
          name: 'LinuxService',
        );
        await hideWindow(showNotification: true);
      }

      if (call.method == 'onWindowMinimized' && !isHidden.value) {
        developer.log(
          'Window minimized: Virtualizing UI tree and reclaiming memory...',
          name: 'LinuxService',
        );
        isHidden.value = true;

        try {
          PaintingBinding.instance.imageCache.maximumSize = 0;
          PaintingBinding.instance.imageCache.maximumSizeBytes = 0;
          PaintingBinding.instance.imageCache.clear();
          PaintingBinding.instance.imageCache.clearLiveImages();
          PaintingBinding.instance.handleMemoryPressure();
        } catch (e) {
          developer.log('Error purging memory: $e', name: 'LinuxService');
        }

        try {
          _trimHeap();
          developer.log(
            'Successfully trimmed Linux heap.',
            name: 'LinuxService',
          );
        } catch (e) {
          developer.log('Heap trim skipped: $e', name: 'LinuxService');
        }
      }

      if (call.method == 'onWindowRestored' && isHidden.value) {
        developer.log(
          'Window restored: Restoring UI tree...',
          name: 'LinuxService',
        );
        PaintingBinding.instance.imageCache.maximumSize = 1000;
        PaintingBinding.instance.imageCache.maximumSizeBytes =
            100 << 20; // 100 MB
        isHidden.value = false;
      }

      return null;
    });

    developer.log(
      'Window event channel listener bound successfully',
      name: 'LinuxService',
    );
  }

  void _trimHeap() {
    final libc = DynamicLibrary.open('libc.so.6');
    final mallocTrim = libc
        .lookupFunction<Int32 Function(IntPtr), int Function(int)>(
          'malloc_trim',
        );
    mallocTrim(0);
  }
}
