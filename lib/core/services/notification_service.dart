import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:url_launcher/url_launcher.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();

  factory NotificationService() {
    return _instance;
  }

  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  bool _isInitialized = false;

  static const String _githubReleasesUrl =
      'https://github.com/BlueberryWolf/GalleVR/releases';

  Future<void> initialize() async {
    if (_isInitialized) {
      developer.log(
        'Notification service already initialized',
        name: 'NotificationService',
      );
      return;
    }

    try {
      if (Platform.isWindows) {
        developer.log(
          'Starting Windows notification service initialization',
          name: 'NotificationService',
        );

        const WindowsInitializationSettings
        initializationSettingsWindows = WindowsInitializationSettings(
          appName: 'GalleVR',
          appUserModelId:
              '{6D809377-6AF0-444B-8957-A3773F02200E}\\GalleVR\\gallevr.exe',
          guid: '2fc54373-926e-545c-883a-dabcd36b229f',
        );

        developer.log(
          'Windows initialization settings created',
          name: 'NotificationService',
        );

        final InitializationSettings initializationSettings =
            InitializationSettings(windows: initializationSettingsWindows);

        developer.log(
          'Calling initialize on flutter_local_notifications plugin',
          name: 'NotificationService',
        );

        final bool? initResult = await _flutterLocalNotificationsPlugin
            .initialize(
              initializationSettings,
              onDidReceiveNotificationResponse: (
                NotificationResponse response,
              ) async {
                developer.log(
                  'Notification tapped: ${response.payload}',
                  name: 'NotificationService',
                );

                if (response.payload == 'update') {
                  await openReleasesPage();
                }
              },
            );

        developer.log(
          'Initialize result: $initResult',
          name: 'NotificationService',
        );

        _isInitialized = true;
        developer.log(
          'Notification service initialized for Windows',
          name: 'NotificationService',
        );
      } else if (Platform.isAndroid) {
        developer.log(
          'Starting Android notification service initialization',
          name: 'NotificationService',
        );

        const AndroidInitializationSettings initializationSettingsAndroid =
            AndroidInitializationSettings('@mipmap/ic_launcher');

        final InitializationSettings initializationSettings =
            InitializationSettings(android: initializationSettingsAndroid);

        final bool? initResult = await _flutterLocalNotificationsPlugin
            .initialize(
              initializationSettings,
              onDidReceiveNotificationResponse: (
                NotificationResponse response,
              ) async {
                developer.log(
                  'Notification tapped: ${response.payload}',
                  name: 'NotificationService',
                );

                if (response.payload == 'update') {
                  await openReleasesPage();
                }
              },
            );

        developer.log(
          'Initialize result: $initResult',
          name: 'NotificationService',
        );

        _isInitialized = true;
        developer.log(
          'Notification service initialized for Android',
          name: 'NotificationService',
        );
      }
    } catch (e) {
      developer.log(
        'Error initializing notification service: $e',
        name: 'NotificationService',
      );
    }
  }

  Future<void> openReleasesPage() async {
    try {
      developer.log(
        'Opening releases page: $_githubReleasesUrl',
        name: 'NotificationService',
      );

      final Uri url = Uri.parse(_githubReleasesUrl);

      final bool launched = await launchUrl(
        url,
        mode: LaunchMode.externalApplication,
        webOnlyWindowName: '_blank',
      );

      developer.log(
        'URL launch result: $launched',
        name: 'NotificationService',
      );
    } catch (e) {
      developer.log(
        'Error opening releases page: $e',
        name: 'NotificationService',
      );
    }
  }

  Future<void> showNotification(String title, String message) async {
    if (!_isInitialized) {
      if (Platform.isWindows || Platform.isAndroid) {
        developer.log(
          'Notification service not initialized, initializing now',
          name: 'NotificationService',
        );
        await initialize();
      } else {
        developer.log(
          'Notifications not supported on this platform',
          name: 'NotificationService',
        );
        return;
      }
    }

    if (!Platform.isWindows && !Platform.isAndroid) {
      developer.log(
        'Notifications are only implemented for Windows and Android in this service',
        name: 'NotificationService',
      );
      return;
    }

    try {
      developer.log(
        'Preparing to show notification: $title - $message',
        name: 'NotificationService',
      );

      final int notificationId = DateTime.now().millisecondsSinceEpoch
          .remainder(100000);

      if (Platform.isWindows) {
        await _flutterLocalNotificationsPlugin.show(
          notificationId,
          title,
          message,
          NotificationDetails(windows: WindowsNotificationDetails()),
        );
      } else if (Platform.isAndroid) {
        const AndroidNotificationDetails androidDetails =
            AndroidNotificationDetails(
              'general_channel',
              'General Notifications',
              channelDescription: 'General app notifications',
              importance: Importance.high,
              priority: Priority.high,
              showWhen: true,
            );

        await _flutterLocalNotificationsPlugin.show(
          notificationId,
          title,
          message,
          NotificationDetails(android: androidDetails),
        );
      }

      developer.log(
        'Notification show method called successfully',
        name: 'NotificationService',
      );
    } catch (e) {
      developer.log(
        'Error showing notification: $e',
        name: 'NotificationService',
      );
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

  Future<void> showUpdateNotification(String title, String message) async {
    if (!_isInitialized) {
      if (Platform.isWindows || Platform.isAndroid) {
        developer.log(
          'Notification service not initialized, initializing now',
          name: 'NotificationService',
        );
        await initialize();
      } else {
        developer.log(
          'Update notifications not supported on this platform',
          name: 'NotificationService',
        );
        return;
      }
    }

    if (!Platform.isWindows && !Platform.isAndroid) {
      developer.log(
        'Update notifications are only implemented for Windows and Android in this service',
        name: 'NotificationService',
      );
      return;
    }

    try {
      developer.log(
        'Preparing to show update notification: $title - $message',
        name: 'NotificationService',
      );

      const int notificationId = 12345;

      if (Platform.isWindows) {
        await _flutterLocalNotificationsPlugin.show(
          notificationId,
          title,
          message,
          NotificationDetails(windows: WindowsNotificationDetails()),
          payload:
              'update', // matched by the tap handler to open the releases page
        );
      } else if (Platform.isAndroid) {
        const AndroidNotificationDetails androidDetails =
            AndroidNotificationDetails(
              'update_channel',
              'App Updates',
              channelDescription: 'Notifications for new app versions',
              importance: Importance.high,
              priority: Priority.high,
              showWhen: true,
            );

        await _flutterLocalNotificationsPlugin.show(
          notificationId,
          title,
          message,
          NotificationDetails(android: androidDetails),
          payload:
              'update', // matched by the tap handler to open the releases page
        );
      }

      developer.log(
        'Update notification show method called successfully',
        name: 'NotificationService',
      );
    } catch (e) {
      developer.log(
        'Error showing update notification: $e',
        name: 'NotificationService',
      );
    }
  }
}
