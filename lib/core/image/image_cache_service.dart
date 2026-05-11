import 'dart:io';
import 'dart:async';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'dart:developer' as developer;

class ImageCacheService {
  static final ImageCacheService _instance = ImageCacheService._internal();

  factory ImageCacheService() {
    return _instance;
  }

  ImageCacheService._internal();

  Directory? _cacheDir;

  final Map<String, Future<File?>> _pendingRequests = {};

  int _activeDecodes = 0;
  static const int _maxConcurrentDecodes = 4;
  final List<Completer<void>> _decodeQueue = [];

  Future<void> initialize() async {
    try {
      final tempDir = await getTemporaryDirectory();
      _cacheDir = Directory(path.join(tempDir.path, 'GalleVR-ImageCache'));

      if (!await _cacheDir!.exists()) {
        await _cacheDir!.create(recursive: true);
      }
    } catch (e) {
      developer.log(
        'Error initializing image cache: $e',
        name: 'ImageCacheService',
      );
    }
  }

  Future<File?> getThumbnailFile(String filePath, {int size = 300}) async {
    if (_pendingRequests.containsKey(filePath)) {
      return _pendingRequests[filePath];
    }

    final completer = Completer<File?>();
    _pendingRequests[filePath] = completer.future;

    try {
      final result = await _getThumbnailInternal(filePath, size);
      completer.complete(result);
      return result;
    } catch (e) {
      completer.complete(null);
      return null;
    } finally {
      _pendingRequests.remove(filePath);
    }
  }

  Future<File?> _getThumbnailInternal(String filePath, int size) async {
    try {
      if (_cacheDir == null) await initialize();

      final file = File(filePath);
      if (!await file.exists()) return null;

      if (Platform.isWindows) {
        return file;
      }

      final stat = await file.stat();
      final cacheKey =
          '${path.basenameWithoutExtension(filePath)}-${stat.modified.millisecondsSinceEpoch}-$size${path.extension(filePath)}';
      final cacheFile = File(path.join(_cacheDir!.path, cacheKey));

      if (await cacheFile.exists()) {
        return cacheFile;
      }

      await _waitForDecodeSlot();
      try {
        final result = await FlutterImageCompress.compressAndGetFile(
          filePath,
          cacheFile.path,
          minWidth: size,
          minHeight: (size * 9 / 16).round(),
          quality: 80,
          format: CompressFormat.jpeg,
        );

        if (result != null) {
          return File(result.path);
        }
      } catch (e) {
        developer.log(
          'Native compression failed for $filePath: $e',
          name: 'ImageCacheService',
        );
      } finally {
        _releaseDecodeSlot();
      }
    } catch (e) {
      developer.log(
        'Critical error generating thumbnail for $filePath: $e',
        name: 'ImageCacheService',
      );
    }

    return null;
  }

  Future<void> _waitForDecodeSlot() async {
    if (_activeDecodes < _maxConcurrentDecodes) {
      _activeDecodes++;
      return;
    }
    final completer = Completer<void>();
    _decodeQueue.add(completer);
    await completer.future;
  }

  void _releaseDecodeSlot() {
    if (_decodeQueue.isNotEmpty) {
      final completer = _decodeQueue.removeAt(0);
      completer.complete();
    } else {
      _activeDecodes--;
    }
  }

  Future<void> clearCache() async {
    if (_cacheDir != null && await _cacheDir!.exists()) {
      try {
        await _cacheDir!.delete(recursive: true);
        await _cacheDir!.create(recursive: true);
      } catch (e) {
        developer.log(
          'Error clearing disk cache: $e',
          name: 'ImageCacheService',
        );
      }
    }
  }
}
