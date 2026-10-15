import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'package:path/path.dart' as path;

import '../../core/platform/platform_service.dart';
import '../../core/platform/platform_service_factory.dart';
import '../models/config_model.dart';

class ConfigRepository {
  final PlatformService _platformService;

  ConfigRepository({PlatformService? platformService})
    : _platformService =
          platformService ?? PlatformServiceFactory.getPlatformService();

  Future<ConfigModel> loadConfig() async {
    try {
      final configDir = await _platformService.getConfigDirectory();
      final configFile = File(path.join(configDir, 'config.json'));

      if (!await configFile.exists()) {
        return _createDefaultConfig();
      }

      final jsonString = await configFile.readAsString();
      final jsonMap = json.decode(jsonString) as Map<String, dynamic>;

      final loaded = ConfigModel.fromJson(jsonMap);
      if (loaded.resonitePhotosDirectory.isEmpty) {
        final resonitePhotosDir =
            await _platformService.getResonitePhotosDirectory();
        final updated = loaded.copyWith(
          resonitePhotosDirectory: resonitePhotosDir,
        );
        await saveConfig(updated);
        return updated;
      }
      return loaded;
    } catch (e) {
      return _createDefaultConfig();
    }
  }

  Future<void> saveConfig(ConfigModel config) async {
    try {
      final configDir = await _platformService.getConfigDirectory();
      final configFile = File(path.join(configDir, 'config.json'));

      final jsonString = json.encode(config.toJson());
      await configFile.writeAsString(jsonString);
    } catch (e) {
      developer.log('Error saving config: $e', name: 'ConfigRepository');
    }
  }

  Future<ConfigModel> _createDefaultConfig() async {
    final photosDir = await _platformService.getPhotosDirectory();
    final logsDir = await _platformService.getLogsDirectory();
    final resonitePhotosDir =
        await _platformService.getResonitePhotosDirectory();

    return ConfigModel(
      photosDirectory: photosDir,
      logsDirectory: logsDir,
      resonitePhotosDirectory: resonitePhotosDir,
      uploadEnabled: true,
    );
  }
}
