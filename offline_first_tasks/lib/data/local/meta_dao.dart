import 'package:sqflite/sqflite.dart';

import 'app_database.dart';

/// Pares clave/valor de sincronización y preferencias del dispositivo.
///
/// Se guardan en SQLite (y no en memoria) porque el isolate de WorkManager
/// también necesita leerlos con la app cerrada.
class MetaDao {
  MetaDao(this._database);

  final AppDatabase _database;

  static const lastSyncAt = 'last_sync_at';
  static const remoteCount = 'remote_count';
  static const simulatedOffline = 'simulated_offline';

  Future<String?> get(String key) async {
    final rows = await _database.db
        .query('sync_meta', where: 'key = ?', whereArgs: [key], limit: 1);
    return rows.isEmpty ? null : rows.first['value'] as String?;
  }

  Future<void> set(String key, String? value) async {
    await _database.db.insert(
      'sync_meta',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    _database.notify('sync_meta');
  }

  /// Documentos que había en Firestore en la última descarga.
  Future<int> getRemoteCount() async => int.tryParse(await get(remoteCount) ?? '') ?? 0;

  Future<DateTime?> getLastSyncAt() async {
    final v = await get(lastSyncAt);
    return v == null ? null : DateTime.tryParse(v)?.toLocal();
  }

  Future<bool> isSimulatedOffline() async => (await get(simulatedOffline)) == '1';
}
