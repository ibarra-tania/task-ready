import 'package:sqflite/sqflite.dart';

import '../models/task.dart';
import 'app_database.dart';

class TaskStats {
  const TaskStats({
    required this.total,
    required this.pending,
    required this.completed,
  });

  final int total;
  final int pending;
  final int completed;

  int get synced => total - pending;
}

/// Acceso a la tabla `tasks`.
class TaskDao {
  TaskDao(this._database);

  final AppDatabase _database;
  Database get _db => _database.db;

  static const table = 'tasks';

  /// Stream reactivo: emite al suscribirse y cada vez que la tabla cambia.
  Stream<List<Task>> watchActive() async* {
    yield await getActive();
    await for (final t in _database.changes) {
      if (t == table) yield await getActive();
    }
  }

  Stream<TaskStats> watchStats() async* {
    yield await stats();
    await for (final t in _database.changes) {
      if (t == table) yield await stats();
    }
  }

  Future<List<Task>> getActive() async {
    final rows = await _db.query(
      table,
      where: 'is_deleted = 0',
      orderBy: 'is_completed ASC, updated_at DESC',
    );
    return rows.map(Task.fromMap).toList();
  }

  Future<Task?> getById(String id) async {
    final rows = await _db.query(table, where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : Task.fromMap(rows.first);
  }

  /// Paso 3 de la práctica: escritura local inmediata con bandera sucia.
  Future<void> saveLocal(Task t) async {
    await _db.insert(
      table,
      t.toMap(isSynced: 0),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    _database.notify(table);
  }

  /// Registros pendientes de subir (is_synced = 0), incluidos borrados.
  Future<List<Task>> getPending() async {
    final rows = await _db.query(table, where: 'is_synced = 0', orderBy: 'updated_at ASC');
    return rows.map(Task.fromMap).toList();
  }

  /// ACK condicional: solo marca como sincronizada la MISMA revisión que se
  /// subió. Si el usuario editó el registro mientras viajaba la petición,
  /// la nueva revisión sigue pendiente y no se pierde.
  Future<bool> markSynced(Task pushed) async {
    final count = await _db.update(
      table,
      {'is_synced': 1},
      where: 'id = ? AND updated_at = ? AND version = ?',
      whereArgs: [
        pushed.id,
        pushed.updatedAt.toUtc().toIso8601String(),
        pushed.version,
      ],
    );
    return count > 0;
  }

  /// Escribe una revisión que viene del servidor (ya sincronizada).
  Future<void> upsertFromRemote(Task remote, {DatabaseExecutor? executor}) async {
    await (executor ?? _db).insert(
      table,
      remote.toMap(isSynced: 1),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  void notifyChanged() => _database.notify(table);

  Future<TaskStats> stats() async {
    final row = (await _db.rawQuery('''
      SELECT
        SUM(CASE WHEN is_deleted = 0 THEN 1 ELSE 0 END) AS total,
        SUM(CASE WHEN is_synced = 0 THEN 1 ELSE 0 END) AS pending,
        SUM(CASE WHEN is_deleted = 0 AND is_completed = 1 THEN 1 ELSE 0 END) AS completed
      FROM tasks
    ''')).first;
    return TaskStats(
      total: (row['total'] as int?) ?? 0,
      pending: (row['pending'] as int?) ?? 0,
      completed: (row['completed'] as int?) ?? 0,
    );
  }
}
