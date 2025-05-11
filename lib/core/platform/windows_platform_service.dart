import 'dart:io'
    show
        Directory,
        FileSystemCreateEvent,
        FileSystemDeleteEvent,
        FileSystemEvent,
        FileSystemModifyEvent,
        Platform;
import 'dart:developer' as developer;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:watcher/watcher.dart';

import 'platform_service.dart';

class WindowsPlatformService implements PlatformService {
  @override
  PlatformType getPlatformType() => PlatformType.windows;

  @override
  Future<String> getPhotosDirectory() async {
    try {
      final String userProfile = Platform.environment['USERPROFILE'] ?? '';
      if (userProfile.isEmpty) {
        throw Exception('Could not determine user profile directory');
      }

      final String picturesPath = path.join(userProfile, 'Pictures');

      final String vrchatPath = path.join(picturesPath, 'VRChat');
      final Directory vrchatDir = Directory(vrchatPath);
      if (!await vrchatDir.exists()) {
        await vrchatDir.create(recursive: true);
      }

      developer.log(
        'Using VRChat photos directory: $vrchatPath',
        name: 'WindowsPlatformService',
      );
      return vrchatPath;
    } catch (e) {
      developer.log(
        'Error getting photos directory: $e',
        name: 'WindowsPlatformService',
      );

      try {
        final Directory tempDir = await getTemporaryDirectory();
        final String vrchatPath = path.join(tempDir.path, 'VRChat');

        final Directory vrchatDir = Directory(vrchatPath);
        if (!await vrchatDir.exists()) {
          await vrchatDir.create(recursive: true);
        }

        developer.log(
          'Using fallback VRChat photos directory: $vrchatPath',
          name: 'WindowsPlatformService',
        );
        return vrchatPath;
      } catch (innerError) {
        developer.log(
          'Error getting fallback photos directory: $innerError',
          name: 'WindowsPlatformService',
        );

        final String fallbackPath = path.join(Directory.current.path, 'VRChat');
        developer.log(
          'Using last resort VRChat photos directory: $fallbackPath',
          name: 'WindowsPlatformService',
        );
        return fallbackPath;
      }
    }
  }

  @override
  Future<String> getLogsDirectory() async {
    try {
      final String appData = Platform.environment['APPDATA'] ?? '';
      if (appData.isEmpty) {
        throw Exception('APPDATA environment variable not found');
      }

      final String logsPath = path.join(
        path.dirname(appData),
        'LocalLow',
        'VRChat',
        'VRChat',
      );

      return logsPath;
    } catch (e) {
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
      final Directory tempDir = await getTemporaryDirectory();
      final String configPath = path.join(tempDir.path, 'GalleVR');

      final Directory configDir = Directory(configPath);
      if (!await configDir.exists()) {
        await configDir.create(recursive: true);
      }

      return configPath;
    }
  }

  @override
  Stream<FileSystemEvent> watchDirectory(String directoryPath) {
    final watcher = DirectoryWatcher(directoryPath);

    return watcher.events.map((event) {
      final path = event.path;

      switch (event.type) {
        case ChangeType.ADD:
          return FileSystemCreateEvent(path, false);
        case ChangeType.MODIFY:
          return FileSystemModifyEvent(path, false, false);
        case ChangeType.REMOVE:
          return FileSystemDeleteEvent(path, false);
        default:
          return FileSystemCreateEvent(path, false);
      }
    });
  }
}
