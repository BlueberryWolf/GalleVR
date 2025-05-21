import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
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

  // In-memory cache to track which files have already been processed
  static final Set<String> _processedFiles = <String>{};

  // In-memory cache to track which files have been checked but don't have VRCX metadata
  static final Set<String> _nonVrcxFiles = <String>{};

  /// Clears the cache of processed files
void clearCache() {
    _processedFiles.clear();
    _nonVrcxFiles.clear();
    developer.log(
      'Cleared VRCX metadata extraction cache',
      name: _logName,
    );
  }

  /// Extracts VRCX metadata from an image file and converts it to GalleVR's format
  ///
  /// Returns null if no VRCX metadata is found or if there's an error
  /// This method is optimized to run in a background thread to prevent UI lag
  Future<PhotoMetadata?> extractVrcxMetadata(String imagePath) async {
    try {
      // Check if we've already processed this file
      if (_processedFiles.contains(imagePath)) {
        developer.log(
          'File already processed with VRCX metadata, skipping: $imagePath',
          name: _logName,
        );
        return null; // We've already processed this file, so metadata should be in the repository
      }

      // Check if we've already determined this file doesn't have VRCX metadata
      if (_nonVrcxFiles.contains(imagePath)) {
        developer.log(
          'File already checked and has no VRCX metadata, skipping: $imagePath',
          name: _logName,
        );
        return null;
      }

      final file = File(imagePath);
      if (!await file.exists()) {
        developer.log(
          'File does not exist: $imagePath',
          name: _logName,
        );
        return null;
      }

      // Read the file bytes - only read the first part of the file to check if it's a PNG
      // Most PNG metadata is at the beginning of the file
      final fileSize = await file.length();
      final bytesToRead = fileSize > 1024 * 50 ? 1024 * 50 : fileSize; // Read at most 50KB

      final randomAccessFile = await file.open(mode: FileMode.read);
      final bytes = await randomAccessFile.read(bytesToRead);
      await randomAccessFile.close();

      // Quick check if this is a PNG file before proceeding
      if (bytes.length < 8 || !_isPngSignature(bytes.sublist(0, 8))) {
        developer.log(
          'Not a PNG file, skipping VRCX metadata extraction: $imagePath',
          name: _logName,
        );
        _nonVrcxFiles.add(imagePath); // Remember this isn't a PNG file
        return null;
      }

      // Process the metadata extraction in a background thread
      final result = await compute(_processVrcxMetadata, _MetadataExtractionParams(
        bytes: bytes,
        imagePath: imagePath,
      ));

      if (result == null) {
        // No VRCX metadata found, add to non-VRCX files cache
        _nonVrcxFiles.add(imagePath);
        return null;
      }

      // Successfully extracted VRCX metadata, add to processed files cache
      _processedFiles.add(imagePath);

      developer.log(
        'Successfully extracted VRCX metadata from: $imagePath',
        name: _logName,
      );

      return result;
    } catch (e) {
      developer.log(
        'Error extracting VRCX metadata: $e',
        name: _logName,
        error: e,
      );
      // Add to non-VRCX files to prevent repeated processing attempts
      _nonVrcxFiles.add(imagePath);
      return null;
    }
  }

  /// Checks if the given bytes match the PNG signature
  bool _isPngSignature(Uint8List bytes) {
    if (bytes.length < 8) return false;
    return bytes[0] == 137 && // 0x89
           bytes[1] == 80 &&  // 'P'
           bytes[2] == 78 &&  // 'N'
           bytes[3] == 71 &&  // 'G'
           bytes[4] == 13 &&  // CR
           bytes[5] == 10 &&  // LF
           bytes[6] == 26 &&  // SUB
           bytes[7] == 10;    // LF
  }

  /// Background processing function for VRCX metadata extraction
  static PhotoMetadata? _processVrcxMetadata(_MetadataExtractionParams params) {
    try {
      // Extract the Description field from PNG metadata
      final description = _extractPngDescriptionSync(params.bytes);

      if (description == null || description.isEmpty) {
        return null;
      }

      // Check if the Description contains VRCX metadata
      if (!description.contains('"application":"VRCX"') &&
          !description.contains('"application": "VRCX"')) {
        return null;
      }

      // Parse the VRCX metadata
      final vrcxMetadata = _parseVrcxMetadataSync(description);
      if (vrcxMetadata == null) {
        return null;
      }

      // Convert to GalleVR metadata format
      return _convertToGalleVrMetadataSync(vrcxMetadata, params.imagePath);
    } catch (e) {
      return null;
    }
  }

  /// Extracts the Description field from PNG metadata (synchronous version for background processing)
  static String? _extractPngDescriptionSync(Uint8List bytes) {
    try {
      // PNG files start with a signature followed by chunks
      // Each chunk has: length (4 bytes), type (4 bytes), data (length bytes), CRC (4 bytes)
      // We're looking for the tEXt or iTXt chunks that might contain the Description

      // Skip the PNG signature (8 bytes)
      int offset = 8;

      while (offset < bytes.length - 12) { // Need at least 12 bytes for chunk header and CRC
        // Read chunk length (4 bytes, big-endian)
        final lengthBytes = bytes.sublist(offset, offset + 4);
        final length = _bytesToIntSync(lengthBytes);
        offset += 4;

        // Read chunk type (4 bytes)
        final typeBytes = bytes.sublist(offset, offset + 4);
        final type = String.fromCharCodes(typeBytes);
        offset += 4;

        // Check if this is a text chunk
        if (type == 'tEXt' || type == 'iTXt') {
          final dataBytes = bytes.sublist(offset, offset + length);
          final data = String.fromCharCodes(dataBytes);

          // Check if this is the Description field
          if (data.startsWith('Description') || data.toLowerCase().contains('description')) {
            // For tEXt, the format is: keyword + null byte + text
            // For iTXt, it's more complex with compression flag, language, etc.
            final nullByteIndex = data.indexOf('\x00');
            if (nullByteIndex != -1 && nullByteIndex < data.length - 1) {
              return data.substring(nullByteIndex + 1);
            }
          }
        }

        // Skip the chunk data and CRC
        offset += length + 4;
      }

      return null;
    } catch (e) {
      return null;
    }
  }

  /// Converts bytes to an integer (big-endian) - sync version for background processing
  static int _bytesToIntSync(Uint8List bytes) {
    int result = 0;
    for (int i = 0; i < bytes.length; i++) {
      result = (result << 8) | bytes[i];
    }
    return result;
  }

  /// Parses VRCX metadata from a JSON string (synchronous version for background processing)
  static Map<String, dynamic>? _parseVrcxMetadataSync(String jsonString) {
    try {
      // Clean up the string before parsing
      String cleanedJson = jsonString.trim();

      // Try to find a JSON object in the string
      final startIndex = cleanedJson.indexOf('{');
      final endIndex = cleanedJson.lastIndexOf('}');

      if (startIndex >= 0 && endIndex > startIndex) {
        cleanedJson = cleanedJson.substring(startIndex, endIndex + 1);
      }

      final json = jsonDecode(cleanedJson);

      // Verify this is VRCX metadata
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

  /// Converts VRCX metadata to GalleVR's metadata format (synchronous version for background processing)
  static PhotoMetadata _convertToGalleVrMetadataSync(
    Map<String, dynamic> vrcxMetadata,
    String imagePath,
  ) {
    try {
      // Extract file information
      final file = File(imagePath);
      final stats = file.statSync();
      final creationTimeMs = stats.modified.millisecondsSinceEpoch;
      final filename = path.basename(imagePath);

      // Extract world information
      WorldInfo? worldInfo;
      if (vrcxMetadata['world'] != null) {
        final world = vrcxMetadata['world'] as Map<String, dynamic>;

        String? worldId;
        String? instanceId;
        String? accessType;
        String? region;
        String? ownerId;
        bool? canRequestInvite;

        // Extract world ID
        if (world['id'] != null) {
          worldId = world['id'] as String;
        }

        // Extract instance information from instanceId
        if (world['instanceId'] != null) {
          final instanceIdStr = world['instanceId'] as String;
          instanceId = instanceIdStr;

          // Parse instance details (format: wrld_xxx:123~private(usr_xxx)~canRequestInvite~region(use))
          final parts = instanceIdStr.split('~');

          // Extract access type
          if (parts.length > 1 && parts[1].isNotEmpty) {
            final accessPart = parts[1];
            if (accessPart.startsWith('private(')) {
              accessType = 'private';
              // Extract owner ID
              final ownerMatch = RegExp(r'private\((usr_[^)]+)\)').firstMatch(accessPart);
              if (ownerMatch != null) {
                ownerId = ownerMatch.group(1);
              }
            } else {
              accessType = accessPart;
            }
          }

          // Extract canRequestInvite
          if (parts.length > 2 && parts[2] == 'canRequestInvite') {
            canRequestInvite = true;
          }

          // Extract region
          if (parts.length > 3 && parts[3].startsWith('region(')) {
            final regionMatch = RegExp(r'region\(([^)]+)\)').firstMatch(parts[3]);
            if (regionMatch != null) {
              region = regionMatch.group(1);
            }
          }
        }

        worldInfo = WorldInfo(
          name: world['name'] as String,
          id: worldId ?? '',
          instanceId: instanceId,
          accessType: accessType,
          region: region,
          ownerId: ownerId,
          canRequestInvite: canRequestInvite,
        );
      }

      // Extract player information
      final players = <Player>[];
      if (vrcxMetadata['players'] != null) {
        final playersList = vrcxMetadata['players'] as List<dynamic>;

        for (final playerData in playersList) {
          if (playerData is Map<String, dynamic> &&
              playerData['id'] != null &&
              playerData['displayName'] != null) {
            players.add(Player(
              id: playerData['id'] as String,
              name: playerData['displayName'] as String,
            ));
          }
        }
      }

      // Add author as a player if not already included
      if (vrcxMetadata['author'] != null) {
        final author = vrcxMetadata['author'] as Map<String, dynamic>;
        if (author['id'] != null && author['displayName'] != null) {
          final authorId = author['id'] as String;

          // Check if author is already in players list
          final authorExists = players.any((player) => player.id == authorId);

          if (!authorExists) {
            players.add(Player(
              id: authorId,
              name: author['displayName'] as String,
            ));
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
      // If there's any error, return a minimal valid PhotoMetadata
      return PhotoMetadata(
        takenDate: DateTime.now().millisecondsSinceEpoch,
        filename: path.basename(imagePath),
        localPath: imagePath,
      );
    }
  }
}
