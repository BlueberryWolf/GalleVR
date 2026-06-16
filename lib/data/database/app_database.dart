import 'dart:io';
import 'dart:developer' as developer;
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path_provider/path_provider.dart';

class AppDatabase {
  static final AppDatabase _instance = AppDatabase._internal();
  static Database? _database;

  factory AppDatabase() => _instance;

  AppDatabase._internal();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    if (Platform.isWindows || Platform.isLinux) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    final dbDirectory = await getApplicationSupportDirectory();
    final path = join(dbDirectory.path, 'gallevr.db');

    return await openDatabase(
      path,
      version: 3,
      onCreate: _onCreate,
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          try {
            await db.execute(
              'ALTER TABLE photo_metadata ADD COLUMN log_checked INTEGER DEFAULT 0',
            );
            developer.log(
              'Successfully migrated database from v1 to v2: added log_checked',
              name: 'AppDatabase',
            );
          } catch (e) {
            developer.log(
              'Database upgrade error from v1 to v2: $e',
              name: 'AppDatabase',
            );
          }
        }
        if (oldVersion < 3) {
          try {
            await db.execute(
              'ALTER TABLE photo_metadata ADD COLUMN application TEXT',
            );
            await db.execute(
              'ALTER TABLE photo_metadata ADD COLUMN taken_global_position TEXT',
            );
            await db.execute(
              'ALTER TABLE photo_metadata ADD COLUMN taken_global_rotation TEXT',
            );
            await db.execute(
              'ALTER TABLE photo_metadata ADD COLUMN taken_global_scale TEXT',
            );
            await db.execute(
              'ALTER TABLE photo_metadata ADD COLUMN camera_fov TEXT',
            );
            await db.execute(
              'ALTER TABLE photo_metadata ADD COLUMN camera_manufacturer TEXT',
            );
            await db.execute(
              'ALTER TABLE photo_metadata ADD COLUMN taken_by_id TEXT',
            );
            developer.log(
              'Successfully migrated database from v2 to v3: added Resonite and application columns',
              name: 'AppDatabase',
            );
          } catch (e) {
            developer.log(
              'Database upgrade error from v2 to v3: $e',
              name: 'AppDatabase',
            );
          }
        }
      },
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE photo_metadata (
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
        taken_by_id TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE players (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE photo_players (
        photo_id TEXT NOT NULL,
        player_id TEXT NOT NULL,
        PRIMARY KEY (photo_id, player_id),
        FOREIGN KEY (photo_id) REFERENCES photo_metadata (id) ON DELETE CASCADE,
        FOREIGN KEY (player_id) REFERENCES players (id) ON DELETE CASCADE
      )
    ''');

    await db.execute('CREATE INDEX idx_filename ON photo_metadata (filename)');
    await db.execute(
      'CREATE INDEX idx_local_path ON photo_metadata (local_path)',
    );
    await db.execute(
      'CREATE INDEX idx_photo_players_photo ON photo_players (photo_id)',
    );
    await db.execute(
      'CREATE INDEX idx_photo_players_player ON photo_players (player_id)',
    );
  }

  Future<void> close() async {
    final db = _database;
    if (db != null) {
      await db.close();
      _database = null;
    }
  }
}
