import 'dart:convert';
import 'dart:io';
import 'dart:developer' as developer;
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gallevr/core/isolate/isolate_worker_pool.dart';

import '../models/photo_metadata.dart';
import '../services/vrcx_metadata_service.dart';

class PhotoMetadataRepository {
  static const String _photoIdsKey = 'gallevr_photo_ids';
  static const String _photoMetadataKeyPrefix = 'gallevr_photo_';
  
  // Regex to find VRChat filename pattern: VRChat_YYYY-MM-DD_HH-MM-SS.mmm_WIDTHxHEIGHT
  static final RegExp _vrcFilenameRegex = RegExp(
    r'VRChat_\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2}\.\d{3}(?:_\d+x\d+)?',
    caseSensitive: false,
  );

  // In-memory cache to avoid repeated SharedPreferences reads
  static final Map<String, PhotoMetadata> _metadataCache = {};
  static final Map<String, String> _filePathToIdCache = {};
  static bool _cacheInitialized = false;

  static SharedPreferences? _prefs;

  // Queue to prevent redundant processing of the same file
  static final Map<String, Future<PhotoMetadata?>> _processingQueue = {};

  // Singleton pattern
  static final PhotoMetadataRepository _instance = PhotoMetadataRepository._internal();
  factory PhotoMetadataRepository() => _instance;
  PhotoMetadataRepository._internal();

  Future<void> _initializeCache() async {
    if (_cacheInitialized && _prefs != null) return;

    try {
      _prefs ??= await SharedPreferences.getInstance();
      if (_cacheInitialized) return;

      developer.log('Initializing metadata cache...', name: 'PhotoMetadataRepository');
      final photoIds = _prefs?.getStringList(_photoIdsKey) ?? [];

      for (final id in photoIds) {
        final metadataJson = _prefs?.getString('$_photoMetadataKeyPrefix$id');
        if (metadataJson != null) {
          try {
            final metadata = PhotoMetadata.fromJson(jsonDecode(metadataJson));
            _metadataCache[id] = metadata;
            _addToLookupCaches(metadata, id);
          } catch (e) {
            developer.log('Error parsing metadata for $id: $e', name: 'PhotoMetadataRepository');
          }
        }
      }

      _cacheInitialized = true;
      developer.log('Metadata cache initialized with ${_metadataCache.length} entries', name: 'PhotoMetadataRepository');
      
      syncWithBackend();
    } catch (e) {
      developer.log('Error initializing metadata cache: $e', name: 'PhotoMetadataRepository');
    }
  }

  void _addToLookupCaches(PhotoMetadata metadata, String id) {
    if (metadata.localPath != null) {
      _filePathToIdCache[metadata.localPath!] = id;
    }
    _filePathToIdCache[metadata.filename] = id;
    
    final nameWithoutExt = path.basenameWithoutExtension(metadata.filename);
    final existingNameId = _filePathToIdCache[nameWithoutExt];
    if (existingNameId == null) {
      _filePathToIdCache[nameWithoutExt] = id;
    } else {
      final existingMeta = _metadataCache[existingNameId];
      if (metadata.galleryUrl != null && existingMeta?.galleryUrl == null) {
        _filePathToIdCache[nameWithoutExt] = id;
      }
    }
  }

  Future<void> syncWithBackend() async {
    try {
      developer.log('Syncing metadata with backend...', name: 'PhotoMetadataRepository');
      final backendPhotos = await VRChatService().fetchPhotoList();
      if (backendPhotos.isNotEmpty) {
        await savePhotoMetadataBatch(backendPhotos);
        developer.log('Synced ${backendPhotos.length} photos from backend', name: 'PhotoMetadataRepository');
      }
    } catch (e) {
      developer.log('Error syncing with backend: $e', name: 'PhotoMetadataRepository');
    }
  }

  Future<PhotoMetadata?> getPhotoMetadataForFile(String filePath) async {
    await _initializeCache();

    final filename = path.basename(filePath);
    final nameWithoutExt = path.basenameWithoutExtension(filename);

    String? photoId = _filePathToIdCache[filePath] ?? 
                     _filePathToIdCache[filename];

    if (photoId != null && _metadataCache.containsKey(photoId)) {
      return _metadataCache[photoId];
    }

    // check vrcx metadata from file
    if (filename.toLowerCase().endsWith('.png')) {
      try {
        final fileMetadata = await _processVrcxMetadataBackground(filePath);
        if (fileMetadata != null && fileMetadata.world != null) {
          developer.log('Extracted valid VRCX metadata directly from file: $filename', name: 'PhotoMetadataRepository');
          return fileMetadata;
        }
      } catch (e) {
        developer.log('Error during direct VRCX extraction: $e', name: 'PhotoMetadataRepository');
      }
    }

    // fuzzy database matching
    photoId = _filePathToIdCache[nameWithoutExt];
    if (photoId != null && _metadataCache.containsKey(photoId)) {
      return _metadataCache[photoId];
    }

    PhotoMetadata? bestFallback;
    for (final metadata in _metadataCache.values) {
      final originalNameBase = path.basenameWithoutExtension(metadata.filename);
      if (nameWithoutExt.contains(originalNameBase) || originalNameBase.contains(nameWithoutExt)) {
        if (metadata.galleryUrl != null) {
          bestFallback = metadata;
          break;
        }
        bestFallback ??= metadata;
      }
    }

    if (bestFallback != null) {
      final foundId = '${bestFallback.filename}_${bestFallback.takenDate}';
      _filePathToIdCache[nameWithoutExt] = foundId;
      return bestFallback;
    }

    // Regex Fallback: Search for the VRChat pattern within the current filename
    final match = _vrcFilenameRegex.firstMatch(filename);
    if (match != null) {
      final vrcBaseName = match.group(0)!;
      developer.log('Detected VRChat pattern in filename: $vrcBaseName', name: 'PhotoMetadataRepository');
      
      for (final metadata in _metadataCache.values) {
        if (metadata.filename.contains(vrcBaseName)) {
           developer.log('Recovered metadata via regex match for $vrcBaseName', name: 'PhotoMetadataRepository');
           return metadata;
        }
      }

      try {
        final config = AppServiceManager().config;
        if (config != null && config.photosDirectory.isNotEmpty) {
          final photosDir = Directory(config.photosDirectory);
          if (await photosDir.exists()) {
            File? originalFile;
            final originalName = '$vrcBaseName.png';
            
            await for (final entity in photosDir.list(recursive: true, followLinks: false)) {
              if (entity is File && path.basename(entity.path) == originalName) {
                originalFile = entity;
                break;
              }
            }

            if (originalFile != null) {
              developer.log('Found original file for smart matching: ${originalFile.path}', name: 'PhotoMetadataRepository');
              final extracted = await _processVrcxMetadataBackground(originalFile.path);
              if (extracted != null && extracted.world != null) {
                final merged = extracted.copyWith(
                  localPath: filePath,
                  filename: filename,
                );
                await savePhotoMetadata(merged);
                return merged;
              }
            }
          }
        }
      } catch (e) {
        developer.log('Error during smart matching: $e', name: 'PhotoMetadataRepository');
      }
    }

    if (_processingQueue.containsKey(filePath)) {
      return _processingQueue[filePath];
    }
    final processingFuture = _processVrcxMetadataBackground(filePath);
    _processingQueue[filePath] = processingFuture;

    try {
      final metadata = await processingFuture;
      if (metadata != null) {
        await savePhotoMetadata(metadata);
      }
      return metadata;
    } finally {
      _processingQueue.remove(filePath);
    }
  }

  Future<bool> savePhotoMetadata(PhotoMetadata metadata) async {
    return await savePhotoMetadataBatch([metadata]);
  }

  Future<bool> savePhotoMetadataBatch(List<PhotoMetadata> metadataList) async {
    if (metadataList.isEmpty) return true;
    await _initializeCache();

    final photoIds = _prefs?.getStringList(_photoIdsKey) ?? [];
    bool listChanged = false;

    for (var metadata in metadataList) {
      final photoId = '${metadata.filename}_${metadata.takenDate}';
      
      final nameWithoutExt = path.basenameWithoutExtension(metadata.filename);
      String? existingId = _filePathToIdCache[nameWithoutExt] ?? _filePathToIdCache[metadata.filename];
      
      if (existingId != null && _metadataCache.containsKey(existingId)) {
        final existing = _metadataCache[existingId]!;
        metadata = existing.copyWith(
          galleryUrl: metadata.galleryUrl ?? existing.galleryUrl,
          world: metadata.world ?? existing.world,
          players: metadata.players.isNotEmpty ? metadata.players : existing.players,
          views: metadata.views > 0 ? metadata.views : existing.views,
        );
        _metadataCache[existingId] = metadata;
        _addToLookupCaches(metadata, existingId);
        await _prefs?.setString('$_photoMetadataKeyPrefix$existingId', jsonEncode(metadata.toJson()));
      } else {
        _metadataCache[photoId] = metadata;
        _addToLookupCaches(metadata, photoId);
        
        if (!photoIds.contains(photoId)) {
          photoIds.add(photoId);
          listChanged = true;
        }
        await _prefs?.setString('$_photoMetadataKeyPrefix$photoId', jsonEncode(metadata.toJson()));
      }
    }

    if (listChanged) {
      await _prefs?.setStringList(_photoIdsKey, photoIds);
    }

    return true;
  }

  /// Extracts metadata in background worker
  Future<PhotoMetadata?> _processVrcxMetadataBackground(String filePath) async {
    final results = await _batchProcessMetadataBackground([filePath]);
    return results[filePath];
  }

  /// Batch extracts metadata in background worker
  Future<Map<String, PhotoMetadata?>> _batchProcessMetadataBackground(List<String> filePaths) async {
    final results = await IsolateWorkerPool().execute<List<String>, Map<String, PhotoMetadata?>>(_batchExtractMetadataTask, filePaths);
    
    final toSave = results.values.whereType<PhotoMetadata>().toList();
    if (toSave.isNotEmpty) {
      await savePhotoMetadataBatch(toSave);
    }
    
    return results;
  }

  Future<Map<String, PhotoMetadata>> getAllPhotoMetadata() async {
    await _initializeCache();
    return Map.from(_metadataCache);
  }

  Future<Map<String, PhotoMetadata?>> getMetadataForFiles(List<String> filePaths) async {
    await _initializeCache();
    
    final result = <String, PhotoMetadata?>{};
    final toProcess = <String>[];
    
    for (final filePath in filePaths) {
      final filename = path.basename(filePath);
      final nameWithoutExt = path.basenameWithoutExtension(filename);
      
      String? photoId = _filePathToIdCache[filePath] ?? 
                       _filePathToIdCache[filename] ?? 
                       _filePathToIdCache[nameWithoutExt];
      
      if (photoId != null && _metadataCache.containsKey(photoId)) {
        result[filePath] = _metadataCache[photoId];
      } else {
        PhotoMetadata? bestMeta;
        for (final metadata in _metadataCache.values) {
          final originalNameBase = path.basenameWithoutExtension(metadata.filename);
          if (nameWithoutExt.contains(originalNameBase) || originalNameBase.contains(nameWithoutExt)) {
            if (metadata.galleryUrl != null) {
              bestMeta = metadata;
              break;
            }
            bestMeta ??= metadata;
          }
        }
        if (bestMeta != null) {
          result[filePath] = bestMeta;
        } else {
          if (!_processingQueue.containsKey(filePath)) {
            toProcess.add(filePath);
          }
        }
      }
    }
    
    if (toProcess.isNotEmpty) {
      final batchFuture = _batchProcessMetadataBackground(toProcess);
      for (final filePath in toProcess) {
        _processingQueue[filePath] = batchFuture.then((map) => map[filePath]);
      }
      
      await batchFuture;
      for (final filePath in toProcess) {
        _processingQueue.remove(filePath);
      }
    }

    for (final filePath in filePaths) {
      if (result.containsKey(filePath)) continue;
      result[filePath] = await getPhotoMetadataForFile(filePath);
    }
    
    return result;
  }
}

Map<String, PhotoMetadata?> _batchExtractMetadataTask(List<String> filePaths) {
  final results = <String, PhotoMetadata?>{};
  for (final filePath in filePaths) {
    try {
      final metadata = VrcxMetadataService.extractVrcxMetadataSync(filePath);
      if (metadata != null) {
        results[filePath] = metadata;
      } else {
        results[filePath] = PhotoMetadata(
          takenDate: File(filePath).statSync().modified.millisecondsSinceEpoch,
          filename: path.basename(filePath),
          localPath: filePath,
          isNonVrcx: true,
        );
      }
    } catch (e) {
      results[filePath] = null;
    }
  }
  return results;
}