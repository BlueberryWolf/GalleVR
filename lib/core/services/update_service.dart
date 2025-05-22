import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io' show Platform;

import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'notification_service.dart';

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

  // Timer for periodic update checks
  Timer? _periodicUpdateTimer;

  // Interval for periodic update checks (30 minutes)
  static const int _periodicUpdateIntervalMinutes = 30;

  // Minimum time between update checks (15 minutes)
  static const int _minimumTimeBetweenChecksMinutes = 15;

  /// Initialize the update service
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      developer.log('Starting update service initialization',
          name: 'UpdateService');

      // Start periodic update checks
      _startPeriodicUpdateChecks();

      _isInitialized = true;
      developer.log('Update service initialized (using shared notification service)',
          name: 'UpdateService');
    } catch (e) {
      developer.log('Error initializing update service: $e',
          name: 'UpdateService');
    }
  }

  /// Start periodic update checks
  void _startPeriodicUpdateChecks() {
    // Cancel any existing timer
    _periodicUpdateTimer?.cancel();

    // Create a new timer that checks for updates every 30 minutes
    _periodicUpdateTimer = Timer.periodic(
      Duration(minutes: _periodicUpdateIntervalMinutes),
      (_) async {
        developer.log('Periodic update check triggered',
            name: 'UpdateService');
        await checkForUpdates();
      }
    );

    developer.log('Periodic update checks scheduled every $_periodicUpdateIntervalMinutes minutes',
        name: 'UpdateService');
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
  /// Now uses forceCheckForUpdates to ensure update check happens every time
  Future<bool> checkForUpdates() async {
    try {
      return await forceCheckForUpdates();
    } catch (e) {
      developer.log('Error in checkForUpdates: $e', name: 'UpdateService');
      return false;
    }
  }

  /// Force check for updates regardless of when the last check was performed
  /// This is useful for manual update checks or when you want to ensure an update check happens
  Future<bool> forceCheckForUpdates() async {
    try {
      // Initialize if not already initialized
      if (!_isInitialized) {
        await initialize();
      }

      developer.log('Forcing update check', name: 'UpdateService');

      // Get current app version
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;

      developer.log('Current version: $currentVersion', name: 'UpdateService');

      // Get latest release version from GitHub
      final latestVersion = await _getLatestReleaseVersion();

      if (latestVersion == null) {
        developer.log('Failed to get latest version', name: 'UpdateService');
        return false;
      }

      developer.log('Latest version: $latestVersion', name: 'UpdateService');

      // Store the latest version
      _latestVersion = latestVersion;

      // Compare versions
      final hasUpdate = _isNewerVersion(currentVersion, latestVersion);
      if (hasUpdate) {
        developer.log('New version available: $latestVersion', name: 'UpdateService');

        // Update the update status
        _updateAvailable = true;

        // Notify listeners about the update
        _updateStreamController.add(true);

        // Show update notification
        await _showUpdateNotification(latestVersion);
      } else {
        developer.log('App is up to date', name: 'UpdateService');

        // Update the update status
        _updateAvailable = false;

        // Notify listeners about the update status
        _updateStreamController.add(false);
      }

      // Update last check time
      await _updateLastCheckTime();

      return _updateAvailable;
    } catch (e) {
      developer.log('Error forcing update check: $e', name: 'UpdateService');
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

  // Track if we've shown a notification for the current version
  String? _lastNotifiedVersion;

  // Reference to the shared notification service
  final NotificationService _notificationService = NotificationService();

  /// Show update notification
  Future<void> _showUpdateNotification(String newVersion) async {
    if (!_isInitialized) {
      developer.log('Cannot show notification: service not initialized',
          name: 'UpdateService');
      return;
    }

    // Check if we've already shown a notification for this version
    if (_lastNotifiedVersion == newVersion) {
      developer.log('Already showed notification for version $newVersion, skipping',
          name: 'UpdateService');
      return;
    }

    try {
      developer.log('Showing update notification for version $newVersion',
          name: 'UpdateService');

      // Use the shared notification service to show the notification for both Windows and Android
      await _notificationService.showUpdateNotification(
        'GalleVR Update Available',
        'Version $newVersion is now available. Tap to download.',
      );

      // Also show an in-app notification using a global key
      _showInAppUpdateNotification(newVersion);

      // Remember that we've shown a notification for this version
      _lastNotifiedVersion = newVersion;

      developer.log('Update notification shown successfully',
          name: 'UpdateService');
    } catch (e) {
      developer.log('Error showing update notification: $e',
          name: 'UpdateService');
    }
  }

  /// Show an in-app update notification using a SnackBar
  void _showInAppUpdateNotification(String newVersion) {
    try {
      // This will be handled by the AppWrapper widget
      developer.log('Broadcasting in-app update notification request',
          name: 'UpdateService');

      // We'll use the stream to notify the app about the update
      _updateStreamController.add(true);
    } catch (e) {
      developer.log('Error showing in-app update notification: $e',
          name: 'UpdateService');
    }
  }

  /// Open the GitHub releases page
  /// This is a public method that can be called from other parts of the app
  Future<void> openReleasesPage() async {
    try {
      developer.log('Attempting to open releases page: $_releasesUrl',
          name: 'UpdateService');

      // Use the shared notification service to open the releases page
      await _notificationService.openReleasesPage();

      developer.log('Successfully opened releases page using NotificationService',
          name: 'UpdateService');
    } catch (e) {
      developer.log('Error opening releases page: $e',
          name: 'UpdateService');
    }
  }

  /// Check if we should check for updates based on last check time
  /// Returns true if enough time has passed since the last check
  Future<bool> _shouldCheckForUpdates() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastCheckTime = prefs.getInt(_lastCheckKey) ?? 0;
      final currentTime = DateTime.now().millisecondsSinceEpoch;

      // Calculate time since last check in minutes
      final timeSinceLastCheckMs = currentTime - lastCheckTime;
      final timeSinceLastCheckMinutes = timeSinceLastCheckMs / 1000 / 60;

      developer.log('Time since last update check: ${timeSinceLastCheckMinutes.toStringAsFixed(1)} minutes',
          name: 'UpdateService');

      // Check if enough time has passed since the last check
      if (timeSinceLastCheckMinutes < _minimumTimeBetweenChecksMinutes) {
        developer.log('Not enough time has passed since last check (minimum: $_minimumTimeBetweenChecksMinutes minutes)',
            name: 'UpdateService');
        return false;
      }

      return true;
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
      // Stop periodic update checks
      _periodicUpdateTimer?.cancel();
      _periodicUpdateTimer = null;
      developer.log('Periodic update checks stopped', name: 'UpdateService');

      await _updateStreamController.close();
      developer.log('Update service disposed', name: 'UpdateService');
    } catch (e) {
      developer.log('Error disposing update service: $e', name: 'UpdateService');
    }
  }
}
