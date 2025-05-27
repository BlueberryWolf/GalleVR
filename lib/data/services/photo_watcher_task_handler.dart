import 'dart:async';
import 'dart:io';
import 'dart:developer' as developer;
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:path/path.dart' as path;

import '../../core/platform/platform_service.dart';
import '../../core/platform/platform_service_factory.dart';
import '../../core/utils/log_file_watcher.dart';
import '../models/config_model.dart';
import '../repositories/config_repository.dart';

// Top-level callback function for the foreground task
@pragma('vm:entry-point')
void startPhotoWatcherCallback() {
  FlutterForegroundTask.setTaskHandler(PhotoWatcherTaskHandler());
}

// Task handler for watching photos in a foreground service
class PhotoWatcherTaskHandler extends TaskHandler {
  // Platform service for platform-specific operations
  final PlatformService _platformService = PlatformServiceFactory.getPlatformService();

  // Config repository to load configuration
  final ConfigRepository _configRepository = ConfigRepository();

  // Current configuration
  ConfigModel? _config;

  // Set of handled photos to avoid duplicates
  final Set<String> _handledPhotos = {};

  // Timer for polling on Android (since file system events are not available sadly)
  Timer? _pollingTimer;

  // Stream subscription for file system events on platforms that support it
  StreamSubscription<FileSystemEvent>? _watcherSubscription;

  // Log file watcher and subscription for monitoring VRChat logs
  LogFileWatcher? _logFileWatcher;
  StreamSubscription<String>? _logWatcherSubscription;

  // Regex pattern to match VRChat screenshot filenames
  // Pattern: VRChat_YYYY-MM-DD_HH-MM-SS.mmm_WIDTHxHEIGHT.png
  static final RegExp _vrchatScreenshotPattern = RegExp(
    r'^VRChat_\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2}\.\d{3}_\d+x\d+\.png$',
  );

  /// Checks if a filename matches the VRChat screenshot pattern
  bool _isVRChatScreenshot(String filePath) {
    final filename = path.basename(filePath);
    return _vrchatScreenshotPattern.hasMatch(filename);
  }

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    // Load configuration
    _config = await _configRepository.loadConfig();

    if (_config == null || _config!.logsDirectory.isEmpty) {
      return;
    }

    // Ensure the logs directory exists
    final directory = Directory(_config!.logsDirectory);
    if (!await directory.exists()) {
      developer.log('Logs directory does not exist: ${_config!.logsDirectory}', name: 'PhotoWatcherTaskHandler');
      return;
    }

    // Start watching the log files
    await _startWatching(_config!);

    // Update notification with current status
    FlutterForegroundTask.updateService(
      notificationTitle: 'GalleVR Photo Watcher',
      notificationText: 'Watching VRChat logs for new screenshots',
    );
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    if (_config != null) {
      FlutterForegroundTask.updateService(
        notificationTitle: 'GalleVR Photo Watcher',
        notificationText: 'Watching VRChat logs for new screenshots',
      );
    }
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    await _watcherSubscription?.cancel();
    _watcherSubscription = null;

    await _logWatcherSubscription?.cancel();
    _logWatcherSubscription = null;

    await _logFileWatcher?.stopWatching();
    _logFileWatcher?.dispose();
    _logFileWatcher = null;

    _pollingTimer?.cancel();
    _pollingTimer = null;
  }

  @override
  void onReceiveData(Object data) {
    if (data is Map<String, dynamic> && data.containsKey('action')) {
      final action = data['action'] as String;

      if (action == 'updateConfig') {
        _handleConfigUpdate(data);
      }
    }
  }

  // Handle configuration updates from the main isolate
  void _handleConfigUpdate(Map<String, dynamic> data) async {
    if (data.containsKey('config')) {
      // Load the updated configuration
      _config = await _configRepository.loadConfig();

      if (_config != null) {
        // Restart watching with the new configuration
        await _watcherSubscription?.cancel();
        _watcherSubscription = null;

        await _logWatcherSubscription?.cancel();
        _logWatcherSubscription = null;

        await _logFileWatcher?.stopWatching();
        _logFileWatcher = null;

        _pollingTimer?.cancel();
        _pollingTimer = null;

        await _startWatching(_config!);

        FlutterForegroundTask.updateService(
          notificationTitle: 'GalleVR Photo Watcher',
          notificationText: 'Watching VRChat logs for new screenshots',
        );
      }
    }
  }

  // Start watching for new screenshots from log files
  Future<void> _startWatching(ConfigModel config) async {
    final logsDir = config.logsDirectory;
    if (logsDir.isEmpty) {
      return;
    }

    try {
      _logFileWatcher = LogFileWatcher(logsDir);
      await _logFileWatcher!.startWatching();

      _logWatcherSubscription = _logFileWatcher!.screenshotStream.listen(
        (screenshotPath) => _handleScreenshotFromLog(screenshotPath, config),
      );
    } catch (e) {
      developer.log('Error starting log file watcher: $e', name: 'PhotoWatcherTaskHandler');
    }
  }

  // Handle screenshot detected from log file
  void _handleScreenshotFromLog(String screenshotPath, ConfigModel config) {
    // Verify the file exists and is a VRChat screenshot
    final file = File(screenshotPath);
    if (!file.existsSync()) {
      developer.log(
        'Screenshot file does not exist: $screenshotPath',
        name: 'PhotoWatcherTaskHandler',
      );
      return;
    }

    if (!_isVRChatScreenshot(screenshotPath)) {
      developer.log(
        'Ignoring non-VRChat screenshot: $screenshotPath',
        name: 'PhotoWatcherTaskHandler',
      );
      return;
    }

    if (_handledPhotos.contains(screenshotPath)) {
      developer.log(
        'Ignoring already handled photo: $screenshotPath',
        name: 'PhotoWatcherTaskHandler',
      );
      return;
    }

    _handledPhotos.add(screenshotPath);
    FlutterForegroundTask.sendDataToMain({'newPhoto': screenshotPath});

    FlutterForegroundTask.updateService(
      notificationTitle: 'GalleVR Photo Watcher',
      notificationText: 'New screenshot detected: ${path.basename(screenshotPath)}',
    );
  }
}
