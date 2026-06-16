import 'dart:convert';
import 'dart:io';
import 'dart:developer' as developer;
import 'package:gallevr/data/models/log_metadata.dart';
import 'package:gallevr/data/models/photo_metadata.dart';
import 'package:gallevr/core/native/gallevr_native.dart';
import 'package:gallevr/core/isolate/isolate_worker_pool.dart';
import 'package:path/path.dart' as path;
import 'package:gallevr/data/services/vrchat_service.dart';

/// Service for extracting and converting VRCX metadata from image files
class VrcxMetadataService {
  static const String _logName = 'VrcxMetadataService';

  // Persistent caches to avoid repeated processing
  static final Set<String> _processedFiles = <String>{};
  static final Set<String> _nonVrcxFiles = <String>{};
  static final Map<String, PhotoMetadata> _metadataCache =
      <String, PhotoMetadata>{};

  // File modification time cache to detect changes
  static final Map<String, int> _fileModTimeCache = <String, int>{};

  /// Clears all caches
  void clearCache() {
    _processedFiles.clear();
    _nonVrcxFiles.clear();
    _metadataCache.clear();
    _fileModTimeCache.clear();
  }

  /// Batch process multiple files for better performance
  Future<Map<String, PhotoMetadata?>> extractMetadataForFiles(
    List<String> imagePaths,
  ) async {
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
      final futures = toProcess.map(
        (imagePath) => extractVrcxMetadata(
          imagePath,
        ).then((metadata) => MapEntry(imagePath, metadata)),
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
    try {
      final imagePath = params['imagePath'] as String;
      final authParams = params['authParams'] as Map<String, dynamic>?;
      final ext = imagePath.toLowerCase();
      if (!ext.endsWith('.png') &&
          !ext.endsWith('.jpg') &&
          !ext.endsWith('.jpeg') &&
          !ext.endsWith('.webp'))
        return null;
      final vrcxJson = GalleVrNative().extractVrcxMetadata(imagePath);
      if (vrcxJson == null) return null;

      final parsed = _parseVrcxMetadata(vrcxJson);
      if (parsed == null) return null;

      final metadata = _convertToGalleVrMetadata(parsed, imagePath, authParams);
      if (metadata == null && authParams == null) {
        final xmpData = parsed['xmp'] as Map<String, dynamic>?;
        final hasXmp =
            xmpData != null &&
            xmpData['worldId'] != null &&
            (xmpData['worldId'] as String).trim().isNotEmpty;
        if (hasXmp) {
          return PhotoMetadata(
            takenDate:
                File(imagePath).statSync().modified.millisecondsSinceEpoch,
            filename: path.basename(imagePath),
            localPath: imagePath,
            application: 'PENDING_AUTH',
          );
        }
      }
      return metadata;
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

  static void _updateCache(
    String imagePath,
    int modTime,
    PhotoMetadata? result,
  ) {
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

Map<String, dynamic>? _parseVrcxMetadata(String jsonString) {
  try {
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

    if (json is Map<String, dynamic> &&
        (json.containsKey('vrcx') ||
            json.containsKey('xmp') ||
            json.containsKey('resonite'))) {
      return json;
    }

    return null;
  } catch (e) {
    return null;
  }
}

PhotoMetadata? _convertToGalleVrMetadata(
  Map<String, dynamic> parsedJson,
  String imagePath,
  Map<String, dynamic>? authParams,
) {
  try {
    final file = File(imagePath);
    final stats = file.statSync();
    final creationTimeMs = stats.modified.millisecondsSinceEpoch;
    final filename = path.basename(imagePath);

    if (parsedJson['application'] == 'Resonite' &&
        parsedJson['resonite'] is Map<String, dynamic>) {
      final resData = parsedJson['resonite'] as Map<String, dynamic>;
      Map<String, dynamic>? v1Data;
      if (resData['v1Json'] != null) {
        try {
          v1Data =
              jsonDecode(resData['v1Json'] as String) as Map<String, dynamic>;
        } catch (_) {}
      }

      final String? locationName =
          resData['locationName'] as String? ??
          v1Data?['LocationName'] as String?;
      final String? locationUrl =
          resData['locationUrl'] as String? ??
          v1Data?['LocationURL'] as String?;

      final String? timeTakenStr =
          resData['timeTaken'] as String? ?? v1Data?['TimeTaken'] as String?;
      int takenDate = creationTimeMs;
      if (timeTakenStr != null && timeTakenStr.isNotEmpty) {
        final parsedDate = DateTime.tryParse(timeTakenStr);
        if (parsedDate != null) {
          takenDate = parsedDate.millisecondsSinceEpoch;
        }
      }

      final String? takenById =
          resData['takenById'] as String? ??
          (v1Data?['TakenBy'] as Map<String, dynamic>?)?['Id'] as String?;
      final String? takenByName =
          resData['takenByName'] as String? ??
          (v1Data?['TakenBy'] as Map<String, dynamic>?)?['Name'] as String?;

      final players = <Player>[];
      final v2Players = resData['players'];
      if (v2Players is List) {
        for (final p in v2Players) {
          if (p is Map<String, dynamic>) {
            final id = p['id'] as String?;
            final displayName = p['displayName'] as String?;
            var headPosition = p['headPosition'] as String?;
            final headOrientation = p['headOrientation'] as String?;
            final headScale = p['headScale'] as String?;
            final isInView = p['isInView'] as String?;

            if (id != null && id.isNotEmpty) {
              if (headPosition != null && headPosition.isNotEmpty) {
                final scaleVal = headScale ?? '1.0';
                final isInViewVal = (isInView == 'true' || isInView == '1') ? '1' : '0';
                final cleaned = headPosition.replaceAll('[', '').replaceAll(']', '').trim();
                final parts = cleaned.contains(';') ? cleaned.split(';') : cleaned.split(',');
                if (parts.length == 3) {
                  headPosition = '[${parts[0].trim()}; ${parts[1].trim()}; ${parts[2].trim()}; $scaleVal; $isInViewVal]';
                }
              }

              players.add(
                Player(
                  id: id,
                  name: displayName ?? id,
                  headPosition: headPosition,
                  headOrientation: headOrientation,
                ),
              );
            }
          }
        }
      }

      final v1UserInfos = v1Data?['UserInfos'];
      if (v1UserInfos is List) {
        for (final info in v1UserInfos) {
          if (info is Map<String, dynamic>) {
            final user = info['User'] as Map<String, dynamic>?;
            if (user != null) {
              final id = user['Id'] as String?;
              final name = user['Name'] as String?;
              final headPos = info['HeadPosition'] as String?;
              final headOri = info['HeadOrientation'] as String?;
              if (id != null && id.isNotEmpty) {
                if (!players.any((p) => p.id == id)) {
                  players.add(
                    Player(
                      id: id,
                      name: name ?? id,
                      headPosition: headPos,
                      headOrientation: headOri,
                    ),
                  );
                }
              }
            }
          }
        }
      }

      if (authParams != null) {
        final selfUserId = authParams['userId'] as String;
        final selfDisplayName =
            authParams['displayName'] as String? ?? selfUserId;
        if (takenById == selfUserId) {
          if (!players.any((p) => p.id == selfUserId)) {
            players.add(Player(id: selfUserId, name: selfDisplayName));
          }
        }
      }

      final String? pos = resData['takenGlobalPosition'] as String?;
      final String? rot = resData['takenGlobalRotation'] as String?;
      final String? scale = resData['takenGlobalScale'] as String?;
      final String? fov = resData['cameraFov'] as String?;
      final String? cameraManufacturer = resData['cameraManufacturer'] as String?;

      return PhotoMetadata(
        takenDate: takenDate,
        filename: filename,
        views: 0,
        world:
            locationName != null
                ? WorldInfo(id: locationUrl ?? '', name: locationName)
                : null,
        players: players,
        localPath: imagePath,
        application: 'Resonite',
        takenGlobalPosition: pos,
        takenGlobalRotation: rot,
        takenGlobalScale: scale,
        cameraFov: fov,
        cameraManufacturer: cameraManufacturer,
        takenById: takenById,
      );
    }

    final vrcxData = parsedJson['vrcx'] as Map<String, dynamic>?;
    final xmpData = parsedJson['xmp'] as Map<String, dynamic>?;

    // Try to extract world from VRCX
    WorldInfo? vrcxWorld;
    if (vrcxData != null && vrcxData['world'] is Map<String, dynamic>) {
      final worldData = vrcxData['world'] as Map<String, dynamic>;
      final id = worldData['id'] as String?;
      final name = worldData['name'] as String?;
      if (id != null &&
          id.trim().isNotEmpty &&
          name != null &&
          name.trim().isNotEmpty) {
        vrcxWorld = WorldInfo(
          id: id,
          name: name,
          instanceId: worldData['instanceId'] as String?,
        );
      }
    }

    // Try to extract world from XMP
    WorldInfo? xmpWorld;
    if (xmpData != null) {
      final id = xmpData['worldId'] as String?;
      final name = xmpData['worldName'] as String?;
      if (id != null &&
          id.trim().isNotEmpty &&
          name != null &&
          name.trim().isNotEmpty) {
        xmpWorld = WorldInfo(id: id, name: name);
      }
    }

    if (vrcxWorld == null && xmpWorld == null) {
      return null;
    }

    final worldInfo = vrcxWorld ?? xmpWorld;
    final application = vrcxWorld != null ? 'VRCX' : 'VRChat';

    String? authorName;
    String? authorId;
    if (vrcxWorld != null) {
      final authorData = vrcxData?['author'];
      if (authorData is Map<String, dynamic>) {
        authorId = authorData['id'] as String?;
        authorName = authorData['displayName'] as String?;
      }
    } else {
      authorName = xmpData?['author'] as String?;
      authorId = authParams?['userId'] as String?;
    }

    if (vrcxWorld == null) {
      bool authorMatches = false;
      if (authorName != null && authParams != null) {
        final cleanAuthor = authorName.trim().toLowerCase();
        final userIdStr = authParams['userId']?.toString();
        final cleanUserId = userIdStr?.trim().toLowerCase();
        final displayNameStr = authParams['displayName']?.toString();
        final cleanDisplayName = displayNameStr?.trim().toLowerCase();
        if (cleanAuthor == cleanUserId || cleanAuthor == cleanDisplayName) {
          authorMatches = true;
        }
      }
      if (!authorMatches) {
        return null;
      }
    }

    final players = <Player>[];
    if (vrcxData != null) {
      final playersData = vrcxData['players'];
      if (playersData is List) {
        for (final p in playersData) {
          if (p is Map<String, dynamic>) {
            final id = p['id'] as String?;
            final name = p['displayName'] as String?;
            if (id != null &&
                id.isNotEmpty &&
                name != null &&
                name.isNotEmpty) {
              players.add(Player(id: id, name: name));
            }
          }
        }
      }
    }

    if (authParams != null && authorName != null) {
      final cleanAuthorName = authorName.trim().toLowerCase();
      final cleanAuthorId = authorId?.trim().toLowerCase();

      final userIdStr = authParams['userId']?.toString();
      final cleanUserId = userIdStr?.trim().toLowerCase();

      final displayNameStr = authParams['displayName']?.toString();
      final cleanDisplayName = displayNameStr?.trim().toLowerCase();

      final matches =
          (cleanUserId != null &&
              (cleanAuthorId == cleanUserId ||
                  cleanAuthorName == cleanUserId)) ||
          (cleanDisplayName != null && cleanAuthorName == cleanDisplayName);

      if (matches) {
        final selfUserId = authParams['userId'] as String;
        final selfDisplayName =
            authParams['displayName'] as String? ?? selfUserId;
        final alreadyExists = players.any((p) => p.id == selfUserId);
        if (!alreadyExists) {
          players.add(Player(id: selfUserId, name: selfDisplayName));
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
      application: application,
    );
  } catch (e) {
    return null;
  }
}
