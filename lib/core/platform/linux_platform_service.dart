import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:watcher/watcher.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:developer' as developer;

import 'platform_service.dart';

class LinuxPlatformService implements PlatformService {
  @override
  PlatformType getPlatformType() => PlatformType.linux;

  @override
  Future<String> getPhotosDirectory() async {
    final vrcPath = await _findVRChatCompatDataPath();
    if (vrcPath != null) {
      final photosPath = path.join(vrcPath, 'pfx', 'drive_c', 'users', 'steamuser', 'Pictures', 'VRChat');
      final dir = Directory(photosPath);
      if (!await dir.exists()) {
          await dir.create(recursive: true);
      }
      return photosPath;
    }
    return '';
  }

  @override
  Future<String> getLogsDirectory() async {
    final vrcPath = await _findVRChatCompatDataPath();
    if (vrcPath != null) {
      final logsPath = path.join(vrcPath, 'pfx', 'drive_c', 'users', 'steamuser', 'AppData', 'LocalLow', 'VRChat', 'VRChat');
      final dir = Directory(logsPath);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      return logsPath;
    }
    return '';
  }

  @override
  Future<String> getConfigDirectory() async {
    final ConfigPath = Platform.environment['XDG_CONFIG_HOME'] ?? path.join(Platform.environment['HOME'] ?? '', '.config');
    final configDir = path.join(ConfigPath, 'GalleVR');
    final dir = Directory(configDir);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return configDir;
  }

  @override
  Stream<FileSystemEvent> watchDirectory(String directoryPath) {
    final watcher = DirectoryWatcher(directoryPath);

    return watcher.events.map((event) {
      final eventPath = event.path;

      switch (event.type) {
        case ChangeType.ADD:
          return FileSystemCreateEvent(eventPath, false);
        case ChangeType.MODIFY:
          return FileSystemModifyEvent(eventPath, false, false);
        case ChangeType.REMOVE:
          return FileSystemDeleteEvent(eventPath, false);
        default:
          return FileSystemCreateEvent(eventPath, false);
      }
    });
  }

  Future<String?> _findVRChatCompatDataPath() async {
    final home = Platform.environment['HOME'] ?? '';
    if (home.isEmpty) return null;

    final possibleSteamRoots = [
      path.join(home, '.local', 'share', 'Steam'),
      path.join(home, '.steam', 'root'),
      path.join(home, '.steam', 'steam'),
      path.join(home, '.var', 'app', 'com.valvesoftware.Steam', '.local', 'share', 'Steam'),
    ];

    for (final steamRoot in possibleSteamRoots) {
      final libraryFoldersPath = path.join(steamRoot, 'steamapps', 'libraryfolders.vdf');
      
      File vdfFile = File(libraryFoldersPath);
      if (!await vdfFile.exists()) {
        final altLibraryFoldersPath = path.join(steamRoot, 'config', 'libraryfolders.vdf');
        vdfFile = File(altLibraryFoldersPath);
        if (!await vdfFile.exists()) {
          continue;
        }
      }

      try {
        final content = await vdfFile.readAsString();
        
        // very basic parsing for library paths
        final pathRegex = RegExp(r'"path"\s+"([^"]+)"');
        final matches = pathRegex.allMatches(content);
        
        for (final match in matches) {
          final libraryPath = match.group(1);
          if (libraryPath != null) {
            // check if vrchat (438100) is in this library
            final vrcCompatDataPath = path.join(libraryPath, 'steamapps', 'compatdata', '438100');
            final vrcDir = Directory(vrcCompatDataPath);
            if (await vrcDir.exists()) {
              developer.log('Found VRChat compatdata at: $vrcCompatDataPath', name: 'LinuxPlatformService');
              return vrcCompatDataPath;
            }
          }
        }
      } catch (e) {
        developer.log('Error reading or parsing libraryfolders.vdf: $e', name: 'LinuxPlatformService');
      }
    }
    
    return null;
  }
}
