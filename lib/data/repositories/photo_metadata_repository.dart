import 'dart:convert';
import 'dart:developer' as developer;
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';

import '../models/photo_metadata.dart';
import '../services/vrcx_metadata_service.dart';

class PhotoMetadataRepository {
  static const String _photoIdsKey = 'gallevr_photo_ids';
  static const String _photoMetadataKeyPrefix = 'gallevr_photo_';

  // In-memory cache to avoid repeated SharedPreferences reads
  static final Map<String, PhotoMetadata> _metadataCache = {};
  static final Map<String, String> _filePathToIdCache = {};
  static bool _cacheInitialized = false;
  static SharedPreferences? _prefs;

  // Background processing queue to avoid blocking UI
  static final Map<String, Future<PhotoMetadata?>> _processingQueue = {};

  /// Initialize the cache by loading all metadata once
  Future<void> _initializeCache() async {
    if (_cacheInitialized) return;

    try {
      _prefs ??= await SharedPreferences.getInstance();
      final photoIds = _prefs!.getStringList(_photoIdsKey) ?? [];

      for (final photoId in photoIds) {
        final metadataJson = _prefs!.getString('$_photoMetadataKeyPrefix$photoId');
        if (metadataJson != null) {
          try {
            final metadata = PhotoMetadata.fromJson(json.decode(metadataJson));
            _metadataCache[photoId] = metadata;
            
            // Build reverse lookup cache for file paths
            if (metadata.localPath != null) {
              _filePathToIdCache[metadata.localPath!] = photoId;
            }
            _filePathToIdCache[metadata.filename] = photoId;
          } catch (e) {
            developer.log(
              'Error parsing cached metadata for $photoId: $e',
              name: 'PhotoMetadataRepository',
            );
          }
        }
      }

      _cacheInitialized = true;
      developer.log(
        'Metadata cache initialized with ${_metadataCache.length} entries',
        name: 'PhotoMetadataRepository',
      );
    } catch (e) {
      developer.log(
        'Error initializing metadata cache: $e',
        name: 'PhotoMetadataRepository',
        error: e,
      );
    }
  }

  Future<bool> savePhotoMetadata(PhotoMetadata metadata) async {
    try {
      _prefs ??= await SharedPreferences.getInstance();
      await _initializeCache();

      final photoId = '${metadata.filename}_${metadata.takenDate}';

      // Check for existing metadata
      final existingId = _findExistingPhotoId(metadata.localPath ?? metadata.filename);
      
      if (existingId != null) {
        // Update existing metadata
        final existingMetadata = _metadataCache[existingId]!;
        final updatedMetadata = existingMetadata.copyWith(
          world: metadata.world ?? existingMetadata.world,
          players: metadata.players.isNotEmpty ? metadata.players : existingMetadata.players,
          galleryUrl: metadata.galleryUrl ?? existingMetadata.galleryUrl,
        );

        final metadataJson = json.encode(updatedMetadata.toJson());
        await _prefs!.setString('$_photoMetadataKeyPrefix$existingId', metadataJson);
        
        // Update cache
        _metadataCache[existingId] = updatedMetadata;
        
        return true;
      } else {
        // Save new metadata
        final metadataJson = json.encode(metadata.toJson());
        await _prefs!.setString('$_photoMetadataKeyPrefix$photoId', metadataJson);

        final photoIds = _prefs!.getStringList(_photoIdsKey) ?? [];
        if (!photoIds.contains(photoId)) {
          photoIds.add(photoId);
          await _prefs!.setStringList(_photoIdsKey, photoIds);
        }

        // Update cache
        _metadataCache[photoId] = metadata;
        if (metadata.localPath != null) {
          _filePathToIdCache[metadata.localPath!] = photoId;
        }
        _filePathToIdCache[metadata.filename] = photoId;

        return true;
      }
    } catch (e) {
      developer.log(
        'Error saving photo metadata: $e',
        name: 'PhotoMetadataRepository',
        error: e,
      );
      return false;
    }
  }

  Future<PhotoMetadata?> getPhotoMetadata(String photoId) async {
    await _initializeCache();
    return _metadataCache[photoId];
  }

  Future<List<PhotoMetadata>> getAllPhotoMetadata() async {
    await _initializeCache();
    final result = _metadataCache.values.toList();
    result.sort((a, b) => b.takenDate.compareTo(a.takenDate));
    return result;
  }

  ///  version that avoids loading all metadata
  Future<PhotoMetadata?> getPhotoMetadataForFile(String filePath) async {
    try {
      await _initializeCache();
      
      final filename = path.basename(filePath);

      // Fast lookup using cached file path mappings
      String? photoId = _filePathToIdCache[filePath] ?? _filePathToIdCache[filename];
      
      if (photoId != null) {
        final metadata = _metadataCache[photoId];
        if (metadata != null) {
          return metadata;
        }
      }

      // Fallback: search by filename contains (less common case)
      final filenameWithoutExt = path.basenameWithoutExtension(filePath);
      for (final metadata in _metadataCache.values) {
        if (metadata.filename.contains(filenameWithoutExt)) {
          // Update cache for faster future lookups
          final metadataId = '${metadata.filename}_${metadata.takenDate}';
          _filePathToIdCache[filePath] = metadataId;
          return metadata;
        }
      }

      // Check if we're already processing this file
      if (_processingQueue.containsKey(filePath)) {
        return await _processingQueue[filePath];
      }

      // Process VRCX metadata in background
      final future = _processVrcxMetadataBackground(filePath);
      _processingQueue[filePath] = future;
      
      final result = await future;
      _processingQueue.remove(filePath);
      
      return result;
    } catch (e) {
      developer.log(
        'Error getting photo metadata for file: $e',
        name: 'PhotoMetadataRepository',
        error: e,
      );
      return null;
    }
  }

  /// Background processing of VRCX metadata to avoid blocking UI
  Future<PhotoMetadata?> _processVrcxMetadataBackground(String filePath) async {
    return await compute(_extractAndSaveVrcxMetadata, {
      'filePath': filePath,
      'cacheData': {
        'photoIds': _prefs?.getStringList(_photoIdsKey) ?? [],
        'metadataPrefix': _photoMetadataKeyPrefix,
      }
    });
  }

  String? _findExistingPhotoId(String filePath) {
    final filename = path.basename(filePath);
    
    // Direct path match
    String? photoId = _filePathToIdCache[filePath];
    if (photoId != null) return photoId;
    
    // Filename match
    photoId = _filePathToIdCache[filename];
    if (photoId != null) return photoId;
    
    return null;
  }

  Future<bool> deletePhotoMetadata(String photoId) async {
    try {
      _prefs ??= await SharedPreferences.getInstance();
      
      await _prefs!.remove('$_photoMetadataKeyPrefix$photoId');

      final photoIds = _prefs!.getStringList(_photoIdsKey) ?? [];
      photoIds.remove(photoId);
      await _prefs!.setStringList(_photoIdsKey, photoIds);

      // Update cache
      final metadata = _metadataCache.remove(photoId);
      if (metadata != null) {
        _filePathToIdCache.removeWhere((key, value) => value == photoId);
      }

      return true;
    } catch (e) {
      developer.log(
        'Error deleting photo metadata: $e',
        name: 'PhotoMetadataRepository',
        error: e,
      );
      return false;
    }
  }

  /// Clears all caches and forces reload
  void clearCache() {
    _metadataCache.clear();
    _filePathToIdCache.clear();
    _processingQueue.clear();
    _cacheInitialized = false;
    VrcxMetadataService().clearCache();
    
    developer.log(
      'All metadata caches cleared',
      name: 'PhotoMetadataRepository',
    );
  }

  /// Batch load metadata for multiple files (for better performance)
  Future<Map<String, PhotoMetadata?>> getMetadataForFiles(List<String> filePaths) async {
    await _initializeCache();
    
    final result = <String, PhotoMetadata?>{};
    final toProcess = <String>[];
    
    // First pass: get cached results
    for (final filePath in filePaths) {
      final filename = path.basename(filePath);
      final photoId = _filePathToIdCache[filePath] ?? _filePathToIdCache[filename];
      
      if (photoId != null) {
        result[filePath] = _metadataCache[photoId];
      } else {
        toProcess.add(filePath);
      }
    }
    
    // Second pass: process remaining files in background
    if (toProcess.isNotEmpty) {
      final futures = toProcess.map((filePath) => 
        getPhotoMetadataForFile(filePath).then((metadata) => 
          MapEntry(filePath, metadata)
        )
      );
      
      final processed = await Future.wait(futures);
      for (final entry in processed) {
        result[entry.key] = entry.value;
      }
    }
    
    return result;
  }
}

/// Background function for VRCX metadata extraction
Future<PhotoMetadata?> _extractAndSaveVrcxMetadata(Map<String, dynamic> params) async {
  try {
    final filePath = params['filePath'] as String;
    
    // Extract VRCX metadata
    final vrcxService = VrcxMetadataService();
    final vrcxMetadata = await vrcxService.extractVrcxMetadata(filePath);
    
    if (vrcxMetadata != null) {
      // Note: We can't save to SharedPreferences from background isolate
      // The main thread will need to handle saving
      return vrcxMetadata;
    }
    
    return null;
  } catch (e) {
    return null;
  }
}