import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as path;

import '../models/config_model.dart';
import '../repositories/config_repository.dart';
import '../../core/image/image_cache_service.dart';
import '../../core/services/windows_service.dart';
import '../../core/services/linux_service.dart';
import '../../core/services/update_service.dart';
import '../../core/audio/sound_service.dart';
import 'photo_watcher_service.dart';
import 'photo_event_service.dart';
import 'photo_processor_service.dart';
import 'log_parser_service.dart';
import 'vrchat_service.dart';
import '../../core/isolate/isolate_worker_pool.dart';
import '../models/verification_models.dart';
import '../database/app_database.dart';
import '../../core/platform/platform_service_factory.dart';

/// Owns the services that run for the whole app lifecycle.
class AppServiceManager {
  static final AppServiceManager _instance = AppServiceManager._internal();

  factory AppServiceManager() {
    return _instance;
  }

  AppServiceManager._internal() {
    authDataStream.listen((authData) async {
      if (authData != null && authData.userId.startsWith('U-')) {
        if (_config != null && _config!.resonitePhotosDirectory.isEmpty) {
          try {
            final defaultResoniteDir =
                await PlatformServiceFactory.getPlatformService()
                    .getResonitePhotosDirectory();
            if (defaultResoniteDir.isNotEmpty) {
              final updatedConfig = _config!.copyWith(
                resonitePhotosDirectory: defaultResoniteDir,
              );
              await _configRepository.saveConfig(updatedConfig);
              await updateConfig(updatedConfig);
            }
          } catch (e) {
            developer.log(
              'Error initializing default Resonite photos directory on login: $e',
              name: 'AppServiceManager',
            );
          }
        }
      }
    });
  }

  bool _isInitialized = false;

  final ConfigRepository _configRepository = ConfigRepository();

  final PhotoWatcherService photoWatcherService = PhotoWatcherService();

  final PhotoEventService photoEventService = PhotoEventService();

  final ImageCacheService _imageCacheService = ImageCacheService();

  final SoundService soundService = SoundService();

  late final PhotoProcessorService _photoProcessorService =
      PhotoProcessorService();
  late final LogParserService _logParserService = LogParserService();

  StreamSubscription<String>? _photoProcessingSubscription;

  final VRChatService _vrchatService = VRChatService();

  WindowsService? _windowsService;
  WindowsService get windowsService => _windowsService ??= WindowsService();

  LinuxService? _linuxService;
  LinuxService get linuxService => _linuxService ??= LinuxService();

  final UpdateService _updateService = UpdateService();

  final _configStreamController = StreamController<ConfigModel>.broadcast();

  Stream<ConfigModel> get configStream => _configStreamController.stream;

  ConfigModel? _config;

  ConfigModel? get config => _config;

  final _authDataStreamController = StreamController<AuthData?>.broadcast();

  Stream<AuthData?> get authDataStream => _authDataStreamController.stream;

  AuthData? _authData;

  AuthData? get authData => _authData;

  void _setAuthData(AuthData? newData) {
    if (_authData == newData) return;
    _authData = newData;
    _authDataStreamController.add(newData);
    refreshWatcher();
  }

  bool isTOSModalVisible = false;

  static const String _onboardingCompleteKey = 'onboarding_complete';

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

  Future<void> checkVerificationStatus() async {
    try {
      await _vrchatService.initialize();

      final authData = await _vrchatService.loadAuthData();
      if (authData != null) {
        final isVerified = await _vrchatService.checkVerificationStatus(
          authData,
        );

        if (!isVerified) {
          developer.log(
            'Verification is invalid, logging out user',
            name: 'AppServiceManager',
          );
          await _vrchatService.logout();
          _setAuthData(null);
        } else {
          final updatedAuthData = await _vrchatService.loadAuthData();
          _setAuthData(updatedAuthData);
        }
      } else {
        _setAuthData(null);
      }
    } catch (e) {
      developer.log(
        'Error checking verification status: $e',
        name: 'AppServiceManager',
      );
    }
  }

  Future<void> refreshAuth() async {
    final loadedAuth = await _vrchatService.loadAuthData();
    _setAuthData(loadedAuth);
  }

  Future<void> refreshWatcher() async {
    if (_config == null) return;
    await _photoProcessingSubscription?.cancel();
    _photoProcessingSubscription = null;
    await photoWatcherService.stopWatching();

    if (await _shouldStartWatcher(_config!)) {
      await _startPhotoWatcher();
    }
  }

  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      _authData = await _vrchatService.loadAuthData();
      await Future.wait([
        _configRepository.loadConfig().then((config) => _config = config),
        AppDatabase().database,
      ]).timeout(const Duration(seconds: 5), onTimeout: () => []);

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
      if (_config != null) {
        if (Platform.isWindows) {
          windowsService.onCloseRequest = () async {
            await handleWindowClose();
          };
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

      if (_config != null && await _shouldStartWatcher(_config!)) {
        await _startPhotoWatcher();
      }

      await Future.wait([
        _imageCacheService.initialize(),
        soundService.initialize(),
      ]).timeout(const Duration(seconds: 10), onTimeout: () => []);

      await checkVerificationStatus();

      if (Platform.isWindows || Platform.isAndroid) {
        Future.delayed(const Duration(seconds: 5), () async {
          await _updateService.initialize();
          await _updateService.forceCheckForUpdates();
        });
      }
    } catch (e) {
      developer.log(
        'Error in background initialization: $e',
        name: 'AppServiceManager',
      );
    }
  }

  Future<bool> _shouldStartWatcher(ConfigModel config) async {
    return config.resonitePhotosDirectory.isNotEmpty ||
        (config.photosDirectory.isNotEmpty && config.logsDirectory.isNotEmpty);
  }

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

  Future<void> _processPhotoInBackground(String photoPath) async {
    if (_config == null) return;
    try {
      developer.log(
        'Background processing photo: $photoPath',
        name: 'AppServiceManager',
      );
      final isResonite =
          (_config!.resonitePhotosDirectory.isNotEmpty &&
              path.isWithin(_config!.resonitePhotosDirectory, photoPath));
      final metadata =
          isResonite
              ? null
              : await _logParserService.getLatestLogMetadata(_config!);
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

  Future<void> updateConfig(ConfigModel config) async {
    final authData = await _vrchatService.loadAuthData();
    _setAuthData(authData);

    final bool photosDirectoryChanged =
        _config?.photosDirectory != config.photosDirectory;
    final bool logsDirectoryChanged =
        _config?.logsDirectory != config.logsDirectory;
    final bool resonitePhotosDirectoryChanged =
        _config?.resonitePhotosDirectory != config.resonitePhotosDirectory;
    final bool startWithWindowsChanged =
        _config?.startWithWindows != config.startWithWindows;

    _config = config;

    if (Platform.isWindows) {
      windowsService.updateMinimizeToTray(config.minimizeToTray);

      if (startWithWindowsChanged) {
        await windowsService.setStartWithWindows(config.startWithWindows);
      }
    } else if (Platform.isLinux) {
      linuxService.updateMinimizeToTray(config.minimizeToTray);
    }
    final bool dirChanged =
        photosDirectoryChanged ||
        logsDirectoryChanged ||
        resonitePhotosDirectoryChanged;

    if (dirChanged) {
      await _photoProcessingSubscription?.cancel();
      _photoProcessingSubscription = null;
      await photoWatcherService.stopWatching();

      if (await _shouldStartWatcher(config)) {
        await _startPhotoWatcher();
      }
    }

    _configStreamController.add(config);
  }

  /// Returns true when the window was minimized to tray instead of closed.
  Future<bool> handleWindowClose({bool forceExit = false}) async {
    if (Platform.isWindows) {
      if (forceExit) {
        await dispose();

        await windowsService.exitApplication();
        return false; // unreachable: exitApplication ends the process
      } else if (_config != null && _config!.minimizeToTray) {
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
