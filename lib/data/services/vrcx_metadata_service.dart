import 'dart:io';
import 'dart:developer' as developer;
import 'package:gallevr/core/isolate/isolate_worker_pool.dart';
import 'package:gallevr/core/metadata/vrcx_metadata_extractor.dart' as extractor;
import 'package:gallevr/data/models/photo_metadata.dart';
import 'package:gallevr/data/services/vrchat_service.dart';

class VrcxMetadataService {
  static const String _logName = 'VrcxMetadataService';

  static final Map<String, PhotoMetadata> _metadataCache = {};
  static final Map<String, int> _fileModTimeCache = {};
  static final Set<String> _processedFiles = {};
  static final Set<String> _nonVrcxFiles = {};

  static final VrcxMetadataService _instance = VrcxMetadataService._internal();
  factory VrcxMetadataService() => _instance;
  VrcxMetadataService._internal();

  void clearCache() {
    _metadataCache.clear();
    _fileModTimeCache.clear();
    _processedFiles.clear();
    _nonVrcxFiles.clear();
  }

  Future<Map<String, PhotoMetadata?>> batchExtractMetadata(
    List<String> imagePaths,
  ) async {
    final result = <String, PhotoMetadata?>{};
    final uncachedPaths = <String>[];

    for (final p in imagePaths) {
      final cached = _getCachedResult(p);
      if (cached != null) {
        result[p] = cached.isEmpty ? null : cached.first;
      } else {
        uncachedPaths.add(p);
      }
    }

    if (uncachedPaths.isEmpty) return result;

    final futures = <Future<MapEntry<String, PhotoMetadata?>>>[];
    for (final p in uncachedPaths) {
      futures.add(extractVrcxMetadata(p).then((meta) => MapEntry(p, meta)));
    }

    final entries = await Future.wait(futures);
    for (final entry in entries) {
      result[entry.key] = entry.value;
    }

    return result;
  }

  Future<PhotoMetadata?> extractVrcxMetadata(String imagePath) async {
    try {
      final file = File(imagePath);
      if (!await file.exists()) {
        return null;
      }

      final stats = await file.stat();
      final modTime = stats.modified.millisecondsSinceEpoch;

      final cached = _getCached(imagePath, modTime);
      if (cached != null) return cached.isEmpty ? null : cached.first;

      final authData = await VRChatService().loadAuthData();
      final authParams =
          authData != null
              ? {'userId': authData.userId, 'displayName': authData.displayName}
              : null;

      final result = await IsolateWorkerPool()
          .execute<Map<String, dynamic>, PhotoMetadata?>(
            VrcxMetadataService.extractVrcxMetadataSync,
            {'imagePath': imagePath, 'authParams': authParams},
          );

      if (result != null && result.application == 'PENDING_AUTH') {
        return null;
      }

      _updateCache(imagePath, modTime, result);
      return result;
    } catch (e) {
      developer.log(
        'Error extracting VRCX metadata: $e',
        name: _logName,
        error: e,
      );
      return null;
    }
  }

  static PhotoMetadata? extractVrcxMetadataSync(Map<String, dynamic> params) {
    return extractor.extractVrcxMetadataSync(params);
  }

  static List<PhotoMetadata>? _getCached(String imagePath, int modTime) {
    final cachedModTime = _fileModTimeCache[imagePath];
    if (cachedModTime == modTime) {
      if (_processedFiles.contains(imagePath)) {
        final metadata = _metadataCache[imagePath];
        if (metadata != null) return [metadata];
      }
      if (_nonVrcxFiles.contains(imagePath)) return [];
    }
    return null;
  }

  static const int _maxCacheEntries = 500;

  static void _updateCache(
    String imagePath,
    int modTime,
    PhotoMetadata? result,
  ) {
    if (_fileModTimeCache.length >= _maxCacheEntries) {
      final keyToRemove = _fileModTimeCache.keys.first;
      _fileModTimeCache.remove(keyToRemove);
      _processedFiles.remove(keyToRemove);
      _metadataCache.remove(keyToRemove);
      _nonVrcxFiles.remove(keyToRemove);
    }
    _fileModTimeCache[imagePath] = modTime;
    if (result != null) {
      _processedFiles.add(imagePath);
      _metadataCache[imagePath] = result;
      _nonVrcxFiles.remove(imagePath);
    } else {
      _processedFiles.remove(imagePath);
      _metadataCache.remove(imagePath);
      _nonVrcxFiles.add(imagePath);
    }
  }

  List<PhotoMetadata>? _getCachedResult(String imagePath) {
    try {
      final file = File(imagePath);
      final stats = file.statSync();
      return _getCached(imagePath, stats.modified.millisecondsSinceEpoch);
    } catch (e) {
      return null;
    }
  }
}
