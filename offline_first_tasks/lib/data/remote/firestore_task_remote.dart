import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/app_config.dart';
import '../../sync/conflict_resolver.dart';
import '../models/task.dart';
import 'remote_exception.dart';
import 'task_remote_data_source.dart';

/// Backend en la nube con Cloud Firestore.
///
/// Estructura: `users/{uid}/tasks/{taskId}`. El ID del documento es el
/// UUID generado en el cliente → la subida es idempotente.
class FirestoreTaskRemote implements TaskRemoteDataSource {
  FirestoreTaskRemote({required this.uid, FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final String uid;
  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _tasks => _db
      .collection(AppConfig.usersCollection)
      .doc(uid)
      .collection(AppConfig.tasksCollection);

  /// Convierte errores de Firebase y timeouts en [RemoteException].
  Future<T> _guard<T>(Future<T> Function() op) async {
    try {
      return await op().timeout(AppConfig.requestTimeout);
    } on TimeoutException {
      throw const RemoteException('Firestore no respondió a tiempo', isNetworkError: true);
    } on FirebaseException catch (e) {
      throw RemoteException.fromCode(e.code, e.message);
    }
  }

  @override
  Future<List<PushResult>> push(List<Task> pending) async {
    final results = <PushResult>[];
    for (final t in pending) {
      results.add(await _guard(() => _pushOne(t)));
    }
    return results;
  }

  /// Transacción: lee la versión de la nube y solo escribe si la revisión
  /// local es más reciente (Last-Write-Wins + versión). Así dos
  /// dispositivos no se pisan aunque sincronicen al mismo tiempo.
  Future<PushResult> _pushOne(Task local) {
    final ref = _tasks.doc(local.id);
    return _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (snap.exists) {
        final remote = Task.fromFirestore(snap.id, snap.data()!);
        final cmp = ConflictResolver.compare(local, remote);
        if (cmp < 0) {
          return PushResult(local.id, PushStatus.conflict, serverTask: remote);
        }
        if (cmp == 0 && remote.sameContentAs(local)) {
          // Reintento idempotente: ya existe exactamente esta revisión.
          return PushResult(local.id, PushStatus.applied);
        }
      }
      tx.set(ref, {
        ...local.toFirestore(),
        'owner_uid': uid,
        'server_updated_at': FieldValue.serverTimestamp(),
      });
      return PushResult(local.id, PushStatus.applied);
    });
  }

  @override
  Future<List<Task>> fetchAll() => _guard(() async {
        // Source.server: la lectura viene de la nube, nunca de la caché de
        // Firestore (SQLite es la única caché local de la app).
        final snap = await _tasks.get(const GetOptions(source: Source.server));
        return snap.docs.map((d) => Task.fromFirestore(d.id, d.data())).toList();
      });

  /// Latencia de ida y vuelta contra Firestore (ms).
  Future<int> ping() => _guard(() async {
        final sw = Stopwatch()..start();
        await _tasks.limit(1).get(const GetOptions(source: Source.server));
        return sw.elapsedMilliseconds;
      });
}
