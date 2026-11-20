import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../../core/app_config.dart';
import '../../sync/background_sync.dart';
import '../local/app_database.dart';
import '../models/session.dart';
import '../remote/firestore_task_remote.dart';
import '../remote/remote_exception.dart';
import '../security/secure_store.dart';

/// Autenticación con Firebase Auth (correo/contraseña) + sesión segura.
class AuthRepository {
  AuthRepository({required this.db, required this.secure, FirebaseAuth? auth})
      : _auth = auth ?? FirebaseAuth.instance;

  final AppDatabase db;
  final SecureStore secure;
  final FirebaseAuth _auth;

  final ValueNotifier<Session?> session = ValueNotifier(null);

  /// Restaura la sesión sin red: Firebase Auth conserva el usuario y el
  /// token cifrado vive en flutter_secure_storage.
  Future<void> restore() async {
    final user = _auth.currentUser;
    if (user == null) {
      await secure.clear();
      session.value = null;
      return;
    }
    session.value = await secure.readSession() ??
        Session(token: '', uid: user.uid, email: user.email ?? '');
  }

  Future<Session> signIn({
    required String email,
    required String password,
    bool register = false,
  }) async {
    try {
      final cred = await (register
              ? _auth.createUserWithEmailAndPassword(email: email.trim(), password: password)
              : _auth.signInWithEmailAndPassword(email: email.trim(), password: password))
          .timeout(AppConfig.requestTimeout);
      final user = cred.user!;
      // ID token (JWT) de Firebase: se guarda cifrado en reposo.
      final token = await user.getIdToken() ?? '';
      final s = Session(token: token, uid: user.uid, email: user.email ?? email.trim());
      await secure.saveSession(s);
      session.value = s;
      return s;
    } on FirebaseAuthException catch (e) {
      throw RemoteException.fromCode(e.code, e.message);
    } on TimeoutException {
      throw const RemoteException('Firebase no respondió a tiempo', isNetworkError: true);
    }
  }

  /// Limpieza de sesión: cierra sesión en Firebase, cancela WorkManager,
  /// purga la base SQLite y borra las credenciales cifradas.
  Future<void> signOut() async {
    await BackgroundSync.cancelAll();
    await _auth.signOut();
    await db.purgeUserData();
    await secure.clear();
    session.value = null;
  }

  /// Fuente remota del usuario autenticado (UI e isolate de WorkManager).
  /// El UID sale de Firebase Auth, nunca de datos que controle el usuario.
  Future<FirestoreTaskRemote?> remoteDataSource() async {
    final user = _auth.currentUser;
    if (user == null) return null;
    return FirestoreTaskRemote(uid: user.uid);
  }

  /// Latencia contra Firestore (ms) o lanza [RemoteException].
  Future<int> ping() async {
    final remote = await remoteDataSource();
    if (remote == null) throw const RemoteException('Inicia sesión primero');
    return remote.ping();
  }
}
