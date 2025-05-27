import 'dart:async';
import 'dart:io';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:path/path.dart' as path;
import 'dart:developer' as developer;

import '../../core/platform/platform_service.dart';
import '../../core/platform/platform_service_factory.dart';
import '../../core/utils/log_file_watcher.dart';
import '../models/config_model.dart';
import 'photo_event_service.dart';
import 'photo_watcher_task_handler.dart';

class PhotoWatcherService {
  final PlatformService _platformService;

  final _photoStreamController = StreamController<String>.broadcast();

  Stream<String> get photoStream => _photoStreamController.stream;

  final Set<String> _handledPhotos = {};

  StreamSubscription<FileSystemEvent>? _watcherSubscription;
  StreamSubscription<String>? _logWatcherSubscription;
  LogFileWatcher? _logFileWatcher;

  bool _isForegroundServiceRunning = false;

  bool _useForegroundService = false;

  // Regex pattern to match VRChat screenshot filenames
  // Pattern: VRChat_YYYY-MM-DD_HH-MM-SS.mmm_WIDTHxHEIGHT.png
  static final RegExp _vrchatScreenshotPattern = RegExp(
    r'^VRChat_\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2}\.\d{3}_\d+x\d+\.png$',
  );

  PhotoWatcherService({PlatformService? platformService})
    : _platformService =
          platformService ?? PlatformServiceFactory.getPlatformService() {
    FlutterForegroundTask.addTaskDataCallback(_onReceiveTaskData);
  }

  /// Checks if a filename matches the VRChat screenshot pattern
  bool _isVRChatScreenshot(String filePath) {
    final filename = path.basename(filePath);
    return _vrchatScreenshotPattern.hasMatch(filename);
  }

  Future<void> _initForegroundTask() async {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'gallevr_photo_watcher',
        channelName: 'GalleVR Photo Watcher',
        channelDescription: 'Monitors for new VRChat photos',
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: true,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(5000),
        autoRunOnBoot: true,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
  }

  Future<bool> _requestPermissions() async {
    final notificationPermission =
        await FlutterForegroundTask.checkNotificationPermission();
    if (notificationPermission != NotificationPermission.granted) {
      await FlutterForegroundTask.requestNotificationPermission();
    }

    if (Platform.isAndroid) {
      if (!await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
        await FlutterForegroundTask.requestIgnoreBatteryOptimization();
      }
    }

    return true;
  }

  Future<bool> _startForegroundService(ConfigModel config) async {
    await _initForegroundTask();
    await _requestPermissions();

    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.updateService(
        notificationTitle: 'GalleVR Photo Watcher',
        notificationText: 'Watching VRChat logs for new screenshots',
      );

      FlutterForegroundTask.sendDataToTask({
        'action': 'updateConfig',
        'config': true,
      });

      _isForegroundServiceRunning = true;
      return true;
    } else {
      try {
        await FlutterForegroundTask.startService(
          notificationTitle: 'GalleVR Photo Watcher',
          notificationText: 'Watching VRChat logs for new screenshots',
          callback: startPhotoWatcherCallback,
        );

        _isForegroundServiceRunning = true;
        return true;
      } catch (e) {
        developer.log(
          'Error starting foreground service: $e',
          name: 'PhotoWatcherService',
        );
        _isForegroundServiceRunning = false;
        return false;
      }
    }
  }

  Future<bool> _stopForegroundService() async {
    try {
      await FlutterForegroundTask.stopService();
      _isForegroundServiceRunning = false;
      return true;
    } catch (e) {
      developer.log(
        'Error stopping foreground service: $e',
        name: 'PhotoWatcherService',
      );
      _isForegroundServiceRunning = false;
      return false;
    }
  }

  void _onReceiveTaskData(Object data) {
    if (data is Map<String, dynamic> && data.containsKey('newPhoto')) {
      final photoPath = data['newPhoto'] as String;
      _handledPhotos.add(photoPath);
      _photoStreamController.add(photoPath);
      PhotoEventService().notifyPhotoAdded(photoPath);
    }
  }

  Future<void> startWatching(ConfigModel config) async {
    developer.log(
      'Starting photo watcher service',
      name: 'PhotoWatcherService',
    );

    await _watcherSubscription?.cancel();
    _watcherSubscription = null;
    await _logWatcherSubscription?.cancel();
    _logWatcherSubscription = null;
    await _logFileWatcher?.stopWatching();
    _logFileWatcher = null;

    final logsDir = config.logsDirectory;
    if (logsDir.isEmpty) {
      final error = 'Logs directory is not set';
      developer.log(error, name: 'PhotoWatcherService');
      PhotoEventService().notifyError('watcher', error);
      throw Exception(error);
    }

    final directory = Directory(logsDir);
    try {
      if (!await directory.exists()) {
        final error = 'Logs directory does not exist: $logsDir';
        developer.log(error, name: 'PhotoWatcherService');
        PhotoEventService().notifyError('watcher', error);
        throw Exception(error);
      }
    } catch (e) {
      final error = 'Failed to access logs directory: $e';
      developer.log(error, name: 'PhotoWatcherService');
      PhotoEventService().notifyError('watcher', error);
      throw Exception(error);
    }

    _useForegroundService = Platform.isAndroid;

    if (_useForegroundService) {
      developer.log(
        'Using foreground service for photo watching',
        name: 'PhotoWatcherService',
      );
      final success = await _startForegroundService(config);
      if (!success) {
        final error = 'Failed to start foreground service';
        developer.log(error, name: 'PhotoWatcherService');
        PhotoEventService().notifyError('watcher', error);
      } else {
        developer.log(
          'Foreground service started successfully',
          name: 'PhotoWatcherService',
        );
        PhotoEventService().notifyError(
          'info',
          'Foreground service started successfully',
        );
      }
    } else {
      developer.log(
        'Using in-app log watcher for photo watching',
        name: 'PhotoWatcherService',
      );

      try {
        _logFileWatcher = LogFileWatcher(logsDir);
        await _logFileWatcher!.startWatching();

        _logWatcherSubscription = _logFileWatcher!.screenshotStream.listen(
          (screenshotPath) => _handleScreenshotFromLog(screenshotPath, config),
          onError: (e) {
            final error = 'Error in log file watcher: $e';
            developer.log(error, name: 'PhotoWatcherService');
            PhotoEventService().notifyError('watcher', error);
          },
        );

        developer.log(
          'Log file watcher started successfully',
          name: 'PhotoWatcherService',
        );
        PhotoEventService().notifyError(
          'info',
          'Log file watcher started successfully',
        );
      } catch (e) {
        final error = 'Failed to start log file watcher: $e';
        developer.log(error, name: 'PhotoWatcherService');
        PhotoEventService().notifyError('watcher', error);
        throw Exception(error);
      }
    }
  }

  Future<void> stopWatching() async {
    developer.log(
      'Stopping photo watcher service',
      name: 'PhotoWatcherService',
    );

    if (_useForegroundService && _isForegroundServiceRunning) {
      await _stopForegroundService();
    }

    await _watcherSubscription?.cancel();
    _watcherSubscription = null;

    await _logWatcherSubscription?.cancel();
    _logWatcherSubscription = null;

    await _logFileWatcher?.stopWatching();
    _logFileWatcher = null;
  }

  void _handleScreenshotFromLog(String screenshotPath, ConfigModel config) {
    // Verify the file exists and is a VRChat screenshot
    final file = File(screenshotPath);
    if (!file.existsSync()) {
      developer.log(
        'Screenshot file does not exist: $screenshotPath',
        name: 'PhotoWatcherService',
      );
      return;
    }

    if (!_isVRChatScreenshot(screenshotPath)) {
      developer.log(
        'Ignoring non-VRChat screenshot: $screenshotPath',
        name: 'PhotoWatcherService',
      );
      return;
    }

    if (_handledPhotos.contains(screenshotPath)) {
      developer.log(
        'Ignoring already handled photo: $screenshotPath',
        name: 'PhotoWatcherService',
      );
      return;
    }

    _handledPhotos.add(screenshotPath);

    developer.log('New screenshot detected from log: $screenshotPath', name: 'PhotoWatcherService');
    PhotoEventService().notifyError(
      'info',
      'New screenshot detected: ${path.basename(screenshotPath)}',
    );

    _photoStreamController.add(screenshotPath);
    PhotoEventService().notifyPhotoAdded(screenshotPath);
  }



  Future<void> dispose() async {
    developer.log('Disposing PhotoWatcherService', name: 'PhotoWatcherService');

    try {
      developer.log('Stopping foreground service', name: 'PhotoWatcherService');
      await FlutterForegroundTask.stopService();
      _isForegroundServiceRunning = false;
    } catch (e) {
      developer.log('Error stopping foreground service: $e', name: 'PhotoWatcherService');
    }

    try {
      FlutterForegroundTask.removeTaskDataCallback(_onReceiveTaskData);
    } catch (e) {
      developer.log('Error removing task data callback: $e', name: 'PhotoWatcherService');
    }

    try {
      await _watcherSubscription?.cancel();
      _watcherSubscription = null;
    } catch (e) {
      developer.log('Error cancelling watcher subscription: $e', name: 'PhotoWatcherService');
    }

    try {
      await _logWatcherSubscription?.cancel();
      _logWatcherSubscription = null;
    } catch (e) {
      developer.log('Error cancelling log watcher subscription: $e', name: 'PhotoWatcherService');
    }

    try {
      await _logFileWatcher?.stopWatching();
      _logFileWatcher?.dispose();
      _logFileWatcher = null;
    } catch (e) {
      developer.log('Error disposing log file watcher: $e', name: 'PhotoWatcherService');
    }

    try {
      await _photoStreamController.close();
    } catch (e) {
      developer.log('Error closing photo stream controller: $e', name: 'PhotoWatcherService');
    }

    developer.log('PhotoWatcherService disposed', name: 'PhotoWatcherService');
  }
}
