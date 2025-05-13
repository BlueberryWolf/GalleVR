import 'dart:async';
import 'dart:io';
import 'dart:developer' as developer;
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:path/path.dart' as path;

import '../../core/platform/platform_service.dart';
import '../../core/platform/platform_service_factory.dart';
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

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    // Load configuration
    _config = await _configRepository.loadConfig();

    if (_config == null || _config!.photosDirectory.isEmpty) {
      return;
    }

    // Ensure the directory exists
    final directory = Directory(_config!.photosDirectory);
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }

    // Always scan for existing photos with hardcoded extension
    await _scanExistingPhotos(_config!.photosDirectory, '.png');

    // Start watching the directory
    await _startWatching(_config!);

    // Update notification with current status
    FlutterForegroundTask.updateService(
      notificationTitle: 'GalleVR Photo Watcher',
      notificationText: 'Watching ${_config!.photosDirectory} for new photos',
    );
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    if (_config != null) {
      FlutterForegroundTask.updateService(
        notificationTitle: 'GalleVR Photo Watcher',
        notificationText: 'Watching ${_config!.photosDirectory} for new photos',
      );
    }
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    await _watcherSubscription?.cancel();
    _watcherSubscription = null;

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

        _pollingTimer?.cancel();
        _pollingTimer = null;

        await _startWatching(_config!);

        FlutterForegroundTask.updateService(
          notificationTitle: 'GalleVR Photo Watcher',
          notificationText: 'Watching ${_config!.photosDirectory} for new photos',
        );
      }
    }
  }

  // Start watching for new photos
  Future<void> _startWatching(ConfigModel config) async {
    final photosDir = config.photosDirectory;
    if (photosDir.isEmpty) {
      return;
    }

    // Start watching the directory using the platform service
    _watcherSubscription = _platformService
        .watchDirectory(photosDir)
        .listen((event) => _handleFileEvent(event, config));
  }

  // Scan for existing photos
  Future<void> _scanExistingPhotos(String directory, String extension) async {
    try {
      final dir = Directory(directory);
      if (!await dir.exists()) return;

      await for (final entity in dir.list(recursive: true)) {
        if (entity is File &&
            path.extension(entity.path).toLowerCase() == extension.toLowerCase()) {
          _handledPhotos.add(entity.path);
        }
      }
    } catch (e) {
      developer.log('Error scanning existing photos: $e', name: 'PhotoWatcherTaskHandler');
    }
  }

  // Handle file system events
  void _handleFileEvent(FileSystemEvent event, ConfigModel config) {
    if (event.type != FileSystemEvent.create &&
        event.type != FileSystemEvent.modify) {
      return;
    }

    final filePath = event.path;

    if (path.extension(filePath).toLowerCase() != '.png') {
      return;
    }

    if (_handledPhotos.contains(filePath)) {
      return;
    }

    _handledPhotos.add(filePath);
    FlutterForegroundTask.sendDataToMain({'newPhoto': filePath});

    FlutterForegroundTask.updateService(
      notificationTitle: 'GalleVR Photo Watcher',
      notificationText: 'New photo detected: ${path.basename(filePath)}',
    );
  }
}
