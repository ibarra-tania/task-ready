import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// Persistencia del "backend en la nube" en un archivo JSON.
///
/// Es deliberadamente simple (sin dependencias externas) para que la
/// práctica pueda ejecutarse en el laboratorio sin cuentas de Firebase.
/// Las reglas de negocio (dueño por UID, Last-Write-Wins, idempotencia)
/// son las mismas que se aplicarían en un backend real.
class CloudStore {
  CloudStore(this._file);

  final File _file;
  final Map<String, Map<String, dynamic>> users = {};
  final Map<String, String> tokens = {}; // token -> uid
  final Map<String, Map<String, dynamic>> tasks = {}; // id -> task

  /// Contador monotónico del servidor. Se usa como cursor de PULL para
  /// no depender del reloj del dispositivo (evita perder cambios por
  /// relojes desfasados).
  int serverSeq = 0;

  final _rand = Random.secure();

  Future<void> load() async {
    if (!await _file.exists()) {
      await _file.parent.create(recursive: true);
      await save();
      return;
    }
    final raw = jsonDecode(await _file.readAsString()) as Map<String, dynamic>;
    users.addAll((raw['users'] as Map? ?? {}).map(
        (k, v) => MapEntry(k as String, Map<String, dynamic>.from(v as Map))));
    tokens.addAll((raw['tokens'] as Map? ?? {})
        .map((k, v) => MapEntry(k as String, v as String)));
    tasks.addAll((raw['tasks'] as Map? ?? {}).map(
        (k, v) => MapEntry(k as String, Map<String, dynamic>.from(v as Map))));
    serverSeq = (raw['serverSeq'] as num?)?.toInt() ?? 0;
  }

  Future<void> save() async {
    final tmp = File('${_file.path}.tmp');
    await tmp.writeAsString(const JsonEncoder.withIndent('  ').convert({
      'users': users,
      'tokens': tokens,
      'tasks': tasks,
      'serverSeq': serverSeq,
    }));
    await tmp.rename(_file.path);
  }

  // ---------------------------------------------------------------- Auth --

  String _randomHex(int bytes) =>
      List.generate(bytes, (_) => _rand.nextInt(256).toRadixString(16).padLeft(2, '0'))
          .join();

  String _hash(String password, String salt) =>
      sha256.convert(utf8.encode('$salt:$password')).toString();

  Map<String, dynamic>? findUserByEmail(String email) {
    for (final entry in users.entries) {
      if (entry.value['email'] == email) {
        return {'uid': entry.key, ...entry.value};
      }
    }
    return null;
  }

  Future<Map<String, String>> register(String email, String password) async {
    final uid = 'uid_${_randomHex(8)}';
    final salt = _randomHex(16);
    users[uid] = {
      'email': email,
      'salt': salt,
      'hash': _hash(password, salt),
      'createdAt': DateTime.now().toUtc().toIso8601String(),
    };
    return _issueToken(uid, email);
  }

  Future<Map<String, String>?> login(String email, String password) async {
    final user = findUserByEmail(email);
    if (user == null) return null;
    if (_hash(password, user['salt'] as String) != user['hash']) return null;
    return _issueToken(user['uid'] as String, email);
  }

  Future<Map<String, String>> _issueToken(String uid, String email) async {
    final token = _randomHex(32);
    tokens[token] = uid;
    await save();
    return {'token': token, 'uid': uid, 'email': email};
  }

  String? uidForToken(String token) => tokens[token];

  Future<void> revokeToken(String token) async {
    tokens.remove(token);
    await save();
  }

  // --------------------------------------------------------------- Tasks --

  /// Cambios del usuario posteriores al cursor (incluye borrados lógicos).
  List<Map<String, dynamic>> changesSince(String uid, int cursor) {
    final list = tasks.values
        .where((t) => t['owner_uid'] == uid && (t['server_seq'] as int) > cursor)
        .toList()
      ..sort((a, b) => (a['server_seq'] as int).compareTo(b['server_seq'] as int));
    return list.map(publicTask).toList();
  }

  static Map<String, dynamic> publicTask(Map<String, dynamic> t) => {
        'id': t['id'],
        'title': t['title'],
        'description': t['description'],
        'is_completed': t['is_completed'],
        'is_deleted': t['is_deleted'],
        'updated_at': t['updated_at'],
        'version': t['version'],
        'created_at': t['created_at'],
      };

  /// Aplica un cambio entrante con Last-Write-Wins + control de versión.
  ///
  /// * Idempotente: reenviar el mismo registro (mismo UUID) no duplica.
  /// * Regla de seguridad: un UID no puede modificar registros de otro UID.
  ///
  /// Devuelve `applied`, `conflict` (gana el servidor) o `forbidden`.
  ({String status, Map<String, dynamic>? task}) applyChange(
      String uid, Map<String, dynamic> incoming, {String source = 'device'}) {
    final id = incoming['id'] as String;
    final existing = tasks[id];

    if (existing != null && existing['owner_uid'] != uid) {
      return (status: 'forbidden', task: null);
    }

    if (existing != null) {
      final cmp = compareWrites(
        incomingUpdatedAt: incoming['updated_at'] as String,
        incomingVersion: (incoming['version'] as num?)?.toInt() ?? 1,
        currentUpdatedAt: existing['updated_at'] as String,
        currentVersion: (existing['version'] as num?)?.toInt() ?? 1,
      );
      if (cmp < 0) {
        // El servidor tiene una escritura más reciente: gana el servidor.
        return (status: 'conflict', task: publicTask(existing));
      }
      if (cmp == 0) {
        // Reintento idempotente del mismo cambio: no se vuelve a escribir.
        return (status: 'applied', task: publicTask(existing));
      }
    }

    final record = <String, dynamic>{
      'id': id,
      'title': incoming['title'],
      'description': incoming['description'] ?? '',
      'is_completed': incoming['is_completed'] ?? 0,
      'is_deleted': incoming['is_deleted'] ?? 0,
      'updated_at': incoming['updated_at'],
      'version': (incoming['version'] as num?)?.toInt() ?? 1,
      'created_at': existing?['created_at'] ?? incoming['created_at'] ?? incoming['updated_at'],
      'owner_uid': uid,
      'server_seq': ++serverSeq,
      'last_source': source,
      'received_at': DateTime.now().toUtc().toIso8601String(),
    };
    tasks[id] = record;
    return (status: 'applied', task: publicTask(record));
  }

  /// > 0 si la escritura entrante es más nueva, < 0 si es más vieja,
  /// 0 si es exactamente la misma escritura.
  static int compareWrites({
    required String incomingUpdatedAt,
    required int incomingVersion,
    required String currentUpdatedAt,
    required int currentVersion,
  }) {
    final a = DateTime.parse(incomingUpdatedAt).toUtc();
    final b = DateTime.parse(currentUpdatedAt).toUtc();
    final byTime = a.compareTo(b);
    if (byTime != 0) return byTime;
    return incomingVersion.compareTo(currentVersion);
  }
}
