import 'dart:async';
import 'dart:io';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:path/path.dart' as path;
import 'dart:developer' as developer;

import '../../core/platform/platform_service.dart';
import '../../core/platform/platform_service_factory.dart';
import '../../core/utils/log_file_watcher.dart';
import '../../core/utils/resonite_dir_watcher.dart';
import '../../core/utils/screenshot_utils.dart';
import '../models/config_model.dart';
import '../repositories/config_repository.dart';
import 'app_service_manager.dart';
import 'photo_event_service.dart';
import 'photo_watcher_task_handler.dart';
import 'vrchat_service.dart';

class PhotoWatcherService {
  final PlatformService _platformService;

  final _photoStreamController = StreamController<String>.broadcast();

  Stream<String> get photoStream => _photoStreamController.stream;

  final Set<String> _handledPhotos = {};

  StreamSubscription<FileSystemEvent>? _vrcWatcherSubscription;
  StreamSubscription<String>? _logWatcherSubscription;
  StreamSubscription<String>? _resoniteDirWatcherSubscription;
  ResoniteDirWatcher? _resoniteDirWatcher;
  LogFileWatcher? _logFileWatcher;

  bool _isForegroundServiceRunning = false;

  bool _useForegroundService = false;

  PhotoWatcherService({PlatformService? platformService})
    : _platformService =
          platformService ?? PlatformServiceFactory.getPlatformService() {
    FlutterForegroundTask.addTaskDataCallback(_onReceiveTaskData);
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
    if (data is Map<String, dynamic>) {
      if (data.containsKey('newPhoto')) {
        final photoPath = data['newPhoto'] as String;
        _handledPhotos.add(photoPath);
        _photoStreamController.add(photoPath);
        PhotoEventService().notifyPhotoAdded(photoPath);
      } else if (data['action'] == 'configAligned') {
        final newPhotosDir = data['photosDirectory'] as String;
        developer.log(
          'Received config alignment from background task: $newPhotosDir',
          name: 'PhotoWatcherService',
        );
        final currentConfig = AppServiceManager().config;
        if (currentConfig != null) {
          final updatedConfig = currentConfig.copyWith(
            photosDirectory: newPhotosDir,
          );
          ConfigRepository().saveConfig(updatedConfig).then((_) {
            AppServiceManager().updateConfig(updatedConfig);
          });
        }
      } else if (data.containsKey('error')) {
        final errorMessage = data['error'] as String;
        developer.log(
          'Error from background task: $errorMessage',
          name: 'PhotoWatcherService',
        );
        PhotoEventService().notifyError('watcher', errorMessage);
      } else if (data.containsKey('status')) {
        final statusMessage = data['status'] as String;
        developer.log(
          'Status from background task: $statusMessage',
          name: 'PhotoWatcherService',
        );
        PhotoEventService().notifyError('info', statusMessage);
      }
    }
  }

  Future<void> startWatching(ConfigModel config) async {
    developer.log(
      'Starting photo watcher service',
      name: 'PhotoWatcherService',
    );

    await _resoniteDirWatcherSubscription?.cancel();
    _resoniteDirWatcherSubscription = null;
    await _resoniteDirWatcher?.stopWatching();
    _resoniteDirWatcher = null;
    await _vrcWatcherSubscription?.cancel();
    _vrcWatcherSubscription = null;
    await _logWatcherSubscription?.cancel();
    _logWatcherSubscription = null;
    await _logFileWatcher?.stopWatching();
    _logFileWatcher = null;

    final resoniteDir = config.resonitePhotosDirectory;
    if (resoniteDir.isNotEmpty) {
      try {
        _resoniteDirWatcher = ResoniteDirWatcher(resoniteDir);
        await _resoniteDirWatcher!.startWatching();
        _resoniteDirWatcherSubscription = _resoniteDirWatcher!.photoStream.listen(
          (photoPath) => _handleResonitePhoto(photoPath, config),
        );
        developer.log(
          'Resonite photo watcher (polling) started on: $resoniteDir',
          name: 'PhotoWatcherService',
        );
      } catch (e) {
        developer.log(
          'Failed to start Resonite dir watcher: $e',
          name: 'PhotoWatcherService',
        );
      }
    }

    final logsDir = config.logsDirectory;
    if (logsDir.isNotEmpty) {
      final directory = Directory(logsDir);
      try {
        if (await directory.exists()) {
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
                (screenshotPath) =>
                    _handleScreenshotFromLog(screenshotPath, config),
                onError: (e) {
                  final error = 'Error in log file watcher: $e';
                  developer.log(error, name: 'PhotoWatcherService');
                  PhotoEventService().notifyError('watcher', error);
                },
              );

              try {
                final photosDir = Directory(config.photosDirectory);
                if (await photosDir.exists()) {
                  _vrcWatcherSubscription = photosDir
                      .watch(events: FileSystemEvent.create, recursive: true)
                      .listen((event) {
                        developer.log(
                          'Native Photos trigger detected: ${event.path}, signaling immediate log check',
                          name: 'PhotoWatcherService',
                        );
                        _logFileWatcher?.checkForUpdates();
                      });
                  developer.log(
                    'Native OS Photo Trigger active (recursive)',
                    name: 'PhotoWatcherService',
                  );
                }
              } catch (e) {
                developer.log(
                  'Native Photo Trigger initialization bypassed ($e), relying solely on polling mode',
                  name: 'PhotoWatcherService',
                );
              }

              developer.log(
                'Log file watcher started successfully',
                name: 'PhotoWatcherService',
              );
            } catch (e) {
              final error = 'Failed to start log file watcher: $e';
              developer.log(error, name: 'PhotoWatcherService');
              PhotoEventService().notifyError('watcher', error);
              throw Exception(error);
            }
          }
        }
      } catch (e) {
        final error = 'Failed to access logs directory: $e';
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

    await _resoniteDirWatcherSubscription?.cancel();
    _resoniteDirWatcherSubscription = null;
    await _resoniteDirWatcher?.stopWatching();
    _resoniteDirWatcher = null;
    await _vrcWatcherSubscription?.cancel();
    _vrcWatcherSubscription = null;

    await _logWatcherSubscription?.cancel();
    _logWatcherSubscription = null;

    await _logFileWatcher?.stopWatching();
    _logFileWatcher = null;
  }

  Future<void> _handleScreenshotFromLog(
    String screenshotPath,
    ConfigModel config,
  ) async {
    String finalPath = ScreenshotUtils.translatePlatformPath(screenshotPath, config.photosDirectory);

    // Verify the file exists and is a VRChat screenshot
    final file = File(finalPath);
    final ready = await ScreenshotUtils.waitForFileReady(file, maxAttempts: 25);

    if (!ready) {
      developer.log(
        'Screenshot file is not ready or does not exist: $finalPath',
        name: 'PhotoWatcherService',
      );
      return;
    }

    if (!ScreenshotUtils.isVRChatScreenshot(finalPath)) {
      developer.log(
        'Ignoring non-VRChat screenshot: $finalPath',
        name: 'PhotoWatcherService',
      );
      return;
    }

    final String screenshotDir = path.dirname(path.dirname(finalPath));

    final String canonicalConfigDir = path.canonicalize(config.photosDirectory);
    final String canonicalScreenshotDir = path.canonicalize(screenshotDir);

    if (canonicalConfigDir != canonicalScreenshotDir) {
      developer.log(
        'Photos directory mismatch detected! Config: ${config.photosDirectory}, actual: $screenshotDir. Aligning settings...',
        name: 'PhotoWatcherService',
      );
      try {
        final updatedConfig = config.copyWith(photosDirectory: screenshotDir);
        await ConfigRepository().saveConfig(updatedConfig);
        await AppServiceManager().updateConfig(updatedConfig);
      } catch (e) {
        developer.log(
          'Error updating photos directory configuration: $e',
          name: 'PhotoWatcherService',
        );
      }
    }

    if (_handledPhotos.contains(finalPath)) {
      developer.log(
        'Ignoring already handled photo: $finalPath',
        name: 'PhotoWatcherService',
      );
      return;
    }

    _handledPhotos.add(finalPath);

    developer.log(
      'New screenshot detected from log: $finalPath',
      name: 'PhotoWatcherService',
    );
    PhotoEventService().notifyError(
      'info',
      'New screenshot detected: ${path.basename(finalPath)}',
    );

    _photoStreamController.add(finalPath);
  }

  Future<void> _handleResonitePhoto(
    String photoPath,
    ConfigModel config,
  ) async {
    if (_handledPhotos.contains(photoPath)) return;

    // Wait for the file to be fully written before processing.
    final file = File(photoPath);
    final ready = await ScreenshotUtils.waitForFileReady(file, maxAttempts: 15);
    if (!ready) return;

    _handledPhotos.add(photoPath);
    developer.log('New Resonite screenshot detected: $photoPath', name: 'PhotoWatcherService');
    PhotoEventService().notifyError('info', 'New Resonite screenshot detected: ${path.basename(photoPath)}');
    _photoStreamController.add(photoPath);
  }

  Future<void> dispose() async {
    developer.log('Disposing PhotoWatcherService', name: 'PhotoWatcherService');

    try {
      developer.log('Stopping foreground service', name: 'PhotoWatcherService');
      await FlutterForegroundTask.stopService();
      _isForegroundServiceRunning = false;
    } catch (e) {
      developer.log(
        'Error stopping foreground service: $e',
        name: 'PhotoWatcherService',
      );
    }

    try {
      FlutterForegroundTask.removeTaskDataCallback(_onReceiveTaskData);
    } catch (e) {
      developer.log(
        'Error removing task data callback: $e',
        name: 'PhotoWatcherService',
      );
    }

    try {
      await _resoniteDirWatcherSubscription?.cancel();
      _resoniteDirWatcherSubscription = null;
      await _resoniteDirWatcher?.stopWatching();
      _resoniteDirWatcher = null;
      await _vrcWatcherSubscription?.cancel();
      _vrcWatcherSubscription = null;
    } catch (e) {
      developer.log(
        'Error cancelling watcher subscription: $e',
        name: 'PhotoWatcherService',
      );
    }

    try {
      await _logWatcherSubscription?.cancel();
      _logWatcherSubscription = null;
    } catch (e) {
      developer.log(
        'Error cancelling log watcher subscription: $e',
        name: 'PhotoWatcherService',
      );
    }

    try {
      await _logFileWatcher?.stopWatching();
      _logFileWatcher?.dispose();
      _logFileWatcher = null;
    } catch (e) {
      developer.log(
        'Error disposing log file watcher: $e',
        name: 'PhotoWatcherService',
      );
    }

    try {
      await _photoStreamController.close();
    } catch (e) {
      developer.log(
        'Error closing photo stream controller: $e',
        name: 'PhotoWatcherService',
      );
    }

    developer.log('PhotoWatcherService disposed', name: 'PhotoWatcherService');
  }
}
