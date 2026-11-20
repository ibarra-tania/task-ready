import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'dashboard.dart';
import 'store.dart';

Response _json(Object body, {int status = 200}) => Response(
      status,
      body: jsonEncode(body),
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

Future<Map<String, dynamic>> _body(Request req) async {
  final raw = await req.readAsString();
  if (raw.isEmpty) return {};
  return jsonDecode(raw) as Map<String, dynamic>;
}

final _emailRe = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

class CloudApi {
  CloudApi(this.store, {required this.adminKey});

  final CloudStore store;
  final String adminKey;

  /// Simula una caída del backend desde la consola (para probar reintentos).
  bool maintenanceMode = false;

  Handler get handler {
    final router = Router()
      ..get('/', (Request r) => Response.ok(dashboardHtml,
          headers: {'content-type': 'text/html; charset=utf-8'}))
      ..get('/api/health', (Request r) => _json({
            'status': maintenanceMode ? 'maintenance' : 'ok',
            'serverTime': DateTime.now().toUtc().toIso8601String(),
          }, status: maintenanceMode ? 503 : 200))
      ..post('/auth/register', _register)
      ..post('/auth/login', _login)
      ..post('/auth/logout', _withAuth(_logout))
      ..get('/api/tasks', _withAuth(_pull))
      ..post('/api/tasks/sync', _withAuth(_push))
      ..get('/admin/state', _withAdmin(_adminState))
      ..post('/admin/tasks/<id>', _withAdmin(_adminEdit))
      ..post('/admin/users/<uid>/tasks', _withAdmin(_adminCreate))
      ..post('/admin/maintenance', _withAdmin(_adminMaintenance));

    return const Pipeline()
        .addMiddleware(_cors())
        .addMiddleware(_log())
        .addHandler(router.call);
  }

  // -------------------------------------------------------------- Middleware

  Middleware _log() => (inner) => (req) async {
        final res = await inner(req);
        if (!req.url.path.startsWith('admin/state')) {
          final t = DateTime.now().toIso8601String().substring(11, 19);
          print('[$t] ${req.method.padRight(5)} /${req.url} -> ${res.statusCode}');
        }
        return res;
      };

  Middleware _cors() => (inner) => (req) async {
        const headers = {
          'access-control-allow-origin': '*',
          'access-control-allow-headers': 'authorization, content-type, x-admin-key',
          'access-control-allow-methods': 'GET, POST, OPTIONS',
        };
        if (req.method == 'OPTIONS') return Response.ok('', headers: headers);
        final res = await inner(req);
        return res.change(headers: headers);
      };

  /// Regla de seguridad: toda ruta /api exige un token válido y el UID
  /// se toma SIEMPRE del token, nunca del cuerpo de la petición.
  Handler _withAuth(Future<Response> Function(Request, String uid) fn) {
    return (Request req) async {
      if (maintenanceMode) {
        return _json({'error': 'Servidor en mantenimiento'}, status: 503);
      }
      final auth = req.headers['authorization'] ?? '';
      if (!auth.startsWith('Bearer ')) {
        return _json({'error': 'Token requerido'}, status: 401);
      }
      final uid = store.uidForToken(auth.substring(7));
      if (uid == null) return _json({'error': 'Token inválido'}, status: 401);
      return fn(req, uid);
    };
  }

  Handler _withAdmin(Future<Response> Function(Request) fn) {
    return (Request req) async {
      final key = req.headers['x-admin-key'] ?? req.url.queryParameters['key'];
      if (key != adminKey) return _json({'error': 'Clave admin inválida'}, status: 403);
      return fn(req);
    };
  }

  // -------------------------------------------------------------------- Auth

  Future<Response> _register(Request req) async {
    if (maintenanceMode) return _json({'error': 'Servidor en mantenimiento'}, status: 503);
    final b = await _body(req);
    final email = (b['email'] as String? ?? '').trim().toLowerCase();
    final password = b['password'] as String? ?? '';
    if (!_emailRe.hasMatch(email)) {
      return _json({'error': 'Correo inválido'}, status: 400);
    }
    if (password.length < 6) {
      return _json({'error': 'La contraseña debe tener al menos 6 caracteres'}, status: 400);
    }
    if (store.findUserByEmail(email) != null) {
      return _json({'error': 'El correo ya está registrado'}, status: 409);
    }
    return _json(await store.register(email, password), status: 201);
  }

  Future<Response> _login(Request req) async {
    if (maintenanceMode) return _json({'error': 'Servidor en mantenimiento'}, status: 503);
    final b = await _body(req);
    final email = (b['email'] as String? ?? '').trim().toLowerCase();
    final session = await store.login(email, b['password'] as String? ?? '');
    if (session == null) {
      return _json({'error': 'Correo o contraseña incorrectos'}, status: 401);
    }
    return _json(session);
  }

  Future<Response> _logout(Request req, String uid) async {
    await store.revokeToken(req.headers['authorization']!.substring(7));
    return _json({'ok': true});
  }

  // ------------------------------------------------------------------- Sync

  /// PULL: devuelve los cambios posteriores al cursor del cliente.
  Future<Response> _pull(Request req, String uid) async {
    final since = int.tryParse(req.url.queryParameters['since'] ?? '0') ?? 0;
    final changes = store.changesSince(uid, since);
    return _json({'tasks': changes, 'cursor': store.serverSeq});
  }

  /// PUSH: recibe un lote de registros pendientes (is_synced = 0).
  Future<Response> _push(Request req, String uid) async {
    final b = await _body(req);
    final changes = (b['changes'] as List? ?? []).cast<Map<String, dynamic>>();
    final results = <Map<String, dynamic>>[];
    for (final change in changes) {
      if (change['id'] is! String || change['updated_at'] is! String ||
          (change['title'] as String? ?? '').trim().isEmpty) {
        results.add({'id': change['id'], 'status': 'invalid'});
        continue;
      }
      final r = store.applyChange(uid, change);
      results.add({'id': change['id'], 'status': r.status, 'task': r.task});
    }
    await store.save();
    return _json({'results': results, 'cursor': store.serverSeq});
  }

  // ------------------------------------------------------------------ Admin

  Future<Response> _adminState(Request req) async {
    final users = store.users.entries
        .map((e) => {'uid': e.key, 'email': e.value['email']})
        .toList();
    final tasks = store.tasks.values.toList()
      ..sort((a, b) => (b['server_seq'] as int).compareTo(a['server_seq'] as int));
    return _json({
      'users': users,
      'tasks': tasks,
      'serverSeq': store.serverSeq,
      'maintenance': maintenanceMode,
    });
  }

  /// Edita un registro "desde otro dispositivo" para provocar colisiones.
  Future<Response> _adminEdit(Request req) async {
    final id = req.params['id']!;
    final current = store.tasks[id];
    if (current == null) return _json({'error': 'No existe'}, status: 404);
    final b = await _body(req);
    final change = {
      ...CloudStore.publicTask(current),
      ...b,
      'id': id,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
      'version': (current['version'] as int) + 1,
    };
    final r = store.applyChange(current['owner_uid'] as String, change, source: 'console');
    await store.save();
    return _json(r.task ?? {});
  }

  Future<Response> _adminCreate(Request req) async {
    final uid = req.params['uid']!;
    if (!store.users.containsKey(uid)) return _json({'error': 'No existe'}, status: 404);
    final b = await _body(req);
    final now = DateTime.now().toUtc().toIso8601String();
    final id = 'srv-${DateTime.now().microsecondsSinceEpoch}';
    final r = store.applyChange(uid, {
      'id': id,
      'title': b['title'] ?? 'Tarea creada en la nube',
      'description': b['description'] ?? 'Creada desde la consola web',
      'is_completed': 0,
      'is_deleted': 0,
      'updated_at': now,
      'created_at': now,
      'version': 1,
    }, source: 'console');
    await store.save();
    return _json(r.task ?? {}, status: 201);
  }

  Future<Response> _adminMaintenance(Request req) async {
    final b = await _body(req);
    maintenanceMode = b['enabled'] == true;
    return _json({'maintenance': maintenanceMode});
  }
}
