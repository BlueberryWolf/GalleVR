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

class MonitorScreen extends StatefulWidget {
  const MonitorScreen({super.key});

  @override
  State<MonitorScreen> createState() => _MonitorScreenState();
}

class _MonitorScreenState extends State<MonitorScreen> {
  final AppServiceManager _appServiceManager = AppServiceManager();
  final LogParserService _logParserService = LogParserService();
  final PhotoProcessorService _photoProcessorService = PhotoProcessorService();
  final PhotoEventService _photoEventService = PhotoEventService();

  ConfigModel? _config;
  bool _isWatching = false;
  bool _isLoading = true;
  bool _rebuildScheduled = false;

  final List<_ProcessingEvent> _events = [];
  StreamSubscription? _photoSubscription;
  StreamSubscription? _configSubscription;
  StreamSubscription? _errorSubscription;

  @override
  void initState() {
    super.initState();
    _loadConfig();
    _listenForConfigChanges();
    _listenForErrorEvents();
  }

  @override
  void dispose() {
    _stopWatching();
    _configSubscription?.cancel();
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

        _addEvent(
          _ProcessingEvent(
            type: _EventType.info,
            message: 'Configuration updated',
            timestamp: DateTime.now(),
          ),
        );
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
          _isLoading = false;
        });

        if (config.photosDirectory.isNotEmpty) {
          _startWatching();
        }
      } else {
        await _appServiceManager.initialize();
        setState(() {
          _config = _appServiceManager.config;
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
        _processPhoto(photoPath);
      });

      setState(() {
        _isWatching = true;
        _addEvent(
          _ProcessingEvent(
            type: _EventType.info,
            message:
                'Started watching for photos in ${_config!.photosDirectory}',
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

  Future<void> _processPhoto(String photoPath) async {
    if (_config == null) return;

    _addEvent(
      _ProcessingEvent(
        type: _EventType.photo,
        message: 'Processing photo: ${path.basename(photoPath)}',
        timestamp: DateTime.now(),
        photoPath: photoPath,
      ),
    );

    try {
      final metadata = await _logParserService.getLatestLogMetadata(_config!);

      final outputPath = await _photoProcessorService.processPhoto(
        photoPath,
        _config!,
        metadata,
      );

      if (outputPath != null) {
        if (_config!.uploadEnabled) {
          _addEvent(
            _ProcessingEvent(
              type: _EventType.upload,
              message: 'Photo metadata saved locally and uploaded to server',
              timestamp: DateTime.now(),
            ),
          );
        } else {
          _addEvent(
            _ProcessingEvent(
              type: _EventType.info,
              message: 'Photo metadata saved locally',
              timestamp: DateTime.now(),
            ),
          );
        }

        _photoEventService.notifyPhotoAdded(photoPath);
      } else {
        _addEvent(
          _ProcessingEvent(
            type: _EventType.error,
            message: 'Failed to process photo: ${path.basename(photoPath)}',
            timestamp: DateTime.now(),
          ),
        );
      }
    } catch (e) {
      developer.log('Error processing photo: $e', name: 'MonitorScreen');
      _addEvent(
        _ProcessingEvent(
          type: _EventType.error,
          message: 'Error processing photo: $e',
          timestamp: DateTime.now(),
        ),
      );
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
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_config == null || _config!.photosDirectory.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.folder_off, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            Text(
              'No photos directory set',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Please set a photos directory in settings',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return Column(
      children: [_buildStatusCard(), Expanded(child: _buildEventList())],
    );
  }

  Widget _buildStatusCard() {
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _isWatching ? Icons.visibility : Icons.visibility_off,
                  color: _isWatching ? Colors.green : Colors.red,
                ),
                const SizedBox(width: 8),
                Text(
                  _isWatching ? 'Watching for photos' : 'Not watching',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const Spacer(),
                ElevatedButton(
                  onPressed: _isWatching ? _stopWatching : _startWatching,
                  child: Text(_isWatching ? 'Stop' : 'Start'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Photos directory: ${_config!.photosDirectory}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            if (_config!.logsDirectory.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                'Logs directory: ${_config!.logsDirectory}',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  _config!.uploadEnabled ? Icons.cloud_upload : Icons.cloud_off,
                  color: _config!.uploadEnabled ? Colors.blue : Colors.grey,
                ),
                const SizedBox(width: 8),
                Text(
                  _config!.uploadEnabled
                      ? 'Photo uploading enabled'
                      : 'Photo uploading disabled',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'All photos are saved locally with metadata',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEventList() {
    if (_events.isEmpty) {
      return Center(
        child: Text(
          'No events yet',
          style: Theme.of(context).textTheme.bodyLarge,
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
        iconData = Icons.info;
        iconColor = Colors.blue;
        break;
      case _EventType.photo:
        iconData = Icons.photo;
        iconColor = Colors.purple;
        break;
      case _EventType.success:
        iconData = Icons.check_circle;
        iconColor = Colors.green;
        break;
      case _EventType.error:
        iconData = Icons.error;
        iconColor = Colors.red;
        break;
      case _EventType.upload:
        iconData = Icons.cloud_upload;
        iconColor = Colors.blue;
        break;
    }

    const cardMargin = EdgeInsets.only(bottom: 8);

    return Card(
      margin: cardMargin,
      child: ListTile(
        leading: Icon(iconData, color: iconColor),
        title: Text(event.message),
        subtitle: Text(
          _formatTimestamp(event.timestamp),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        onTap:
            event.photoPath != null
                ? () => _showPhotoPreview(event.photoPath!)
                : null,
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
