enum LogLevel { info, success, warning, error }

/// Entrada de la bitácora de sincronización (persistida en SQLite para
/// poder auditar lo que hizo WorkManager aunque la app estuviera cerrada).
class SyncLogEntry {
  const SyncLogEntry({
    required this.id,
    required this.createdAt,
    required this.level,
    required this.source,
    required this.message,
  });

  final int id;
  final DateTime createdAt;
  final LogLevel level;
  final String source;
  final String message;

  factory SyncLogEntry.fromMap(Map<String, Object?> map) => SyncLogEntry(
        id: map['id'] as int,
        createdAt: DateTime.parse(map['created_at'] as String).toLocal(),
        level: LogLevel.values.byName(map['level'] as String),
        source: map['source'] as String,
        message: map['message'] as String,
      );
}
