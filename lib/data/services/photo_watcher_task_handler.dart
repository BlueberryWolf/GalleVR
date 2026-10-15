import 'dart:async';
import 'dart:io';
import 'dart:developer' as developer;
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:path/path.dart' as path;

import '../../core/utils/log_file_watcher.dart';
import '../../core/utils/screenshot_utils.dart';
import '../models/config_model.dart';
import '../repositories/config_repository.dart';

@pragma('vm:entry-point')
void startPhotoWatcherCallback() {
  FlutterForegroundTask.setTaskHandler(PhotoWatcherTaskHandler());
}

class PhotoWatcherTaskHandler extends TaskHandler {
  final ConfigRepository _configRepository = ConfigRepository();

  ConfigModel? _config;

  final Set<String> _handledPhotos = {};

  /// Android has no file system events, so photos are polled.
  Timer? _pollingTimer;

  StreamSubscription<FileSystemEvent>? _watcherSubscription;

  LogFileWatcher? _logFileWatcher;
  StreamSubscription<String>? _logWatcherSubscription;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    _config = await _configRepository.loadConfig();

    if (_config == null) {
      return;
    }

    final logsDir = _config!.logsDirectory;
    final photosDir = _config!.photosDirectory;

    if (logsDir.isEmpty) {
      developer.log(
        'Logs directory is not set',
        name: 'PhotoWatcherTaskHandler',
      );
      FlutterForegroundTask.sendDataToMain({
        'error': 'Watcher stopped: Logs directory is not set in configuration.',
      });
      return;
    }

    if (photosDir.isEmpty) {
      developer.log(
        'Photos directory is not set',
        name: 'PhotoWatcherTaskHandler',
      );
      FlutterForegroundTask.sendDataToMain({
        'error':
            'Watcher stopped: Photos directory is not set in configuration.',
      });
      return;
    }

    final directory = Directory(logsDir);
    if (!await directory.exists()) {
      final errorMsg = 'Logs directory does not exist: $logsDir';
      developer.log(errorMsg, name: 'PhotoWatcherTaskHandler');
      FlutterForegroundTask.sendDataToMain({
        'error':
            'Cannot find logs directory. Please check your settings.\nPath: $logsDir',
      });
      return;
    }

    final photosDirectory = Directory(photosDir);
    if (!await photosDirectory.exists()) {
      final errorMsg = 'Photos directory does not exist: $photosDir';
      developer.log(errorMsg, name: 'PhotoWatcherTaskHandler');
      FlutterForegroundTask.sendDataToMain({
        'error':
            'Cannot find VRChat photos directory. Please check your settings.\nPath: $photosDir',
      });
      return;
    }

    await _startWatching(_config!);

    FlutterForegroundTask.updateService(
      notificationTitle: 'GalleVR Photo Watcher',
      notificationText: 'Monitoring VRChat logs for new photos...',
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

  void _handleConfigUpdate(Map<String, dynamic> data) async {
    if (data.containsKey('config')) {
      _config = await _configRepository.loadConfig();

      if (_config != null) {
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
        onError: (e) {
          developer.log(
            'Error in log file watcher stream: $e',
            name: 'PhotoWatcherTaskHandler',
          );
          FlutterForegroundTask.sendDataToMain({
            'error': 'Monitoring Error: Failed to read log updates.',
          });
        },
      );

      developer.log(
        'Log file watcher started successfully',
        name: 'PhotoWatcherTaskHandler',
      );
      FlutterForegroundTask.sendDataToMain({
        'status': 'Monitoring started successfully',
      });
    } catch (e) {
      developer.log(
        'Error starting log file watcher: $e',
        name: 'PhotoWatcherTaskHandler',
      );
      FlutterForegroundTask.sendDataToMain({
        'error': 'Failed to start log monitor: $e',
      });
    }
  }

  void _handleScreenshotFromLog(String screenshotPath, ConfigModel config) {
    String finalPath = ScreenshotUtils.translatePlatformPath(
      screenshotPath,
      config.photosDirectory,
    );

    final file = File(finalPath);
    if (!file.existsSync()) {
      final errorMsg =
          'Screenshot detected in log but file not found at: $finalPath';
      developer.log(errorMsg, name: 'PhotoWatcherTaskHandler');

      FlutterForegroundTask.sendDataToMain({
        'error':
            'New photo detected but file is inaccessible. Check storage permissions.\nFile: ${path.basename(finalPath)}',
      });
      return;
    }

    if (!ScreenshotUtils.isVRChatScreenshot(finalPath)) {
      developer.log(
        'Ignoring non-VRChat screenshot: $finalPath',
        name: 'PhotoWatcherTaskHandler',
      );
      return;
    }

    final String screenshotDir = path.dirname(path.dirname(finalPath));

    final String canonicalConfigDir = path.canonicalize(config.photosDirectory);
    final String canonicalScreenshotDir = path.canonicalize(screenshotDir);

    if (canonicalConfigDir != canonicalScreenshotDir) {
      developer.log(
        'Photos directory mismatch detected in background task! Config: ${config.photosDirectory}, actual: $screenshotDir. Aligning settings...',
        name: 'PhotoWatcherTaskHandler',
      );
      try {
        final updatedConfig = config.copyWith(photosDirectory: screenshotDir);
        _config = updatedConfig;

        // The main isolate saves config, so writes never race.
        FlutterForegroundTask.sendDataToMain({
          'action': 'configAligned',
          'photosDirectory': screenshotDir,
        });
      } catch (e) {
        developer.log(
          'Error updating photos directory in background task: $e',
          name: 'PhotoWatcherTaskHandler',
        );
      }
    }

    if (_handledPhotos.contains(finalPath)) {
      developer.log(
        'Ignoring already handled photo: $finalPath',
        name: 'PhotoWatcherTaskHandler',
      );
      return;
    }

    _handledPhotos.add(finalPath);
    FlutterForegroundTask.sendDataToMain({'newPhoto': finalPath});

    FlutterForegroundTask.updateService(
      notificationTitle: 'GalleVR Photo Watcher',
      notificationText: 'New screenshot detected: ${path.basename(finalPath)}',
    );
  }
}
