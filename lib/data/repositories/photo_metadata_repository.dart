import 'dart:convert';
import 'dart:io';
import 'dart:developer' as developer;
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gallevr/core/isolate/isolate_worker_pool.dart';
import 'package:path_provider/path_provider.dart';

import '../models/photo_metadata.dart';
import '../services/vrcx_metadata_service.dart';
import '../services/vrchat_service.dart';
import '../services/app_service_manager.dart';
import '../models/log_metadata.dart';

import 'package:sqflite/sqflite.dart';
import '../database/app_database.dart';

class PhotoMetadataRepository {
  static const String _photoIdsKey = 'gallevr_photo_ids';
  static const String _photoMetadataKeyPrefix = 'gallevr_photo_';
  static const String _migrationDoneKey = 'gallevr_webp_migration_v2_done';
  static const String _sqliteMigrationDoneKey = 'gallevr_sqlite_migration_done';

  // Regex to find VRChat filename pattern: VRChat_YYYY-MM-DD_HH-MM-SS.mmm_WIDTHxHEIGHT
  static final RegExp _vrcFilenameRegex = RegExp(
    r'VRChat_\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2}\.\d{3}(?:_\d+x\d+)?',
    caseSensitive: false,
  );

  static final PhotoMetadataRepository _instance =
      PhotoMetadataRepository._internal();
  factory PhotoMetadataRepository() => _instance;
  PhotoMetadataRepository._internal();

  static SharedPreferences? _prefs;

  // Queue to prevent redundant processing of the same file
  static final Map<String, Future<PhotoMetadata?>> _processingQueue = {};

  Future<void> _initializeCache() async {
    try {
      _prefs ??= await SharedPreferences.getInstance();

      // Check if you still have legacy photo data stored in SharedPreferences
      final hasLegacyData = _prefs?.containsKey(_photoIdsKey) ?? false;
      if (hasLegacyData) {
        await _migrateToSqlite();
        await _prefs?.setBool(_sqliteMigrationDoneKey, true);
      }

      _checkAndMigrateLegacyMetadata();
      syncWithBackend();
    } catch (e) {
      developer.log(
        'Error initializing metadata repository: $e',
        name: 'PhotoMetadataRepository',
      );
    }
  }

  Future<void> _migrateToSqlite() async {
    final photoIds = _prefs?.getStringList(_photoIdsKey) ?? [];
    if (photoIds.isEmpty) return;

    final List<PhotoMetadata> toMigrate = [];
    for (final id in photoIds) {
      final jsonStr = _prefs?.getString('$_photoMetadataKeyPrefix$id');
      if (jsonStr != null) {
        try {
          toMigrate.add(PhotoMetadata.fromJson(jsonDecode(jsonStr)));
        } catch (e) {
          developer.log(
            'Error decoding $id during migration: $e',
            name: 'PhotoMetadataRepository',
          );
        }
      }
    }

    if (toMigrate.isNotEmpty) {
      await savePhotoMetadataBatch(toMigrate);
      developer.log(
        'Migrated ${toMigrate.length} entries to SQLite',
        name: 'PhotoMetadataRepository',
      );
    }

    for (final id in photoIds) {
      await _prefs?.remove('$_photoMetadataKeyPrefix$id');
    }
    await _prefs?.remove(_photoIdsKey);
  }

  PhotoMetadata _fromDbMap(
    Map<String, dynamic> map, [
    List<Player> players = const [],
  ]) {
    final hasWorld = map['world_id'] != null || map['world_name'] != null;
    final world =
        hasWorld
            ? WorldInfo(
              id: map['world_id'] as String? ?? '',
              name: map['world_name'] as String? ?? '',
              instanceId: map['world_instance_id'] as String?,
              accessType: map['world_access_type'] as String?,
              region: map['world_region'] as String?,
              ownerId: map['world_owner_id'] as String?,
              groupId: map['world_group_id'] as String?,
              groupAccessType: map['world_group_access_type'] as String?,
              canRequestInvite:
                  map['world_can_request_invite'] == null
                      ? null
                      : (map['world_can_request_invite'] as int) == 1,
              inviteOnly:
                  map['world_invite_only'] == null
                      ? null
                      : (map['world_invite_only'] as int) == 1,
            )
            : null;

    return PhotoMetadata(
      takenDate: map['taken_date'] as int,
      filename: map['filename'] as String,
      views: map['views'] as int? ?? 0,
      localPath: map['local_path'] as String?,
      galleryUrl: map['gallery_url'] as String?,
      isNonVrcx: (map['is_non_vrcx'] as int? ?? 0) == 1,
      isEdited: (map['is_edited'] as int? ?? 0) == 1,
      world: world,
      players: players,
    );
  }

  Future<PhotoMetadata> _hydrateMetadata(
    DatabaseExecutor db,
    Map<String, dynamic> map,
  ) async {
    final id = map['id'] as String;
    final playersMap = await _fetchPlayersForPhotos(db, [id]);
    return _fromDbMap(map, playersMap[id] ?? []);
  }

  Future<Map<String, List<Player>>> _fetchPlayersForPhotos(
    DatabaseExecutor db,
    List<String> photoIds,
  ) async {
    if (photoIds.isEmpty) return {};

    final Map<String, List<Player>> results = {};
    for (final id in photoIds) {
      results[id] = [];
    }

    final placeholders = List.filled(photoIds.length, '?').join(',');
    final List<Map<String, dynamic>> maps = await db.rawQuery('''
      SELECT pp.photo_id, p.id, p.name 
      FROM photo_players pp
      JOIN players p ON pp.player_id = p.id
      WHERE pp.photo_id IN ($placeholders)
    ''', photoIds);

    for (final row in maps) {
      final photoId = row['photo_id'] as String;
      final player = Player(
        id: row['id'] as String,
        name: row['name'] as String,
      );
      results[photoId]?.add(player);
    }

    return results;
  }

  Map<String, dynamic> _toDbMap(PhotoMetadata metadata, String id) {
    return {
      'id': id,
      'filename': metadata.filename,
      'taken_date': metadata.takenDate,
      'local_path': metadata.localPath,
      'gallery_url': metadata.galleryUrl,
      'views': metadata.views,
      'is_non_vrcx': metadata.isNonVrcx ? 1 : 0,
      'is_edited': metadata.isEdited ? 1 : 0,

      'world_id': metadata.world?.id,
      'world_name': metadata.world?.name,
      'world_instance_id': metadata.world?.instanceId,
      'world_access_type': metadata.world?.accessType,
      'world_region': metadata.world?.region,
      'world_owner_id': metadata.world?.ownerId,
      'world_group_id': metadata.world?.groupId,
      'world_group_access_type': metadata.world?.groupAccessType,
      'world_can_request_invite':
          metadata.world?.canRequestInvite == true
              ? 1
              : (metadata.world?.canRequestInvite == false ? 0 : null),
      'world_invite_only':
          metadata.world?.inviteOnly == true
              ? 1
              : (metadata.world?.inviteOnly == false ? 0 : null),
    };
  }

  Future<void> _checkAndMigrateLegacyMetadata() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_migrationDoneKey) == true) return;

      await migrateLegacyWebpMetadata();
      await prefs.setBool(_migrationDoneKey, true);
    } catch (e) {
      developer.log(
        'Error during legacy metadata migration check: $e',
        name: 'PhotoMetadataRepository',
      );
    }
  }

  Future<void> migrateLegacyWebpMetadata() async {
    final config = AppServiceManager().config;
    if (config == null || config.photosDirectory.isEmpty) return;

    final photosDir = Directory(config.photosDirectory);
    if (!await photosDir.exists()) return;

    int migratedCount = 0;
    final List<PhotoMetadata> toUpdate = [];

    final db = await AppDatabase().database;
    final List<Map<String, dynamic>> maps = await db.query('photo_metadata');
    final photoIds = maps.map((m) => m['id'] as String).toList();
    final playersMap = await _fetchPlayersForPhotos(db, photoIds);
    final entries =
        maps.map((m) => _fromDbMap(m, playersMap[m['id']] ?? [])).toList();

    final Map<String, String> pngLookup = {};
    try {
      await for (final entity in photosDir.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is File && entity.path.toLowerCase().endsWith('.png')) {
          pngLookup[path.basename(entity.path)] = entity.path;
        }
      }
    } catch (e) {
      developer.log(
        'Error building PNG lookup: $e',
        name: 'PhotoMetadataRepository',
      );
    }

    for (final metadata in entries) {
      if (metadata.localPath != null &&
          (metadata.localPath!.contains('GalleVR-Temp') ||
              metadata.localPath!.contains('GalleVR-ManualUpload'))) {
        // this is a legacy WebP path
        final nameWithoutExt = path.basenameWithoutExtension(metadata.filename);
        final possiblePngName = '$nameWithoutExt.png';

        final pngPath = pngLookup[possiblePngName];
        if (pngPath != null) {
          toUpdate.add(
            metadata.copyWith(localPath: pngPath, filename: possiblePngName),
          );
          migratedCount++;
        }
      }
    }

    if (toUpdate.isNotEmpty) {
      await savePhotoMetadataBatch(toUpdate);
    }

    // after migration attempt, we can safely delete the temporary directories
    await _cleanupGalleVRTemp();
  }

  Future<void> _cleanupGalleVRTemp() async {
    try {
      final tempDir = await getTemporaryDirectory();
      final galleVRTemp = Directory(path.join(tempDir.path, 'GalleVR-Temp'));
      if (await galleVRTemp.exists()) {
        developer.log(
          'Cleaning up legacy WebP cache at ${galleVRTemp.path}',
          name: 'PhotoMetadataRepository',
        );
        await galleVRTemp.delete(recursive: true);
      }

      final manualUploadTemp = Directory(
        path.join(tempDir.path, 'GalleVR-ManualUpload'),
      );
      if (await manualUploadTemp.exists()) {
        developer.log(
          'Cleaning up legacy manual upload cache at ${manualUploadTemp.path}',
          name: 'PhotoMetadataRepository',
        );
        await manualUploadTemp.delete(recursive: true);
      }
    } catch (e) {
      developer.log(
        'Error cleaning up legacy WebP cache: $e',
        name: 'PhotoMetadataRepository',
      );
    }
  }

  void _addToLookupCaches(PhotoMetadata metadata, String id) {}

  Future<void> syncWithBackend() async {
    try {
      final backendPhotos = await VRChatService().fetchPhotoList();
      if (backendPhotos.isNotEmpty) {
        await savePhotoMetadataBatch(backendPhotos, isRemote: true);
      }
    } catch (e) {
      developer.log(
        'Error syncing with backend: $e',
        name: 'PhotoMetadataRepository',
      );
    }
  }

  Future<PhotoMetadata?> getPhotoMetadataForFile(String filePath) async {
    await _initializeCache();

    final filename = path.basename(filePath);
    final nameWithoutExt = path.basenameWithoutExtension(filename);

    final db = await AppDatabase().database;

    final List<Map<String, dynamic>> pathMatches = await db.query(
      'photo_metadata',
      where: 'local_path = ?',
      whereArgs: [filePath],
      limit: 1,
    );
    if (pathMatches.isNotEmpty)
      return await _hydrateMetadata(db, pathMatches.first);

    final List<Map<String, dynamic>> filenameMatches = await db.query(
      'photo_metadata',
      where: 'filename = ?',
      whereArgs: [filename],
      limit: 1,
    );
    if (filenameMatches.isNotEmpty)
      return await _hydrateMetadata(db, filenameMatches.first);

    if (filename.toLowerCase().endsWith('.png')) {
      try {
        final fileMetadata = await _processVrcxMetadataBackground(filePath);
        if (fileMetadata != null && fileMetadata.world != null) {
          return fileMetadata;
        }
      } catch (e) {
        developer.log(
          'Error during direct VRCX extraction: $e',
          name: 'PhotoMetadataRepository',
        );
      }
    }

    final List<Map<String, dynamic>> fuzzyMatches = await db.query(
      'photo_metadata',
      where: 'filename LIKE ?',
      whereArgs: ['%$nameWithoutExt%'],
      limit: 1,
    );
    if (fuzzyMatches.isNotEmpty)
      return await _hydrateMetadata(db, fuzzyMatches.first);

    final match = _vrcFilenameRegex.firstMatch(filename);
    if (match != null) {
      final vrcBaseName = match.group(0)!;
      final List<Map<String, dynamic>> patternMatches = await db.query(
        'photo_metadata',
        where: 'filename LIKE ?',
        whereArgs: ['%$vrcBaseName%'],
        limit: 1,
      );
      if (patternMatches.isNotEmpty)
        return await _hydrateMetadata(db, patternMatches.first);

      try {
        final config = AppServiceManager().config;
        if (config != null && config.photosDirectory.isNotEmpty) {
          final photosDir = Directory(config.photosDirectory);
          if (await photosDir.exists()) {
            File? originalFile;
            final originalName = '$vrcBaseName.png';

            await for (final entity in photosDir.list(
              recursive: true,
              followLinks: false,
            )) {
              if (entity is File &&
                  path.basename(entity.path) == originalName) {
                originalFile = entity;
                break;
              }
            }

            if (originalFile != null) {
              final extracted = await _processVrcxMetadataBackground(
                originalFile.path,
              );
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
        developer.log(
          'Error during smart matching: $e',
          name: 'PhotoMetadataRepository',
        );
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

  Future<bool> savePhotoMetadata(
    PhotoMetadata metadata, {
    bool isRemote = false,
  }) async {
    return await savePhotoMetadataBatch([metadata], isRemote: isRemote);
  }

  Future<bool> savePhotoMetadataBatch(
    List<PhotoMetadata> metadataList, {
    bool isRemote = false,
  }) async {
    if (metadataList.isEmpty) return true;
    await _initializeCache();

    final db = await AppDatabase().database;

    await db.transaction((txn) async {
      final batch = txn.batch();

      for (var metadata in metadataList) {
        final nameWithoutExt = path.basenameWithoutExtension(metadata.filename);

        List<Map<String, dynamic>> existing = await txn.query(
          'photo_metadata',
          where: 'filename = ? OR local_path = ?',
          whereArgs: [metadata.filename, metadata.localPath],
          limit: 1,
        );

        if (existing.isEmpty) {
          existing = await txn.query(
            'photo_metadata',
            where: 'filename LIKE ?',
            whereArgs: ['%$nameWithoutExt%'],
            limit: 1,
          );
        }

        if (existing.isEmpty) {
          final match = _vrcFilenameRegex.firstMatch(metadata.filename);
          if (match != null) {
            final vrcBaseName = match.group(0)!;
            existing = await txn.query(
              'photo_metadata',
              where: 'filename LIKE ?',
              whereArgs: ['%$vrcBaseName%'],
              limit: 1,
            );
          }
        }

        String photoId;
        if (existing.isNotEmpty) {
          final existingMeta = await _hydrateMetadata(txn, existing.first);
          photoId = existing.first['id'] as String;

          if (isRemote) {
            metadata = existingMeta.copyWith(
              galleryUrl: metadata.galleryUrl ?? existingMeta.galleryUrl,
              views: metadata.views > 0 ? metadata.views : existingMeta.views,
              world: existingMeta.world ?? metadata.world,
              players:
                  existingMeta.players.isNotEmpty
                      ? existingMeta.players
                      : metadata.players,
            );
          } else {
            metadata = metadata.copyWith(
              galleryUrl: metadata.galleryUrl ?? existingMeta.galleryUrl,
              views: metadata.views > 0 ? metadata.views : existingMeta.views,
              world: metadata.world ?? existingMeta.world,
              players:
                  metadata.players.isNotEmpty
                      ? metadata.players
                      : existingMeta.players,
            );
          }
        } else {
          photoId = '${metadata.filename}_${metadata.takenDate}';
        }

        batch.insert(
          'photo_metadata',
          _toDbMap(metadata, photoId),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );

        batch.delete(
          'photo_players',
          where: 'photo_id = ?',
          whereArgs: [photoId],
        );
        for (final player in metadata.players) {
          batch.insert('players', {
            'id': player.id,
            'name': player.name,
          }, conflictAlgorithm: ConflictAlgorithm.ignore);
          batch.insert('photo_players', {
            'photo_id': photoId,
            'player_id': player.id,
          }, conflictAlgorithm: ConflictAlgorithm.ignore);
        }
      }

      await batch.commit(noResult: true);
    });

    return true;
  }

  /// Extracts metadata in background worker
  Future<PhotoMetadata?> _processVrcxMetadataBackground(String filePath) async {
    final results = await _batchProcessMetadataBackground([filePath]);
    return results[filePath];
  }

  /// Batch extracts metadata in background worker
  Future<Map<String, PhotoMetadata?>> _batchProcessMetadataBackground(
    List<String> filePaths,
  ) async {
    final results = await IsolateWorkerPool()
        .execute<List<String>, Map<String, PhotoMetadata?>>(
          _batchExtractMetadataTask,
          filePaths,
        );

    final toSave = results.values.whereType<PhotoMetadata>().toList();
    if (toSave.isNotEmpty) {
      await savePhotoMetadataBatch(toSave);
    }

    return results;
  }

  Future<Map<String, PhotoMetadata>> getAllPhotoMetadata() async {
    final db = await AppDatabase().database;
    final List<Map<String, dynamic>> maps = await db.query('photo_metadata');
    final photoIds = maps.map((m) => m['id'] as String).toList();
    final playersMap = await _fetchPlayersForPhotos(db, photoIds);

    final result = <String, PhotoMetadata>{};
    for (final map in maps) {
      final id = map['id'] as String;
      result[id] = _fromDbMap(map, playersMap[id] ?? []);
    }
    return result;
  }

  Future<Map<String, PhotoMetadata?>> getMetadataForFiles(
    List<String> filePaths,
  ) async {
    await _initializeCache();

    final result = <String, PhotoMetadata?>{};
    final toProcess = <String>[];

    final db = await AppDatabase().database;
    final filenames = filePaths.map((p) => path.basename(p)).toList();

    final List<Map<String, dynamic>> matches = await db.query(
      'photo_metadata',
      where: 'filename IN (${List.filled(filenames.length, '?').join(',')})',
      whereArgs: filenames,
    );

    final photoIds = matches.map((m) => m['id'] as String).toList();
    final playersMap = await _fetchPlayersForPhotos(db, photoIds);
    final Map<String, PhotoMetadata> matchMap = {};
    for (final m in matches) {
      final meta = _fromDbMap(m, playersMap[m['id']] ?? []);
      matchMap[meta.filename] = meta;
    }

    for (final filePath in filePaths) {
      final filename = path.basename(filePath);
      if (matchMap.containsKey(filename)) {
        result[filePath] = matchMap[filename];
      } else {
        if (!_processingQueue.containsKey(filePath)) {
          toProcess.add(filePath);
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

  Future<Set<String>> getNonVrcxFilenames() async {
    try {
      final db = await AppDatabase().database;
      final List<Map<String, dynamic>> results = await db.query(
        'photo_metadata',
        columns: ['filename'],
        where: 'is_non_vrcx = 1',
      );
      return results.map((r) => r['filename'] as String).toSet();
    } catch (e) {
      developer.log(
        'Error fetching non-VRCX filenames: $e',
        name: 'PhotoMetadataRepository',
      );
      return {};
    }
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
