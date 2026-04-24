import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as path;
import 'dart:developer' as developer;

import '../../data/repositories/config_repository.dart';
import '../../data/models/config_model.dart';
import '../../data/services/mass_upload_service.dart';
import '../../data/services/vrchat_service.dart';
import '../../data/repositories/photo_metadata_repository.dart';
import '../theme/app_theme.dart';
import '../widgets/cached_image.dart';

class MassUploadScreen extends StatefulWidget {
  const MassUploadScreen({super.key});

  @override
  State<MassUploadScreen> createState() => _MassUploadScreenState();
}

class _MassUploadScreenState extends State<MassUploadScreen> with TickerProviderStateMixin {
  final MassUploadService _massUploadService = MassUploadService();
  final ConfigRepository _configRepository = ConfigRepository();
  final VRChatService _vrchatService = VRChatService();
  
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
      final newTasks = result.files
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
          if (!task.hasMetadata) {
            task.message = 'No metadata found. Rename to match original VRChat filename.';
          }
        }
      });
    }
  }

  Future<void> _startUpload() async {
    if (_isProcessing || _tasks.isEmpty) return;

    final config = await _configRepository.loadConfig();
    if (config == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to load configuration')),
      );
      return;
    }

    setState(() {
      _isProcessing = true;
      _completedCount = 0;
      _failedCount = 0;
    });

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

      setState(() {
        _tasks[i].status = TaskStatus.processing;
      });

      try {
        final result = await _massUploadService.processFile(_tasks[i].path, config);
        
        if (!mounted) return;
        setState(() {
          if (result.success) {
            _tasks[i].status = TaskStatus.completed;
            _tasks[i].message = 'Success';
            _completedCount++;
          } else {
            _tasks[i].status = TaskStatus.failed;
            _tasks[i].message = result.errorMessage ?? 'Unknown error';
            _failedCount++;
          }
        });
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _tasks[i].status = TaskStatus.failed;
          _tasks[i].message = e.toString();
          _failedCount++;
        });
      }
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
          const _MeshBackground(),
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
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.2),
            border: Border(bottom: BorderSide(color: AppTheme.cardBorderColor.withOpacity(0.5))),
          ),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white70, size: 20),
                onPressed: () => Navigator.of(context).pop(),
              ),
              const SizedBox(width: 8),
              const Text(
                'Mass Upload',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
              const Spacer(),
              if (_tasks.isNotEmpty && !_isProcessing)
                TextButton.icon(
                  onPressed: _pickFiles,
                  icon: const Icon(Icons.add_circle_outline_rounded, size: 20),
                  label: const Text('Add More'),
                  style: TextButton.styleFrom(foregroundColor: AppTheme.primaryLightColor),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: AppTheme.primaryColor.withOpacity(0.05),
              shape: BoxShape.circle,
              border: Border.all(color: AppTheme.primaryColor.withOpacity(0.1), width: 2),
            ),
            child: Icon(Icons.cloud_upload_outlined, size: 80, color: AppTheme.primaryColor.withOpacity(0.4)),
          ),
          const SizedBox(height: 32),
          const Text(
            'Ready for Mass Upload',
            style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Text(
            'Select edited PNGs from your computer\nto batch process and upload them.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 16),
          ),
          const SizedBox(height: 48),
          ElevatedButton.icon(
            onPressed: _pickFiles,
            icon: const Icon(Icons.add_photo_alternate_rounded),
            label: const Text('Select Files'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
              padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
              elevation: 10,
              shadowColor: AppTheme.primaryColor.withOpacity(0.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTaskList() {
    return Column(
      children: [
        _buildSummaryCard(),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            itemCount: _tasks.length,
            itemBuilder: (context, index) {
              final task = _tasks[index];
              return _TaskTile(
                task: task,
                onRemove: _isProcessing
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
    );
  }

  Widget _buildSummaryCard() {
    return SizeTransition(
      sizeFactor: CurvedAnimation(parent: _summaryController, curve: Curves.easeOutBack),
      child: Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppTheme.cardBackgroundColor.withOpacity(0.8),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppTheme.cardBorderColor),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildSummaryStat('Queue', _tasks.length.toString(), Icons.list_alt_rounded, Colors.white70),
            _buildSummaryStat('Done', _completedCount.toString(), Icons.check_circle_rounded, Colors.greenAccent),
            _buildSummaryStat('Failed', _failedCount.toString(), Icons.error_rounded, Colors.redAccent),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryStat(String label, String value, IconData icon, Color color) {
    return Column(
      children: [
        Icon(icon, color: color.withOpacity(0.5), size: 20),
        const SizedBox(height: 8),
        Text(value, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: color)),
        Text(label, style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.4))),
      ],
    );
  }

  Widget _buildActionFooter() {
    if (_tasks.isEmpty) return const SizedBox.shrink();

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.3),
            border: Border(top: BorderSide(color: AppTheme.cardBorderColor.withOpacity(0.5))),
          ),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _isProcessing ? null : () => setState(() {
                    _tasks.clear();
                    _summaryController.reverse();
                  }),
                  icon: const Icon(Icons.delete_sweep_rounded),
                  label: const Text('Clear All'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white70,
                    side: const BorderSide(color: Colors.white12),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                flex: 2,
                child: ElevatedButton.icon(
                  onPressed: _isProcessing ? null : _startUpload,
                  icon: _isProcessing 
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.rocket_launch_rounded),
                  label: Text(_isProcessing ? 'Processing...' : 'Upload ${_tasks.length} Photos'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    elevation: 5,
                    shadowColor: AppTheme.primaryColor.withOpacity(0.3),
                  ),
                ),
              ),
            ],
          ),
        ),
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
      decoration: BoxDecoration(
        color: AppTheme.cardBackgroundColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: task.status == TaskStatus.completed 
              ? Colors.greenAccent.withOpacity(0.3) 
              : task.status == TaskStatus.failed 
                  ? Colors.redAccent.withOpacity(0.3)
                  : AppTheme.cardBorderColor,
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        leading: _buildLeading(context),
        title: Text(
          path.basename(task.path),
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500, fontSize: 14),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: task.message != null
            ? Text(
                task.message!,
                style: TextStyle(
                  color: task.status == TaskStatus.failed 
                      ? Colors.redAccent 
                      : !task.hasMetadata 
                          ? Colors.orangeAccent 
                          : Colors.white54,
                  fontSize: 12,
                ),
              )
            : Text(
                task.hasMetadata ? 'Ready for processing' : 'Metadata missing - Rename to original',
                style: TextStyle(
                  color: task.hasMetadata ? Colors.white.withOpacity(0.3) : Colors.orangeAccent.withOpacity(0.8),
                  fontSize: 12,
                  fontWeight: task.hasMetadata ? FontWeight.normal : FontWeight.bold,
                ),
              ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!task.hasMetadata)
              IconButton(
                icon: const Icon(Icons.info_outline_rounded, color: Colors.orangeAccent, size: 20),
                onPressed: () => _showMetadataInfo(context),
                tooltip: 'Metadata Help',
              ),
            if (onRemove != null)
              IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.white24, size: 20),
                onPressed: onRemove,
              ),
          ],
        ),
      ),
    );
  }

  void _showMetadataInfo(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.info_outline_rounded, color: Colors.orangeAccent),
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
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Example:', style: TextStyle(fontSize: 12, color: Colors.white54)),
                  SizedBox(height: 4),
                  Text('Original: VRChat_2024-01-01_...png', style: TextStyle(fontFamily: 'monospace', fontSize: 12)),
                  Text('Edited:   VRChat_2024-01-01_..._EDIT.png', style: TextStyle(fontFamily: 'monospace', fontSize: 12)),
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

  Widget _buildLeading(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 60,
          height: 40,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white10),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.2),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: CachedImage(
              filePath: task.path,
              fit: BoxFit.cover,
              thumbnailSize: 150,
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
              color: Colors.orangeAccent.withOpacity(small ? 1.0 : 0.1),
              shape: BoxShape.circle,
              border: small ? Border.all(color: AppTheme.backgroundColor, width: 2) : null,
            ),
            child: Icon(Icons.warning_amber_rounded, color: small ? Colors.black : Colors.orangeAccent, size: iconSize),
          );
        }
        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: AppTheme.surfaceColor,
            shape: BoxShape.circle,
            border: small ? Border.all(color: AppTheme.backgroundColor, width: 2) : null,
          ),
          child: Icon(Icons.hourglass_bottom_rounded, color: Colors.white24, size: iconSize),
        );
      case TaskStatus.processing:
        return Container(
          width: size,
          height: size,
          padding: EdgeInsets.all(small ? 4 : 8),
          decoration: small ? BoxDecoration(
            color: AppTheme.surfaceColor,
            shape: BoxShape.circle,
            border: Border.all(color: AppTheme.backgroundColor, width: 2),
          ) : null,
          child: CircularProgressIndicator(strokeWidth: 2),
        );
      case TaskStatus.completed:
        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: Colors.greenAccent.withOpacity(small ? 1.0 : 0.1),
            shape: BoxShape.circle,
            border: small ? Border.all(color: AppTheme.backgroundColor, width: 2) : null,
          ),
          child: Icon(Icons.check_rounded, color: small ? Colors.black : Colors.greenAccent, size: iconSize),
        );
      case TaskStatus.failed:
        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: Colors.redAccent.withOpacity(small ? 1.0 : 0.1),
            shape: BoxShape.circle,
            border: small ? Border.all(color: AppTheme.backgroundColor, width: 2) : null,
          ),
          child: Icon(Icons.error_outline_rounded, color: small ? Colors.white : Colors.redAccent, size: iconSize),
        );
    }
  }
}

class _MeshBackground extends StatelessWidget {
  const _MeshBackground();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(child: Container(color: AppTheme.backgroundColor)),
        Positioned(
          top: -150,
          right: -50,
          child: _MeshCircle(color: AppTheme.primaryColor.withOpacity(0.15), size: 450),
        ),
        Positioned(
          bottom: -200,
          left: -100,
          child: _MeshCircle(color: const Color(0xFF8B5CF6).withOpacity(0.12), size: 600),
        ),
        Positioned(
          top: 300,
          left: -200,
          child: _MeshCircle(color: const Color(0xFF3B82F6).withOpacity(0.08), size: 500),
        ),
      ],
    );
  }
}

class _MeshCircle extends StatelessWidget {
  final Color color;
  final double size;
  const _MeshCircle({required this.color, required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [color, color.withOpacity(0)],
          stops: const [0.3, 1.0],
        ),
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
    this.hasMetadata = true, // Assume true until checked
  });
}
