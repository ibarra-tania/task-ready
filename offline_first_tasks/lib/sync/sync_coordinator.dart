import 'dart:async';

import '../core/app_config.dart';
import '../data/local/app_database.dart';
import '../data/models/sync_log_entry.dart';
import 'background_sync.dart';
import 'connectivity_monitor.dart';
import 'sync_engine.dart';

/// Orquesta CUÁNDO sincronizar:
///
/// * Tras cada escritura local (agrupando ráfagas con debounce).
/// * Al recuperar la conexión (disparo automático de la cola).
/// * Sin red: delega en WorkManager con restricción `NetworkType.connected`.
class SyncCoordinator {
  SyncCoordinator({
    required this.engine,
    required this.connectivity,
    required this.db,
  });

  final SyncEngine engine;
  final ConnectivityMonitor connectivity;
  final AppDatabase db;

  bool _wasOnline = true;
  Timer? _debounce;
  bool enabled = false;

  void start() {
    _wasOnline = connectivity.value.isOnline;
    connectivity.addListener(_onConnectivityChanged);
  }

  void _onConnectivityChanged() {
    final online = connectivity.value.isOnline;
    if (online == _wasOnline) return;
    _wasOnline = online;
    if (!enabled) return;

    if (online) {
      db.log.add(LogLevel.info, 'Conectividad',
          'Conexión recuperada (${connectivity.value.label}): ejecutando la cola pendiente.');
      syncNow('Reconexión');
    } else {
      db.log.add(LogLevel.warning, 'Conectividad',
          'Sin conexión: la app sigue funcionando sobre SQLite; los cambios quedan en cola.');
    }
  }

  /// Llamado por el repositorio después de cada escritura local.
  void onLocalChange(String description) {
    if (!enabled) return;
    if (connectivity.value.isOnline) {
      _debounce?.cancel();
      _debounce = Timer(AppConfig.syncDebounce, () => syncNow('Escritura local'));
    } else {
      db.log.add(LogLevel.info, 'Offline',
          '$description guardado en SQLite (is_synced = 0). WorkManager programado para cuando vuelva la red.');
      BackgroundSync.enqueueOneOff();
    }
  }

  Future<SyncReport?> syncNow(String source) async {
    if (!enabled || !connectivity.value.isOnline) return null;
    final report = await engine.sync(source: source);
    if (!report.ok && report.networkError) {
      // El servidor no respondió: WorkManager reintentará con backoff.
      await BackgroundSync.enqueueOneOff();
    }
    return report;
  }

  void dispose() {
    _debounce?.cancel();
    connectivity.removeListener(_onConnectivityChanged);
  }
}
