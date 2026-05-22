import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/config_model.dart';
import '../repositories/config_repository.dart';
import '../../core/image/image_cache_service.dart';
import '../../core/services/permission_service.dart';
import '../../core/services/windows_service.dart';
import '../../core/services/linux_service.dart';
import '../../core/services/update_service.dart';
import '../../core/audio/sound_service.dart';
import 'photo_watcher_service.dart';
import 'photo_event_service.dart';
import 'photo_processor_service.dart';
import 'log_parser_service.dart';
import 'vrchat_service.dart';
import '../repositories/photo_metadata_repository.dart';
import '../../core/isolate/isolate_worker_pool.dart';
import '../models/verification_models.dart';
import '../database/app_database.dart';

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

  // Sound service
  final SoundService soundService = SoundService();

  late final PhotoProcessorService _photoProcessorService =
      PhotoProcessorService();
  late final LogParserService _logParserService = LogParserService();

  // Permanent subscription to the photo stream
  StreamSubscription<String>? _photoProcessingSubscription;

  // VRChat service
  final VRChatService _vrchatService = VRChatService();

  // Windows service for system tray and auto-start
  WindowsService? _windowsService;
  WindowsService get windowsService => _windowsService ??= WindowsService();

  // Linux service for system tray
  LinuxService? _linuxService;
  LinuxService get linuxService => _linuxService ??= LinuxService();

  // Update service for checking new versions
  final UpdateService _updateService = UpdateService();

  // Stream controller for config changes
  final _configStreamController = StreamController<ConfigModel>.broadcast();

  // Stream of configuration changes
  Stream<ConfigModel> get configStream => _configStreamController.stream;

  // Current configuration
  ConfigModel? _config;

  // Get the current configuration
  ConfigModel? get config => _config;

  // Stream controller for auth data changes
  final _authDataStreamController = StreamController<AuthData?>.broadcast();

  // Stream of auth data changes
  Stream<AuthData?> get authDataStream => _authDataStreamController.stream;

  // Current auth data
  AuthData? _authData;

  // Get the current auth data
  AuthData? get authData => _authData;

  // Track if a TOS modal is currently being shown
  bool _isTOSModalVisible = false;

  // Check if a TOS modal is currently visible
  bool get isTOSModalVisible => _isTOSModalVisible;

  // Set the TOS modal visibility
  set isTOSModalVisible(bool value) {
    _isTOSModalVisible = value;
  }

  // Key for storing onboarding completion status
  static const String _onboardingCompleteKey = 'onboarding_complete';

  // Check if onboarding has been completed
  Future<bool> isOnboardingComplete() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_onboardingCompleteKey) ?? false;
    } catch (e) {
      developer.log(
        'Error checking onboarding status: $e',
        name: 'AppServiceManager',
      );
      return false;
    }
  }

  // Mark onboarding as complete
  Future<void> markOnboardingComplete() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_onboardingCompleteKey, true);
    } catch (e) {
      developer.log(
        'Error saving onboarding status: $e',
        name: 'AppServiceManager',
      );
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
        // Check if the verification is still valid
        final isVerified = await _vrchatService.checkVerificationStatus(
          authData,
        );

        if (!isVerified) {
          developer.log(
            'Verification is invalid, logging out user',
            name: 'AppServiceManager',
          );
          // Clear auth data if verification is invalid
          await _vrchatService.logout();
          _authData = null;
          _authDataStreamController.add(null);
        } else {
          final updatedAuthData = await _vrchatService.loadAuthData();
          _authData = updatedAuthData;
          _authDataStreamController.add(updatedAuthData);
        }
      } else {
        _authData = null;
        _authDataStreamController.add(null);
      }
    } catch (e) {
      developer.log(
        'Error checking verification status: $e',
        name: 'AppServiceManager',
      );
    }
  }

  // Initialize
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      await Future.wait([
        _configRepository.loadConfig().then((config) => _config = config),
        AppDatabase().database,
      ]).timeout(const Duration(seconds: 5), onTimeout: () => []);

      // Start the rest in the background
      _initializeBackgroundTasks();

      _isInitialized = true;
    } catch (e) {
      developer.log(
        'Error initializing AppServiceManager: $e',
        name: 'AppServiceManager',
      );
    }
  }

  Future<void> _initializeBackgroundTasks() async {
    try {
      await Future.wait([
        IsolateWorkerPool().initialize(),
        _imageCacheService.initialize(),
        soundService.initialize(),
      ]).timeout(const Duration(seconds: 10), onTimeout: () => []);

      PaintingBinding.instance.imageCache.maximumSizeBytes =
          50 * 1024 * 1024; // 50MB
      PaintingBinding.instance.imageCache.maximumSize = 50;

      // Load initial auth data
      _authData = await _vrchatService.loadAuthData();
      if (_authData != null) {
        _authDataStreamController.add(_authData);
      }

      await checkVerificationStatus();

      if (_config != null) {
        if (Platform.isWindows) {
          await windowsService.initialize(
            minimizeToTray: _config!.minimizeToTray,
            appTitle: 'GalleVR',
          );
        } else if (Platform.isLinux) {
          await linuxService.initialize(
            minimizeToTray: _config!.minimizeToTray,
            appTitle: 'GalleVR',
          );
        }
      }

      // Update service
      if (Platform.isWindows || Platform.isAndroid) {
        await _updateService.initialize();
        Future.delayed(const Duration(seconds: 2), () {
          _updateService.forceCheckForUpdates();
        });
      }

      // Start watching for photos
      if (_config != null && _config!.photosDirectory.isNotEmpty) {
        await _startPhotoWatcher();
      }
    } catch (e) {
      developer.log(
        'Error in background initialization: $e',
        name: 'AppServiceManager',
      );
    }
  }

  // Start the photo watcher service and wire up the permanent processing subscription
  Future<void> _startPhotoWatcher() async {
    if (_config == null) return;

    try {
      await photoWatcherService.startWatching(_config!);

      await _photoProcessingSubscription?.cancel();

      _photoProcessingSubscription = photoWatcherService.photoStream.listen(
        (photoPath) => _processPhotoInBackground(photoPath),
      );

      developer.log(
        'Permanent photo processing subscription active',
        name: 'AppServiceManager',
      );
    } catch (e) {
      developer.log(
        'Error starting photo watcher: $e',
        name: 'AppServiceManager',
      );
    }
  }

  // Process a photo in the background
  Future<void> _processPhotoInBackground(String photoPath) async {
    if (_config == null) return;
    try {
      developer.log(
        'Background processing photo: $photoPath',
        name: 'AppServiceManager',
      );
      final metadata = await _logParserService.getLatestLogMetadata(_config!);
      final outputPath = await _photoProcessorService.processPhoto(
        photoPath,
        _config!,
        metadata,
      );
      if (outputPath != null) {
        photoEventService.notifyPhotoAdded(photoPath);
        developer.log(
          'Background photo processed successfully: $photoPath',
          name: 'AppServiceManager',
        );

        if (Platform.isWindows && windowsService.isHidden.value) {
          await windowsService.trimMemory();
        }
      }
    } catch (e) {
      developer.log(
        'Error in background photo processing: $e',
        name: 'AppServiceManager',
      );
    }
  }

  // Update configuration and restart services if needed
  Future<void> updateConfig(ConfigModel config) async {
    final bool photosDirectoryChanged =
        _config?.photosDirectory != config.photosDirectory;
    final bool logsDirectoryChanged =
        _config?.logsDirectory != config.logsDirectory;
    final bool minimizeToTrayChanged =
        _config?.minimizeToTray != config.minimizeToTray;
    final bool startWithWindowsChanged =
        _config?.startWithWindows != config.startWithWindows;

    // Update the config
    _config = config;

    // Update Windows-specific settings if needed
    if (Platform.isWindows) {
      // Update minimize to tray setting
      if (minimizeToTrayChanged) {
        windowsService.updateMinimizeToTray(config.minimizeToTray);
      }

      // Update auto-start setting
      if (startWithWindowsChanged) {
        await windowsService.setStartWithWindows(config.startWithWindows);
      }
    } else if (Platform.isLinux) {
      if (minimizeToTrayChanged) {
        linuxService.updateMinimizeToTray(config.minimizeToTray);
      }
    }

    // Restart photo watcher if important filesystem paths changed
    if (photosDirectoryChanged || logsDirectoryChanged) {
      await _photoProcessingSubscription?.cancel();
      _photoProcessingSubscription = null;
      await photoWatcherService.stopWatching();

      if (config.photosDirectory.isNotEmpty &&
          config.logsDirectory.isNotEmpty) {
        await _startPhotoWatcher();
      }
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
        // Dispose all services first to ensure clean shutdown
        await dispose();

        // Exit the application
        await windowsService.exitApplication();
        return false; // This line will never be reached
      } else if (_config != null && _config!.minimizeToTray) {
        // Minimize to tray if enabled
        return await windowsService.handleWindowClose();
      }
    } else if (Platform.isLinux) {
      if (forceExit) {
        await dispose();
        await linuxService.exitApplication();
        return false;
      } else if (_config != null && _config!.minimizeToTray) {
        return await linuxService.handleWindowClose();
      }
    }
    return false;
  }

  // Dispose all services
  Future<void> dispose() async {
    try {
      IsolateWorkerPool().dispose();
    } catch (e) {
      developer.log(
        'Error disposing isolate worker pool: $e',
        name: 'AppServiceManager',
      );
    }

    try {
      // Stop foreground tasks first
      await FlutterForegroundTask.stopService();
    } catch (e) {
      developer.log(
        'Error stopping foreground tasks: $e',
        name: 'AppServiceManager',
      );
    }

    try {
      await _photoProcessingSubscription?.cancel();
      _photoProcessingSubscription = null;
    } catch (e) {
      developer.log(
        'Error cancelling photo processing subscription: $e',
        name: 'AppServiceManager',
      );
    }

    try {
      await photoWatcherService.dispose();
    } catch (e) {
      developer.log(
        'Error disposing photo watcher service: $e',
        name: 'AppServiceManager',
      );
    }

    try {
      soundService.dispose();
    } catch (e) {
      developer.log(
        'Error disposing sound service: $e',
        name: 'AppServiceManager',
      );
    }

    // Dispose platform services
    if (Platform.isWindows) {
      try {
        _windowsService?.dispose();
      } catch (e) {
        developer.log(
          'Error disposing Windows service: $e',
          name: 'AppServiceManager',
        );
      }
    } else if (Platform.isLinux) {
      try {
        _linuxService?.dispose();
      } catch (e) {
        developer.log(
          'Error disposing Linux service: $e',
          name: 'AppServiceManager',
        );
      }
    }

    try {
      await _configStreamController.close();
      await _authDataStreamController.close();
    } catch (e) {
      developer.log(
        'Error closing stream controllers: $e',
        name: 'AppServiceManager',
      );
    }

    try {
      await _imageCacheService.clearCache();
    } catch (e) {
      developer.log(
        'Error clearing image cache: $e',
        name: 'AppServiceManager',
      );
    }



    // Dispose update service
    try {
      await _updateService.dispose();
    } catch (e) {
      developer.log(
        'Error disposing update service: $e',
        name: 'AppServiceManager',
      );
    }
  }
}
