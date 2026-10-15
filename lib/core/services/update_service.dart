import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io'
    show Platform, Directory, File, Process, ProcessStartMode, exit;

import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'notification_service.dart';

/// Checks GitHub releases for newer versions.
class UpdateService {
  static final UpdateService _instance = UpdateService._internal();

  factory UpdateService() {
    return _instance;
  }

  UpdateService._internal();

  static const String _githubOwner = 'BlueberryWolf';
  static const String _githubRepo = 'GalleVR';
  static const String _githubApiUrl =
      'https://api.github.com/repos/$_githubOwner/$_githubRepo/releases/latest';
  static const String _releasesUrl =
      'https://github.com/$_githubOwner/$_githubRepo/releases';

  bool _isInitialized = false;

  String? _latestVersion;
  bool _updateAvailable = false;

  final _updateStreamController = StreamController<bool>.broadcast();

  Stream<bool> get updateAvailableStream => _updateStreamController.stream;

  bool get isUpdateAvailable => _updateAvailable;

  String? get latestVersion => _latestVersion;

  static const String _lastCheckKey = 'update_last_check_time';

  Timer? _periodicUpdateTimer;

  static const int _periodicUpdateIntervalMinutes = 30;

  static const int _minimumTimeBetweenChecksMinutes = 15;

  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      developer.log(
        'Starting update service initialization',
        name: 'UpdateService',
      );

      _startPeriodicUpdateChecks();

      _isInitialized = true;
      developer.log(
        'Update service initialized (using shared notification service)',
        name: 'UpdateService',
      );
    } catch (e) {
      developer.log(
        'Error initializing update service: $e',
        name: 'UpdateService',
      );
    }
  }

  void _startPeriodicUpdateChecks() {
    _periodicUpdateTimer?.cancel();

    _periodicUpdateTimer = Timer.periodic(
      Duration(minutes: _periodicUpdateIntervalMinutes),
      (_) async {
        developer.log('Periodic update check triggered', name: 'UpdateService');
        await checkForUpdates();
      },
    );

    developer.log(
      'Periodic update checks scheduled every $_periodicUpdateIntervalMinutes minutes',
      name: 'UpdateService',
    );
  }

  Future<void> checkForUpdatesOnStartup() async {
    try {
      if (!_isInitialized) {
        await initialize();
      }

      if (!await _shouldCheckForUpdates()) {
        developer.log(
          'Skipping update check (checked recently)',
          name: 'UpdateService',
        );
        return;
      }

      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;

      developer.log(
        'Checking for updates. Current version: $currentVersion',
        name: 'UpdateService',
      );

      final latestVersion = await _getLatestReleaseVersion();

      if (latestVersion == null) {
        developer.log('Failed to get latest version', name: 'UpdateService');
        return;
      }

      developer.log('Latest version: $latestVersion', name: 'UpdateService');

      _latestVersion = latestVersion;

      final hasUpdate = _isNewerVersion(currentVersion, latestVersion);
      if (hasUpdate) {
        developer.log(
          'New version available: $latestVersion',
          name: 'UpdateService',
        );

        _updateAvailable = true;

        _updateStreamController.add(true);

        await _showUpdateNotification(latestVersion);
      } else {
        developer.log('App is up to date', name: 'UpdateService');

        _updateAvailable = false;

        _updateStreamController.add(false);
      }

      await _updateLastCheckTime();
    } catch (e) {
      developer.log('Error checking for updates: $e', name: 'UpdateService');
    }
  }

  Future<bool> checkForUpdates() async {
    try {
      return await forceCheckForUpdates();
    } catch (e) {
      developer.log('Error in checkForUpdates: $e', name: 'UpdateService');
      return false;
    }
  }

  /// Checks for updates even if the last check was recent.
  Future<bool> forceCheckForUpdates() async {
    try {
      if (!_isInitialized) {
        await initialize();
      }

      developer.log('Forcing update check', name: 'UpdateService');

      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;

      developer.log('Current version: $currentVersion', name: 'UpdateService');

      final latestVersion = await _getLatestReleaseVersion();

      if (latestVersion == null) {
        developer.log('Failed to get latest version', name: 'UpdateService');
        return false;
      }

      developer.log('Latest version: $latestVersion', name: 'UpdateService');

      _latestVersion = latestVersion;

      final hasUpdate = _isNewerVersion(currentVersion, latestVersion);
      if (hasUpdate) {
        developer.log(
          'New version available: $latestVersion',
          name: 'UpdateService',
        );

        _updateAvailable = true;

        _updateStreamController.add(true);

        await _showUpdateNotification(latestVersion);
      } else {
        developer.log('App is up to date', name: 'UpdateService');

        _updateAvailable = false;

        _updateStreamController.add(false);
      }

      await _updateLastCheckTime();

      return _updateAvailable;
    } catch (e) {
      developer.log('Error forcing update check: $e', name: 'UpdateService');
      return false;
    }
  }

  Future<String?> _getLatestReleaseVersion() async {
    try {
      final response = await http.get(
        Uri.parse(_githubApiUrl),
        headers: {'Accept': 'application/vnd.github.v3+json'},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final tagName = data['tag_name'] as String?;

        if (tagName != null && tagName.startsWith('v')) {
          return tagName.substring(1);
        }

        return tagName;
      } else {
        developer.log(
          'GitHub API error: ${response.statusCode} ${response.body}',
          name: 'UpdateService',
        );
        return null;
      }
    } catch (e) {
      developer.log('Error getting latest release: $e', name: 'UpdateService');
      return null;
    }
  }

  bool _isNewerVersion(String currentVersion, String latestVersion) {
    try {
      final currentParts =
          currentVersion
              .split('.')
              .map((part) => int.tryParse(part) ?? 0)
              .toList();
      final latestParts =
          latestVersion
              .split('.')
              .map((part) => int.tryParse(part) ?? 0)
              .toList();

      while (currentParts.length < 3) {
        currentParts.add(0);
      }
      while (latestParts.length < 3) {
        latestParts.add(0);
      }

      if (latestParts[0] > currentParts[0]) return true;
      if (latestParts[0] < currentParts[0]) return false;

      if (latestParts[1] > currentParts[1]) return true;
      if (latestParts[1] < currentParts[1]) return false;

      return latestParts[2] > currentParts[2];
    } catch (e) {
      developer.log('Error comparing versions: $e', name: 'UpdateService');
      return false;
    }
  }

  String? _lastNotifiedVersion;

  final NotificationService _notificationService = NotificationService();

  Future<void> _showUpdateNotification(String newVersion) async {
    if (!_isInitialized) {
      developer.log(
        'Cannot show notification: service not initialized',
        name: 'UpdateService',
      );
      return;
    }

    if (_lastNotifiedVersion == newVersion) {
      developer.log(
        'Already showed notification for version $newVersion, skipping',
        name: 'UpdateService',
      );
      return;
    }

    try {
      developer.log(
        'Showing update notification for version $newVersion',
        name: 'UpdateService',
      );

      await _notificationService.showUpdateNotification(
        'GalleVR Update Available',
        'Version $newVersion is now available. Tap to download.',
      );

      _showInAppUpdateNotification(newVersion);

      _lastNotifiedVersion = newVersion;

      developer.log(
        'Update notification shown successfully',
        name: 'UpdateService',
      );
    } catch (e) {
      developer.log(
        'Error showing update notification: $e',
        name: 'UpdateService',
      );
    }
  }

  void _showInAppUpdateNotification(String newVersion) {
    try {
      developer.log(
        'Broadcasting in-app update notification request',
        name: 'UpdateService',
      );

      _updateStreamController.add(true);
    } catch (e) {
      developer.log(
        'Error showing in-app update notification: $e',
        name: 'UpdateService',
      );
    }
  }

  Future<void> openReleasesPage() async {
    try {
      developer.log(
        'Attempting to open releases page: $_releasesUrl',
        name: 'UpdateService',
      );

      await _notificationService.openReleasesPage();

      developer.log(
        'Successfully opened releases page using NotificationService',
        name: 'UpdateService',
      );
    } catch (e) {
      developer.log('Error opening releases page: $e', name: 'UpdateService');
    }
  }

  /// Whether enough time has passed since the last update check.
  Future<bool> _shouldCheckForUpdates() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastCheckTime = prefs.getInt(_lastCheckKey) ?? 0;
      final currentTime = DateTime.now().millisecondsSinceEpoch;

      final timeSinceLastCheckMs = currentTime - lastCheckTime;
      final timeSinceLastCheckMinutes = timeSinceLastCheckMs / 1000 / 60;

      developer.log(
        'Time since last update check: ${timeSinceLastCheckMinutes.toStringAsFixed(1)} minutes',
        name: 'UpdateService',
      );

      if (timeSinceLastCheckMinutes < _minimumTimeBetweenChecksMinutes) {
        developer.log(
          'Not enough time has passed since last check (minimum: $_minimumTimeBetweenChecksMinutes minutes)',
          name: 'UpdateService',
        );
        return false;
      }

      return true;
    } catch (e) {
      developer.log(
        'Error checking last update time: $e',
        name: 'UpdateService',
      );
      return true; // check anyway if the last check time can't be read
    }
  }

  Future<void> _updateLastCheckTime() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_lastCheckKey, DateTime.now().millisecondsSinceEpoch);
    } catch (e) {
      developer.log(
        'Error updating last check time: $e',
        name: 'UpdateService',
      );
    }
  }

  Future<void> dispose() async {
    try {
      _periodicUpdateTimer?.cancel();
      _periodicUpdateTimer = null;
      developer.log('Periodic update checks stopped', name: 'UpdateService');

      await _updateStreamController.close();
      developer.log('Update service disposed', name: 'UpdateService');
    } catch (e) {
      developer.log(
        'Error disposing update service: $e',
        name: 'UpdateService',
      );
    }
  }

  Future<String?> getLatestInstallerUrl() async {
    try {
      final response = await http.get(
        Uri.parse(_githubApiUrl),
        headers: {'Accept': 'application/vnd.github.v3+json'},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final assets = data['assets'] as List<dynamic>?;

        if (assets != null) {
          for (final asset in assets) {
            final name = asset['name'] as String?;
            final downloadUrl = asset['browser_download_url'] as String?;
            if (name != null &&
                name.toLowerCase().endsWith('.exe') &&
                downloadUrl != null) {
              developer.log(
                'Found installer asset: $name -> $downloadUrl',
                name: 'UpdateService',
              );
              return downloadUrl;
            }
          }
        }
      }
      return null;
    } catch (e) {
      developer.log(
        'Error getting latest installer URL: $e',
        name: 'UpdateService',
      );
      return null;
    }
  }

  /// Downloads and launches the Windows installer, then exits.
  Future<void> downloadAndInstall({Function(double)? onProgress}) async {
    if (!Platform.isWindows) return;

    try {
      developer.log(
        'Starting installer download process',
        name: 'UpdateService',
      );

      final downloadUrl = await getLatestInstallerUrl();
      if (downloadUrl == null) {
        throw Exception(
          'Could not find installer download URL in GitHub assets.',
        );
      }

      developer.log(
        'Downloading installer from: $downloadUrl',
        name: 'UpdateService',
      );

      final tempDir = Directory.systemTemp;
      final tempFilePath = '${tempDir.path}\\GalleVR-Setup.exe';
      final tempFile = File(tempFilePath);

      if (await tempFile.exists()) {
        await tempFile.delete();
      }

      final client = http.Client();
      final request = http.Request('GET', Uri.parse(downloadUrl));
      final response = await client.send(request);

      if (response.statusCode != 200) {
        throw Exception(
          'Failed to download installer. HTTP ${response.statusCode}',
        );
      }

      final contentLength = response.contentLength ?? 0;
      int downloadedBytes = 0;

      final sink = tempFile.openWrite();

      await for (final chunk in response.stream) {
        sink.add(chunk);
        downloadedBytes += chunk.length;
        if (contentLength > 0 && onProgress != null) {
          final progress = downloadedBytes / contentLength;
          onProgress(progress);
        }
      }

      await sink.close();
      client.close();

      developer.log(
        'Installer downloaded successfully to: $tempFilePath',
        name: 'UpdateService',
      );
      developer.log(
        'Launching installer and exiting app...',
        name: 'UpdateService',
      );
      await Process.start(tempFilePath, [], mode: ProcessStartMode.detached);
      exit(0);
    } catch (e) {
      developer.log(
        'Error during download and install: $e',
        name: 'UpdateService',
        error: e,
      );
      rethrow;
    }
  }
}
