import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/config_model.dart';
import '../repositories/config_repository.dart';
import '../../core/image/image_cache_service.dart';
import '../../core/services/permission_service.dart';
import '../../core/services/windows_service.dart';
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

  // Photo event service - used by other services
  final PhotoEventService photoEventService = PhotoEventService();

  // Image cache service
  final ImageCacheService _imageCacheService = ImageCacheService();

  // Permission service
  final PermissionService _permissionService = PermissionService();

  // Sound service
  final SoundService soundService = SoundService();

  // VRChat service
  final VRChatService _vrchatService = VRChatService();

  // Windows service for system tray and auto-start
  final WindowsService _windowsService = WindowsService();

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

      // Initialize Windows-specific services if on Windows
      if (Platform.isWindows && _config != null) {
        await _windowsService.initialize(
          minimizeToTray: _config!.minimizeToTray,
          appTitle: 'GalleVR',
        );

        // Check if auto-start setting matches registry
        final isAutoStartEnabled = await _windowsService.isStartWithWindowsEnabled();
        if (isAutoStartEnabled != _config!.startWithWindows) {
          // Update registry to match settings
          await _windowsService.setStartWithWindows(_config!.startWithWindows);
        }

        developer.log('Windows-specific services initialized', name: 'AppServiceManager');
      }

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
    final bool minimizeToTrayChanged = _config?.minimizeToTray != config.minimizeToTray;
    final bool startWithWindowsChanged = _config?.startWithWindows != config.startWithWindows;

    // Update the config
    _config = config;

    // Update Windows-specific settings if needed
    if (Platform.isWindows) {
      // Update minimize to tray setting
      if (minimizeToTrayChanged) {
        _windowsService.updateMinimizeToTray(config.minimizeToTray);
        developer.log('Updated minimize to tray setting: ${config.minimizeToTray}',
            name: 'AppServiceManager');
      }

      // Update auto-start setting
      if (startWithWindowsChanged) {
        await _windowsService.setStartWithWindows(config.startWithWindows);
        developer.log('Updated start with Windows setting: ${config.startWithWindows}',
            name: 'AppServiceManager');
      }
    }

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

  // Handle window close event
  // Returns true if the app should be minimized to tray instead of closed
  Future<bool> handleWindowClose({bool forceExit = false}) async {
    if (Platform.isWindows) {
      if (forceExit) {
        // Force exit the app
        developer.log('Force exiting application from AppServiceManager', name: 'AppServiceManager');

        // Dispose all services first to ensure clean shutdown
        developer.log('Disposing all services before exit', name: 'AppServiceManager');
        await dispose();

        // Exit the application
        await _windowsService.exitApplication();
        return false; // This line will never be reached
      } else if (_config != null && _config!.minimizeToTray) {
        // Minimize to tray if enabled
        return await _windowsService.handleWindowClose();
      }
    }
    return false;
  }

  // Dispose all services
  Future<void> dispose() async {
    developer.log('Disposing all services', name: 'AppServiceManager');

    try {
      // Stop foreground tasks first
      developer.log('Stopping foreground tasks', name: 'AppServiceManager');
      await FlutterForegroundTask.stopService();
    } catch (e) {
      developer.log('Error stopping foreground tasks: $e', name: 'AppServiceManager');
    }

    try {
      await photoWatcherService.dispose();
    } catch (e) {
      developer.log('Error disposing photo watcher service: $e', name: 'AppServiceManager');
    }

    try {
      soundService.dispose();
    } catch (e) {
      developer.log('Error disposing sound service: $e', name: 'AppServiceManager');
    }

    // Dispose Windows service if on Windows
    if (Platform.isWindows) {
      try {
        _windowsService.dispose();
      } catch (e) {
        developer.log('Error disposing Windows service: $e', name: 'AppServiceManager');
      }
    }

    try {
      await _configStreamController.close();
    } catch (e) {
      developer.log('Error closing config stream controller: $e', name: 'AppServiceManager');
    }

    try {
      await _imageCacheService.clearCache();
    } catch (e) {
      developer.log('Error clearing image cache: $e', name: 'AppServiceManager');
    }

    // Logout from VRChat service if needed
    try {
      await _vrchatService.logout();
    } catch (e) {
      developer.log('Error during VRChat logout on dispose: $e', name: 'AppServiceManager');
    }

    developer.log('All services disposed', name: 'AppServiceManager');
  }
}
