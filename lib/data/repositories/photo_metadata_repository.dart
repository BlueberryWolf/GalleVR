import 'dart:async';
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
import '../services/photo_event_service.dart';
import '../models/log_metadata.dart';

import 'package:sqflite/sqflite.dart';
import '../database/app_database.dart';

class PhotoMetadataRepository {
  static const String _photoIdsKey = 'gallevr_photo_ids';
  static const String _photoMetadataKeyPrefix = 'gallevr_photo_';
  static const String _migrationDoneKey = 'gallevr_webp_migration_v2_done';
  static const String _sqliteMigrationDoneKey = 'gallevr_sqlite_migration_done';

  // Regex to find VRChat filename pattern: VRChat_YYYY-MM-DD_HH-MM-SS.mmm_WIDTHxHEIGHT
  static final RegExp vrcFilenameRegex = RegExp(
    r'VRChat_\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2}\.\d{3}(?:_\d+x\d+)?',
    caseSensitive: false,
  );

  static final PhotoMetadataRepository _instance =
      PhotoMetadataRepository._internal();
  factory PhotoMetadataRepository() => _instance;
  PhotoMetadataRepository._internal();

  static SharedPreferences? _prefs;
  static Completer<void>? _initCompleter;

  // Queue to prevent redundant processing of the same file
  static final Map<String, Future<PhotoMetadata?>> _processingQueue = {};

  Future<void> _initializeCache() async {
    if (_prefs != null) return;

    if (_initCompleter != null) {
      return _initCompleter!.future;
    }

    _initCompleter = Completer<void>();

    try {
      _prefs ??= await SharedPreferences.getInstance();

      final isDone = _prefs?.getBool(_sqliteMigrationDoneKey) ?? false;

      if (!isDone) {
        final hasLegacyData = _prefs?.containsKey(_photoIdsKey) ?? false;
        if (hasLegacyData) {
          await _migrateToSqlite();
          await _prefs?.setBool(_sqliteMigrationDoneKey, true);
        }
      }

      await _forcePurgeRemainingLegacyBloat();

      _checkAndMigrateLegacyMetadata();

      // Heal incorrectly marked non-VRCX photos in the background
      AppDatabase().database.then((db) {
        db.execute(
          'UPDATE photo_metadata SET is_non_vrcx = 0 WHERE is_non_vrcx = 1 AND filename LIKE "VRChat_%"',
        ).then((_) {
          // Notify UI to refresh and show newly visible photos
          PhotoEventService().notifyPhotoAdded('__HEAL_SYNC__');
        }).catchError((e) {
          developer.log('Error during background healing: $e', name: 'PhotoMetadataRepository');
        });
      });

      syncWithBackend();

      _initCompleter?.complete();
    } catch (e) {
      developer.log(
        'Error initializing metadata repository: $e',
        name: 'PhotoMetadataRepository',
      );
      _initCompleter?.completeError(e);
      _initCompleter = null;
    }
  }

  Future<void> _migrateToSqlite() async {
    final photoIds = _prefs?.getStringList(_photoIdsKey) ?? [];
    if (photoIds.isEmpty) return;

    const int chunkSize = 50;
    for (int i = 0; i < photoIds.length; i += chunkSize) {
      final chunk = photoIds.skip(i).take(chunkSize).toList();
      final List<PhotoMetadata> batch = [];

      for (final id in chunk) {
        final jsonStr = _prefs?.getString('$_photoMetadataKeyPrefix$id');
        if (jsonStr != null) {
          try {
            batch.add(PhotoMetadata.fromJson(jsonDecode(jsonStr)));
          } catch (e) {
            developer.log(
              'Error decoding $id during migration: $e',
              name: 'PhotoMetadataRepository',
            );
          }
        }
      }

      if (batch.isNotEmpty) {
        await savePhotoMetadataBatch(batch);
      }

      developer.log(
        'Migrated batch ${(i / chunkSize).ceil() + 1} of ${(photoIds.length / chunkSize).ceil()}',
        name: 'PhotoMetadataRepository',
      );

      await Future.delayed(const Duration(milliseconds: 10));
    }

    developer.log(
      'All legacy data cleared successfully!',
      name: 'PhotoMetadataRepository',
    );
  }

  Future<void> _forcePurgeRemainingLegacyBloat() async {
    try {
      if (_prefs == null) return;

      final allKeys = _prefs!.getKeys();
      final legacyKeys =
          allKeys
              .where(
                (k) =>
                    k.startsWith(_photoMetadataKeyPrefix) || k == _photoIdsKey,
              )
              .toList();

      if (legacyKeys.isEmpty) return;

      final backup = <String, Object>{};
      for (final key in allKeys) {
        if (!key.startsWith(_photoMetadataKeyPrefix) && key != _photoIdsKey) {
          final value = _prefs!.get(key);
          if (value != null) {
            backup[key] = value;
          }
        }
      }

      await _prefs!.clear();

      for (final entry in backup.entries) {
        final k = entry.key;
        final v = entry.value;
        if (v is bool) {
          _prefs!.setBool(k, v);
        } else if (v is String) {
          _prefs!.setString(k, v);
        } else if (v is int) {
          _prefs!.setInt(k, v);
        } else if (v is double) {
          _prefs!.setDouble(k, v);
        } else if (v is List<String>) {
          _prefs!.setStringList(k, v);
        }
      }
    } catch (e) {
      developer.log('routine error: $e', name: 'PhotoMetadataRepository');
    }
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

    const int chunkSize = 500;
    for (int i = 0; i < photoIds.length; i += chunkSize) {
      final chunk = photoIds.skip(i).take(chunkSize).toList();
      final placeholders = List.filled(chunk.length, '?').join(',');

      final List<Map<String, dynamic>> maps = await db.rawQuery('''
        SELECT pp.photo_id, p.id, p.name 
        FROM photo_players pp
        JOIN players p ON pp.player_id = p.id
        WHERE pp.photo_id IN ($placeholders)
      ''', chunk);

      for (final row in maps) {
        final photoId = row['photo_id'] as String;
        final player = Player(
          id: row['id'] as String,
          name: row['name'] as String,
        );
        results[photoId]?.add(player);
      }
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
      await _initializeCache();

      final lastSync = _prefs?.getInt('last_backend_sync_time') ?? 0;
      final now = DateTime.now().millisecondsSinceEpoch;
      const syncCooldown = 30 * 60 * 1000;

      if (now - lastSync < syncCooldown) {
        developer.log(
          'Skipping backend sync - last sync was less than 30 minutes ago',
          name: 'PhotoMetadataRepository',
        );
        return;
      }

      final backendPhotos = await VRChatService().fetchPhotoList();
      if (backendPhotos.isEmpty) {
        await _prefs?.setInt('last_backend_sync_time', now);
        return;
      }

      final config = AppServiceManager().config;
      final Map<String, String> localLookup = {};

      if (config != null && config.photosDirectory.isNotEmpty) {
        final photosDir = Directory(config.photosDirectory);
        if (await photosDir.exists()) {
          try {
            await for (final entity in photosDir.list(
              recursive: true,
              followLinks: false,
            )) {
              if (entity is File &&
                  entity.path.toLowerCase().endsWith('.png')) {
                final baseKey =
                    path.basenameWithoutExtension(entity.path).toLowerCase();
                localLookup[baseKey] = entity.path;
              }
            }
          } catch (e) {
            developer.log(
              'Partial failure scanning for local sync matches: $e',
              name: 'PhotoMetadataRepository',
            );
          }
        }
      }

      final List<PhotoMetadata> matchedPhotos = [];
      for (final photo in backendPhotos) {
        final remoteKey =
            path.basenameWithoutExtension(photo.filename).toLowerCase();
        final localMatch = localLookup[remoteKey];

        if (localMatch != null) {
          matchedPhotos.add(photo.copyWith(localPath: localMatch));
        } else {
          matchedPhotos.add(photo);
        }
      }

      await savePhotoMetadataBatch(matchedPhotos, isRemote: true);
      
      // Update sync timestamp
      await _prefs?.setInt('last_backend_sync_time', now);

      PhotoEventService().notifyPhotoAdded('__CLOUD_SYNC_COMPLETE__');
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

    final match = vrcFilenameRegex.firstMatch(filename);
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

    const int batchSize = 50;
    for (
      int batchIndex = 0;
      batchIndex < metadataList.length;
      batchIndex += batchSize
    ) {
      final currentBatch =
          metadataList.skip(batchIndex).take(batchSize).toList();

      final Set<String> searchFilenames = {};
      for (final m in currentBatch) {
        final root = path.basenameWithoutExtension(m.filename);
        searchFilenames.add(m.filename);
        searchFilenames.add('$root.png');
        searchFilenames.add('$root.webp');
      }
      final filenamesExpanded = searchFilenames.toList();

      final localPaths =
          currentBatch.map((m) => m.localPath).whereType<String>().toList();

      final placeholdersF = List.filled(
        filenamesExpanded.length,
        '?',
      ).join(',');
      final List<String> whereArgs = [...filenamesExpanded];

      String whereClause = 'filename IN ($placeholdersF)';
      if (localPaths.isNotEmpty) {
        final placeholdersP = List.filled(localPaths.length, '?').join(',');
        whereClause += ' OR local_path IN ($placeholdersP)';
        whereArgs.addAll(localPaths);
      }

      final List<Map<String, dynamic>> existingRows = await db.query(
        'photo_metadata',
        where: whereClause,
        whereArgs: whereArgs,
      );

      final Map<String, PhotoMetadata> hydratedExisting = {};
      final Map<String, String> filenameToIdMap = {};

      if (existingRows.isNotEmpty) {
        final photoIds = existingRows.map((m) => m['id'] as String).toList();
        final playersMap = await _fetchPlayersForPhotos(db, photoIds);

        for (final row in existingRows) {
          final meta = _fromDbMap(row, playersMap[row['id']] ?? []);
          final id = row['id'] as String;

          filenameToIdMap[meta.filename] = id;
          final baseMatchKey =
              path.basenameWithoutExtension(meta.filename).toLowerCase();
          filenameToIdMap[baseMatchKey] = id;

          hydratedExisting[id] = meta;

          if (meta.localPath != null) {
            filenameToIdMap[meta.localPath!] = id;
          }
        }
      }

      await db.transaction((txn) async {
        final batch = txn.batch();

        for (var metadata in currentBatch) {
          PhotoMetadata? existingMeta;
          String? existingId;

          final lookupBaseKey =
              path.basenameWithoutExtension(metadata.filename).toLowerCase();

          if (filenameToIdMap.containsKey(metadata.filename)) {
            existingId = filenameToIdMap[metadata.filename];
          } else if (filenameToIdMap.containsKey(lookupBaseKey)) {
            existingId = filenameToIdMap[lookupBaseKey];
          } else if (metadata.localPath != null &&
              filenameToIdMap.containsKey(metadata.localPath!)) {
            existingId = filenameToIdMap[metadata.localPath!];
          }

          if (existingId != null) {
            existingMeta = hydratedExisting[existingId];
          }

          if (existingMeta == null && !isRemote) {
            final nameWithoutExt = path.basenameWithoutExtension(
              metadata.filename,
            );

            List<Map<String, dynamic>> fuzzy = await txn.query(
              'photo_metadata',
              where: 'filename LIKE ?',
              whereArgs: ['%$nameWithoutExt%'],
              limit: 1,
            );

            if (fuzzy.isEmpty) {
              final match = vrcFilenameRegex.firstMatch(metadata.filename);
              if (match != null) {
                final vrcBaseName = match.group(0)!;
                fuzzy = await txn.query(
                  'photo_metadata',
                  where: 'filename LIKE ?',
                  whereArgs: ['%$vrcBaseName%'],
                  limit: 1,
                );
              }
            }

            if (fuzzy.isNotEmpty) {
              existingId = fuzzy.first['id'] as String;
              existingMeta = await _hydrateMetadata(txn, fuzzy.first);
            }
          }

          final finalPhotoId =
              existingId ?? '${metadata.filename}_${metadata.takenDate}';

          if (existingMeta != null) {
            if (isRemote) {
              // Trust local data but update with remote info
              metadata = metadata.copyWith(
                localPath: existingMeta.localPath ?? metadata.localPath,
                isNonVrcx: false,
                isEdited: existingMeta.isEdited || metadata.isEdited,
                takenDate: existingMeta.takenDate, // Prefer local file stats/metadata
                world: existingMeta.world ?? metadata.world,
                players:
                    existingMeta.players.isNotEmpty
                        ? existingMeta.players
                        : metadata.players,
              );
            } else {
              metadata = metadata.copyWith(
                galleryUrl: existingMeta.galleryUrl ?? metadata.galleryUrl,
                views:
                    existingMeta.views > metadata.views
                        ? existingMeta.views
                        : metadata.views,
                world: existingMeta.world ?? metadata.world,
                players:
                    existingMeta.players.isNotEmpty
                        ? existingMeta.players
                        : metadata.players,
                isEdited: existingMeta.isEdited || metadata.isEdited,
                isNonVrcx:
                    existingMeta.galleryUrl != null
                        ? false
                        : metadata.isNonVrcx,
              );
            }
          }

          batch.insert(
            'photo_metadata',
            _toDbMap(metadata, finalPhotoId),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );

          batch.delete(
            'photo_players',
            where: 'photo_id = ?',
            whereArgs: [finalPhotoId],
          );

          for (final player in metadata.players) {
            batch.insert('players', {
              'id': player.id,
              'name': player.name,
            }, conflictAlgorithm: ConflictAlgorithm.ignore);

            batch.insert('photo_players', {
              'photo_id': finalPhotoId,
              'player_id': player.id,
            }, conflictAlgorithm: ConflictAlgorithm.ignore);
          }
        }

        await batch.commit(noResult: true);
      });

      await Future.delayed(const Duration(milliseconds: 5));
    }

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

    final List<PhotoMetadata> toHeal = [];
    for (final entry in result.entries) {
      final filePath = entry.key;
      final meta = entry.value;
      if (meta != null && meta.localPath != filePath) {
        final updated = meta.copyWith(localPath: filePath);
        result[filePath] = updated;
        toHeal.add(updated);
      }
    }

    if (toHeal.isNotEmpty) {
      savePhotoMetadataBatch(toHeal).catchError((e) {
        return false;
      });
    }

    return result;
  }

  Future<Set<String>> getNonVrcxFilenames() async {
    try {
      final db = await AppDatabase().database;
      final List<Map<String, dynamic>> results = await db.query(
        'photo_metadata',
        columns: ['filename'],
        where: 'is_non_vrcx = 1 AND gallery_url IS NULL',
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
          isNonVrcx: !PhotoMetadataRepository.vrcFilenameRegex.hasMatch(
            path.basename(filePath),
          ),
        );
      }
    } catch (e) {
      results[filePath] = null;
    }
  }
  return results;
}
