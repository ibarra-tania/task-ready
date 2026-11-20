/// Entidad de dominio con los metadatos de sincronización de la práctica.
///
/// * [isSynced]  0 = pendiente de subir, 1 = confirmado por el servidor.
/// * [updatedAt] marca temporal ISO-8601 UTC usada para Last-Write-Wins.
/// * [isDeleted] borrado lógico (soft delete) para propagar eliminaciones.
/// * [version]   contador incremental por edición (desempate y detección
///               de ediciones concurrentes).
class Task {
  const Task({
    required this.id,
    required this.title,
    this.description = '',
    this.isCompleted = false,
    this.isSynced = false,
    required this.updatedAt,
    this.isDeleted = false,
    this.version = 1,
    required this.createdAt,
  });

  final String id;
  final String title;
  final String description;
  final bool isCompleted;
  final bool isSynced;
  final DateTime updatedAt;
  final bool isDeleted;
  final int version;
  final DateTime createdAt;

  Task copyWith({
    String? title,
    String? description,
    bool? isCompleted,
    bool? isSynced,
    DateTime? updatedAt,
    bool? isDeleted,
    int? version,
  }) {
    return Task(
      id: id,
      title: title ?? this.title,
      description: description ?? this.description,
      isCompleted: isCompleted ?? this.isCompleted,
      isSynced: isSynced ?? this.isSynced,
      updatedAt: updatedAt ?? this.updatedAt,
      isDeleted: isDeleted ?? this.isDeleted,
      version: version ?? this.version,
      createdAt: createdAt,
    );
  }

  /// Genera una nueva revisión local: nueva marca temporal, versión + 1
  /// y bandera sucia (is_synced = 0).
  Task touch({
    String? title,
    String? description,
    bool? isCompleted,
    bool? isDeleted,
  }) {
    return copyWith(
      title: title,
      description: description,
      isCompleted: isCompleted,
      isDeleted: isDeleted,
      isSynced: false,
      updatedAt: DateTime.now().toUtc(),
      version: version + 1,
    );
  }

  // ------------------------------------------------------------ SQLite --

  Map<String, Object?> toMap({int? isSynced}) => {
        'id': id,
        'title': title,
        'description': description,
        'is_completed': isCompleted ? 1 : 0,
        'is_synced': isSynced ?? (this.isSynced ? 1 : 0),
        'updated_at': updatedAt.toUtc().toIso8601String(),
        'is_deleted': isDeleted ? 1 : 0,
        'version': version,
        'created_at': createdAt.toUtc().toIso8601String(),
      };

  factory Task.fromMap(Map<String, Object?> map) => Task(
        id: map['id'] as String,
        title: map['title'] as String,
        description: (map['description'] as String?) ?? '',
        isCompleted: (map['is_completed'] as int? ?? 0) == 1,
        isSynced: (map['is_synced'] as int? ?? 0) == 1,
        updatedAt: DateTime.parse(map['updated_at'] as String).toUtc(),
        isDeleted: (map['is_deleted'] as int? ?? 0) == 1,
        version: map['version'] as int? ?? 1,
        createdAt: DateTime.parse(
                (map['created_at'] ?? map['updated_at']) as String)
            .toUtc(),
      );

  // --------------------------------------------------------- Firestore --

  /// Documento de Firestore (`users/{uid}/tasks/{id}`). El ID del documento
  /// es el UUID; `owner_uid` y `server_updated_at` los agrega la capa remota.
  Map<String, Object?> toFirestore() => {
        'title': title,
        'description': description,
        'is_completed': isCompleted,
        'is_deleted': isDeleted,
        'updated_at': updatedAt.toUtc().toIso8601String(),
        'version': version,
        'created_at': createdAt.toUtc().toIso8601String(),
      };

  /// Un registro recibido de la nube ya está sincronizado por definición.
  /// Es tolerante a documentos creados/editados a mano en la consola.
  factory Task.fromFirestore(String id, Map<String, dynamic> data) {
    final serverTime = _parseDate(data['server_updated_at']);
    final updatedAt =
        _parseDate(data['updated_at']) ?? serverTime ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    return Task(
      id: id,
      title: (data['title'] ?? '(sin título)').toString(),
      description: (data['description'] ?? '').toString(),
      isCompleted: _parseBool(data['is_completed']),
      isDeleted: _parseBool(data['is_deleted']),
      isSynced: true,
      updatedAt: updatedAt,
      version: (data['version'] as num?)?.toInt() ?? 1,
      createdAt: _parseDate(data['created_at']) ?? updatedAt,
    );
  }

  static bool _parseBool(Object? v) => v == true || v == 1 || v == '1' || v == 'true';

  /// Acepta ISO-8601 (texto), DateTime o Timestamp de Firestore.
  static DateTime? _parseDate(Object? v) {
    if (v == null) return null;
    if (v is String) return DateTime.tryParse(v)?.toUtc();
    if (v is DateTime) return v.toUtc();
    try {
      final d = (v as dynamic).toDate();
      if (d is DateTime) return d.toUtc();
    } catch (_) {}
    return null;
  }

  /// Igualdad de contenido (ignora la bandera de sincronización).
  bool sameContentAs(Task other) =>
      id == other.id &&
      title == other.title &&
      description == other.description &&
      isCompleted == other.isCompleted &&
      isDeleted == other.isDeleted &&
      version == other.version &&
      updatedAt.isAtSameMomentAs(other.updatedAt);

  @override
  String toString() =>
      'Task($id, "$title", v$version, synced=$isSynced, deleted=$isDeleted)';
}
