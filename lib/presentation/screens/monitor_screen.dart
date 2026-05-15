import 'dart:async';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'dart:io';
import 'dart:developer' as developer;
import '../../data/services/app_service_manager.dart';
import '../../data/services/log_parser_service.dart';
import '../../data/services/photo_processor_service.dart';
import '../../data/services/photo_event_service.dart';
import '../../data/models/config_model.dart';
import '../../data/models/verification_models.dart';
import '../widgets/app_card.dart';

class MonitorScreen extends StatefulWidget {
  const MonitorScreen({super.key});

  @override
  State<MonitorScreen> createState() => _MonitorScreenState();
}

class _MonitorScreenState extends State<MonitorScreen>
    with TickerProviderStateMixin {
  final AppServiceManager _appServiceManager = AppServiceManager();
  final LogParserService _logParserService = LogParserService();
  final PhotoProcessorService _photoProcessorService = PhotoProcessorService();
  final PhotoEventService _photoEventService = PhotoEventService();
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  ConfigModel? _config;
  AuthData? _authData;
  bool _isWatching = false;
  bool _isLoading = true;
  bool _rebuildScheduled = false;

  final List<_ProcessingEvent> _events = [];
  StreamSubscription<String>? _photoSubscription;
  StreamSubscription<ConfigModel>? _configSubscription;
  StreamSubscription<AuthData?>? _authSubscription;
  StreamSubscription<PhotoErrorEvent>? _errorSubscription;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _loadConfig();
    _listenForConfigChanges();
    _listenForAuthChanges();
    _listenForErrorEvents();
  }

  @override
  void dispose() {
    _pulseController.dispose();
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
          _config?.uploadEnabled != updatedConfig.uploadEnabled;

      if (configChanged) {
        _config = updatedConfig;

        if (mounted) {
          setState(() {});
        }

        _updateWatcherStatus();
      }
    });
  }

  void _listenForAuthChanges() {
    _authSubscription = _appServiceManager.authDataStream.listen((authData) {
      if (mounted) {
        setState(() {
          _authData = authData;
        });
      }
    });
  }

  void _updateWatcherStatus() {
    if (_config != null) {
      if (_config!.photosDirectory.isNotEmpty && !_isWatching) {
        _startWatching();
      } else if (_config!.photosDirectory.isEmpty && _isWatching) {
        _stopWatching();
      }
    }
  }

  Future<void> _loadConfig() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final config = _appServiceManager.config;

      if (config != null) {
        setState(() {
          _config = config;
          _authData = _appServiceManager.authData;
          _isLoading = false;
        });

        if (config.photosDirectory.isNotEmpty) {
          _startWatching();
        }
      } else {
        await _appServiceManager.initialize();
        setState(() {
          _config = _appServiceManager.config;
          _authData = _appServiceManager.authData;
          _isLoading = false;
        });

        if (_config != null && _config!.photosDirectory.isNotEmpty) {
          _startWatching();
        }
      }
    } catch (e) {
      developer.log('Error loading config: $e', name: 'MonitorScreen');
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _startWatching() async {
    if (_config == null || _isWatching) return;

    try {
      final photoWatcherService = _appServiceManager.photoWatcherService;

      _photoSubscription = photoWatcherService.photoStream.listen((photoPath) {
        _addEvent(
          _ProcessingEvent(
            type: _EventType.photo,
            message: 'Processing photo: ${path.basename(photoPath)}',
            timestamp: DateTime.now(),
            photoPath: photoPath,
          ),
        );
      });

      setState(() {
        _isWatching = true;
        _addEvent(
          _ProcessingEvent(
            type: _EventType.info,
            message: 'Started watching VRChat logs for new screenshots',
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

  @override
  Widget build(BuildContext context) {
    final isConfigMissing = _config == null ||
        _config!.photosDirectory.isEmpty ||
        _config!.logsDirectory.isEmpty;

    if (isConfigMissing) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.settings_suggest_rounded,
                size: 64,
                color: Colors.white24,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Configuration Incomplete',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: Colors.white70,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 48),
              child: Text(
                'Please ensure both Photos and Logs directories are set in the application settings.',
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: Colors.white38),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [_buildStatusHeader(), Expanded(child: _buildEventList())],
    );
  }

  Widget _buildStatusHeader() {
    final statusColor =
        _isWatching ? const Color(0xFF4ade80) : const Color(0xFFf87171);
    final hasPhotosDir = _config != null && _config!.photosDirectory.isNotEmpty;
    final hasLogsDir = _config != null && _config!.logsDirectory.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: AppCard(
        padding: const EdgeInsets.all(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            statusColor.withOpacity(0.15),
            Colors.white.withOpacity(0.05),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Text(
                      'Live Monitor',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.5,
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: statusColor.withOpacity(0.3)),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _isWatching
                                ? Icons.sync_rounded
                                : Icons.sync_disabled_rounded,
                            color: statusColor,
                            size: 14,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _isWatching ? 'ACTIVE' : 'STOPPED',
                            style: TextStyle(
                              color: statusColor,
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                _buildModernButton(
                  onPressed: _isWatching ? _stopWatching : _startWatching,
                  label: _isWatching ? 'Stop' : 'Start',
                  color: _isWatching ? Colors.redAccent : statusColor,
                ),
              ],
            ),
            const SizedBox(height: 24),
            _buildDirectoryStatusRow(
              Icons.photo_library_rounded,
              'VRChat Photos Path',
              _config?.photosDirectory ?? 'Not set',
              hasPhotosDir,
            ),
            const SizedBox(height: 16),
            _buildDirectoryStatusRow(
              Icons.article_rounded,
              'VRChat Logs Path',
              _config?.logsDirectory ?? 'Not set',
              hasLogsDir,
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                _buildInteractiveBadge(
                  icon:
                      _config?.uploadEnabled ?? false
                          ? Icons.cloud_done_rounded
                          : Icons.cloud_off_rounded,
                  label:
                      _config?.uploadEnabled ?? false
                          ? 'Auto-Upload'
                          : 'Local-Only',
                  color:
                      _config?.uploadEnabled ?? false
                          ? const Color(0xFF60a5fa)
                          : Colors.white30,
                  onTap: () {
                    if (_config != null) {
                      final newConfig = _config!.copyWith(
                        uploadEnabled: !_config!.uploadEnabled,
                      );
                      _appServiceManager.updateConfig(newConfig);
                    }
                  },
                ),
                const SizedBox(width: 12),
                _buildSupporterStatus(),
                const Spacer(),
                if (Platform.isAndroid)
                  const Text(
                    'POLLING MODE',
                    style: TextStyle(
                      color: Colors.white12,
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.0,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDirectoryStatusRow(
    IconData icon,
    String label,
    String pathStr,
    bool isSet,
  ) {
    bool exists = false;
    if (isSet && pathStr != 'Not set') {
      try {
        exists = Directory(pathStr).existsSync();
      } catch (_) {}
    }

    final color = isSet ? (exists ? Colors.greenAccent : Colors.orangeAccent) : Colors.redAccent;

    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 18, color: color.withOpacity(0.7)),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    label.toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white24,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (isSet)
                    Text(
                      exists ? '● FOUND' : '● NOT FOUND',
                      style: TextStyle(
                        color: color.withOpacity(0.5),
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                pathStr,
                style: TextStyle(
                  color: isSet ? Colors.white70 : Colors.white24,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }


  Widget _buildInteractiveBadge({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withOpacity(0.2)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModernButton({
    required VoidCallback onPressed,
    required String label,
    required Color color,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withOpacity(0.3)),
          ),
          child: Text(
            label.toUpperCase(),
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSupporterStatus() {
    if (_authData == null) return const SizedBox.shrink();

    final tier = _authData!.supporterTier;
    final colorValue = tier.color as int?;
    final color = colorValue != null ? Color(colorValue) : Colors.grey;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            tier == SupporterTier.none
                ? Icons.person_rounded
                : Icons.stars_rounded,
            color: color,
            size: 14,
          ),
          const SizedBox(width: 8),
          Text(
            tier.name.toUpperCase(),
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w900,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEventList() {
    if (_events.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.history_rounded, size: 48, color: Colors.white10),
            const SizedBox(height: 16),
            Text(
              'Activity stream is empty',
              style: Theme.of(
                context,
              ).textTheme.bodyLarge?.copyWith(color: Colors.white24),
            ),
          ],
        ),
      );
    }

    return RepaintBoundary(
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _events.length,

        addAutomaticKeepAlives: false,
        addRepaintBoundaries: true,

        cacheExtent: 300,
        itemBuilder: (context, index) {
          final event = _events[index];
          return _buildEventItem(event);
        },
      ),
    );
  }

  Widget _buildEventItem(_ProcessingEvent event) {
    IconData iconData;
    Color iconColor;

    switch (event.type) {
      case _EventType.info:
        iconData = Icons.info_outline_rounded;
        iconColor = const Color(0xFF60a5fa);
        break;
      case _EventType.photo:
        iconData = Icons.photo_rounded;
        iconColor = const Color(0xFFf472b6);
        break;
      case _EventType.success:
        iconData = Icons.check_circle_rounded;
        iconColor = const Color(0xFF4ade80);
        break;
      case _EventType.error:
        iconData = Icons.error_outline_rounded;
        iconColor = const Color(0xFFf87171);
        break;
      case _EventType.upload:
        iconData = Icons.cloud_upload_rounded;
        iconColor = const Color(0xFF3b82f6);
        break;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: AppCard(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        borderRadius: 12,
        child: Row(
          children: [
            Icon(iconData, color: iconColor.withOpacity(0.7), size: 18),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    event.message,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _formatTimestamp(event.timestamp),
                    style: const TextStyle(color: Colors.white30, fontSize: 11),
                  ),
                ],
              ),
            ),
            if (event.photoPath != null) ...[
              const SizedBox(width: 12),
              IconButton(
                icon: const Icon(Icons.visibility_rounded, size: 18),
                onPressed: () => _showPhotoPreview(event.photoPath!),
                color: Colors.white38,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ],
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
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppBar(
                  title: Text(path.basename(photoPath)),
                  automaticallyImplyLeading: false,
                  actions: [
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                Flexible(
                  child: Image.file(
                    File(photoPath),
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) {
                      return Container(
                        color: Colors.grey[300],
                        child: const Center(
                          child: Icon(
                            Icons.broken_image,
                            color: Colors.grey,
                            size: 64,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
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
