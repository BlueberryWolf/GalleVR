import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;

import '../../core/platform/platform_service.dart';
import '../../core/platform/platform_service_factory.dart';
import '../models/config_model.dart';

// Repository for managing application configuration
class ConfigRepository {
  final PlatformService _platformService;

  // Default constructor
  ConfigRepository({PlatformService? platformService})
      : _platformService = platformService ?? PlatformServiceFactory.getPlatformService();

  // Load configuration from disk
  Future<ConfigModel> loadConfig() async {
    try {
      final configDir = await _platformService.getConfigDirectory();
      final configFile = File(path.join(configDir, 'config.json'));

      if (!await configFile.exists()) {
        // If config file doesn't exist, create default config
        return _createDefaultConfig();
      }

      final jsonString = await configFile.readAsString();
      final jsonMap = json.decode(jsonString) as Map<String, dynamic>;

      return ConfigModel.fromJson(jsonMap);
    } catch (e) {
      // If there's an error loading the config, return default config
      return _createDefaultConfig();
    }
  }

  // Save configuration to disk
  Future<void> saveConfig(ConfigModel config) async {
    try {
      final configDir = await _platformService.getConfigDirectory();
      final configFile = File(path.join(configDir, 'config.json'));

      final jsonString = json.encode(config.toJson());
      await configFile.writeAsString(jsonString);
    } catch (e) {
      // Handle error (could throw or log)
      debugPrint('Error saving config: $e');
    }
  }

  // Create default configuration with platform-specific paths
  Future<ConfigModel> _createDefaultConfig() async {
    final photosDir = await _platformService.getPhotosDirectory();
    final logsDir = await _platformService.getLogsDirectory();

    return ConfigModel(
      photosDirectory: photosDir,
      logsDirectory: logsDir,
      uploadEnabled: true,
    );
  }
}
