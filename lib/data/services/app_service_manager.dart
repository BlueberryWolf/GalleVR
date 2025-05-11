import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/config_model.dart';
import '../repositories/config_repository.dart';
import '../../core/image/image_cache_service.dart';
import '../../core/services/permission_service.dart';
import '../../core/audio/sound_service.dart';
import 'photo_watcher_service.dart';
import 'photo_event_service.dart';
import 'vrchat_service.dart';

// Singleton service manager for the application
// Manages global services that should run throughout the app lifecycle
class AppServiceManager {
  // Singleton instance
  static final AppServiceManager _instance = AppServiceManager._internal();

  // Factory constructor to return the singleton instance
  factory AppServiceManager() {
    return _instance;
  }

  // Private constructor for singleton
  AppServiceManager._internal();

  // Flag to track if services have been initialized
  bool _isInitialized = false;

  // Config repository
  final ConfigRepository _configRepository = ConfigRepository();

  // Photo watcher service
  final PhotoWatcherService photoWatcherService = PhotoWatcherService();

  // Photo event service
  final PhotoEventService _photoEventService = PhotoEventService();

  // Image cache service
  final ImageCacheService _imageCacheService = ImageCacheService();

  // Permission service
  final PermissionService _permissionService = PermissionService();

  // Sound service
  final SoundService soundService = SoundService();

  // VRChat service
  final VRChatService _vrchatService = VRChatService();

  // Stream controller for config changes
  final _configStreamController = StreamController<ConfigModel>.broadcast();

  // Stream of configuration changes
  Stream<ConfigModel> get configStream => _configStreamController.stream;

  // Current configuration
  ConfigModel? _config;

  // Get the current configuration
  ConfigModel? get config => _config;

  // Key for storing onboarding completion status
  static const String _onboardingCompleteKey = 'onboarding_complete';

  // Check if onboarding has been completed
  Future<bool> isOnboardingComplete() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_onboardingCompleteKey) ?? false;
    } catch (e) {
      developer.log('Error checking onboarding status: $e', name: 'AppServiceManager');
      return false;
    }
  }

  // Mark onboarding as complete
  Future<void> markOnboardingComplete() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_onboardingCompleteKey, true);
      developer.log('Onboarding marked as complete', name: 'AppServiceManager');
    } catch (e) {
      developer.log('Error saving onboarding status: $e', name: 'AppServiceManager');
    }
  }

  // Check verification status and log out if invalid
  Future<void> checkVerificationStatus() async {
    try {
      // Initialize VRChat service if needed
      await _vrchatService.initialize();

      // Check if there's saved verification data
      final authData = await _vrchatService.loadAuthData();
      if (authData != null) {
        developer.log('Checking verification status on app launch', name: 'AppServiceManager');

        // Check if the verification is still valid
        final isVerified = await _vrchatService.checkVerificationStatus(authData);

        if (!isVerified) {
          developer.log('Verification is invalid, logging out user', name: 'AppServiceManager');
          // Clear auth data if verification is invalid
          await _vrchatService.logout();
        } else {
          developer.log('Verification is valid', name: 'AppServiceManager');
        }
      }
    } catch (e) {
      developer.log('Error checking verification status: $e', name: 'AppServiceManager');
    }
  }

  // Initialize all application services
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // Request permissions on Android at startup
      if (Platform.isAndroid) {
        developer.log('Requesting permissions at app startup', name: 'AppServiceManager');
        final hasPermissions = await _permissionService.requestStoragePermissionsOnStartup();
        developer.log('Permission request result: $hasPermissions', name: 'AppServiceManager');
      }

      // Initialize image cache service
      await _imageCacheService.initialize();
      developer.log('Image cache service initialized', name: 'AppServiceManager');

      // Initialize sound service
      await soundService.initialize();
      developer.log('Sound service initialized', name: 'AppServiceManager');

      // Load configuration
      _config = await _configRepository.loadConfig();

      // Check verification status
      await checkVerificationStatus();

      // Start watching for photos if directory is set
      if (_config != null && _config!.photosDirectory.isNotEmpty) {
        await _startPhotoWatcher();
      }

      _isInitialized = true;
      developer.log('AppServiceManager initialized successfully', name: 'AppServiceManager');
    } catch (e) {
      developer.log('Error initializing AppServiceManager: $e', name: 'AppServiceManager');
    }
  }

  // Start the photo watcher service
  Future<void> _startPhotoWatcher() async {
    if (_config == null) return;

    try {
      await photoWatcherService.startWatching(_config!);
      developer.log('Photo watcher started', name: 'AppServiceManager');
    } catch (e) {
      developer.log('Error starting photo watcher: $e', name: 'AppServiceManager');
    }
  }

  // Update configuration and restart services if needed
  Future<void> updateConfig(ConfigModel config) async {
    final bool photosDirectoryChanged = _config?.photosDirectory != config.photosDirectory;

    // Update the config
    _config = config;

    // Restart photo watcher if photos directory changed
    if (photosDirectoryChanged) {
      developer.log('Photos directory changed, restarting watcher', name: 'AppServiceManager');
      if (config.photosDirectory.isNotEmpty) {
        await photoWatcherService.stopWatching();
        await _startPhotoWatcher();
      } else {
        await photoWatcherService.stopWatching();
      }
    } else if (_config?.photosDirectory.isNotEmpty == true) {
      // If other settings changed but photos directory is still set, restart the watcher
      // to ensure it picks up the new configuration
      developer.log('Configuration changed, restarting watcher with new settings', name: 'AppServiceManager');
      await photoWatcherService.stopWatching();
      await _startPhotoWatcher();
    }

    // Notify listeners about the config change
    _configStreamController.add(config);
  }

  // Dispose all services
  Future<void> dispose() async {
    photoWatcherService.dispose();
    soundService.dispose();
    await _configStreamController.close();
    await _imageCacheService.clearCache();

    // Logout from VRChat service if needed
    try {
      await _vrchatService.logout();
    } catch (e) {
      developer.log('Error during VRChat logout on dispose: $e', name: 'AppServiceManager');
    }
  }
}
