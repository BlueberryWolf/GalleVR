import 'dart:async';
import 'dart:io';
import 'dart:developer' as developer;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import 'platform_service.dart';

class AndroidPlatformService implements PlatformService {
  @override
  PlatformType getPlatformType() => PlatformType.android;

  @override
  Future<String> getPhotosDirectory() async {
    try {
      final Directory? externalDir = await getExternalStorageDirectory();
      if (externalDir == null) {
        throw Exception('External storage not available');
      }

      String externalPath = externalDir.path;
      while (path.basename(externalPath) != 'Android' &&
          path.dirname(externalPath) != externalPath) {
        externalPath = path.dirname(externalPath);
      }
      externalPath = path.dirname(externalPath);

      final String vrchatPath = path.join(externalPath, 'Pictures', 'VRChat');

      developer.log(
        'Using VRChat photos directory: $vrchatPath',
        name: 'AndroidPlatformService',
      );

      final Directory vrchatDir = Directory(vrchatPath);
      if (!await vrchatDir.exists()) {
        await vrchatDir.create(recursive: true);
      }

      return vrchatPath;
    } catch (e) {
      developer.log(
        'Error getting photos directory: $e',
        name: 'AndroidPlatformService',
      );

      final Directory cacheDir = await getTemporaryDirectory();
      final String vrchatPath = path.join(cacheDir.path, 'GalleVR', 'Photos');

      developer.log(
        'Using fallback VRChat photos directory: $vrchatPath',
        name: 'AndroidPlatformService',
      );

      final Directory vrchatDir = Directory(vrchatPath);
      if (!await vrchatDir.exists()) {
        await vrchatDir.create(recursive: true);
      }

      return vrchatPath;
    }
  }

  @override
  Future<String> getLogsDirectory() async {
    try {
      final Directory? externalDir = await getExternalStorageDirectory();
      if (externalDir == null) {
        throw Exception('External storage not available');
      }

      String externalPath = externalDir.path;
      while (path.basename(externalPath) != 'Android' &&
          path.dirname(externalPath) != externalPath) {
        externalPath = path.dirname(externalPath);
      }
      externalPath = path.dirname(externalPath);

      final String logsPath = path.join(externalPath, 'Documents', 'Logs');
      return logsPath;
    } catch (e) {
      developer.log(
        'Error getting logs directory: $e',
        name: 'AndroidPlatformService',
      );
      return '';
    }
  }

  @override
  Future<String> getConfigDirectory() async {
    try {
      final Directory appDir = await getApplicationSupportDirectory();
      final String configPath = path.join(appDir.path, 'GalleVR');

      final Directory configDir = Directory(configPath);
      if (!await configDir.exists()) {
        await configDir.create(recursive: true);
      }

      return configPath;
    } catch (e) {
      final Directory cacheDir = await getTemporaryDirectory();
      final String configPath = path.join(cacheDir.path, 'GalleVR');

      final Directory configDir = Directory(configPath);
      if (!await configDir.exists()) {
        await configDir.create(recursive: true);
      }

      return configPath;
    }
  }

  @override
  Stream<FileSystemEvent> watchDirectory(String directoryPath) {
    final controller = StreamController<FileSystemEvent>.broadcast();

    final knownFiles = <String, DateTime>{};

    Timer.periodic(const Duration(seconds: 2), (timer) async {
      try {
        final directory = Directory(directoryPath);
        if (!await directory.exists()) {
          return;
        }

        final currentFiles = <String, DateTime>{};
        await for (final entity in directory.list(recursive: true)) {
          if (entity is File) {
            final stat = await entity.stat();
            currentFiles[entity.path] = stat.modified;
          }
        }

        for (final entry in currentFiles.entries) {
          final path = entry.key;
          final modTime = entry.value;

          if (!knownFiles.containsKey(path)) {
            controller.add(FileSystemCreateEvent(path, false));
          } else if (knownFiles[path] != modTime) {
            controller.add(FileSystemModifyEvent(path, false, false));
          }
        }

        for (final path in knownFiles.keys) {
          if (!currentFiles.containsKey(path)) {
            controller.add(FileSystemDeleteEvent(path, false));
          }
        }

        knownFiles.clear();
        knownFiles.addAll(currentFiles);
      } catch (e) {
        developer.log(
          'Error in directory watcher: $e',
          name: 'AndroidPlatformService',
        );
      }
    });

    return controller.stream;
  }
}
