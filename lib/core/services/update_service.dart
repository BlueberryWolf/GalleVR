import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

/// Service for checking for app updates from GitHub releases
class UpdateService {
  // Singleton instance
  static final UpdateService _instance = UpdateService._internal();

  // Factory constructor to return the singleton instance
  factory UpdateService() {
    return _instance;
  }

  // Private constructor
  UpdateService._internal();

  // GitHub repository information
  static const String _githubOwner = 'BlueberryWolf';
  static const String _githubRepo = 'GalleVR';
  static const String _githubApiUrl = 'https://api.github.com/repos/$_githubOwner/$_githubRepo/releases/latest';
  static const String _releasesUrl = 'https://github.com/$_githubOwner/$_githubRepo/releases';

  // Notification service
  final FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  // Flag to track if service has been initialized
  bool _isInitialized = false;

  // Update information
  String? _latestVersion;
  bool _updateAvailable = false;

  // Stream controller for update status
  final _updateStreamController = StreamController<bool>.broadcast();

  // Stream of update availability
  Stream<bool> get updateAvailableStream => _updateStreamController.stream;

  // Getter for update availability
  bool get isUpdateAvailable => _updateAvailable;

  // Getter for latest version
  String? get latestVersion => _latestVersion;

  // Last check timestamp key for shared preferences
  static const String _lastCheckKey = 'update_last_check_time';
  // Minimum interval between checks (24 hours in milliseconds)
  static const int _checkIntervalMs = 24 * 60 * 60 * 1000;

  /// Initialize the update service
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      developer.log('Starting update service initialization',
          name: 'UpdateService');

      if (Platform.isWindows) {
        const WindowsInitializationSettings initializationSettingsWindows =
            WindowsInitializationSettings(
          appName: 'GalleVR',
          appUserModelId: '{6D809377-6AF0-444B-8957-A3773F02200E}\\GalleVR\\gallevr.exe',
          guid: '2fc54373-926e-545c-883a-dabcd36b229f',
        );

        developer.log('Windows initialization settings created',
            name: 'UpdateService');

        // Initialize the plugin with platform-specific settings for Windows
        final InitializationSettings initializationSettings =
            InitializationSettings(
          windows: initializationSettingsWindows,
        );

        developer.log('Calling initialize on flutter_local_notifications plugin for Windows',
            name: 'UpdateService');

        final bool? initResult = await _flutterLocalNotificationsPlugin.initialize(
          initializationSettings,
          onDidReceiveNotificationResponse: (NotificationResponse response) {
            developer.log('Update notification tapped: ${response.payload}',
                name: 'UpdateService');

            // Open the releases page when notification is tapped
            if (response.payload == 'update') {
              _openReleasesPage();
            }
          },
        );

        developer.log('Initialize result for Windows: $initResult',
            name: 'UpdateService');
      }
      else if (Platform.isAndroid) {
        // Android initialization settings
        const AndroidInitializationSettings initializationSettingsAndroid =
            AndroidInitializationSettings('@mipmap/ic_launcher');

        developer.log('Android initialization settings created',
            name: 'UpdateService');

        // Initialize the plugin with platform-specific settings for Android
        final InitializationSettings initializationSettings =
            InitializationSettings(
          android: initializationSettingsAndroid,
        );

        developer.log('Calling initialize on flutter_local_notifications plugin for Android',
            name: 'UpdateService');

        final bool? initResult = await _flutterLocalNotificationsPlugin.initialize(
          initializationSettings,
          onDidReceiveNotificationResponse: (NotificationResponse response) {
            developer.log('Update notification tapped: ${response.payload}',
                name: 'UpdateService');

            // Open the releases page when notification is tapped
            if (response.payload == 'update') {
              _openReleasesPage();
            }
          },
        );

        developer.log('Initialize result for Android: $initResult',
            name: 'UpdateService');
      }

      _isInitialized = true;
      developer.log('Update service initialized', name: 'UpdateService');
    } catch (e) {
      developer.log('Error initializing update service: $e',
          name: 'UpdateService');
    }
  }

  /// Check for updates on app startup
  Future<void> checkForUpdatesOnStartup() async {
    try {
      // Initialize if not already initialized
      if (!_isInitialized) {
        await initialize();
      }

      // Check if we should check for updates (not too frequent)
      if (!await _shouldCheckForUpdates()) {
        developer.log('Skipping update check (checked recently)',
            name: 'UpdateService');
        return;
      }

      // Get current app version
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;

      developer.log('Checking for updates. Current version: $currentVersion',
          name: 'UpdateService');

      // Get latest release version from GitHub
      final latestVersion = await _getLatestReleaseVersion();

      if (latestVersion == null) {
        developer.log('Failed to get latest version',
            name: 'UpdateService');
        return;
      }

      developer.log('Latest version: $latestVersion',
          name: 'UpdateService');

      // Store the latest version
      _latestVersion = latestVersion;

      // Compare versions
      final hasUpdate = _isNewerVersion(currentVersion, latestVersion);
      if (hasUpdate) {
        developer.log('New version available: $latestVersion',
            name: 'UpdateService');

        // Update the update status
        _updateAvailable = true;

        // Notify listeners about the update
        _updateStreamController.add(true);

        // Show update notification
        await _showUpdateNotification(latestVersion);
      } else {
        developer.log('App is up to date',
            name: 'UpdateService');

        // Update the update status
        _updateAvailable = false;

        // Notify listeners about the update status
        _updateStreamController.add(false);
      }

      // Update last check time
      await _updateLastCheckTime();
    } catch (e) {
      developer.log('Error checking for updates: $e',
          name: 'UpdateService');
    }
  }

  /// Check for updates and return whether an update is available
  Future<bool> checkForUpdates() async {
    try {
      await checkForUpdatesOnStartup();
      return _updateAvailable;
    } catch (e) {
      developer.log('Error in checkForUpdates: $e', name: 'UpdateService');
      return false;
    }
  }

  /// Get the latest release version from GitHub
  Future<String?> _getLatestReleaseVersion() async {
    try {
      final response = await http.get(
        Uri.parse(_githubApiUrl),
        headers: {'Accept': 'application/vnd.github.v3+json'},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final tagName = data['tag_name'] as String?;

        // Remove 'v' prefix if present
        if (tagName != null && tagName.startsWith('v')) {
          return tagName.substring(1);
        }

        return tagName;
      } else {
        developer.log('GitHub API error: ${response.statusCode} ${response.body}',
            name: 'UpdateService');
        return null;
      }
    } catch (e) {
      developer.log('Error getting latest release: $e',
          name: 'UpdateService');
      return null;
    }
  }

  /// Compare version strings to determine if latest is newer than current
  bool _isNewerVersion(String currentVersion, String latestVersion) {
    try {
      // Split version strings into components
      final currentParts = currentVersion.split('.')
          .map((part) => int.tryParse(part) ?? 0)
          .toList();
      final latestParts = latestVersion.split('.')
          .map((part) => int.tryParse(part) ?? 0)
          .toList();

      // Ensure both lists have the same length
      while (currentParts.length < 3) {
        currentParts.add(0);
      }
      while (latestParts.length < 3) {
        latestParts.add(0);
      }

      // Compare major version
      if (latestParts[0] > currentParts[0]) return true;
      if (latestParts[0] < currentParts[0]) return false;

      // Compare minor version
      if (latestParts[1] > currentParts[1]) return true;
      if (latestParts[1] < currentParts[1]) return false;

      // Compare patch version
      return latestParts[2] > currentParts[2];
    } catch (e) {
      developer.log('Error comparing versions: $e',
          name: 'UpdateService');
      return false;
    }
  }

  /// Show update notification
  Future<void> _showUpdateNotification(String newVersion) async {
    if (!_isInitialized) {
      developer.log('Cannot show notification: service not initialized',
          name: 'UpdateService');
      return;
    }

    try {
      developer.log('Showing update notification for version $newVersion',
          name: 'UpdateService');

      final int notificationId = DateTime.now().millisecondsSinceEpoch.remainder(100000);

      if (Platform.isWindows) {
        await _flutterLocalNotificationsPlugin.show(
          notificationId,
          'GalleVR Update Available',
          'Version $newVersion is now available. Tap to download.',
          NotificationDetails(
            windows: WindowsNotificationDetails(),
          ),
          payload: 'update',
        );
      }
      else if (Platform.isAndroid) {
        const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
          'update_channel',
          'App Updates',
          channelDescription: 'Notifications for new app versions',
          importance: Importance.high,
          priority: Priority.high,
          showWhen: true,
        );

        await _flutterLocalNotificationsPlugin.show(
          notificationId,
          'GalleVR Update Available',
          'Version $newVersion is now available. Tap to download.',
          NotificationDetails(
            android: androidDetails,
          ),
          payload: 'update',
        );
      }

      developer.log('Update notification shown successfully',
          name: 'UpdateService');
    } catch (e) {
      developer.log('Error showing update notification: $e',
          name: 'UpdateService');
    }
  }

  /// Open the GitHub releases page (private method used by notification)
  Future<void> _openReleasesPage() async {
    try {
      final Uri url = Uri.parse(_releasesUrl);
      await launchUrl(url);
      developer.log('Opened releases page: $_releasesUrl',
          name: 'UpdateService');
    } catch (e) {
      developer.log('Error opening releases page: $e',
          name: 'UpdateService');
    }
  }

  /// Open the GitHub releases page (public method for UI)
  Future<void> openReleasesPage() async {
    await _openReleasesPage();
  }

  /// Check if we should check for updates based on last check time
  Future<bool> _shouldCheckForUpdates() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastCheckTime = prefs.getInt(_lastCheckKey) ?? 0;
      final currentTime = DateTime.now().millisecondsSinceEpoch;

      // Check if enough time has passed since the last check
      return (currentTime - lastCheckTime) >= _checkIntervalMs;
    } catch (e) {
      developer.log('Error checking last update time: $e',
          name: 'UpdateService');
      return true; // Default to checking if there's an error
    }
  }

  /// Update the last check time
  Future<void> _updateLastCheckTime() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_lastCheckKey, DateTime.now().millisecondsSinceEpoch);
    } catch (e) {
      developer.log('Error updating last check time: $e',
          name: 'UpdateService');
    }
  }

  /// Dispose resources
  Future<void> dispose() async {
    try {
      await _updateStreamController.close();
      developer.log('Update service disposed', name: 'UpdateService');
    } catch (e) {
      developer.log('Error disposing update service: $e', name: 'UpdateService');
    }
  }
}
