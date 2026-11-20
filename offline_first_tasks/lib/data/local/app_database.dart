import 'dart:async';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'log_dao.dart';
import 'meta_dao.dart';
import 'task_dao.dart';

/// Base de datos SQLite local: la **fuente única de verdad** (SSOT).
///
/// La UI nunca lee del servidor; solo escucha los streams que emite esta
/// capa. El servidor alimenta SQLite en segundo plano.
class AppDatabase {
  AppDatabase._(this.db) {
    tasks = TaskDao(this);
    meta = MetaDao(this);
    log = LogDao(this);
  }

  static const fileName = 'offline_first.db';
  static const schemaVersion = 1;

  final Database db;
  late final TaskDao tasks;
  late final MetaDao meta;
  late final LogDao log;

  final _changes = StreamController<String>.broadcast();

  /// Emite el nombre de la tabla modificada para refrescar streams.
  Stream<String> get changes => _changes.stream;

  void notify(String table) {
    if (!_changes.isClosed) _changes.add(table);
  }

  static Future<AppDatabase> open({
    String? path,
    DatabaseFactory? factory,
  }) async {
    final f = factory ?? databaseFactory;
    final dbPath = path ?? p.join(await f.getDatabasesPath(), fileName);
    final db = await f.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: schemaVersion,
        onConfigure: (db) async {
          // WAL permite que WorkManager (otro isolate) y la UI lean/escriban
          // sin bloquearse mutuamente.
          await db.rawQuery('PRAGMA journal_mode=WAL');
        },
        onCreate: _createSchema,
      ),
    );
    return AppDatabase._(db);
  }

  static Future<void> _createSchema(Database db, int version) async {
    final batch = db.batch();
    // Tabla de la práctica (Paso 2) + columnas de soporte.
    batch.execute('''
      CREATE TABLE tasks (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        description TEXT NOT NULL DEFAULT '',
        is_completed INTEGER NOT NULL DEFAULT 0,
        is_synced INTEGER DEFAULT 0,
        updated_at TEXT NOT NULL,
        is_deleted INTEGER DEFAULT 0,
        version INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL
      )
    ''');
    batch.execute('CREATE INDEX idx_tasks_sync ON tasks(is_synced)');
    batch.execute('''
      CREATE TABLE sync_meta (
        key TEXT PRIMARY KEY,
        value TEXT
      )
    ''');
    batch.execute('''
      CREATE TABLE sync_log (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        created_at TEXT NOT NULL,
        level TEXT NOT NULL,
        source TEXT NOT NULL,
        message TEXT NOT NULL
      )
    ''');
    await batch.commit(noResult: true);
  }

  /// Limpieza de sesión: purga todos los datos del usuario. Se conservan
  /// solo las preferencias del dispositivo (modo laboratorio).
  Future<void> purgeUserData() async {
    await db.transaction((txn) async {
      await txn.delete('tasks');
      await txn.delete('sync_log');
      await txn.delete('sync_meta',
          where: 'key IN (?, ?)',
          whereArgs: [MetaDao.remoteCount, MetaDao.lastSyncAt]);
    });
    notify('tasks');
    notify('sync_log');
    notify('sync_meta');
  }

  Future<void> close() async {
    await _changes.close();
    await db.close();
  }
}
