import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:offline_first_tasks/data/local/app_database.dart';
import 'package:offline_first_tasks/data/models/task.dart';
import 'package:offline_first_tasks/data/remote/api_client.dart';
import 'package:offline_first_tasks/data/repositories/task_repository.dart';
import 'package:offline_first_tasks/sync/sync_engine.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Backend falso en memoria con las mismas reglas que cloud_server
/// (LWW + versión, idempotencia por UUID, cursor server_seq).
class FakeCloud {
  final Map<String, Map<String, dynamic>> tasks = {};
  int seq = 0;
  bool down = false;
  Future<void> Function()? duringPush;

  int _cmp(Map a, Map b) {
    final t = DateTime.parse(a['updated_at']).compareTo(DateTime.parse(b['updated_at']));
    return t != 0 ? t : (a['version'] as int).compareTo(b['version'] as int);
  }

  void serverEdit(String id, Map<String, dynamic> fields, {Duration ahead = Duration.zero}) {
    final cur = tasks[id]!;
    tasks[id] = {
      ...cur,
      ...fields,
      'updated_at': DateTime.now().toUtc().add(ahead).toIso8601String(),
      'version': (cur['version'] as int) + 1,
      'seq': ++seq,
    };
  }

  /// JSON en UTF-8, igual que el backend real.
  static http.Response _json(Object body, [int status = 200]) => http.Response.bytes(
        utf8.encode(jsonEncode(body)),
        status,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );

  late final client = MockClient((req) async {
    if (down) throw http.ClientException('offline');
    if (req.method == 'POST' && req.url.path == '/api/tasks/sync') {
      await duringPush?.call();
      final changes = (jsonDecode(req.body)['changes'] as List).cast<Map<String, dynamic>>();
      final results = [];
      for (final c in changes) {
        final cur = tasks[c['id']];
        if (cur != null && _cmp(c, cur) < 0) {
          results.add({'id': c['id'], 'status': 'conflict', 'task': cur});
        } else if (cur != null && _cmp(c, cur) == 0) {
          results.add({'id': c['id'], 'status': 'applied', 'task': cur});
        } else {
          tasks[c['id']] = {...c, 'seq': ++seq};
          results.add({'id': c['id'], 'status': 'applied', 'task': c});
        }
      }
      return _json({'results': results, 'cursor': seq});
    }
    if (req.method == 'GET' && req.url.path == '/api/tasks') {
      final since = int.parse(req.url.queryParameters['since'] ?? '0');
      final list = tasks.values.where((t) => (t['seq'] as int) > since).toList();
      return _json({'tasks': list, 'cursor': seq});
    }
    return _json({'error': 'not found'}, 404);
  });
}

void main() {
  sqfliteFfiInit();

  late AppDatabase db;
  late FakeCloud cloud;
  late SyncEngine engine;
  late TaskRepository repo;

  late Directory tmp;

  setUp(() async {
    // Un archivo SQLite real y aislado por prueba.
    tmp = Directory.systemTemp.createTempSync('offline_first_test');
    db = await AppDatabase.open(
      path: p.join(tmp.path, 'test.db'),
      factory: databaseFactoryFfiNoIsolate,
    );
    cloud = FakeCloud();
    engine = SyncEngine(
      db: db,
      clientFactory: () async =>
          ApiClient(baseUrl: 'http://cloud.test', token: 't', client: cloud.client),
    );
    repo = TaskRepository(db, onLocalChange: (_) {});
  });

  tearDown(() async {
    await db.close();
    tmp.deleteSync(recursive: true);
  });

  test('Escenario 1: 3 registros offline quedan pendientes y se suben al reconectar', () async {
    cloud.down = true; // modo avión
    final a = await repo.create(title: 'Tarea A');
    await repo.create(title: 'Tarea B');
    await repo.create(title: 'Tarea C');
    await repo.update(a, title: 'Tarea A editada');

    expect((await db.tasks.stats()).pending, 3);

    final failed = await engine.sync(source: 'test');
    expect(failed.ok, isFalse);
    expect(failed.networkError, isTrue);
    expect((await db.tasks.stats()).pending, 3, reason: 'nada se pierde si falla la red');

    cloud.down = false; // reconexión
    final r = await engine.sync(source: 'test');
    expect(r.ok, isTrue);
    expect(r.pushed, 3);
    expect(r.acked, 3);
    expect((await db.tasks.stats()).pending, 0);
    expect(cloud.tasks.length, 3);
    expect(cloud.tasks[a.id]!['title'], 'Tarea A editada');
    expect(cloud.tasks[a.id]!['version'], 2);
  });

  test('PULL trae registros creados en la nube', () async {
    final now = DateTime.now().toUtc().toIso8601String();
    cloud.tasks['srv-1'] = {
      'id': 'srv-1', 'title': 'Desde la nube', 'description': '', 'is_completed': 0,
      'is_deleted': 0, 'updated_at': now, 'created_at': now, 'version': 1, 'seq': ++cloud.seq,
    };
    final r = await engine.sync(source: 'test');
    expect(r.ok, isTrue, reason: r.error);
    expect(r.pulled, 1);
    final local = await db.tasks.getById('srv-1');
    expect(local?.title, 'Desde la nube');
    expect(local?.isSynced, isTrue);
  });

  test('Colisión: la edición más reciente en la nube gana (LWW)', () async {
    final t = await repo.create(title: 'Original');
    await engine.sync(source: 'test');

    // Edición offline en el dispositivo…
    await repo.update(t, title: 'Edición offline');
    // …y edición posterior desde otro dispositivo.
    cloud.serverEdit(t.id, {'title': 'Edición en la nube'}, ahead: const Duration(seconds: 5));

    final r = await engine.sync(source: 'test');
    expect(r.ok, isTrue, reason: r.error);
    expect(r.conflicts, greaterThanOrEqualTo(1));
    final local = await db.tasks.getById(t.id);
    expect(local!.title, 'Edición en la nube');
    expect(local.isSynced, isTrue);
  });

  test('Colisión: la edición offline más reciente gana y se sube', () async {
    final t = await repo.create(title: 'Original');
    await engine.sync(source: 'test');

    cloud.serverEdit(t.id, {'title': 'Edición en la nube'}, ahead: const Duration(seconds: -5));
    await repo.update(t, title: 'Edición offline más reciente');

    await engine.sync(source: 'test');
    expect(cloud.tasks[t.id]!['title'], 'Edición offline más reciente');
    expect((await db.tasks.getById(t.id))!.title, 'Edición offline más reciente');
  });

  test('Borrado lógico se propaga a la nube', () async {
    final t = await repo.create(title: 'Por borrar');
    await engine.sync(source: 'test');
    await repo.delete(t);
    expect(await db.tasks.getActive(), isEmpty);

    await engine.sync(source: 'test');
    expect(cloud.tasks[t.id]!['is_deleted'], 1);
    expect((await db.tasks.stats()).pending, 0);
  });

  test('ACK condicional: una edición durante el PUSH no se marca como sincronizada', () async {
    final t = await repo.create(title: 'v1');
    late Task edited;
    cloud.duringPush = () async {
      cloud.duringPush = null;
      edited = await repo.update(t, title: 'v2 (editada mientras subía)');
    };

    await engine.sync(source: 'test');
    final local = await db.tasks.getById(t.id);
    expect(local!.title, edited.title);
    expect(local.isSynced, isFalse, reason: 'la v2 sigue pendiente');

    await engine.sync(source: 'test');
    expect(cloud.tasks[t.id]!['title'], 'v2 (editada mientras subía)');
    expect((await db.tasks.getById(t.id))!.isSynced, isTrue);
  });

  test('Idempotencia: reenviar el mismo registro no lo duplica', () async {
    await repo.create(title: 'Única');
    await engine.sync(source: 'test');
    // Simula que el ACK se perdió: se vuelve a marcar como pendiente.
    await db.db.update('tasks', {'is_synced': 0});
    await engine.sync(source: 'test');
    expect(cloud.tasks.length, 1);
    expect((await db.tasks.stats()).pending, 0);
  });

  test('Limpieza de sesión purga SQLite', () async {
    await repo.create(title: 'Dato sensible');
    await db.purgeUserData();
    expect(await db.tasks.getActive(), isEmpty);
    expect(await db.meta.getPullCursor(), 0);
  });
}
