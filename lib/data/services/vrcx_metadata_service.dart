import 'dart:convert';
import 'dart:io';
import 'dart:developer' as developer;
import 'package:gallevr/data/models/log_metadata.dart';
import 'package:gallevr/data/models/photo_metadata.dart';
import 'package:gallevr/core/native/gallevr_native.dart';
import 'package:gallevr/core/isolate/isolate_worker_pool.dart';
import 'package:path/path.dart' as path;

/// Service for extracting and converting VRCX metadata from image files
class VrcxMetadataService {
  static const String _logName = 'VrcxMetadataService';

  // Persistent caches to avoid repeated processing
  static final Set<String> _processedFiles = <String>{};
  static final Set<String> _nonVrcxFiles = <String>{};
  static final Map<String, PhotoMetadata> _metadataCache = <String, PhotoMetadata>{};
  
  // File modification time cache to detect changes
  static final Map<String, int> _fileModTimeCache = <String, int>{};

  /// Clears all caches
  void clearCache() {
    _processedFiles.clear();
    _nonVrcxFiles.clear();
    _metadataCache.clear();
    _fileModTimeCache.clear();
    developer.log('Cleared all VRCX metadata caches', name: _logName);
  }

  /// Batch process multiple files for better performance
  Future<Map<String, PhotoMetadata?>> extractMetadataForFiles(List<String> imagePaths) async {
    final result = <String, PhotoMetadata?>{};
    final toProcess = <String>[];
    
    // First pass: check caches and file modifications
    for (final imagePath in imagePaths) {
      final cachedResult = _getCachedResult(imagePath);
      if (cachedResult != null) {
        result[imagePath] = cachedResult.isEmpty ? null : cachedResult.first;
      } else {
        toProcess.add(imagePath);
      }
    }
    
    // Second pass: process remaining files
    if (toProcess.isNotEmpty) {
      final futures = toProcess.map((imagePath) => 
        extractVrcxMetadata(imagePath).then((metadata) => 
          MapEntry(imagePath, metadata)
        )
      );
      
      final processed = await Future.wait(futures);
      for (final entry in processed) {
        result[entry.key] = entry.value;
      }
    }
    
    return result;
  }

  /// Metadata extraction with better caching
  Future<PhotoMetadata?> extractVrcxMetadata(String imagePath) async {
    try {
      // Check if file has been modified since last processing
      final file = File(imagePath);
      if (!await file.exists()) {
        return null;
      }

      final stats = await file.stat();
      final modTime = stats.modified.millisecondsSinceEpoch;
      
      final cached = _getCached(imagePath, modTime);
      if (cached != null) return cached.isEmpty ? null : cached.first;

      final result = await IsolateWorkerPool().execute<String, PhotoMetadata?>(
        VrcxMetadataService.extractVrcxMetadataSync, 
        imagePath,
      );

      _updateCache(imagePath, modTime, result);
      return result;
    } catch (e) {
      developer.log('Error extracting VRCX metadata: $e', name: _logName, error: e);
      return null;
    }
  }

  static PhotoMetadata? extractVrcxMetadataSync(String imagePath) {
    try {
      if (!imagePath.toLowerCase().endsWith('.png')) return null;
      final vrcxJson = GalleVrNative().extractVrcxMetadata(imagePath);
      if (vrcxJson == null) return null;

      final vrcxMetadata = _parseVrcxMetadata(vrcxJson);
      if (vrcxMetadata == null) return null;

      return _convertToGalleVrMetadata(vrcxMetadata, imagePath);
    } catch (e) {
      return null;
    }
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

  static void _updateCache(String imagePath, int modTime, PhotoMetadata? result) {
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

///  JSON parsing with better error handling
Map<String, dynamic>? _parseVrcxMetadata(String jsonString) {
  try {
    // Find JSON boundaries more efficiently
    int startIndex = -1;
    int endIndex = -1;
    int braceCount = 0;
    
    for (int i = 0; i < jsonString.length; i++) {
      final char = jsonString[i];
      if (char == '{') {
        if (startIndex == -1) startIndex = i;
        braceCount++;
      } else if (char == '}') {
        braceCount--;
        if (braceCount == 0 && startIndex != -1) {
          endIndex = i;
          break;
        }
      }
    }
    
    if (startIndex == -1 || endIndex == -1) return null;
    
    final cleanedJson = jsonString.substring(startIndex, endIndex + 1);
    final json = jsonDecode(cleanedJson);
    
    // Quick validation
    if (json is Map<String, dynamic> && 
        json['application'] == 'VRCX' && 
        json['version'] != null) {
      return json;
    }
    
    return null;
  } catch (e) {
    return null;
  }
}

///  metadata conversion with reduced object creation
PhotoMetadata _convertToGalleVrMetadata(
  Map<String, dynamic> vrcxMetadata,
  String imagePath,
) {
  try {
    // Get file stats once
    final file = File(imagePath);
    final stats = file.statSync();
    final creationTimeMs = stats.modified.millisecondsSinceEpoch;
    final filename = path.basename(imagePath);

    // Extract world information efficiently
    WorldInfo? worldInfo;
    final worldData = vrcxMetadata['world'];
    if (worldData is Map<String, dynamic>) {
      final worldId = worldData['id'] as String?;
      final instanceIdStr = worldData['instanceId'] as String?;
      
      String? accessType;
      String? region;
      String? ownerId;
      bool? canRequestInvite;
      
      // Parse instance details if available
      if (instanceIdStr != null) {
        final parts = instanceIdStr.split('~');
        
        if (parts.length > 1) {
          final accessPart = parts[1];
          if (accessPart.startsWith('private(')) {
            accessType = 'private';
            final ownerMatch = RegExp(r'private\((usr_[^)]+)\)').firstMatch(accessPart);
            ownerId = ownerMatch?.group(1);
          } else {
            accessType = accessPart;
          }
        }
        
        if (parts.length > 2 && parts[2] == 'canRequestInvite') {
          canRequestInvite = true;
        }
        
        if (parts.length > 3) {
          final regionMatch = RegExp(r'region\(([^)]+)\)').firstMatch(parts[3]);
          region = regionMatch?.group(1);
        }
      }

      worldInfo = WorldInfo(
        name: worldData['name'] as String,
        id: worldId ?? '',
        instanceId: instanceIdStr,
        accessType: accessType,
        region: region,
        ownerId: ownerId,
        canRequestInvite: canRequestInvite,
      );
    }

    // Extract players efficiently
    final players = <Player>[];
    final playersData = vrcxMetadata['players'];
    if (playersData is List) {
      for (final playerData in playersData) {
        if (playerData is Map<String, dynamic>) {
          final id = playerData['id'] as String?;
          final displayName = playerData['displayName'] as String?;
          if (id != null && displayName != null) {
            players.add(Player(id: id, name: displayName));
          }
        }
      }
    }

    // Add author if not already included
    final authorData = vrcxMetadata['author'];
    if (authorData is Map<String, dynamic>) {
      final authorId = authorData['id'] as String?;
      final authorName = authorData['displayName'] as String?;
      
      if (authorId != null && authorName != null) {
        final authorExists = players.any((player) => player.id == authorId);
        if (!authorExists) {
          players.add(Player(id: authorId, name: authorName));
        }
      }
    }

    return PhotoMetadata(
      takenDate: creationTimeMs,
      filename: filename,
      views: 0,
      world: worldInfo,
      players: players,
      localPath: imagePath,
    );
  } catch (e) {
    // Return minimal valid metadata on error
    return PhotoMetadata(
      takenDate: DateTime.now().millisecondsSinceEpoch,
      filename: path.basename(imagePath),
      localPath: imagePath,
    );
  }
}