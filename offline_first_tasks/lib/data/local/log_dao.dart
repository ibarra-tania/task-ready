import '../models/sync_log_entry.dart';
import 'app_database.dart';

/// Bitácora persistente de sincronización.
class LogDao {
  LogDao(this._database);

  final AppDatabase _database;
  static const table = 'sync_log';
  static const _maxEntries = 300;

  Future<void> add(LogLevel level, String source, String message) async {
    await _database.db.insert(table, {
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'level': level.name,
      'source': source,
      'message': message,
    });
    // Mantiene la bitácora acotada.
    await _database.db.rawDelete(
      'DELETE FROM $table WHERE id NOT IN (SELECT id FROM $table ORDER BY id DESC LIMIT $_maxEntries)',
    );
    _database.notify(table);
  }

  Future<List<SyncLogEntry>> recent({int limit = 150}) async {
    final rows = await _database.db.query(table, orderBy: 'id DESC', limit: limit);
    return rows.map(SyncLogEntry.fromMap).toList();
  }

  Stream<List<SyncLogEntry>> watchRecent() async* {
    yield await recent();
    await for (final t in _database.changes) {
      if (t == table) yield await recent();
    }
  }

  Future<void> clear() async {
    await _database.db.delete(table);
    _database.notify(table);
  }
}
