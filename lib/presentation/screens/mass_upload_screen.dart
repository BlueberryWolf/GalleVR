import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as path;

import '../../data/repositories/config_repository.dart';
import '../../data/services/mass_upload_service.dart';
import '../../data/services/manual_upload_service.dart';
import '../../data/repositories/photo_metadata_repository.dart';
import '../theme/app_theme.dart';
import '../widgets/cached_image.dart';
import '../widgets/app_card.dart';
import '../widgets/tinted_button.dart';

class MassUploadScreen extends StatefulWidget {
  final List<String>? initialFilePaths;
  final bool isManualUpload;
  const MassUploadScreen({
    super.key,
    this.initialFilePaths,
    this.isManualUpload = false,
  });

  @override
  State<MassUploadScreen> createState() => _MassUploadScreenState();
}

class _MassUploadScreenState extends State<MassUploadScreen>
    with TickerProviderStateMixin {
  final MassUploadService _massUploadService = MassUploadService();
  final ManualUploadService _manualUploadService = ManualUploadService();
  final ConfigRepository _configRepository = ConfigRepository();

  final List<FileTask> _tasks = [];
  bool _isProcessing = false;
  int _completedCount = 0;
  int _failedCount = 0;

  late AnimationController _summaryController;

  @override
  void initState() {
    super.initState();
    _summaryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    if (widget.initialFilePaths != null &&
        widget.initialFilePaths!.isNotEmpty) {
      final initialTasks =
          widget.initialFilePaths!.map((path) => FileTask(path: path)).toList();
      _tasks.addAll(initialTasks);
      _summaryController.forward();
      _loadMetadataForInitialTasks(initialTasks);
    }
  }

  Future<void> _loadMetadataForInitialTasks(List<FileTask> newTasks) async {
    final metadataMap = await PhotoMetadataRepository().getMetadataForFiles(
      newTasks.map((t) => t.path).toList(),
    );

    if (!mounted) return;
    setState(() {
      for (var task in newTasks) {
        final metadata = metadataMap[task.path];
        task.hasMetadata = metadata != null && metadata.world != null;
        final galleryUrl = metadata?.galleryUrl;
        if (!task.hasMetadata) {
          task.message =
              'No metadata found. Rename to match original VRChat filename.';
        } else if (galleryUrl != null && galleryUrl.isNotEmpty) {
          task.status = TaskStatus.completed;
          task.message = 'Already uploaded';
        }
      }
    });
  }

  @override
  void dispose() {
    _summaryController.dispose();
    super.dispose();
  }

  Future<void> _pickFiles() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.image,
      allowedExtensions: ['png'],
    );

    if (result != null && result.files.isNotEmpty) {
      final newTasks =
          result.files
              .where((f) => f.path != null)
              .map((f) => FileTask(path: f.path!))
              .toList();

      setState(() {
        _tasks.addAll(newTasks);
        if (_tasks.isNotEmpty) _summaryController.forward();
      });

      final metadataMap = await PhotoMetadataRepository().getMetadataForFiles(
        newTasks.map((t) => t.path).toList(),
      );

      if (!mounted) return;
      setState(() {
        for (var task in newTasks) {
          final metadata = metadataMap[task.path];
          task.hasMetadata = metadata != null && metadata.world != null;
          final galleryUrl = metadata?.galleryUrl;
          if (!task.hasMetadata) {
            task.message =
                'No metadata found. Rename to match original VRChat filename.';
          } else if (galleryUrl != null && galleryUrl.isNotEmpty) {
            task.status = TaskStatus.completed;
            task.message = 'Already uploaded';
          }
        }
      });
    }
  }

  Future<void> _startUpload() async {
    if (_isProcessing || _tasks.isEmpty) return;

    final config = await _configRepository.loadConfig();

    setState(() {
      _isProcessing = true;
      _completedCount = 0;
      _failedCount = 0;
    });

    final tasksToProcess = <int>[];
    for (var i = 0; i < _tasks.length; i++) {
      if (_tasks[i].status == TaskStatus.completed) {
        _completedCount++;
        continue;
      }

      if (!_tasks[i].hasMetadata) {
        setState(() {
          _tasks[i].status = TaskStatus.failed;
          _tasks[i].message = 'Skipped: Missing metadata';
          _failedCount++;
        });
        continue;
      }

      tasksToProcess.add(i);
    }

    if (tasksToProcess.isNotEmpty) {
      int taskPointer = 0;

      Future<void> runWorker() async {
        while (taskPointer < tasksToProcess.length) {
          final taskIndex = tasksToProcess[taskPointer++];

          setState(() {
            _tasks[taskIndex].status = TaskStatus.processing;
          });

          try {
            if (widget.isManualUpload) {
              final resultUrl = await _manualUploadService.uploadPhoto(
                _tasks[taskIndex].path,
                config,
              );

              if (!mounted) return;
              setState(() {
                if (resultUrl != null) {
                  _tasks[taskIndex].status = TaskStatus.completed;
                  _tasks[taskIndex].message = 'Success';
                  _completedCount++;
                } else {
                  _tasks[taskIndex].status = TaskStatus.failed;
                  _tasks[taskIndex].message = 'Upload failed';
                  _failedCount++;
                }
              });
            } else {
              final result = await _massUploadService.processFile(
                _tasks[taskIndex].path,
                config,
              );

              if (!mounted) return;
              setState(() {
                if (result.success) {
                  _tasks[taskIndex].status = TaskStatus.completed;
                  _tasks[taskIndex].message = 'Success';
                  _completedCount++;
                } else {
                  _tasks[taskIndex].status = TaskStatus.failed;
                  _tasks[taskIndex].message =
                      result.errorMessage ?? 'Unknown error';
                  _failedCount++;
                }
              });
            }
          } catch (e) {
            if (!mounted) return;
            setState(() {
              _tasks[taskIndex].status = TaskStatus.failed;
              _tasks[taskIndex].message = e.toString();
              _failedCount++;
            });
          }
        }
      }

      final int concurrency =
          tasksToProcess.length < 4 ? tasksToProcess.length : 4;
      final workers = List.generate(concurrency, (_) => runWorker());
      await Future.wait(workers);
    }

    setState(() {
      _isProcessing = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      body: Stack(
        children: [
          SafeArea(
            child: Column(
              children: [
                _buildHeader(),
                Expanded(
                  child: _tasks.isEmpty ? _buildEmptyState() : _buildTaskList(),
                ),
                _buildActionFooter(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: const BoxDecoration(
        color: AppTheme.chromeColor,
        border: Border(
          bottom: BorderSide(color: AppTheme.headerBorderColor),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(
              Icons.arrow_back_rounded,
              color: AppTheme.secondaryTextColor,
              size: 20,
            ),
            onPressed: () => Navigator.of(context).pop(),
          ),
          const SizedBox(width: 8),
          Text.rich(
            TextSpan(
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              ),
              children: [
                TextSpan(text: widget.isManualUpload ? 'Bulk ' : 'Mass '),
                const TextSpan(
                  text: 'Upload',
                  style: TextStyle(color: AppTheme.brandPurple),
                ),
              ],
            ),
          ),
          const Spacer(),
          if (_tasks.isNotEmpty && !_isProcessing)
            TintedButton.neutral(
              onPressed: _pickFiles,
              icon: Icons.add_circle_outline_rounded,
              label: 'Add More',
              dense: true,
            ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: AppCard(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.cloud_upload_outlined,
                  size: 48,
                  color: AppTheme.brandPurple,
                ),
                const SizedBox(height: 20),
                Text(
                  widget.isManualUpload ? 'Bulk Upload' : 'Mass Upload',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  widget.isManualUpload
                      ? 'Batch process and upload your original gallery photos.\nYour local photos will be safely queued and verified.'
                      : 'Batch process and upload edited photos.\nSelect PNGs from your computer to begin.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppTheme.secondaryTextColor,
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 28),
                TintedButton(
                  onPressed: _pickFiles,
                  label: 'Select Files',
                  color: AppTheme.brandPurple,
                  icon: Icons.add_photo_alternate_rounded,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTaskList() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1200),
        child: Column(
          children: [
            _buildSummaryCard(),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 8,
                ),
                itemCount: _tasks.length,
                itemBuilder: (context, index) {
                  final task = _tasks[index];
                  return _TaskTile(
                    task: task,
                    onRemove:
                        _isProcessing
                            ? null
                            : () {
                              setState(() {
                                _tasks.removeAt(index);
                                if (_tasks.isEmpty) _summaryController.reverse();
                              });
                            },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCard() {
    return SizeTransition(
      sizeFactor: CurvedAnimation(
        parent: _summaryController,
        curve: const Cubic(0.16, 1, 0.3, 1),
      ),
      child: Container(
        margin: const EdgeInsets.fromLTRB(20, 20, 20, 12),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: AppTheme.stripDividerColor,
          borderRadius: BorderRadius.circular(AppTheme.radiusCard),
          border: Border.all(color: AppTheme.cardBorderColor),
        ),
        child: IntrinsicHeight(
          child: Row(
            children: [
              Expanded(
                child: _buildSummaryStat(
                  'QUEUE',
                  _tasks.length.toString(),
                  Icons.list_alt_rounded,
                  AppTheme.brandPurple,
                ),
              ),
              const SizedBox(width: 1),
              Expanded(
                child: _buildSummaryStat(
                  'DONE',
                  _completedCount.toString(),
                  Icons.check_circle_rounded,
                  AppTheme.successColor,
                ),
              ),
              const SizedBox(width: 1),
              Expanded(
                child: _buildSummaryStat(
                  'FAILED',
                  _failedCount.toString(),
                  Icons.error_rounded,
                  AppTheme.errorTextColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryStat(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Container(
      color: AppTheme.cardBackgroundColor,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                  color: AppTheme.secondaryTextColor,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textColor,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActionFooter() {
    if (_tasks.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: const BoxDecoration(
        color: AppTheme.chromeColor,
        border: Border(top: BorderSide(color: AppTheme.headerBorderColor)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          TintedButton.neutral(
            onPressed:
                _isProcessing
                    ? null
                    : () => setState(() {
                      _tasks.clear();
                      _summaryController.reverse();
                    }),
            label: 'Clear',
            icon: Icons.delete_sweep_rounded,
          ),
          TintedButton(
            onPressed: _isProcessing ? null : _startUpload,
            label: _isProcessing ? 'Processing...' : 'Start Upload',
            color: AppTheme.brandPurple,
            icon: Icons.cloud_upload_rounded,
            loading: _isProcessing,
          ),
        ],
      ),
    );
  }
}

class _TaskTile extends StatelessWidget {
  final FileTask task;
  final VoidCallback? onRemove;

  const _TaskTile({required this.task, this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: AppCard(
        padding: const EdgeInsets.all(12),
        borderColor:
            task.status == TaskStatus.completed
                ? AppTheme.cardAccentBorder(AppTheme.successColor)
                : task.status == TaskStatus.failed
                ? AppTheme.cardAccentBorder(AppTheme.errorColor)
                : AppTheme.cardBorderColor,
        child: Row(
          children: [
            _buildLeading(context),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    path.basename(task.path),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  if (task.message != null)
                    Text(
                      task.message!,
                      style: TextStyle(
                        color:
                            task.status == TaskStatus.failed
                                ? AppTheme.errorTextColor
                                : !task.hasMetadata
                                ? AppTheme.warningColor
                                : AppTheme.secondaryTextColor,
                        fontSize: 12,
                      ),
                    )
                  else
                    Row(
                      children: [
                        Icon(
                          task.hasMetadata
                              ? Icons.check_circle_outline_rounded
                              : Icons.warning_amber_rounded,
                          size: 14,
                          color:
                              task.hasMetadata
                                  ? AppTheme.secondaryTextColor
                                  : AppTheme.warningColor,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          task.hasMetadata
                              ? 'Ready for processing'
                              : 'Missing metadata',
                          style: TextStyle(
                            color:
                                task.hasMetadata
                                    ? AppTheme.secondaryTextColor
                                    : AppTheme.warningColor,
                            fontSize: 12,
                            fontWeight:
                                task.hasMetadata
                                    ? FontWeight.normal
                                    : FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!task.hasMetadata)
                  IconButton(
                    icon: const Icon(
                      Icons.info_outline_rounded,
                      color: AppTheme.warningColor,
                      size: 20,
                    ),
                    onPressed: () => _showMetadataInfo(context),
                    tooltip: 'Metadata Help',
                  ),
                if (onRemove != null)
                  IconButton(
                    icon: const Icon(
                      Icons.close_rounded,
                      color: AppTheme.secondaryTextColor,
                      size: 20,
                    ),
                    onPressed: onRemove,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLeading(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 100,
          height: 56,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTheme.radiusControl),
            border: Border.all(color: Colors.white10),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppTheme.radiusControl),
            child: CachedImage(
              filePath: task.path,
              fit: BoxFit.cover,
              useOriginal: false,
            ),
          ),
        ),
        Positioned(
          right: -6,
          bottom: -6,
          child: _buildStatusIndicator(small: true),
        ),
      ],
    );
  }

  Widget _buildStatusIndicator({bool small = false}) {
    final double size = small ? 20 : 32;
    final double iconSize = small ? 12 : 18;

    switch (task.status) {
      case TaskStatus.pending:
        if (!task.hasMetadata) {
          return Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: AppTheme.warningColor.withValues(alpha: small ? 1.0 : 0.1),
              shape: BoxShape.circle,
              border:
                  small
                      ? Border.all(color: AppTheme.backgroundColor, width: 2)
                      : null,
            ),
            child: Icon(
              Icons.warning_amber_rounded,
              color: small ? Colors.black : AppTheme.warningColor,
              size: iconSize,
            ),
          );
        }
        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: AppTheme.surfaceColor,
            shape: BoxShape.circle,
            border:
                small
                    ? Border.all(color: AppTheme.backgroundColor, width: 2)
                    : null,
          ),
          child: Icon(
            Icons.hourglass_bottom_rounded,
            color: Colors.white24,
            size: iconSize,
          ),
        );
      case TaskStatus.processing:
        return Container(
          width: size,
          height: size,
          padding: EdgeInsets.all(small ? 4 : 8),
          decoration:
              small
                  ? BoxDecoration(
                    color: AppTheme.surfaceColor,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppTheme.backgroundColor,
                      width: 2,
                    ),
                  )
                  : null,
          child: const SizedBox(
            width: 10,
            height: 10,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.white,
            ),
          ),
        );
      case TaskStatus.completed:
        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: AppTheme.successColor.withValues(alpha: small ? 1.0 : 0.1),
            shape: BoxShape.circle,
            border:
                small
                    ? Border.all(color: AppTheme.backgroundColor, width: 2)
                    : null,
          ),
          child: Icon(
            Icons.check_rounded,
            color: small ? Colors.black : AppTheme.successColor,
            size: iconSize,
          ),
        );
      case TaskStatus.failed:
        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: AppTheme.errorColor.withValues(alpha: small ? 1.0 : 0.1),
            shape: BoxShape.circle,
            border:
                small
                    ? Border.all(color: AppTheme.backgroundColor, width: 2)
                    : null,
          ),
          child: Icon(
            Icons.error_outline_rounded,
            color: small ? Colors.white : AppTheme.errorColor,
            size: iconSize,
          ),
        );
    }
  }

  void _showMetadataInfo(BuildContext context) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.info_outline_rounded, color: AppTheme.warningColor),
                SizedBox(width: 12),
                Text('Missing Metadata'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'GalleVR cannot find VRChat or VRCX metadata for this photo.',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                const Text(
                  'To fix this, ensure the filename is identical or very similar to the original photo taken in VRChat. This allows the app to correlate the edited image with the original session data.',
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceBase,
                    borderRadius: BorderRadius.circular(AppTheme.radiusControl),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Example:',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.secondaryTextColor,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Original: VRChat_2024-01-01_...png',
                        style: TextStyle(fontFamily: 'monospace', fontSize: 12),
                      ),
                      Text(
                        'Edited:   VRChat_2024-01-01_..._EDIT.png',
                        style: TextStyle(fontFamily: 'monospace', fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Got it'),
              ),
            ],
          ),
    );
  }
}

enum TaskStatus { pending, processing, completed, failed }

class FileTask {
  final String path;
  TaskStatus status;
  String? message;
  bool hasMetadata;

  FileTask({
    required this.path,
    this.status = TaskStatus.pending,
    this.hasMetadata = true,
  });
}
