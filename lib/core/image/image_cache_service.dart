import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'dart:developer' as developer;
import 'package:image/image.dart' as img;

class ImageCacheService {
  static final ImageCacheService _instance = ImageCacheService._internal();

  factory ImageCacheService() {
    return _instance;
  }

  ImageCacheService._internal();

  final Map<String, Uint8List> _thumbnailCache = {};

  int _currentCacheSize = 0;

  static const int _maxCacheEntries = 100;

  static const int _maxMemoryCacheSize = 50 * 1024 * 1024;

  Directory? _cacheDir;

  final List<String> _cacheAccessOrder = [];

  Future<void> initialize() async {
    try {
      final tempDir = await getTemporaryDirectory();
      _cacheDir = Directory(path.join(tempDir.path, 'GalleVR-ImageCache'));

      if (!await _cacheDir!.exists()) {
        await _cacheDir!.create(recursive: true);
      }

      developer.log(
        'Image cache initialized at ${_cacheDir!.path}',
        name: 'ImageCacheService',
      );
    } catch (e) {
      developer.log(
        'Error initializing image cache: $e',
        name: 'ImageCacheService',
      );
    }
  }

  Future<Uint8List?> getThumbnail(String filePath, {int size = 300}) async {
    final cacheKey = _getCacheKey(filePath, size);

    if (_thumbnailCache.containsKey(cacheKey)) {
      developer.log(
        'Thumbnail found in memory cache: $cacheKey',
        name: 'ImageCacheService',
      );

      if (_cacheAccessOrder.contains(cacheKey)) {
        _cacheAccessOrder.remove(cacheKey);
      }
      _cacheAccessOrder.add(cacheKey);

      return _thumbnailCache[cacheKey];
    }

    final thumbnailFile = await _getThumbnailFile(cacheKey);
    if (await thumbnailFile.exists()) {
      try {
        final bytes = await thumbnailFile.readAsBytes();

        _addToMemoryCache(cacheKey, bytes);
        developer.log(
          'Thumbnail loaded from disk cache: $cacheKey',
          name: 'ImageCacheService',
        );
        return bytes;
      } catch (e) {
        developer.log(
          'Error reading cached thumbnail: $e',
          name: 'ImageCacheService',
        );
      }
    }

    return await _generateThumbnail(filePath, size, cacheKey);
  }

  Future<Uint8List?> _generateThumbnail(
    String filePath,
    int size,
    String cacheKey,
  ) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        developer.log(
          'File does not exist: $filePath',
          name: 'ImageCacheService',
        );
        return null;
      }

      final bytes = await file.readAsBytes();

      final thumbnail = await compute(
        _decodeThumbnail,
        ThumbnailParams(bytes, size),
      );

      if (thumbnail != null) {
        final thumbnailFile = await _getThumbnailFile(cacheKey);
        await thumbnailFile.writeAsBytes(thumbnail);

        _addToMemoryCache(cacheKey, thumbnail);

        developer.log(
          'Generated new thumbnail: $cacheKey',
          name: 'ImageCacheService',
        );
        return thumbnail;
      }
    } catch (e) {
      developer.log(
        'Error generating thumbnail: $e',
        name: 'ImageCacheService',
      );

      try {
        final file = File(filePath);
        if (await file.exists()) {
          developer.log(
            'Using original image as fallback: $filePath',
            name: 'ImageCacheService',
          );
          return await file.readAsBytes();
        }
      } catch (fallbackError) {
        developer.log(
          'Fallback also failed: $fallbackError',
          name: 'ImageCacheService',
        );
      }
    }

    return null;
  }

  void _addToMemoryCache(String key, Uint8List bytes) {
    if (_cacheAccessOrder.contains(key)) {
      _cacheAccessOrder.remove(key);
    }
    _cacheAccessOrder.add(key);

    if (_thumbnailCache.containsKey(key)) {
      _currentCacheSize -= _thumbnailCache[key]!.length;
    }

    if (_currentCacheSize + bytes.length > _maxMemoryCacheSize) {
      while (_cacheAccessOrder.isNotEmpty &&
          _currentCacheSize + bytes.length > _maxMemoryCacheSize) {
        final oldestKey = _cacheAccessOrder.first;
        if (_thumbnailCache.containsKey(oldestKey)) {
          final oldBytes = _thumbnailCache[oldestKey]!;
          _currentCacheSize -= oldBytes.length;
          _thumbnailCache.remove(oldestKey);
        }
        _cacheAccessOrder.removeAt(0);
      }
    }

    while (_thumbnailCache.length >= _maxCacheEntries &&
        _cacheAccessOrder.isNotEmpty) {
      final oldestKey = _cacheAccessOrder.first;
      if (_thumbnailCache.containsKey(oldestKey)) {
        final oldBytes = _thumbnailCache[oldestKey]!;
        _currentCacheSize -= oldBytes.length;
        _thumbnailCache.remove(oldestKey);
      }
      _cacheAccessOrder.removeAt(0);
    }

    _thumbnailCache[key] = bytes;
    _currentCacheSize += bytes.length;

    if (_thumbnailCache.length % 10 == 0) {
      developer.log(
        'Cache stats: ${_thumbnailCache.length} entries, ${(_currentCacheSize / 1024 / 1024).toStringAsFixed(2)}MB used',
        name: 'ImageCacheService',
      );
    }
  }

  String _getCacheKey(String filePath, int size) {
    final fileName = path.basenameWithoutExtension(filePath);
    final fileExt = path.extension(filePath);
    final fileStats = FileStat.statSync(filePath);
    final modified = fileStats.modified.millisecondsSinceEpoch;

    return '$fileName-$modified-$size$fileExt';
  }

  Future<File> _getThumbnailFile(String cacheKey) async {
    if (_cacheDir == null) {
      await initialize();
    }

    return File(path.join(_cacheDir!.path, cacheKey));
  }

  Future<void> clearCache() async {
    _thumbnailCache.clear();
    _cacheAccessOrder.clear();
    _currentCacheSize = 0;

    if (_cacheDir != null && await _cacheDir!.exists()) {
      await _cacheDir!.delete(recursive: true);
      await _cacheDir!.create(recursive: true);
    }

    developer.log('Image cache cleared', name: 'ImageCacheService');
  }
}

class ThumbnailParams {
  final Uint8List bytes;
  final int size;

  ThumbnailParams(this.bytes, this.size);
}

Uint8List? _decodeThumbnail(ThumbnailParams params) {
  try {
    final image = img.decodeImage(params.bytes);
    if (image == null) return null;

    int width, height;
    if (image.width > image.height) {
      width = params.size;
      height = (params.size * image.height / image.width).round();
    } else {
      height = params.size;
      width = (params.size * image.width / image.height).round();
    }

    final resized = img.copyResize(
      image,
      width: width,
      height: height,
      interpolation: img.Interpolation.average,
    );

    final pngBytes = img.encodePng(resized);

    return pngBytes;
  } catch (e) {
    debugPrint('Error in _decodeThumbnail: $e');
  }

  return null;
}
