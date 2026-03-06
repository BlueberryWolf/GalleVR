import 'dart:io';
import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
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

  final Map<String, Uint8List> _thumbnailCache = {};

  int _currentCacheSize = 0;

  static const int _maxCacheEntries = 300;

  static const int _maxMemoryCacheSize = 80 * 1024 * 1024;

  Directory? _cacheDir;

  final List<String> _cacheAccessOrder = [];
  
  final Map<String, Future<Uint8List?>> _pendingRequests = {};
  
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
    if (_thumbnailCache.containsKey(filePath)) {
      _updateAccessOrder(filePath);
      return _thumbnailCache[filePath];
    }

    if (_pendingRequests.containsKey(filePath)) {
      return _pendingRequests[filePath];
    }

    final completer = Completer<Uint8List?>();
    _pendingRequests[filePath] = completer.future;

    try {
      final result = await _loadThumbnailInternal(filePath, size);
      completer.complete(result);
      return result;
    } catch (e) {
      completer.complete(null);
      return null;
    } finally {
      _pendingRequests.remove(filePath);
    }
  }

  Future<Uint8List?> _loadThumbnailInternal(String filePath, int size) async {
    try {
      if (_cacheDir == null) await initialize();
      
      final file = File(filePath);
      if (!await file.exists()) return null;

      final stat = await file.stat();
      final cacheKey = '${path.basenameWithoutExtension(filePath)}-${stat.modified.millisecondsSinceEpoch}-$size${path.extension(filePath)}';
      final cacheFile = File(path.join(_cacheDir!.path, cacheKey));

      if (await cacheFile.exists()) {
        try {
          final data = await cacheFile.readAsBytes();
          _addToMemoryCache(filePath, data);
          return data;
        } catch (e) {
          developer.log('Error reading disk cache: $e', name: 'ImageCacheService');
        }
      }

      try {
        final result = await FlutterImageCompress.compressWithFile(
          filePath,
          minWidth: size,
          minHeight: (size * 9 / 16).round(),
          quality: 80,
          format: CompressFormat.jpeg,
        );
        
        if (result != null) {
          _saveToDiskCache(cacheFile, result);
          _addToMemoryCache(filePath, result);
          return result;
        }
      } catch (e) {
        developer.log('Native compression failed for $filePath: $e', name: 'ImageCacheService');
      }

      await _waitForDecodeSlot();
      try {
        developer.log('Using Flutter Engine fallback for $filePath', name: 'ImageCacheService');
        final bytes = await file.readAsBytes();
        
        final ui.Codec codec = await ui.instantiateImageCodec(
          bytes,
          targetWidth: size,
          allowUpscaling: false,
        );
        
        final ui.FrameInfo frameInfo = await codec.getNextFrame();
        final ui.Image image = frameInfo.image;
        
        final ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
        if (byteData != null) {
          final result = byteData.buffer.asUint8List();
          _saveToDiskCache(cacheFile, result);
          _addToMemoryCache(filePath, result);
          return result;
        }
      } catch (e) {
        developer.log('Flutter Engine fallback failed for $filePath: $e', name: 'ImageCacheService');
      } finally {
        _releaseDecodeSlot();
      }
    } catch (e) {
      developer.log('Critical error generating thumbnail for $filePath: $e', name: 'ImageCacheService');
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

  Future<void> _saveToDiskCache(File cacheFile, Uint8List data) async {
    try {
      if (!await cacheFile.parent.exists()) {
        await cacheFile.parent.create(recursive: true);
      }
      await cacheFile.writeAsBytes(data);
    } catch (_) {}
  }

  void _updateAccessOrder(String key) {
    if (_cacheAccessOrder.contains(key)) {
      _cacheAccessOrder.remove(key);
    }
    _cacheAccessOrder.add(key);
  }

  void _addToMemoryCache(String key, Uint8List bytes) {
    _updateAccessOrder(key);

    if (_thumbnailCache.containsKey(key)) {
      _currentCacheSize -= _thumbnailCache[key]!.length;
    }

    while (_currentCacheSize + bytes.length > _maxMemoryCacheSize && _cacheAccessOrder.isNotEmpty) {
      final oldestKey = _cacheAccessOrder.removeAt(0);
      final oldBytes = _thumbnailCache.remove(oldestKey);
      if (oldBytes != null) _currentCacheSize -= oldBytes.length;
    }

    while (_thumbnailCache.length >= _maxCacheEntries && _cacheAccessOrder.isNotEmpty) {
      final oldestKey = _cacheAccessOrder.removeAt(0);
      final oldBytes = _thumbnailCache.remove(oldestKey);
      if (oldBytes != null) _currentCacheSize -= oldBytes.length;
    }

    _thumbnailCache[key] = bytes;
    _currentCacheSize += bytes.length;
  }

  Future<void> clearCache() async {
    _thumbnailCache.clear();
    _cacheAccessOrder.clear();
    _currentCacheSize = 0;

    if (_cacheDir != null && await _cacheDir!.exists()) {
      await _cacheDir!.delete(recursive: true);
      await _cacheDir!.create(recursive: true);
    }
  }
}
