import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as path;
import 'dart:developer' as developer;

import '../../data/repositories/config_repository.dart';
import '../../data/models/config_model.dart';
import '../../data/services/mass_upload_service.dart';
import '../../data/services/vrchat_service.dart';

class MassUploadScreen extends StatefulWidget {
  const MassUploadScreen({super.key});

  @override
  State<MassUploadScreen> createState() => _MassUploadScreenState();
}

class _MassUploadScreenState extends State<MassUploadScreen> {
  final MassUploadService _massUploadService = MassUploadService();
  final ConfigRepository _configRepository = ConfigRepository();
  final VRChatService _vrchatService = VRChatService();
  
  List<FileTask> _tasks = [];
  bool _isProcessing = false;
  int _completedCount = 0;
  int _failedCount = 0;

  Future<void> _pickFiles() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.image,
      allowedExtensions: ['png'],
    );

    if (result != null && result.files.isNotEmpty) {
      setState(() {
        _tasks.addAll(result.files.map((f) => FileTask(path: f.path!)));
      });
    }
  }

  Future<void> _startUpload() async {
    if (_isProcessing) return;

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
      if (_tasks[i].status == TaskStatus.completed) continue;

      setState(() {
        _tasks[i].status = TaskStatus.processing;
      });

      try {
        final result = await _massUploadService.processFile(_tasks[i].path, config);
        
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
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Mass Upload (Editor Mode)', style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Column(
        children: [
          _buildSummary(),
          Expanded(
            child: _tasks.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.cloud_upload_outlined, size: 64, color: Colors.white24),
                        const SizedBox(height: 16),
                        const Text('No files selected', style: TextStyle(color: Colors.white54)),
                        const SizedBox(height: 24),
                        ElevatedButton.icon(
                          onPressed: _pickFiles,
                          icon: const Icon(Icons.add),
                          label: const Text('Select Edited PNGs'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blueAccent,
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: _tasks.length,
                    itemBuilder: (context, index) {
                      final task = _tasks[index];
                      return ListTile(
                        leading: _buildStatusIcon(task.status),
                        title: Text(
                          path.basename(task.path),
                          style: const TextStyle(color: Colors.white),
                        ),
                        subtitle: task.message != null
                            ? Text(task.message!, style: TextStyle(color: task.status == TaskStatus.failed ? Colors.redAccent : Colors.white54))
                            : null,
                        trailing: IconButton(
                          icon: const Icon(Icons.close, color: Colors.white24),
                          onPressed: _isProcessing ? null : () {
                            setState(() {
                              _tasks.removeAt(index);
                            });
                          },
                        ),
                      );
                    },
                  ),
          ),
          if (_tasks.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isProcessing ? null : () => setState(() => _tasks.clear()),
                      style: OutlinedButton.styleFrom(foregroundColor: Colors.white54),
                      child: const Text('Clear All'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: _isProcessing ? null : _startUpload,
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
                      child: Text(_isProcessing ? 'Processing...' : 'Upload ${_tasks.length} Photos'),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSummary() {
    if (_tasks.isEmpty) return const SizedBox.shrink();
    
    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildStat('Total', _tasks.length.toString()),
          _buildStat('Done', _completedCount.toString(), color: Colors.greenAccent),
          _buildStat('Failed', _failedCount.toString(), color: Colors.redAccent),
        ],
      ),
    );
  }

  Widget _buildStat(String label, String value, {Color color = Colors.white70}) {
    return Column(
      children: [
        Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.white38)),
      ],
    );
  }

  Widget _buildStatusIcon(TaskStatus status) {
    switch (status) {
      case TaskStatus.pending: return const Icon(Icons.hourglass_empty, color: Colors.white24);
      case TaskStatus.processing: return const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2));
      case TaskStatus.completed: return const Icon(Icons.check_circle, color: Colors.greenAccent);
      case TaskStatus.failed: return const Icon(Icons.error_outline, color: Colors.redAccent);
    }
  }
}

enum TaskStatus { pending, processing, completed, failed }

class FileTask {
  final String path;
  TaskStatus status;
  String? message;

  FileTask({required this.path, this.status = TaskStatus.pending});
}
