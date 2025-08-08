import 'dart:convert';
import 'dart:io';
import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';

import 'package:gallevr/data/models/log_metadata.dart';
import 'package:gallevr/data/models/photo_metadata.dart';
import 'package:path/path.dart' as path;

/// Parameters for VRCX metadata extraction
class _MetadataExtractionParams {
  final Uint8List bytes;
  final String imagePath;

  _MetadataExtractionParams({
    required this.bytes,
    required this.imagePath,
  });
}

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

  /// metadata extraction with better caching
  Future<PhotoMetadata?> extractVrcxMetadata(String imagePath) async {
    try {
      // Check if file has been modified since last processing
      final file = File(imagePath);
      if (!await file.exists()) {
        return null;
      }

      final stats = await file.stat();
      final modTime = stats.modified.millisecondsSinceEpoch;
      final cachedModTime = _fileModTimeCache[imagePath];
      
      // If file hasn't changed, use cached result
      if (cachedModTime == modTime) {
        if (_processedFiles.contains(imagePath)) {
          return _metadataCache[imagePath];
        }
        if (_nonVrcxFiles.contains(imagePath)) {
          return null;
        }
      } else {
        // File changed, clear old cache entries
        _processedFiles.remove(imagePath);
        _nonVrcxFiles.remove(imagePath);
        _metadataCache.remove(imagePath);
        _fileModTimeCache[imagePath] = modTime;
      }

      // Quick file type check before reading bytes
      if (!imagePath.toLowerCase().endsWith('.png')) {
        _nonVrcxFiles.add(imagePath);
        return null;
      }

      // Read only the header portion for PNG signature check
      final randomAccessFile = await file.open(mode: FileMode.read);
      final headerBytes = await randomAccessFile.read(8);
      
      if (!_isPngSignature(headerBytes)) {
        await randomAccessFile.close();
        _nonVrcxFiles.add(imagePath);
        return null;
      }

      // Read metadata portion (typically in first 64KB of PNG files)
      await randomAccessFile.setPosition(0);
      final fileSize = await file.length();
      final bytesToRead = fileSize > 1024 * 64 ? 1024 * 64 : fileSize;
      final bytes = await randomAccessFile.read(bytesToRead);
      await randomAccessFile.close();

      // Process in background isolate
      final result = await compute(_processVrcxMetadata, _MetadataExtractionParams(
        bytes: bytes,
        imagePath: imagePath,
      ));

      if (result == null) {
        _nonVrcxFiles.add(imagePath);
        return null;
      }

      // Cache successful result
      _processedFiles.add(imagePath);
      _metadataCache[imagePath] = result;

      return result;
    } catch (e) {
      developer.log('Error extracting VRCX metadata: $e', name: _logName, error: e);
      _nonVrcxFiles.add(imagePath);
      return null;
    }
  }

  /// Get cached result if available
  List<PhotoMetadata>? _getCachedResult(String imagePath) {
    try {
      final file = File(imagePath);
      final stats = file.statSync();
      final modTime = stats.modified.millisecondsSinceEpoch;
      final cachedModTime = _fileModTimeCache[imagePath];
      
      if (cachedModTime == modTime) {
        if (_processedFiles.contains(imagePath)) {
          final metadata = _metadataCache[imagePath];
          return metadata != null ? [metadata] : [];
        }
        if (_nonVrcxFiles.contains(imagePath)) {
          return []; // Empty list indicates "no metadata"
        }
      }
    } catch (e) {
      // File access error, remove from caches
      _processedFiles.remove(imagePath);
      _nonVrcxFiles.remove(imagePath);
      _metadataCache.remove(imagePath);
      _fileModTimeCache.remove(imagePath);
    }
    
    return null; // Null indicates "not cached"
  }

  ///  PNG signature check
  bool _isPngSignature(Uint8List bytes) {
    if (bytes.length < 8) return false;
    
    // PNG signature: 89 50 4E 47 0D 0A 1A 0A
    return bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47 &&
           bytes[4] == 0x0D && bytes[5] == 0x0A && bytes[6] == 0x1A && bytes[7] == 0x0A;
  }

  /// Get cache statistics for debugging
  Map<String, int> getCacheStats() {
    return {
      'processedFiles': _processedFiles.length,
      'nonVrcxFiles': _nonVrcxFiles.length,
      'metadataCache': _metadataCache.length,
      'fileModTimeCache': _fileModTimeCache.length,
    };
  }
}

///  background processing function
PhotoMetadata? _processVrcxMetadata(_MetadataExtractionParams params) {
  try {
    // Fast PNG chunk parsing with early exit
    final description = _extractPngDescription(params.bytes);
    
    if (description == null || description.isEmpty) {
      return null;
    }

    // Quick VRCX check before JSON parsing
    if (!description.contains('"application"') || 
        (!description.contains('"VRCX"') && !description.contains(': "VRCX"'))) {
      return null;
    }

    // Parse VRCX metadata
    final vrcxMetadata = _parseVrcxMetadata(description);
    if (vrcxMetadata == null) {
      return null;
    }

    // Convert to GalleVR format
    return _convertToGalleVrMetadata(vrcxMetadata, params.imagePath);
  } catch (e) {
    return null;
  }
}

///  PNG description extraction with early exit
String? _extractPngDescription(Uint8List bytes) {
  try {
    // Skip PNG signature
    int offset = 8;
    
    // Limit search to reasonable chunk count to avoid infinite loops
    int chunkCount = 0;
    const maxChunks = 50;
    
    while (offset < bytes.length - 12 && chunkCount < maxChunks) {
      chunkCount++;
      
      // Read chunk length (big-endian)
      if (offset + 4 > bytes.length) break;
      final length = (bytes[offset] << 24) | (bytes[offset + 1] << 16) | 
                    (bytes[offset + 2] << 8) | bytes[offset + 3];
      offset += 4;
      
      // Sanity check for chunk length
      if (length < 0 || length > bytes.length - offset) break;
      
      // Read chunk type
      if (offset + 4 > bytes.length) break;
      final type = String.fromCharCodes(bytes.sublist(offset, offset + 4));
      offset += 4;
      
      // Check for text chunks
      if (type == 'tEXt' || type == 'iTXt') {
        if (offset + length > bytes.length) break;
        
        final dataBytes = bytes.sublist(offset, offset + length);
        final data = String.fromCharCodes(dataBytes);
        
        // Quick check for Description field
        if (data.startsWith('Description') || data.contains('Description')) {
          final nullByteIndex = data.indexOf('\x00');
          if (nullByteIndex != -1 && nullByteIndex < data.length - 1) {
            final description = data.substring(nullByteIndex + 1);
            // Quick VRCX check before returning
            if (description.contains('VRCX')) {
              return description;
            }
          }
        }
      }
      
      // Skip chunk data and CRC
      offset += length + 4;
      
      // Early exit if we've found IDAT (image data) - metadata should come before this
      if (type == 'IDAT') break;
    }
    
    return null;
  } catch (e) {
    return null;
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