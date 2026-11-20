import '../models/task.dart';

enum PushStatus {
  /// La nube aceptó la revisión (o ya la tenía: reintento idempotente).
  applied,

  /// La nube tiene una revisión más reciente (Last-Write-Wins).
  conflict,
}

class PushResult {
  const PushResult(this.id, this.status, {this.serverTask});

  final String id;
  final PushStatus status;

  /// Revisión que conserva la nube cuando hay [PushStatus.conflict].
  final Task? serverTask;
}

/// Contrato del backend en la nube. El motor de sincronización depende de
/// esta abstracción, no de Firestore: así se prueba con un backend falso.
abstract class TaskRemoteDataSource {
  /// 01 PUSH: sube revisiones pendientes y devuelve el resultado por registro.
  Future<List<PushResult>> push(List<Task> pending);

  /// 03 PULL: descarga los registros del usuario (incluye borrados lógicos).
  Future<List<Task>> fetchAll();
}
