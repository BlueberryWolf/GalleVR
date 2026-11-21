import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../data/models/config_model.dart';
import '../data/models/log_metadata.dart';
import '../data/models/photo_metadata.dart';
import '../data/models/verification_models.dart';
import 'daemon_paths.dart';

class DaemonStorage {
  static final RegExp _vrcFilenameRegex = RegExp(
    r'VRChat_\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2}\.\d{3}(?:_\d+x\d+)?',
    caseSensitive: false,
  );

  Database? _db;
  bool _ffiInitialized = false;

  Future<Database> get database async {
    if (_db != null && _db!.isOpen) return _db!;
    if (!_ffiInitialized) {
      sqfliteFfiInit();
      _ffiInitialized = true;
    }

    final dbPath = DaemonPaths.getDbPath();
    _db = await databaseFactoryFfi.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 4,
        onCreate: _onCreate,
        onOpen: (db) async {
          try {
            await db.rawQuery('PRAGMA journal_mode = WAL');
            await db.rawQuery('PRAGMA busy_timeout = 5000');
            await db.execute('PRAGMA cache_size = -512');
          } catch (_) {}
        },
        onUpgrade: _onUpgrade,
      ),
    );
    return _db!;
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS photo_metadata (
        id TEXT PRIMARY KEY,
        filename TEXT NOT NULL,
        taken_date INTEGER NOT NULL,
        local_path TEXT,
        gallery_url TEXT,
        views INTEGER DEFAULT 0,
        is_non_vrcx INTEGER DEFAULT 0,
        is_edited INTEGER DEFAULT 0,
        log_checked INTEGER DEFAULT 0,
        world_id TEXT,
        world_name TEXT,
        world_instance_id TEXT,
        world_access_type TEXT,
        world_region TEXT,
        world_owner_id TEXT,
        world_group_id TEXT,
        world_group_access_type TEXT,
        world_can_request_invite INTEGER,
        world_invite_only INTEGER,
        application TEXT,
        taken_global_position TEXT,
        taken_global_rotation TEXT,
        taken_global_scale TEXT,
        camera_fov TEXT,
        camera_manufacturer TEXT,
        taken_by_id TEXT,
        metadata_json TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS players (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS photo_players (
        photo_id TEXT NOT NULL,
        player_id TEXT NOT NULL,
        PRIMARY KEY (photo_id, player_id),
        FOREIGN KEY (photo_id) REFERENCES photo_metadata (id) ON DELETE CASCADE,
        FOREIGN KEY (player_id) REFERENCES players (id) ON DELETE CASCADE
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_filename ON photo_metadata (filename)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_local_path ON photo_metadata (local_path)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_photo_players_photo ON photo_players (photo_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_photo_players_player ON photo_players (player_id)',
    );
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      try {
        await db.execute(
          'ALTER TABLE photo_metadata ADD COLUMN log_checked INTEGER DEFAULT 0',
        );
      } catch (_) {}
    }
    if (oldVersion < 3) {
      for (final col in [
        'application',
        'taken_global_position',
        'taken_global_rotation',
        'taken_global_scale',
        'camera_fov',
        'camera_manufacturer',
        'taken_by_id',
      ]) {
        try {
          await db.execute('ALTER TABLE photo_metadata ADD COLUMN $col TEXT');
        } catch (_) {}
      }
    }
    if (oldVersion < 4) {
      try {
        await db.execute(
          'ALTER TABLE photo_metadata ADD COLUMN metadata_json TEXT',
        );
      } catch (_) {}
    }
  }

  Future<void> shrinkMemory() async {
    final db = _db;
    if (db == null || !db.isOpen) return;
    try {
      await db.execute('PRAGMA shrink_memory');
    } catch (_) {}
  }

  Future<void> close() async {
    final db = _db;
    _db = null;
    if (db != null && db.isOpen) {
      await db.close();
    }
  }

  Future<ConfigModel> loadConfig() async {
    try {
      final configFile = File(DaemonPaths.getConfigFilePath());
      if (await configFile.exists()) {
        final raw = await configFile.readAsString();
        final map = json.decode(raw) as Map<String, dynamic>;
        return ConfigModel.fromJson(map);
      }
    } catch (_) {}
    return ConfigModel(
      photosDirectory: DaemonPaths.getDefaultPhotosDir(),
      logsDirectory: DaemonPaths.getDefaultLogsDir(),
      resonitePhotosDirectory: DaemonPaths.getDefaultResoniteDir(),
      uploadEnabled: true,
    );
  }

  Future<Map<String, dynamic>> _readSharedPrefs() async {
    try {
      final file = File(DaemonPaths.getSharedPrefsPath());
      if (!await file.exists()) return {};
      final decoded = json.decode(await file.readAsString());
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {}
    return {};
  }

  Future<void> _writeSharedPrefs(Map<String, dynamic> map) async {
    try {
      final filePath = DaemonPaths.getSharedPrefsPath();
      final tmp = File('$filePath.tmp');
      await tmp.writeAsString(json.encode(map), flush: true);
      await tmp.rename(filePath);
    } catch (_) {}
  }

  Future<AuthData?> loadAuthData({bool secondary = false}) async {
    final prefs = await _readSharedPrefs();
    final key =
        secondary
            ? 'flutter.gallevr_auth_data_secondary'
            : 'flutter.gallevr_auth_data';
    final raw = prefs[key];
    if (raw is! String || raw.isEmpty) return null;
    try {
      return AuthData.fromJson(json.decode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveAuthData(AuthData authData, {bool secondary = false}) async {
    final prefs = await _readSharedPrefs();
    final key =
        secondary
            ? 'flutter.gallevr_auth_data_secondary'
            : 'flutter.gallevr_auth_data';
    prefs[key] = json.encode(authData.toJson());
    await _writeSharedPrefs(prefs);
  }

  Future<void> savePhotoMetadata(
    PhotoMetadata metadata, {
    AuthData? primaryAuth,
  }) async {
    final db = await database;

    if (metadata.application == 'VRChat' && primaryAuth != null) {
      final updatedPlayers =
          metadata.players.map((p) {
            if (p.id.isEmpty) {
              return Player(id: primaryAuth.userId, name: p.name);
            }
            return p;
          }).toList();
      metadata = metadata.copyWith(players: updatedPlayers);
    }

    final root = path.basenameWithoutExtension(metadata.filename);
    final filenames = <String>{metadata.filename, '$root.png', '$root.webp'}.toList();
    final placeholdersF = List.filled(filenames.length, '?').join(',');
    final whereArgs = <Object?>[...filenames];
    var whereClause = 'filename IN ($placeholdersF)';
    if (metadata.localPath != null) {
      whereClause += ' OR local_path = ?';
      whereArgs.add(metadata.localPath);
    }

    final existingRows = await db.query(
      'photo_metadata',
      where: whereClause,
      whereArgs: whereArgs,
    );

    String? existingId;
    PhotoMetadata? existingMeta;

    if (existingRows.isNotEmpty) {
      final row = existingRows.first;
      existingId = row['id'] as String;
      existingMeta = await _hydrateRow(db, row);
    } else {
      var fuzzy = await db.query(
        'photo_metadata',
        where: 'filename LIKE ?',
        whereArgs: ['%$root%'],
        limit: 1,
      );
      if (fuzzy.isEmpty) {
        final match = _vrcFilenameRegex.firstMatch(metadata.filename);
        if (match != null) {
          fuzzy = await db.query(
            'photo_metadata',
            where: 'filename LIKE ?',
            whereArgs: ['%${match.group(0)!}%'],
            limit: 1,
          );
        }
      }
      if (fuzzy.isNotEmpty) {
        existingId = fuzzy.first['id'] as String;
        existingMeta = await _hydrateRow(db, fuzzy.first);
      }
    }

    final finalId = existingId ?? '${metadata.filename}_${metadata.takenDate}';
    if (existingMeta != null) {
      metadata = metadata.merge(existingMeta, isRemote: false);
    }

    await db.transaction((txn) async {
      final batch = txn.batch();
      batch.insert(
        'photo_metadata',
        _toDbMap(metadata, finalId),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      batch.delete(
        'photo_players',
        where: 'photo_id = ?',
        whereArgs: [finalId],
      );
      for (final player in metadata.players) {
        batch.insert('players', {
          'id': player.id,
          'name': player.name,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
        batch.insert('photo_players', {
          'photo_id': finalId,
          'player_id': player.id,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
      await batch.commit(noResult: true);
    });
  }

  Future<PhotoMetadata> _hydrateRow(
    Database db,
    Map<String, dynamic> row,
  ) async {
    final photoId = row['id'] as String;
    final playerRows = await db.rawQuery(
      '''
      SELECT p.id, p.name
      FROM players p
      INNER JOIN photo_players pp ON p.id = pp.player_id
      WHERE pp.photo_id = ?
      ''',
      [photoId],
    );
    final players =
        playerRows
            .map(
              (r) => Player(id: r['id'] as String, name: r['name'] as String),
            )
            .toList();

    final jsonStr = row['metadata_json'] as String?;
    if (jsonStr != null && jsonStr.isNotEmpty) {
      try {
        final decoded = json.decode(jsonStr) as Map<String, dynamic>;
        return PhotoMetadata.fromJson(decoded).copyWith(
          localPath: row['local_path'] as String?,
          galleryUrl: row['gallery_url'] as String?,
          views: row['views'] as int? ?? 0,
          isNonVrcx: (row['is_non_vrcx'] as int? ?? 0) == 1,
          isEdited: (row['is_edited'] as int? ?? 0) == 1,
          logChecked: (row['log_checked'] as int? ?? 0) == 1,
        );
      } catch (_) {}
    }

    final hasWorld = row['world_id'] != null || row['world_name'] != null;
    final world =
        hasWorld
            ? WorldInfo(
              id: row['world_id'] as String? ?? '',
              name: row['world_name'] as String? ?? '',
              instanceId: row['world_instance_id'] as String?,
              accessType: row['world_access_type'] as String?,
              region: row['world_region'] as String?,
              ownerId: row['world_owner_id'] as String?,
              groupId: row['world_group_id'] as String?,
              groupAccessType: row['world_group_access_type'] as String?,
              canRequestInvite:
                  row['world_can_request_invite'] == null
                      ? null
                      : (row['world_can_request_invite'] as int) == 1,
              inviteOnly:
                  row['world_invite_only'] == null
                      ? null
                      : (row['world_invite_only'] as int) == 1,
            )
            : null;

    return PhotoMetadata(
      takenDate: row['taken_date'] as int,
      filename: row['filename'] as String,
      localPath: row['local_path'] as String?,
      galleryUrl: row['gallery_url'] as String?,
      views: row['views'] as int? ?? 0,
      isNonVrcx: (row['is_non_vrcx'] as int? ?? 0) == 1,
      isEdited: (row['is_edited'] as int? ?? 0) == 1,
      logChecked: (row['log_checked'] as int? ?? 0) == 1,
      world: world,
      players: players,
      application: row['application'] as String?,
      takenGlobalPosition: row['taken_global_position'] as String?,
      takenGlobalRotation: row['taken_global_rotation'] as String?,
      takenGlobalScale: row['taken_global_scale'] as String?,
      cameraFov: row['camera_fov'] as String?,
      cameraManufacturer: row['camera_manufacturer'] as String?,
      takenById: row['taken_by_id'] as String?,
    );
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
      'metadata_json': json.encode(metadata.toJson()),
    };
  }
}
