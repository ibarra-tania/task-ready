import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/session.dart';

/// Cifrado en reposo de credenciales (Codificación segura · Unidad II).
///
/// flutter_secure_storage cifra los valores con claves del Android Keystore
/// (AES-GCM) y en iOS usa el Keychain. El token nunca toca SQLite.
class SecureStore {
  SecureStore([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _kToken = 'auth_token';
  static const _kUid = 'auth_uid';
  static const _kEmail = 'auth_email';

  Future<Session?> readSession() async {
    final values = await _storage.readAll();
    final token = values[_kToken];
    final uid = values[_kUid];
    final email = values[_kEmail];
    if (token == null || uid == null || email == null) return null;
    return Session(token: token, uid: uid, email: email);
  }

  Future<void> saveSession(Session s) async {
    await _storage.write(key: _kToken, value: s.token);
    await _storage.write(key: _kUid, value: s.uid);
    await _storage.write(key: _kEmail, value: s.email);
  }

  Future<void> clear() async {
    await _storage.delete(key: _kToken);
    await _storage.delete(key: _kUid);
    await _storage.delete(key: _kEmail);
  }
}
