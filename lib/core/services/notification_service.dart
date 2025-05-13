import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Service for handling notifications across platforms
class NotificationService {
  // Singleton instance
  static final NotificationService _instance = NotificationService._internal();

  // Factory constructor to return the singleton instance
  factory NotificationService() {
    return _instance;
  }

  // Private constructor
  NotificationService._internal();

  // Flutter Local Notifications Plugin instance
  final FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  bool _isInitialized = false;

  /// Initialize the notification service
  Future<void> initialize() async {
    if (_isInitialized) {
      developer.log('Notification service already initialized',
          name: 'NotificationService');
      return;
    }

    try {
      // Initialize only for Windows
      if (Platform.isWindows) {
        developer.log('Starting Windows notification service initialization',
            name: 'NotificationService');
        
        const WindowsInitializationSettings initializationSettingsWindows =
            WindowsInitializationSettings(
          appName: 'GalleVR',
          appUserModelId: '{6D809377-6AF0-444B-8957-A3773F02200E}\\GalleVR\\gallevr.exe',
          guid: '2fc54373-926e-545c-883a-dabcd36b229f',
        );

        developer.log('Windows initialization settings created',
            name: 'NotificationService');

        // Initialize the plugin with platform-specific settings
        final InitializationSettings initializationSettings =
            InitializationSettings(
          windows: initializationSettingsWindows,
        );

        developer.log('Calling initialize on flutter_local_notifications plugin',
            name: 'NotificationService');

        final bool? initResult = await _flutterLocalNotificationsPlugin.initialize(
          initializationSettings,
          onDidReceiveNotificationResponse: (NotificationResponse response) {
            developer.log('Notification tapped: ${response.payload}',
                name: 'NotificationService');
          },
        );

        developer.log('Initialize result: $initResult',
            name: 'NotificationService');

        _isInitialized = true;
        developer.log('Notification service initialized for Windows',
            name: 'NotificationService');
      }
    } catch (e) {
      developer.log('Error initializing notification service: $e',
          name: 'NotificationService');
    }
  }

  Future<void> showNotification(String title, String message) async {
    if (!_isInitialized && Platform.isWindows) {
      developer.log('Notification service not initialized, initializing now',
          name: 'NotificationService');
      await initialize();
    }

    if (!Platform.isWindows) {
      developer.log(
          'Notifications are only implemented for Windows in this service',
          name: 'NotificationService');
      return;
    }

    try {
      developer.log('Preparing to show notification: $title - $message',
          name: 'NotificationService');

      final int notificationId = DateTime.now().millisecondsSinceEpoch.remainder(100000);

      await _flutterLocalNotificationsPlugin.show(
        notificationId,
        title,
        message,
        NotificationDetails(
          windows: WindowsNotificationDetails(),
        ),
      );

      developer.log('Notification show method called successfully',
          name: 'NotificationService');
    } catch (e) {
      developer.log('Error showing notification: $e',
          name: 'NotificationService');
    }
  }

  Future<void> showMinimizedNotification() async {
    return showNotification(
      "GalleVR is running in the background",
      "The app is still running and monitoring for new photos. Click the tray icon to show the app.",
    );
  }

  Future<void> showStartMinimizedNotification() async {
    return showNotification(
      "GalleVR started minimized",
      "The app is running in the background. Click the tray icon to show the app.",
    );
  }
}
