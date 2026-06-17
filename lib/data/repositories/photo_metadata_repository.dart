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

      // Heal metadata status in the background:
      AppDatabase().database
          .then((db) async {
            await db.execute(
              'UPDATE photo_metadata SET is_non_vrcx = 1 WHERE gallery_url IS NULL AND world_name IS NULL AND world_id IS NULL',
            );
            await db.execute(
              'UPDATE photo_metadata SET is_non_vrcx = 0 WHERE is_non_vrcx = 1 AND (gallery_url IS NOT NULL OR world_name IS NOT NULL OR world_id IS NOT NULL)',
            );
            // Notify UI to refresh and show newly visible photos
            PhotoEventService().notifyPhotoAdded('__HEAL_SYNC__');
          })
          .catchError((e) {
            developer.log(
              'Error during background healing: $e',
              name: 'PhotoMetadataRepository',
            );
          });

      final vrcXmpMigrationDone =
          _prefs?.getBool('gallevr_vrc_xmp_migration_done') ?? false;
      if (!vrcXmpMigrationDone) {
        AppDatabase().database
            .then((db) async {
              await db.execute(
                'DELETE FROM photo_metadata WHERE world_name IS NULL AND gallery_url IS NULL',
              );
              await _prefs?.setBool('gallevr_vrc_xmp_migration_done', true);
              developer.log(
                'Cleared placeholder metadata records for VRChat XMP migration',
                name: 'PhotoMetadataRepository',
              );
            })
            .catchError((e) {
              developer.log(
                'Error clearing placeholders: $e',
                name: 'PhotoMetadataRepository',
              );
            });
      }

      final cleanV5Done =
          _prefs?.getBool('gallevr_metadata_clean_v5_done') ?? false;
      if (!cleanV5Done) {
        AppDatabase().database
            .then((db) async {
              await db.transaction((txn) async {
                await txn.execute(
                  'DELETE FROM photo_players WHERE photo_id IN (SELECT id FROM photo_metadata WHERE gallery_url IS NULL)',
                );
                await txn.execute(
                  'DELETE FROM photo_metadata WHERE gallery_url IS NULL',
                );
              });
              await _prefs?.setBool('gallevr_metadata_clean_v5_done', true);
              developer.log(
                'Cleared local metadata records for clean v5 migration to repopulate database with Resonite columns',
                name: 'PhotoMetadataRepository',
              );
            })
            .catchError((e) {
              developer.log(
                'Error running metadata clean v5 migration: $e',
                name: 'PhotoMetadataRepository',
                error: e,
              );
            });
      }

      syncWithBackend();
      runRetroactiveLogScanner();

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
      logChecked: (map['log_checked'] as int? ?? 0) == 1,
      world: world,
      players: players,
      application: map['application'] as String?,
      takenGlobalPosition: map['taken_global_position'] as String?,
      takenGlobalRotation: map['taken_global_rotation'] as String?,
      takenGlobalScale: map['taken_global_scale'] as String?,
      cameraFov: map['camera_fov'] as String?,
      cameraManufacturer: map['camera_manufacturer'] as String?,
      takenById: map['taken_by_id'] as String?,
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
      'log_checked': metadata.logChecked ? 1 : 0,

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

      'application': metadata.application,
      'taken_global_position': metadata.takenGlobalPosition,
      'taken_global_rotation': metadata.takenGlobalRotation,
      'taken_global_scale': metadata.takenGlobalScale,
      'camera_fov': metadata.cameraFov,
      'camera_manufacturer': metadata.cameraManufacturer,
      'taken_by_id': metadata.takenById,
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

  Future<void> syncWithBackend({bool force = false}) async {
    try {
      await _initializeCache();

      final lastSync = _prefs?.getInt('last_backend_sync_time') ?? 0;
      final now = DateTime.now().millisecondsSinceEpoch;
      const syncCooldown = 30 * 60 * 1000;

      if (!force && (now - lastSync < syncCooldown)) {
        developer.log(
          'Skipping backend sync - last sync was less than 30 minutes ago',
          name: 'PhotoMetadataRepository',
        );
        return;
      }

      final backendPhotos = await VRChatService().fetchPhotoList();
      if (backendPhotos == null) {
        developer.log(
          'Skipping backend sync because backend photo list fetch failed',
          name: 'PhotoMetadataRepository',
        );
        return;
      }

      // Identify local photos that have a gallery_url but are not in the remote list,
      // and clear their gallery_url so they can be re-uploaded.
      final db = await AppDatabase().database;
      final List<Map<String, dynamic>> localUploaded = await db.query(
        'photo_metadata',
        where: 'gallery_url IS NOT NULL AND gallery_url != ?',
        whereArgs: [''],
      );

      if (localUploaded.isNotEmpty) {
        final Set<String> remoteUrls =
            backendPhotos.map((p) => p.galleryUrl).whereType<String>().toSet();
        final Set<String> remoteBasenames =
            backendPhotos
                .map(
                  (p) =>
                      path.basenameWithoutExtension(p.filename).toLowerCase(),
                )
                .toSet();

        final List<String> idsToClear = [];
        for (final row in localUploaded) {
          final localUrl = row['gallery_url'] as String?;
          final localFilename = row['filename'] as String;
          final localBase =
              path.basenameWithoutExtension(localFilename).toLowerCase();

          bool isStillRemote = false;
          if (localUrl != null && remoteUrls.contains(localUrl)) {
            isStillRemote = true;
          } else if (remoteBasenames.contains(localBase)) {
            isStillRemote = true;
          }

          if (!isStillRemote) {
            idsToClear.add(row['id'] as String);
          }
        }

        if (idsToClear.isNotEmpty) {
          developer.log(
            'Found ${idsToClear.length} local photos no longer present on the remote backend. Clearing local gallery URLs to allow re-upload.',
            name: 'PhotoMetadataRepository',
          );
          await db.transaction((txn) async {
            final batch = txn.batch();
            for (final id in idsToClear) {
              batch.update(
                'photo_metadata',
                {'gallery_url': null},
                where: 'id = ?',
                whereArgs: [id],
              );
            }
            await batch.commit(noResult: true);
          });
        }
      }

      if (backendPhotos.isEmpty) {
        await _prefs?.setInt('last_backend_sync_time', now);
        PhotoEventService().notifyPhotoAdded('__CLOUD_SYNC_COMPLETE__');
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

    final authData = await VRChatService().loadAuthData();

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
          if (metadata.application == 'VRChat' && authData != null) {
            final updatedPlayers =
                metadata.players.map((p) {
                  if (p.id.isEmpty) {
                    return Player(id: authData.userId, name: p.name);
                  }
                  return p;
                }).toList();
            metadata = metadata.copyWith(players: updatedPlayers);
          }
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
              metadata = metadata.copyWith(
                localPath: existingMeta.localPath ?? metadata.localPath,
                isNonVrcx: false,
                isEdited: existingMeta.isEdited || metadata.isEdited,
                takenDate:
                    existingMeta.takenDate, // Prefer local file stats/metadata
                world: existingMeta.world ?? metadata.world,
                players:
                    existingMeta.players.isNotEmpty
                        ? existingMeta.players
                        : metadata.players,
                logChecked: existingMeta.logChecked || metadata.logChecked,
                application: existingMeta.application ?? metadata.application,
                cameraManufacturer:
                    existingMeta.cameraManufacturer ??
                    metadata.cameraManufacturer,
                takenById: existingMeta.takenById ?? metadata.takenById,
                takenGlobalPosition:
                    existingMeta.takenGlobalPosition ??
                    metadata.takenGlobalPosition,
                takenGlobalRotation:
                    existingMeta.takenGlobalRotation ??
                    metadata.takenGlobalRotation,
                takenGlobalScale:
                    existingMeta.takenGlobalScale ?? metadata.takenGlobalScale,
                cameraFov: existingMeta.cameraFov ?? metadata.cameraFov,
              );
            } else {
              metadata = metadata.copyWith(
                galleryUrl:
                    (metadata.galleryUrl != null &&
                            metadata.galleryUrl!.isNotEmpty)
                        ? metadata.galleryUrl
                        : existingMeta.galleryUrl,
                views:
                    existingMeta.views > metadata.views
                        ? existingMeta.views
                        : metadata.views,
                world: metadata.world ?? existingMeta.world,
                players:
                    metadata.players.isNotEmpty
                        ? metadata.players
                        : existingMeta.players,
                isEdited: existingMeta.isEdited || metadata.isEdited,
                isNonVrcx:
                    (existingMeta.galleryUrl != null ||
                            existingMeta.world != null ||
                            existingMeta.players.isNotEmpty ||
                            metadata.galleryUrl != null ||
                            metadata.world != null ||
                            metadata.players.isNotEmpty)
                        ? false
                        : metadata.isNonVrcx,
                logChecked: existingMeta.logChecked || metadata.logChecked,
                application: metadata.application ?? existingMeta.application,
                cameraManufacturer:
                    metadata.cameraManufacturer ??
                    existingMeta.cameraManufacturer,
                takenById: metadata.takenById ?? existingMeta.takenById,
                takenGlobalPosition:
                    metadata.takenGlobalPosition ??
                    existingMeta.takenGlobalPosition,
                takenGlobalRotation:
                    metadata.takenGlobalRotation ??
                    existingMeta.takenGlobalRotation,
                takenGlobalScale:
                    metadata.takenGlobalScale ?? existingMeta.takenGlobalScale,
                cameraFov: metadata.cameraFov ?? existingMeta.cameraFov,
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
    final authData = await VRChatService().loadAuthData();
    final authParams =
        authData != null
            ? {'userId': authData.userId, 'displayName': authData.displayName}
            : null;

    final resoniteDir = AppServiceManager().config?.resonitePhotosDirectory;

    final results = await IsolateWorkerPool()
        .execute<Map<String, dynamic>, Map<String, PhotoMetadata?>>(
          _batchExtractMetadataTask,
          {
            'filePaths': filePaths,
            'authParams': authParams,
            'resoniteDir': resoniteDir,
          },
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

    final missingPaths = <String>[];
    for (final filePath in filePaths) {
      if (!result.containsKey(filePath)) {
        missingPaths.add(filePath);
      }
    }

    if (missingPaths.isNotEmpty) {
      final Map<String, String> originalFileLookup = {};
      final config = AppServiceManager().config;
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
                final name = path.basename(entity.path);
                originalFileLookup[name] = entity.path;
              }
            }
          } catch (e) {
            developer.log(
              'Error scanning photosDirectory in getMetadataForFiles: $e',
              name: 'PhotoMetadataRepository',
            );
          }
        }
      }

      final Map<String, List<String>> patternToFiles = {};
      for (final filePath in missingPaths) {
        final filename = path.basename(filePath);
        final match = vrcFilenameRegex.firstMatch(filename);
        if (match != null) {
          final vrcBaseName = match.group(0)!;
          patternToFiles.putIfAbsent(vrcBaseName, () => []).add(filePath);
        }
      }

      if (patternToFiles.isNotEmpty) {
        final patterns = patternToFiles.keys.toList();
        final List<String> whereClauses = List.filled(
          patterns.length,
          'filename LIKE ?',
        );
        final List<String> whereArgs = patterns.map((p) => '%$p%').toList();

        final List<Map<String, dynamic>> patternDbMatches = await db.query(
          'photo_metadata',
          where: whereClauses.join(' OR '),
          whereArgs: whereArgs,
        );

        if (patternDbMatches.isNotEmpty) {
          final matchPhotoIds =
              patternDbMatches.map((m) => m['id'] as String).toList();
          final matchPlayersMap = await _fetchPlayersForPhotos(
            db,
            matchPhotoIds,
          );

          for (final row in patternDbMatches) {
            final meta = _fromDbMap(row, matchPlayersMap[row['id']] ?? []);
            for (final pattern in patterns) {
              if (meta.filename.contains(pattern)) {
                final filePathsForPattern = patternToFiles[pattern]!;
                for (final filePath in filePathsForPattern) {
                  if (!result.containsKey(filePath)) {
                    final filename = path.basename(filePath);
                    result[filePath] = meta.copyWith(
                      localPath: filePath,
                      filename: filename,
                    );
                  }
                }
              }
            }
          }
        }
      }

      for (final filePath in missingPaths) {
        if (result.containsKey(filePath)) continue;

        final filename = path.basename(filePath);
        final match = vrcFilenameRegex.firstMatch(filename);
        if (match != null) {
          final vrcBaseName = match.group(0)!;
          final originalName = '$vrcBaseName.png';
          final originalPath = originalFileLookup[originalName];

          if (originalPath != null) {
            try {
              final extracted = await _processVrcxMetadataBackground(
                originalPath,
              );
              if (extracted != null && extracted.world != null) {
                final merged = extracted.copyWith(
                  localPath: filePath,
                  filename: filename,
                );
                await savePhotoMetadata(merged);
                result[filePath] = merged;
              }
            } catch (e) {
              developer.log(
                'Failed to extract metadata during batch heal: $e',
                name: 'PhotoMetadataRepository',
              );
            }
          }
        }
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

    Timer(const Duration(seconds: 2), () {
      runRetroactiveLogScanner();
    });

    return result;
  }

  Future<Set<String>> getNonVrcxFilenames() async {
    try {
      final db = await AppDatabase().database;
      final List<Map<String, dynamic>> results = await db.query(
        'photo_metadata',
        columns: ['filename'],
        where:
            'gallery_url IS NULL AND (is_non_vrcx = 1 OR (application = \'Resonite\' AND (camera_manufacturer IS NULL OR camera_manufacturer = \'\')))',
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

  // Set to track photo paths currently queued for log scanning
  static final Set<String> _scanningQueue = {};

  /// Scans background log files for any photos in database marked as non-VRCX but not yet log checked
  Future<void> runRetroactiveLogScanner() async {
    await _initializeCache();
    final config = AppServiceManager().config;
    if (config == null ||
        config.photosDirectory.isEmpty ||
        config.logsDirectory.isEmpty) {
      developer.log(
        'Retroactive log scanner skipped: config or directories not set (photos: ${config?.photosDirectory}, logs: ${config?.logsDirectory})',
        name: 'PhotoMetadataRepository',
      );
      return;
    }

    developer.log(
      'Retroactive log scanner started. Photos: ${config.photosDirectory}, Logs: ${config.logsDirectory}',
      name: 'PhotoMetadataRepository',
    );

    try {
      final photosDir = Directory(config.photosDirectory);
      if (await photosDir.exists()) {
        final List<File> localFiles = [];
        try {
          await for (final entity in photosDir.list(
            recursive: true,
            followLinks: false,
          )) {
            if (entity is File && entity.path.toLowerCase().endsWith('.png')) {
              localFiles.add(entity);
            }
          }
        } catch (e) {
          developer.log(
            'Error scanning photos directory for placeholders: $e',
            name: 'PhotoMetadataRepository',
          );
        }

        if (localFiles.isNotEmpty) {
          final db = await AppDatabase().database;
          final List<Map<String, dynamic>> dbRows = await db.query(
            'photo_metadata',
            columns: ['filename', 'local_path', 'world_name', 'gallery_url'],
          );

          final Set<String> existingNames = {};
          final Set<String> existingPaths = {};
          for (final row in dbRows) {
            final filename = row['filename'] as String;
            final localPath = row['local_path'] as String?;
            final worldName = row['world_name'] as String?;
            final galleryUrl = row['gallery_url'] as String?;

            if (worldName != null || galleryUrl != null) {
              existingNames.add(filename);
              if (localPath != null) {
                existingPaths.add(localPath);
              }
            }
          }

          final List<String> newPaths = [];
          for (final file in localFiles) {
            final filename = path.basename(file.path);
            if (!existingNames.contains(filename) &&
                !existingPaths.contains(file.path)) {
              newPaths.add(file.path);
            }
          }

          if (newPaths.isNotEmpty) {
            developer.log(
              'Processing ${newPaths.length} local photos for VRChat/VRCX metadata extraction in background',
              name: 'PhotoMetadataRepository',
            );
            await _batchProcessMetadataBackground(newPaths);
          }
        }
      }

      final db = await AppDatabase().database;

      // Discard photos taken before the earliest log file on disk (VRChat clears old logs)
      try {
        final logsDir = Directory(config.logsDirectory);
        if (await logsDir.exists()) {
          DateTime? earliestLogStart;
          final filenameRegex = RegExp(
            r'output_log_(\d{4}-\d{2}-\d{2})_(\d{2})-(\d{2})-(\d{2})',
          );

          await for (final entity in logsDir.list(
            recursive: false,
            followLinks: false,
          )) {
            if (entity is File &&
                path.basename(entity.path).startsWith('output_log_')) {
              DateTime? sessionStart;
              final filename = path.basename(entity.path);

              final match = filenameRegex.firstMatch(filename);
              if (match != null) {
                try {
                  final datePart = match.group(1)!;
                  final hh = match.group(2)!;
                  final mm = match.group(3)!;
                  final ss = match.group(4)!;
                  sessionStart = DateTime.parse('$datePart $hh:$mm:$ss');
                } catch (_) {}
              }

              if (sessionStart == null) {
                try {
                  final mod = entity.statSync().modified;
                  sessionStart = mod.subtract(const Duration(hours: 2));
                } catch (_) {}
              }

              if (sessionStart != null) {
                if (earliestLogStart == null ||
                    sessionStart.isBefore(earliestLogStart)) {
                  earliestLogStart = sessionStart;
                }
              }
            }
          }

          developer.log(
            'Earliest log session start time parsed from filename: $earliestLogStart',
            name: 'PhotoMetadataRepository',
          );

          if (earliestLogStart != null) {
            final thresholdMs =
                earliestLogStart
                    .subtract(const Duration(minutes: 2))
                    .millisecondsSinceEpoch;
            final updated = await db.update(
              'photo_metadata',
              {'log_checked': 1},
              where: 'taken_date < ? AND log_checked = 0 AND is_non_vrcx = 1',
              whereArgs: [thresholdMs],
            );
            if (updated > 0) {
              developer.log(
                'Discarded $updated photos taken before the earliest VRChat log session ($earliestLogStart)',
                name: 'PhotoMetadataRepository',
              );
            }
          }
        }
      } catch (e) {
        developer.log(
          'Error checking earliest log session: $e',
          name: 'PhotoMetadataRepository',
        );
      }

      final List<Map<String, dynamic>> toCheck = await db.query(
        'photo_metadata',
        where: 'is_non_vrcx = 1 AND log_checked = 0',
      );

      developer.log(
        'Database query for is_non_vrcx = 1 AND log_checked = 0 returned ${toCheck.length} records: ${toCheck.map((r) => r['filename']).toList()}',
        name: 'PhotoMetadataRepository',
      );

      if (toCheck.isEmpty) return;

      final List<Map<String, dynamic>> eligibleToCheck = [];
      for (final row in toCheck) {
        final localPath = row['local_path'] as String?;
        if (localPath != null &&
            localPath.isNotEmpty &&
            !_scanningQueue.contains(localPath)) {
          eligibleToCheck.add(row);
        }
      }

      developer.log(
        'Eligible photos to scan in VRChat logs: ${eligibleToCheck.map((r) => r['filename']).toList()}',
        name: 'PhotoMetadataRepository',
      );

      if (eligibleToCheck.isEmpty) return;

      developer.log(
        'Found ${eligibleToCheck.length} photos requiring retroactive log checking',
        name: 'PhotoMetadataRepository',
      );

      _processLogScannerQueue(eligibleToCheck, config.logsDirectory);
    } catch (e) {
      developer.log(
        'Error starting retroactive log scanner: $e',
        name: 'PhotoMetadataRepository',
      );
    }
  }

  Future<void> _processLogScannerQueue(
    List<Map<String, dynamic>> rows,
    String logsDirectory,
  ) async {
    final List<Map<String, String>> batchParams = [];
    for (final row in rows) {
      final localPath = row['local_path'] as String?;
      final filename = row['filename'] as String;

      if (localPath == null || localPath.isEmpty) continue;

      final file = File(localPath);
      if (!await file.exists()) continue;

      _scanningQueue.add(localPath);
      batchParams.add({'filePath': localPath, 'filename': filename});
    }

    if (batchParams.isEmpty) return;

    IsolateWorkerPool()
        .execute<Map<String, dynamic>, List<PhotoMetadata>>(
          _scanLogsForPhotosBatchTask,
          {'photos': batchParams, 'logsDirectory': logsDirectory},
        )
        .then((results) async {
          for (final param in batchParams) {
            _scanningQueue.remove(param['filePath']);
          }

          if (results.isNotEmpty) {
            developer.log(
              'Successfully recovered log metadata for ${results.length} photos',
              name: 'PhotoMetadataRepository',
            );
            await savePhotoMetadataBatch(results);
            // Notify the UI that metadata has loaded/changed
            PhotoEventService().notifyPhotoAdded('__LOG_RECOVER_COMPLETE__');
          }

          final Set<String> foundPaths =
              results.map((r) => r.localPath!).toSet();
          final List<String> failedPaths = [];

          for (final param in batchParams) {
            final path = param['filePath']!;
            if (!foundPaths.contains(path)) {
              failedPaths.add(path);
            }
          }

          if (failedPaths.isNotEmpty) {
            final db = await AppDatabase().database;
            await db.transaction((txn) async {
              final batch = txn.batch();
              for (final path in failedPaths) {
                batch.update(
                  'photo_metadata',
                  {'log_checked': 1},
                  where: 'local_path = ?',
                  whereArgs: [path],
                );
              }
              await batch.commit(noResult: true);
            });
            developer.log(
              'Finished log scan for ${failedPaths.length} photos (no metadata found in logs)',
              name: 'PhotoMetadataRepository',
            );
          }
        })
        .catchError((e) {
          for (final param in batchParams) {
            _scanningQueue.remove(param['filePath']);
          }
          developer.log(
            'Error running batch log scan: $e',
            name: 'PhotoMetadataRepository',
          );
        });
  }
}

Map<String, PhotoMetadata?> _batchExtractMetadataTask(
  Map<String, dynamic> params,
) {
  final filePaths = List<String>.from(params['filePaths'] as List);
  final authParams = params['authParams'] as Map<String, dynamic>?;
  final resoniteDir = params['resoniteDir'] as String?;
  final results = <String, PhotoMetadata?>{};
  for (final filePath in filePaths) {
    try {
      final metadata = VrcxMetadataService.extractVrcxMetadataSync({
        'imagePath': filePath,
        'authParams': authParams,
      });
      if (metadata != null) {
        if (metadata.application == 'PENDING_AUTH') {
          continue;
        }
        results[filePath] = metadata.copyWith(logChecked: true);
      } else {
        final isResonitePath = resoniteDir != null &&
            resoniteDir.isNotEmpty &&
            path.isWithin(resoniteDir, filePath);
        results[filePath] = PhotoMetadata(
          takenDate: File(filePath).statSync().modified.millisecondsSinceEpoch,
          filename: path.basename(filePath),
          localPath: filePath,
          isNonVrcx: isResonitePath ? false : true,
          application: isResonitePath ? 'Resonite' : null,
          logChecked: isResonitePath ? true : false,
        );
      }
    } catch (e) {
      results[filePath] = null;
    }
  }
  return results;
}

List<PhotoMetadata> _scanLogsForPhotosBatchTask(Map<String, dynamic> params) {
  final photos = List<Map<String, String>>.from(params['photos'] as List);
  final logsDirectory = params['logsDirectory'] as String;

  final List<PhotoMetadata> recovered = [];
  if (photos.isEmpty) return recovered;

  final Map<String, _PhotoSearchEntry> searchMap = {};
  DateTime? earliestThreshold;

  for (final photo in photos) {
    final filePath = photo['filePath']!;
    final filename = photo['filename']!;
    final file = File(filePath);
    if (!file.existsSync()) continue;

    DateTime? photoTime;
    final match = RegExp(
      r'VRChat_(\d{4}-\d{2}-\d{2})_(\d{2})-(\d{2})-(\d{2})',
    ).firstMatch(filename);
    if (match != null) {
      try {
        final datePart = match.group(1)!;
        final hh = match.group(2)!;
        final mm = match.group(3)!;
        final ss = match.group(4)!;
        photoTime = DateTime.parse('$datePart $hh:$mm:$ss');
      } catch (_) {}
    }
    photoTime ??= file.statSync().modified;

    // Search term prefix
    final nameWithoutExt = path.basenameWithoutExtension(filename);
    final vrcBaseMatch = RegExp(
      r'VRChat_\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2}\.\d{3}',
    ).firstMatch(nameWithoutExt);
    final searchTerm =
        vrcBaseMatch != null ? vrcBaseMatch.group(0)! : nameWithoutExt;

    final entry = _PhotoSearchEntry(
      filePath: filePath,
      filename: filename,
      photoTime: photoTime,
      searchTerm: searchTerm,
    );
    searchMap[searchTerm] = entry;

    // Keep track of the earliest photo time
    final threshold = photoTime.subtract(const Duration(minutes: 2));
    if (earliestThreshold == null || threshold.isBefore(earliestThreshold)) {
      earliestThreshold = threshold;
    }
  }

  if (searchMap.isEmpty) return recovered;

  final logsDir = Directory(logsDirectory);
  if (!logsDir.existsSync()) return recovered;

  final List<File> logFiles = [];
  try {
    for (final entity in logsDir.listSync()) {
      if (entity is File &&
          path.basename(entity.path).startsWith('output_log_')) {
        logFiles.add(entity);
      }
    }
  } catch (_) {
    return recovered;
  }

  if (logFiles.isEmpty) return recovered;

  final List<MapEntry<File, DateTime>> candidates = [];
  for (final logFile in logFiles) {
    try {
      final modified = logFile.statSync().modified;
      if (earliestThreshold == null || modified.isAfter(earliestThreshold)) {
        candidates.add(MapEntry(logFile, modified));
      }
    } catch (_) {}
  }

  if (candidates.isEmpty) return recovered;

  // Sort candidates ascending (oldest modified first)
  candidates.sort((a, b) => a.value.compareTo(b.value));

  final screenshotRegex = RegExp(
    r'VRChat_\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2}\.\d{3}',
  );
  final playerRegex = RegExp(
    r'\[Behaviour\] OnPlayer(Joined|Left) (.+?) \((.+?)\)',
  );

  for (final candidate in candidates) {
    if (searchMap.isEmpty) break; // All photos processed!

    final logFile = candidate.key;
    List<String> lines = [];
    try {
      lines = logFile.readAsLinesSync();
    } catch (_) {
      continue;
    }

    DateTime? logStartTime;
    DateTime? logEndTime;
    final timestampRegex = RegExp(
      r'^(\d{4})\.(\d{2})\.(\d{2}) (\d{2}):(\d{2}):(\d{2})',
    );

    // Find start time of this log session
    for (int i = 0; i < lines.length && i < 100; i++) {
      final m = timestampRegex.firstMatch(lines[i]);
      if (m != null) {
        try {
          logStartTime = DateTime.parse(
            '${m.group(1)}-${m.group(2)}-${m.group(3)} ${m.group(4)}:${m.group(5)}:${m.group(6)}',
          );
          break;
        } catch (_) {}
      }
    }

    // Find end time of this log session
    for (int i = lines.length - 1; i >= 0 && i >= lines.length - 100; i--) {
      final m = timestampRegex.firstMatch(lines[i]);
      if (m != null) {
        try {
          logEndTime = DateTime.parse(
            '${m.group(1)}-${m.group(2)}-${m.group(3)} ${m.group(4)}:${m.group(5)}:${m.group(6)}',
          );
          break;
        } catch (_) {}
      }
    }

    // Filter check to see if any photo could possibly be inside this log session duration
    bool hasAnyPotentialPhoto = false;
    for (final entry in searchMap.values) {
      final time = entry.photoTime;
      final takenBeforeStart =
          logStartTime != null &&
          time.isBefore(logStartTime.subtract(const Duration(minutes: 2)));
      final takenAfterEnd =
          logEndTime != null &&
          time.isAfter(logEndTime.add(const Duration(minutes: 2)));
      if (!takenBeforeStart && !takenAfterEnd) {
        hasAnyPotentialPhoto = true;
        break;
      }
    }

    if (!hasAnyPotentialPhoto) {
      continue; // Skip scanning the lines of this log entirely
    }

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (!line.contains('VRChat_')) {
        continue;
      }

      final match = screenshotRegex.firstMatch(line);
      if (match == null) continue;

      final extractedBaseName = match.group(0)!;
      final entry = searchMap[extractedBaseName];
      if (entry == null) continue;

      // Found a match for this photo! Search backward for world join
      int worldJoinLineIndex = -1;
      for (int k = i; k >= 0; k--) {
        final backwardLine = lines[k];
        if (backwardLine.contains('[Behaviour] Joining wrld_') ||
            backwardLine.contains('[Behaviour] Entering Room:')) {
          worldJoinLineIndex = k;
          break;
        }
      }

      if (worldJoinLineIndex == -1) {
        // Photo line found but no world join line exists in this log before it
        recovered.add(
          PhotoMetadata(
            takenDate: entry.photoTime.millisecondsSinceEpoch,
            filename: entry.filename,
            localPath: entry.filePath,
            isNonVrcx: true,
            logChecked: true,
          ),
        );
        searchMap.remove(extractedBaseName);
        continue;
      }

      // Parse room name
      String roomName = '';
      for (
        int j = (worldJoinLineIndex - 5 < 0 ? 0 : worldJoinLineIndex - 5);
        j <=
            (worldJoinLineIndex + 5 >= lines.length
                ? lines.length - 1
                : worldJoinLineIndex + 5);
        j++
      ) {
        final m = RegExp(
          r'\[Behaviour\] Entering Room: (.*?)(?:\r?\n|$)',
        ).firstMatch(lines[j]);
        if (m != null) {
          roomName = m.group(1)?.trim() ?? '';
          break;
        }
      }

      WorldInfo? worldInfo;
      final joinLine = lines[worldJoinLineIndex];
      final List<RegExp> worldPatterns = [
        RegExp(
          r'\[Behaviour\] Joining (wrld_[^:]+):([^~]+)~([^(]+)\(([^)]+)\)~canRequestInvite~region\(([^)]+)\)',
        ),
        RegExp(
          r'\[Behaviour\] Joining (wrld_[^:]+):([^~]+)~([^(]+)\(([^)]+)\)~region\(([^)]+)\)',
        ),
        RegExp(
          r'\[Behaviour\] Joining (wrld_[^:]+):([^~]+)~group\(([^)]+)\)~groupAccessType\(([^)]+)\)~region\(([^)]+)\)',
        ),
        RegExp(
          r'\[Behaviour\] Joining (wrld_[^:]+):([^~]+)~group\(([^)]+)\)~groupAccessType\(([^)]+)\)~inviteOnly~region\(([^)]+)\)',
        ),
        RegExp(r'\[Behaviour\] Joining (wrld_[^:]+):([^~]+)~region\(([^)]+)\)'),
      ];

      for (final regex in worldPatterns) {
        final m = regex.firstMatch(joinLine);
        if (m != null) {
          if (regex.pattern.contains('canRequestInvite')) {
            worldInfo = WorldInfo(
              name: roomName,
              id: m.group(1) ?? '',
              instanceId: m.group(2),
              accessType: m.group(3),
              ownerId: m.group(4),
              region: m.group(5),
              canRequestInvite: true,
            );
          } else if (regex.pattern.contains('group')) {
            final isInviteOnly = regex.pattern.contains('inviteOnly');
            worldInfo = WorldInfo(
              name: roomName,
              id: m.group(1) ?? '',
              instanceId: m.group(2),
              accessType: 'group',
              groupId: m.group(3),
              groupAccessType: m.group(4),
              region: m.group(5),
              inviteOnly: isInviteOnly ? true : null,
            );
          } else if (m.groupCount >= 5) {
            worldInfo = WorldInfo(
              name: roomName,
              id: m.group(1) ?? '',
              instanceId: m.group(2),
              accessType: m.group(3),
              ownerId: m.group(4),
              region: m.group(5),
            );
          } else {
            worldInfo = WorldInfo(
              name: roomName,
              id: m.group(1) ?? '',
              instanceId: m.group(2),
              accessType: 'public',
              region: m.group(3),
            );
          }
          break;
        }
      }

      if (worldInfo == null && roomName.isNotEmpty) {
        final worldIdMatch = RegExp(
          r'Joining (wrld_[^:]+):',
        ).firstMatch(joinLine);
        final worldId = worldIdMatch?.group(1) ?? '';
        worldInfo = WorldInfo(name: roomName, id: worldId);
      }

      // Reconstruct players
      final playerMap = <String, String>{};
      for (int k = worldJoinLineIndex; k <= i; k++) {
        final playerLine = lines[k];
        final pm = playerRegex.firstMatch(playerLine);
        if (pm != null && pm.groupCount >= 3) {
          final action = pm.group(1);
          final name = pm.group(2) ?? '';
          final id = pm.group(3) ?? '';
          if (action == 'Joined') {
            playerMap[id] = name;
          } else if (action == 'Left') {
            playerMap.remove(id);
          }
        }
      }

      final players =
          playerMap.entries
              .map((e) => Player(id: e.key, name: e.value))
              .toList();

      recovered.add(
        PhotoMetadata(
          takenDate: entry.photoTime.millisecondsSinceEpoch,
          filename: entry.filename,
          localPath: entry.filePath,
          isNonVrcx: worldInfo == null,
          logChecked: true,
          world: worldInfo,
          players: players,
        ),
      );

      searchMap.remove(extractedBaseName);
    }
  }

  return recovered;
}

class _PhotoSearchEntry {
  final String filePath;
  final String filename;
  final DateTime photoTime;
  final String searchTerm;

  _PhotoSearchEntry({
    required this.filePath,
    required this.filename,
    required this.photoTime,
    required this.searchTerm,
  });
}
