/// Configuración global de la app.
class AppConfig {
  const AppConfig._();

  static const appName = 'Tareas Offline-First';

  /// Estructura en Cloud Firestore: users/{uid}/tasks/{taskId}
  static const usersCollection = 'users';
  static const tasksCollection = 'tasks';

  static const requestTimeout = Duration(seconds: 12);

  /// Retraso para agrupar varias escrituras locales en una sola subida.
  static const syncDebounce = Duration(milliseconds: 700);

  // WorkManager (Paso 5 de la práctica).
  static const syncTaskUniqueName = 'sync-task-id';
  static const periodicTaskUniqueName = 'periodic-sync-task';
  static const syncTaskName = 'bidirectionalSync';
  static const periodicFrequency = Duration(minutes: 15);
}
