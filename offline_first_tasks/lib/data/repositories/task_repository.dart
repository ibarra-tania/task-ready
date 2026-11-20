import 'package:uuid/uuid.dart';

import '../local/app_database.dart';
import '../models/task.dart';

typedef LocalChangeCallback = void Function(String description);

/// Repositorio de tareas. Toda escritura va PRIMERO a SQLite (respuesta
/// instantánea, 0 ms de latencia percibida) y después se notifica al
/// coordinador para que sincronice cuando sea posible.
class TaskRepository {
  TaskRepository(this._db, {required this.onLocalChange});

  final AppDatabase _db;
  final LocalChangeCallback onLocalChange;
  final _uuid = const Uuid();

  Stream<List<Task>> watchTasks() => _db.tasks.watchActive();

  /// La clave primaria se genera en el cliente (UUID v4): permite crear
  /// registros offline y hace idempotente la subida al API.
  Future<Task> create({required String title, String description = ''}) async {
    final now = DateTime.now().toUtc();
    final task = Task(
      id: _uuid.v4(),
      title: title.trim(),
      description: description.trim(),
      updatedAt: now,
      createdAt: now,
    );
    await _db.tasks.saveLocal(task);
    onLocalChange('Nueva tarea "${task.title}"');
    return task;
  }

  Future<Task> update(Task task, {required String title, String description = ''}) async {
    final updated = task.touch(title: title.trim(), description: description.trim());
    await _db.tasks.saveLocal(updated);
    onLocalChange('Edición de "${updated.title}"');
    return updated;
  }

  Future<Task> toggleCompleted(Task task) async {
    final updated = task.touch(isCompleted: !task.isCompleted);
    await _db.tasks.saveLocal(updated);
    onLocalChange('${updated.isCompleted ? 'Completado' : 'Reapertura'} de "${task.title}"');
    return updated;
  }

  /// Borrado lógico (soft delete): el registro se conserva con
  /// is_deleted = 1 para que la eliminación también se sincronice.
  Future<Task> delete(Task task) async {
    final deleted = task.touch(isDeleted: true);
    await _db.tasks.saveLocal(deleted);
    onLocalChange('Borrado lógico de "${task.title}"');
    return deleted;
  }

  Future<Task> restore(Task deleted) async {
    final restored = deleted.touch(isDeleted: false);
    await _db.tasks.saveLocal(restored);
    onLocalChange('Restauración de "${deleted.title}"');
    return restored;
  }
}
