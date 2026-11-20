import '../data/models/task.dart';

enum MergeAction {
  /// El registro no existe localmente: se inserta.
  insert,

  /// Gana la revisión remota: se sobrescribe la copia local.
  overwrite,

  /// Gana la revisión local (pendiente): se subirá en el siguiente PUSH.
  keepLocal,

  /// Es exactamente la misma revisión: no hay nada que hacer.
  skip,
}

class MergeDecision {
  const MergeDecision(this.action, {this.isConflict = false});

  final MergeAction action;

  /// Hubo ediciones concurrentes (local pendiente vs. remoto distinto).
  final bool isConflict;
}

/// Estrategia de resolución de colisiones de la práctica:
///
/// 1. **Last-Write-Wins (LWW)** comparando `updated_at` en UTC.
/// 2. **Control de versiones** como desempate cuando las marcas temporales
///    coinciden (y para detectar ediciones concurrentes).
///
/// Es una clase pura (sin E/S) para poder probarla con pruebas unitarias.
class ConflictResolver {
  const ConflictResolver._();

  /// > 0 si [a] es más reciente que [b]; < 0 si es más antigua; 0 si es la
  /// misma escritura.
  static int compare(Task a, Task b) {
    final byTime = a.updatedAt.toUtc().compareTo(b.updatedAt.toUtc());
    if (byTime != 0) return byTime;
    return a.version.compareTo(b.version);
  }

  static MergeDecision resolve({required Task? local, required Task remote}) {
    if (local == null) return const MergeDecision(MergeAction.insert);

    final cmp = compare(remote, local);

    if (local.isSynced) {
      // Sin cambios locales pendientes: el servidor es la referencia.
      if (cmp == 0 && remote.sameContentAs(local)) {
        return const MergeDecision(MergeAction.skip);
      }
      if (cmp >= 0) return const MergeDecision(MergeAction.overwrite);
      return const MergeDecision(MergeAction.skip);
    }

    // La copia local tiene cambios sin subir (is_synced = 0).
    if (cmp > 0) {
      // El remoto es más nuevo: LWW → gana el remoto, se descarta lo local.
      return const MergeDecision(MergeAction.overwrite, isConflict: true);
    }
    if (cmp == 0) {
      // Mismo updated_at y versión: es nuestro propio cambio de vuelta.
      return const MergeDecision(MergeAction.overwrite);
    }
    // Lo local es más nuevo: se conserva y se subirá en el siguiente PUSH.
    // Es colisión si el remoto trae una versión que no deriva de la local.
    return MergeDecision(
      MergeAction.keepLocal,
      isConflict: remote.version >= local.version,
    );
  }
}
