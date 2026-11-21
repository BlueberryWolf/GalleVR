import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'dart:io';
import 'dart:developer' as developer;
import '../../data/services/app_service_manager.dart';
import '../../data/services/photo_event_service.dart';
import '../../data/services/vrchat_service.dart';
import '../../data/models/config_model.dart';
import '../../data/repositories/config_repository.dart';
import '../../data/models/verification_models.dart';
import '../theme/app_theme.dart';
import '../widgets/app_card.dart';
import '../widgets/app_switch.dart';
import '../widgets/tinted_button.dart';

class MonitorScreen extends StatefulWidget {
  const MonitorScreen({super.key});

  @override
  State<MonitorScreen> createState() => _MonitorScreenState();
}

class _MonitorScreenState extends State<MonitorScreen> {
  final AppServiceManager _appServiceManager = AppServiceManager();
  final ConfigRepository _configRepository = ConfigRepository();
  final PhotoEventService _photoEventService = PhotoEventService();

  ConfigModel? _config;
  AuthData? _authData;
  AuthData? _authDataSec;
  bool _isWatching = false;
  bool _rebuildScheduled = false;

  bool get _hasVRC =>
      (_authData != null && !_authData!.userId.startsWith('U-')) ||
      (_authDataSec != null && !_authDataSec!.userId.startsWith('U-'));

  bool get _hasResonite =>
      (_authData != null && _authData!.userId.startsWith('U-')) ||
      (_authDataSec != null && _authDataSec!.userId.startsWith('U-'));

  bool get _shouldWatch {
    final cfg = _config;
    if (cfg == null) return false;
    return (_hasVRC && cfg.photosDirectory.isNotEmpty) ||
        (_hasResonite && cfg.resonitePhotosDirectory.isNotEmpty) ||
        (!_hasVRC && !_hasResonite && cfg.photosDirectory.isNotEmpty);
  }

  final List<_ProcessingEvent> _events = [];
  final Map<String, bool> _dirExists = {};

  bool _directoryExists(String directory) {
    final known = _dirExists[directory];
    if (known != null) return known;
    _dirExists[directory] = true;
    Directory(directory).exists().catchError((_) => false).then((exists) {
      if (!mounted || exists) return;
      setState(() => _dirExists[directory] = false);
    });
    return true;
  }

  StreamSubscription<String>? _photoSubscription;
  StreamSubscription<ConfigModel>? _configSubscription;
  StreamSubscription<AuthData?>? _authSubscription;
  StreamSubscription<PhotoErrorEvent>? _errorSubscription;

  @override
  void initState() {
    super.initState();
    _initializeEventsFromHistory();

    _loadConfig();
    _listenForConfigChanges();
    _listenForAuthChanges();
    _listenForErrorEvents();
  }

  @override
  void dispose() {
    _stopWatching();
    _configSubscription?.cancel();
    _authSubscription?.cancel();
    _errorSubscription?.cancel();
    super.dispose();
  }

  void _listenForErrorEvents() {
    _errorSubscription = _photoEventService.errors.listen((errorEvent) {
      _EventType eventType;

      switch (errorEvent.type) {
        case 'error':
        case 'watcher':
        case 'processing':
        case 'upload':
          eventType = _EventType.error;
          break;
        case 'success':
          eventType = _EventType.success;
          break;
        case 'warning':
          eventType = _EventType.error;
          break;
        case 'info':
          eventType = _EventType.info;
          break;
        default:
          eventType = _EventType.info;
      }

      _addEvent(
        _ProcessingEvent(
          type: eventType,
          message: errorEvent.message,
          timestamp: DateTime.now(),
          photoPath: errorEvent.photoPath,
        ),
      );
    });
  }

  void _listenForConfigChanges() {
    _configSubscription = _appServiceManager.configStream.listen((
      updatedConfig,
    ) {
      developer.log('Config updated in MonitorScreen', name: 'MonitorScreen');

      final configChanged =
          _config?.photosDirectory != updatedConfig.photosDirectory ||
          _config?.logsDirectory != updatedConfig.logsDirectory ||
          _config?.resonitePhotosDirectory !=
              updatedConfig.resonitePhotosDirectory ||
          _config?.uploadEnabled != updatedConfig.uploadEnabled;

      if (configChanged) {
        _dirExists.clear();
        if (mounted) {
          setState(() => _config = updatedConfig);
        } else {
          _config = updatedConfig;
        }

        _updateWatcherStatus();
      }
    });
  }

  Future<void> _setUploadEnabled(bool value) async {
    final updated = _config!.copyWith(uploadEnabled: value);
    setState(() => _config = updated);
    await _configRepository.saveConfig(updated);
    await _appServiceManager.updateConfig(updated);
  }

  void _listenForAuthChanges() {
    _authSubscription = _appServiceManager.authDataStream.listen((
      authData,
    ) async {
      final authDataSec = await VRChatService().loadAuthDataSecondary();
      if (mounted) {
        setState(() {
          _authData = authData;
          _authDataSec = authDataSec;
        });
      }
      _updateWatcherStatus();
    });
  }

  void _updateWatcherStatus() {
    if (_shouldWatch && !_isWatching) {
      _startWatching();
    } else if (!_shouldWatch && _isWatching) {
      _stopWatching();
    }
  }

  Future<void> _loadConfig() async {
    try {
      final authDataSec = await VRChatService().loadAuthDataSecondary();
      final config =
          _appServiceManager.config ??
          await _appServiceManager.initialize().then(
            (_) => _appServiceManager.config,
          );
      setState(() {
        _config = config ?? _appServiceManager.config;
        _authData = _appServiceManager.authData;
        _authDataSec = authDataSec;
      });
      _updateWatcherStatus();
    } catch (e) {
      developer.log('Error loading config: $e', name: 'MonitorScreen');
    }
  }

  Future<void> _startWatching() async {
    if (_config == null || _isWatching) return;

    try {
      final photoStream =
          _appServiceManager.isDaemonManaged
              ? _photoEventService.photoAdded
              : _appServiceManager.photoWatcherService.photoStream;

      _photoSubscription = photoStream.listen((photoPath) {
        if (photoPath == '__HEAL_SYNC__') return;
        _addEvent(
          _ProcessingEvent(
            type: _EventType.photo,
            message: 'Processing photo: ${path.basename(photoPath)}',
            timestamp: DateTime.now(),
            photoPath: photoPath,
          ),
        );
      });

      final hasVrcDir = _config!.photosDirectory.isNotEmpty;
      final hasResoniteDir = _config!.resonitePhotosDirectory.isNotEmpty;

      String watchMsg;
      if (_hasResonite && hasResoniteDir && _hasVRC && hasVrcDir) {
        watchMsg =
            'Started watching VRChat logs and Resonite folder for new screenshots';
      } else if (_hasResonite && hasResoniteDir) {
        watchMsg = 'Started watching Resonite folder for new screenshots';
      } else {
        watchMsg = 'Started watching VRChat logs for new screenshots';
      }

      setState(() {
        _isWatching = true;
        _addEvent(
          _ProcessingEvent(
            type: _EventType.info,
            message: watchMsg,
            timestamp: DateTime.now(),
          ),
        );
      });
    } catch (e) {
      developer.log('Error starting watcher: $e', name: 'MonitorScreen');
      _addEvent(
        _ProcessingEvent(
          type: _EventType.error,
          message: 'Error starting watcher: $e',
          timestamp: DateTime.now(),
        ),
      );
    }
  }

  Future<void> _stopWatching() async {
    await _photoSubscription?.cancel();
    _photoSubscription = null;

    if (mounted) {
      setState(() {
        _isWatching = false;
        _addEvent(
          _ProcessingEvent(
            type: _EventType.info,
            message: 'Stopped watching for photos',
            timestamp: DateTime.now(),
          ),
        );
      });
    } else {
      _isWatching = false;
    }
  }

  void _addEvent(_ProcessingEvent event) {
    if (!mounted) return;

    _events.insert(0, event);

    if (_events.length > 100) {
      _events.removeLast();
    }

    if (!_rebuildScheduled) {
      _rebuildScheduled = true;

      Future.microtask(() {
        if (mounted) {
          setState(() {
            _rebuildScheduled = false;
          });
        }
      });
    }
  }

  void _initializeEventsFromHistory() {
    _events.clear();
    for (final errorEvent in _photoEventService.history) {
      _EventType eventType;
      switch (errorEvent.type) {
        case 'error':
        case 'watcher':
        case 'processing':
        case 'upload':
          eventType = _EventType.error;
          break;
        case 'success':
          eventType = _EventType.success;
          break;
        case 'warning':
          eventType = _EventType.error;
          break;
        case 'info':
          eventType = _EventType.info;
          break;
        default:
          eventType = _EventType.info;
      }
      _events.add(
        _ProcessingEvent(
          type: eventType,
          message: errorEvent.message,
          timestamp: errorEvent.timestamp,
          photoPath: errorEvent.photoPath,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    bool isConfigMissing;
    String missingMessage;

    if (_hasResonite && !_hasVRC) {
      isConfigMissing =
          _config == null || _config!.resonitePhotosDirectory.isEmpty;
      missingMessage =
          'Please ensure Resonite Photos directory is set in the application settings.';
    } else if (_hasVRC && !_hasResonite) {
      isConfigMissing =
          _config == null ||
          _config!.photosDirectory.isEmpty ||
          _config!.logsDirectory.isEmpty;
      missingMessage =
          'Please ensure both VRChat Photos and Logs directories are set in the application settings.';
    } else if (_hasResonite && _hasVRC) {
      isConfigMissing =
          _config == null ||
          (_config!.resonitePhotosDirectory.isEmpty &&
              (_config!.photosDirectory.isEmpty ||
                  _config!.logsDirectory.isEmpty));
      missingMessage =
          'Please ensure VRChat directories (Photos & Logs) or Resonite directory is set in the application settings.';
    } else {
      isConfigMissing =
          _config == null ||
          _config!.photosDirectory.isEmpty ||
          _config!.logsDirectory.isEmpty;
      missingMessage =
          'Please ensure both VRChat Photos and Logs directories are set in the application settings.';
    }

    if (isConfigMissing) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: AppCard(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.settings_suggest_rounded,
                    size: 44,
                    color: AppTheme.iconFeed,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Configuration Incomplete',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textColor,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    missingMessage,
                    style: const TextStyle(
                      fontSize: 14,
                      color: AppTheme.secondaryTextColor,
                      height: 1.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final horizontalPad =
            width < 600 ? 16.0 : max(28.0, (width - 1200) / 2);

        return ListView(
          padding: EdgeInsets.symmetric(
            horizontal: horizontalPad,
            vertical: width < 600 ? 16 : 24,
          ),
          children: [
        _buildStatusCard(),
        const SizedBox(height: 24),
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            children: [
              const Icon(
                Icons.history_rounded,
                size: 20,
                color: AppTheme.iconFeed,
              ),
              const SizedBox(width: 8),
              const Text(
                'Activity',
                style: TextStyle(
                  color: AppTheme.textColor,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${_events.length}',
                style: const TextStyle(
                  color: AppTheme.secondaryTextColor,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: _events.isEmpty ? null : _clearEvents,
                icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                label: const Text('Clear'),
                style: TextButton.styleFrom(
                  foregroundColor: AppTheme.secondaryTextColor,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  minimumSize: Size.zero,
                  textStyle: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
        _buildEventList(),
      ],
    );
      },
    );
  }

  void _clearEvents() {
    _photoEventService.clearHistory();
    setState(_events.clear);
  }

  Widget _buildStatusCard() {
    final showVRC = _hasVRC || !_hasResonite;
    final directories = [
      if (showVRC) ('VRChat photos', _config?.photosDirectory ?? ''),
      if (showVRC) ('VRChat logs', _config?.logsDirectory ?? ''),
      if (_hasResonite)
        ('Resonite photos', _config?.resonitePhotosDirectory ?? ''),
    ];
    final statusColor =
        _isWatching ? AppTheme.successColor : AppTheme.secondaryTextColor;

    return AppCard(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 16,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            alignment: WrapAlignment.spaceBetween,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _isWatching
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    color: statusColor,
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    _isWatching ? 'Watching for new photos' : 'Not watching',
                    style: const TextStyle(
                      color: AppTheme.textColor,
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Auto-upload',
                    style: TextStyle(
                      color: AppTheme.secondaryTextColor,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(width: 10),
                  AppSwitch(
                    value: _config?.uploadEnabled ?? false,
                    onChanged: _config == null ? null : _setUploadEnabled,
                  ),
                  const SizedBox(width: 16),
                  _isWatching
                      ? TintedButton.neutral(
                        onPressed: _stopWatching,
                        label: 'Stop',
                        dense: true,
                      )
                      : TintedButton(
                        onPressed: _startWatching,
                        label: 'Start',
                        color: AppTheme.successColor,
                        dense: true,
                      ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            decoration: BoxDecoration(
              color: AppTheme.surfaceBase,
              borderRadius: BorderRadius.circular(AppTheme.radiusControl),
              border: Border.all(color: AppTheme.cardBorderColor),
            ),
            child: Column(
              children: [
                for (var i = 0; i < directories.length; i++) ...[
                  if (i > 0)
                    const Divider(height: 1, color: AppTheme.cardBorderColor),
                  _buildDirectoryRow(directories[i].$1, directories[i].$2),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDirectoryRow(String label, String directory) {
    final exists = directory.isNotEmpty && _directoryExists(directory);

    final problem =
        directory.isEmpty
            ? 'Not set'
            : exists
            ? null
            : 'Not found';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      child: Row(
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: const TextStyle(
                color: AppTheme.secondaryTextColor,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              directory.isEmpty ? '-' : directory,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppTheme.bodyTextColor,
                fontSize: 14,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Icon(
            problem == null ? Icons.check_rounded : Icons.warning_amber_rounded,
            size: 16,
            color:
                problem == null ? AppTheme.successColor : AppTheme.warningColor,
          ),
          if (problem != null) ...[
            const SizedBox(width: 6),
            Text(
              problem,
              style: const TextStyle(
                color: AppTheme.warningColor,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEventList() {
    if (_events.isEmpty) {
      return const AppCard(
        padding: EdgeInsets.symmetric(vertical: 40, horizontal: 24),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.inbox_outlined,
                size: 32,
                color: AppTheme.secondaryTextColor,
              ),
              SizedBox(height: 10),
              Text(
                'No activity yet',
                style: TextStyle(
                  color: AppTheme.secondaryTextColor,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return AppCard(
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: _events.length,
        separatorBuilder:
            (_, __) => const Divider(height: 1, color: AppTheme.cardBorderColor),
        itemBuilder: (context, index) => _buildEventItem(_events[index]),
      ),
    );
  }

  Widget _buildEventItem(_ProcessingEvent event) {
    final (iconData, color) = switch (event.type) {
      _EventType.error => (Icons.error_outline_rounded, AppTheme.errorTextColor),
      _EventType.success => (
        Icons.check_circle_outline_rounded,
        AppTheme.successColor,
      ),
      _EventType.upload => (
        Icons.cloud_upload_outlined,
        AppTheme.iconWorld,
      ),
      _EventType.photo => (Icons.photo_outlined, AppTheme.iconPhotos),
      _EventType.info => (
        Icons.info_outline_rounded,
        AppTheme.secondaryTextColor,
      ),
    };

    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        mouseCursor:
            event.photoPath != null
                ? SystemMouseCursors.click
                : SystemMouseCursors.basic,
        hoverColor: AppTheme.cardHoverColor,
        onTap:
            event.photoPath != null
                ? () => _showPhotoPreview(event.photoPath!)
                : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Text(
                _formatTimestamp(event.timestamp),
                style: const TextStyle(
                  color: AppTheme.secondaryTextColor,
                  fontSize: 13,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(width: 14),
              Icon(iconData, color: color, size: 18),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  event.message,
                  style: TextStyle(
                    color:
                        event.type == _EventType.error
                            ? AppTheme.errorTextColor
                            : AppTheme.bodyTextColor,
                    fontSize: 14,
                  ),
                ),
              ),
              if (event.photoPath != null)
                const Padding(
                  padding: EdgeInsets.only(left: 12),
                  child: Icon(
                    Icons.visibility_outlined,
                    size: 16,
                    color: AppTheme.secondaryTextColor,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatTimestamp(DateTime timestamp) {
    return '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}:${timestamp.second.toString().padLeft(2, '0')}';
  }

  void _showPhotoPreview(String photoPath) {
    showDialog(
      context: context,
      builder:
          (context) => Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.all(24),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 900, maxHeight: 700),
              decoration: AppTheme.modalDecoration,
              clipBehavior: Clip.antiAlias,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 14,
                    ),
                    decoration: const BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: AppTheme.cardBorderColor),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            path.basename(photoPath),
                            style: const TextStyle(
                              color: AppTheme.textColor,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.close_rounded,
                            color: AppTheme.secondaryTextColor,
                            size: 20,
                          ),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
                  ),
                  Flexible(
                    child: Image.file(
                      File(photoPath),
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) {
                        return const Padding(
                          padding: EdgeInsets.all(48),
                          child: Icon(
                            Icons.broken_image_rounded,
                            color: AppTheme.secondaryTextColor,
                            size: 48,
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
    );
  }
}

enum _EventType { info, photo, success, error, upload }

class _ProcessingEvent {
  final _EventType type;
  final String message;
  final DateTime timestamp;
  final String? photoPath;

  _ProcessingEvent({
    required this.type,
    required this.message,
    required this.timestamp,
    this.photoPath,
  });
}
