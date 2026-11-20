import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:workmanager/workmanager.dart';

import '../core/app_config.dart';
import '../core/firebase_setup.dart';
import '../data/local/app_database.dart';
import '../data/models/sync_log_entry.dart';
import '../data/repositories/auth_repository.dart';
import '../data/security/secure_store.dart';
import 'sync_engine.dart';

/// Punto de entrada del isolate de WorkManager (se ejecuta incluso con la
/// app cerrada). Debe ser una función de nivel superior.
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();
    DartPluginRegistrant.ensureInitialized();

    AppDatabase? db;
    try {
      await initFirebase();
      db = await AppDatabase.open();
      if (await db.meta.isSimulatedOffline()) {
        await db.log.add(LogLevel.info, 'WorkManager',
            'Tarea en segundo plano omitida: modo sin conexión simulado activo.');
        return true;
      }
      final auth = AuthRepository(db: db, secure: SecureStore());
      final engine = SyncEngine(db: db, remoteFactory: auth.remoteDataSource);
      final report = await engine.sync(source: 'WorkManager');
      // false → WorkManager reintenta con backoff exponencial.
      return report.ok || !report.networkError;
    } catch (e) {
      debugPrint('WorkManager error: $e');
      return false;
    } finally {
      await db?.close();
    }
  });
}

/// Paso 5 de la práctica: tareas en segundo plano con WorkManager.
class BackgroundSync {
  const BackgroundSync._();

  static bool get _supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static Future<void> initialize() async {
    if (!_supported) return;
    await Workmanager().initialize(callbackDispatcher);
  }

  /// Sincronización única que el sistema ejecuta en cuanto haya red,
  /// aunque el usuario haya cerrado la app.
  static Future<void> enqueueOneOff() async {
    if (!_supported) return;
    try {
      await Workmanager().registerOneOffTask(
        AppConfig.syncTaskUniqueName,
        AppConfig.syncTaskName,
        constraints: Constraints(networkType: NetworkType.connected),
        existingWorkPolicy: ExistingWorkPolicy.replace,
        backoffPolicy: BackoffPolicy.exponential,
        backoffPolicyDelay: const Duration(seconds: 30),
      );
    } catch (e) {
      debugPrint('No se pudo programar WorkManager: $e');
    }
  }

  /// Respaldo periódico (mínimo permitido por Android: 15 minutos).
  static Future<void> registerPeriodic() async {
    if (!_supported) return;
    try {
      await Workmanager().registerPeriodicTask(
        AppConfig.periodicTaskUniqueName,
        AppConfig.syncTaskName,
        frequency: AppConfig.periodicFrequency,
        constraints: Constraints(networkType: NetworkType.connected),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
      );
    } catch (e) {
      debugPrint('No se pudo programar la tarea periódica: $e');
    }
  }

  static Future<void> cancelAll() async {
    if (!_supported) return;
    try {
      await Workmanager().cancelAll();
    } catch (_) {}
  }
}
