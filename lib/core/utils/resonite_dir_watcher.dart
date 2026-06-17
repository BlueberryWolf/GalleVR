import 'dart:async';
import 'dart:io';
import 'dart:developer' as developer;
import 'package:path/path.dart' as path;

/// Watches the Resonite photos directory for new image files using inotify.
///
/// Watches the root directory for new subdirectories (month folders like 2026-06/)
/// and also watches every existing subdirectory directly. This avoids relying on
/// [Directory.watch] recursive mode, which is unreliable on Linux.
class ResoniteDirWatcher {
  static const _allowedExtensions = {'.png', '.jpg', '.jpeg', '.webp'};

  final String _directory;
  final StreamController<String> _photoController =
      StreamController<String>.broadcast();

  StreamSubscription<FileSystemEvent>? _rootSubscription;
  final Map<String, StreamSubscription<FileSystemEvent>> _subdirSubscriptions = {};
  final Set<String> _seenFiles = {};

  ResoniteDirWatcher(this._directory);

  Stream<String> get photoStream => _photoController.stream;

  Future<void> startWatching() async {
    await stopWatching();

    final root = Directory(_directory);
    if (!await root.exists()) {
      developer.log('ResoniteDirWatcher: directory does not exist: $_directory', name: 'ResoniteDirWatcher');
      return;
    }

    // Seed existing files so we don't re-process on startup.
    await _seedExistingFiles(root);

    // Watch each existing subdirectory.
    await for (final entity in root.list(followLinks: false)) {
      if (entity is Directory) {
        await _watchSubdir(entity.path);
      }
    }

    // Watch the root for new subdirectories.
    _rootSubscription = root.watch(events: FileSystemEvent.create).listen((event) async {
      if (event is FileSystemCreateEvent && FileSystemEntity.isDirectorySync(event.path)) {
        developer.log('ResoniteDirWatcher: new subdirectory: ${event.path}', name: 'ResoniteDirWatcher');
        await _watchSubdir(event.path);
      } else {
        _onFileEvent(event.path);
      }
    }, onError: (e) {
      developer.log('ResoniteDirWatcher: root watcher error: $e', name: 'ResoniteDirWatcher');
    });

    developer.log('ResoniteDirWatcher: watching $_directory + ${_subdirSubscriptions.length} subdirs', name: 'ResoniteDirWatcher');
  }

  Future<void> _watchSubdir(String dirPath) async {
    if (_subdirSubscriptions.containsKey(dirPath)) return;
    try {
      final sub = Directory(dirPath)
          .watch(events: FileSystemEvent.create)
          .listen((event) => _onFileEvent(event.path), onError: (e) {
        developer.log('ResoniteDirWatcher: subdir watcher error ($dirPath): $e', name: 'ResoniteDirWatcher');
      });
      _subdirSubscriptions[dirPath] = sub;
      developer.log('ResoniteDirWatcher: watching subdir $dirPath', name: 'ResoniteDirWatcher');
    } catch (e) {
      developer.log('ResoniteDirWatcher: failed to watch subdir $dirPath: $e', name: 'ResoniteDirWatcher');
    }
  }

  void _onFileEvent(String filePath) {
    final ext = path.extension(filePath).toLowerCase();
    if (!_allowedExtensions.contains(ext)) return;
    if (_seenFiles.contains(filePath)) return;
    _seenFiles.add(filePath);
    developer.log('ResoniteDirWatcher: new photo: $filePath', name: 'ResoniteDirWatcher');
    _photoController.add(filePath);
  }

  Future<void> _seedExistingFiles(Directory root) async {
    try {
      await for (final entity in root.list(recursive: true, followLinks: false)) {
        if (entity is File &&
            _allowedExtensions.contains(path.extension(entity.path).toLowerCase())) {
          _seenFiles.add(entity.path);
        }
      }
      developer.log('ResoniteDirWatcher: seeded ${_seenFiles.length} existing files', name: 'ResoniteDirWatcher');
    } catch (e) {
      developer.log('ResoniteDirWatcher: seed error: $e', name: 'ResoniteDirWatcher');
    }
  }

  Future<void> stopWatching() async {
    await _rootSubscription?.cancel();
    _rootSubscription = null;
    for (final sub in _subdirSubscriptions.values) {
      await sub.cancel();
    }
    _subdirSubscriptions.clear();
    _seenFiles.clear();
  }

  void dispose() {
    stopWatching();
    _photoController.close();
  }
}
