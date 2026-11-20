import '../data/local/app_database.dart';
import '../data/repositories/auth_repository.dart';
import '../data/repositories/task_repository.dart';
import '../data/security/secure_store.dart';
import '../sync/connectivity_monitor.dart';
import '../sync/sync_coordinator.dart';
import '../sync/sync_engine.dart';

/// Composición de dependencias (inyección manual, sin paquetes extra).
class AppServices {
  AppServices._({
    required this.db,
    required this.auth,
    required this.connectivity,
    required this.engine,
    required this.coordinator,
    required this.tasks,
  });

  static late AppServices instance;

  final AppDatabase db;
  final AuthRepository auth;
  final ConnectivityMonitor connectivity;
  final SyncEngine engine;
  final SyncCoordinator coordinator;
  final TaskRepository tasks;

  static Future<AppServices> init() async {
    final db = await AppDatabase.open();
    final auth = AuthRepository(db: db, secure: SecureStore());
    await auth.restore();

    final connectivity = ConnectivityMonitor(db.meta);
    await connectivity.start();

    final engine = SyncEngine(db: db, remoteFactory: auth.remoteDataSource);
    final coordinator = SyncCoordinator(
      engine: engine,
      connectivity: connectivity,
      db: db,
    )..start();

    final tasks = TaskRepository(db, onLocalChange: coordinator.onLocalChange);

    return instance = AppServices._(
      db: db,
      auth: auth,
      connectivity: connectivity,
      engine: engine,
      coordinator: coordinator,
      tasks: tasks,
    );
  }
}
