import 'dart:async';
import 'dart:io';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:path/path.dart' as path;
import 'dart:developer' as developer;

import '../../core/platform/platform_service.dart';
import '../../core/platform/platform_service_factory.dart';
import '../models/config_model.dart';
import 'photo_event_service.dart';
import 'photo_watcher_task_handler.dart';

class PhotoWatcherService {
  final PlatformService _platformService;

  final _photoStreamController = StreamController<String>.broadcast();

  Stream<String> get photoStream => _photoStreamController.stream;

  final Set<String> _handledPhotos = {};

  StreamSubscription<FileSystemEvent>? _watcherSubscription;

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
        notificationText: 'Watching ${config.photosDirectory} for new photos',
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
          notificationText: 'Watching ${config.photosDirectory} for new photos',
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

    final photosDir = config.photosDirectory;
    if (photosDir.isEmpty) {
      final error = 'Photos directory is not set';
      developer.log(error, name: 'PhotoWatcherService');
      PhotoEventService().notifyError('watcher', error);
      throw Exception(error);
    }

    final directory = Directory(photosDir);
    try {
      if (!await directory.exists()) {
        developer.log(
          'Creating photos directory: $photosDir',
          name: 'PhotoWatcherService',
        );
        await directory.create(recursive: true);
        PhotoEventService().notifyError(
          'info',
          'Created photos directory: $photosDir',
        );
      }
    } catch (e) {
      final error = 'Failed to create photos directory: $e';
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
        'Using in-app watcher for photo watching',
        name: 'PhotoWatcherService',
      );

      try {
        await _scanExistingPhotos(photosDir, '.png');
      } catch (e) {
        final error = 'Error scanning existing photos: $e';
        developer.log(error, name: 'PhotoWatcherService');
        PhotoEventService().notifyError('watcher', error);
      }

      try {
        _watcherSubscription = _platformService
            .watchDirectory(photosDir)
            .listen(
              (event) => _handleFileEvent(event, config),
              onError: (e) {
                final error = 'Error in directory watcher: $e';
                developer.log(error, name: 'PhotoWatcherService');
                PhotoEventService().notifyError('watcher', error);
              },
            );
        developer.log(
          'Directory watcher started successfully',
          name: 'PhotoWatcherService',
        );
        PhotoEventService().notifyError(
          'info',
          'Directory watcher started successfully',
        );
      } catch (e) {
        final error = 'Failed to start directory watcher: $e';
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
  }

  Future<void> _scanExistingPhotos(String directory, String extension) async {
    try {
      final dir = Directory(directory);
      if (!await dir.exists()) {
        developer.log(
          'Directory does not exist: $directory',
          name: 'PhotoWatcherService',
        );
        PhotoEventService().notifyError(
          'watcher',
          'Directory does not exist: $directory',
        );
        return;
      }

      developer.log(
        'Scanning for existing photos in $directory',
        name: 'PhotoWatcherService',
      );
      int count = 0;

      await for (final entity in dir.list(recursive: true)) {
        if (entity is File &&
            path.extension(entity.path).toLowerCase() ==
                extension.toLowerCase()) {
          _handledPhotos.add(entity.path);
          count++;
        }
      }

      developer.log(
        'Found $count existing photos in $directory',
        name: 'PhotoWatcherService',
      );
      if (count > 0) {
        PhotoEventService().notifyError(
          'info',
          'Found $count existing photos in directory',
        );
      }
    } catch (e) {
      final error = 'Error scanning existing photos: $e';
      developer.log(error, name: 'PhotoWatcherService');
      PhotoEventService().notifyError('watcher', error);
      rethrow;
    }
  }

  void _handleFileEvent(FileSystemEvent event, ConfigModel config) {
    final filePath = event.path;

    if (event.type != FileSystemEvent.create &&
        event.type != FileSystemEvent.modify) {
      developer.log(
        'Ignoring non-create/modify event: ${event.type} for $filePath',
        name: 'PhotoWatcherService',
      );
      return;
    }

    if (path.extension(filePath).toLowerCase() != '.png') {
      developer.log(
        'Ignoring non-PNG file: $filePath',
        name: 'PhotoWatcherService',
      );
      return;
    }

    if (_handledPhotos.contains(filePath)) {
      developer.log(
        'Ignoring already handled photo: $filePath',
        name: 'PhotoWatcherService',
      );
      return;
    }

    _handledPhotos.add(filePath);

    developer.log('New photo detected: $filePath', name: 'PhotoWatcherService');
    PhotoEventService().notifyError(
      'info',
      'New photo detected: ${path.basename(filePath)}',
    );

    _photoStreamController.add(filePath);
    PhotoEventService().notifyPhotoAdded(filePath);
  }

  void dispose() async {
    if (_useForegroundService && _isForegroundServiceRunning) {
      await _stopForegroundService();
    }

    FlutterForegroundTask.removeTaskDataCallback(_onReceiveTaskData);
    await _watcherSubscription?.cancel();
    _photoStreamController.close();
  }
}
