import 'dart:async';
import 'dart:io';
import 'dart:developer' as developer;
import 'package:path/path.dart' as path;

/// Utility class for watching VRChat log files for screenshot events
class LogFileWatcher {
  static const String _logPattern = 'output_log_';
  static final RegExp _screenshotRegex = RegExp(
    r'\d{4}\.\d{2}\.\d{2} \d{2}:\d{2}:\d{2} Debug\s+-\s+\[VRC Camera\] Took screenshot to: (.+\.png)',
  );

  final String _logsDirectory;
  final StreamController<String> _screenshotController = StreamController<String>.broadcast();
  
  Timer? _pollingTimer;
  String? _currentLogFile;
  int _lastPosition = 0;
  final Set<String> _processedScreenshots = <String>{};

  LogFileWatcher(this._logsDirectory);

  /// Stream of screenshot file paths detected from log entries
  Stream<String> get screenshotStream => _screenshotController.stream;

  /// Start watching for screenshot events in the log files
  Future<void> startWatching() async {
    developer.log('Starting log file watcher for directory: $_logsDirectory', name: 'LogFileWatcher');
    
    await stopWatching();
    
    // Find the current log file
    await _findCurrentLogFile();
    
    if (_currentLogFile == null) {
      developer.log('No log file found in $_logsDirectory', name: 'LogFileWatcher');
      return;
    }

    developer.log('Watching log file: $_currentLogFile', name: 'LogFileWatcher');
    
    // Start polling for changes
    _pollingTimer = Timer.periodic(const Duration(milliseconds: 500), (_) => _checkForUpdates());
  }

  /// Stop watching for screenshot events
  Future<void> stopWatching() async {
    _pollingTimer?.cancel();
    _pollingTimer = null;
    _currentLogFile = null;
    _lastPosition = 0;
    _processedScreenshots.clear();
    developer.log('Stopped log file watcher', name: 'LogFileWatcher');
  }

  /// Dispose of resources
  void dispose() {
    stopWatching();
    _screenshotController.close();
  }

  /// Find the most recent log file in the logs directory
  Future<void> _findCurrentLogFile() async {
    try {
      final logsDir = Directory(_logsDirectory);
      if (!await logsDir.exists()) {
        developer.log('Logs directory does not exist: $_logsDirectory', name: 'LogFileWatcher');
        return;
      }

      File? latestLogFile;
      DateTime? latestModified;

      await for (final entity in logsDir.list()) {
        if (entity is File) {
          final fileName = path.basename(entity.path);
          if (fileName.startsWith(_logPattern)) {
            final stat = await entity.stat();
            if (latestModified == null || stat.modified.isAfter(latestModified)) {
              latestModified = stat.modified;
              latestLogFile = entity;
            }
          }
        }
      }

      if (latestLogFile != null) {
        _currentLogFile = latestLogFile.path;
        // Start from the end of the file to only catch new entries
        final stat = await latestLogFile.stat();
        _lastPosition = stat.size;
        developer.log('Found current log file: $_currentLogFile (size: $_lastPosition)', name: 'LogFileWatcher');
      }
    } catch (e) {
      developer.log('Error finding current log file: $e', name: 'LogFileWatcher');
    }
  }

  /// Check for updates in the current log file
  Future<void> _checkForUpdates() async {
    if (_currentLogFile == null) {
      // Try to find a log file again
      await _findCurrentLogFile();
      return;
    }

    try {
      final logFile = File(_currentLogFile!);
      if (!await logFile.exists()) {
        developer.log('Log file no longer exists: $_currentLogFile', name: 'LogFileWatcher');
        // Try to find a new log file
        await _findCurrentLogFile();
        return;
      }

      final stat = await logFile.stat();
      final currentSize = stat.size;

      if (currentSize < _lastPosition) {
        // File was truncated or replaced, start from beginning
        developer.log('Log file was truncated or replaced, restarting from beginning', name: 'LogFileWatcher');
        _lastPosition = 0;
      }

      if (currentSize > _lastPosition) {
        // Read new content
        final randomAccessFile = await logFile.open(mode: FileMode.read);
        await randomAccessFile.setPosition(_lastPosition);
        final newBytes = await randomAccessFile.read(currentSize - _lastPosition);
        await randomAccessFile.close();

        final newContent = String.fromCharCodes(newBytes);
        _lastPosition = currentSize;

        // Process new lines for screenshot events
        _processNewContent(newContent);
      }
    } catch (e) {
      developer.log('Error checking for log updates: $e', name: 'LogFileWatcher');
      // Try to find a new log file on error
      await _findCurrentLogFile();
    }
  }

  /// Process new content from the log file for screenshot events
  void _processNewContent(String content) {
    final lines = content.split('\n');
    
    for (final line in lines) {
      final match = _screenshotRegex.firstMatch(line);
      if (match != null && match.groupCount >= 1) {
        final screenshotPath = match.group(1)?.trim();
        if (screenshotPath != null && screenshotPath.isNotEmpty) {
          // Check if we've already processed this screenshot
          if (!_processedScreenshots.contains(screenshotPath)) {
            _processedScreenshots.add(screenshotPath);
            developer.log('Screenshot detected from log: $screenshotPath', name: 'LogFileWatcher');
            _screenshotController.add(screenshotPath);
          }
        }
      }
    }
  }
}
