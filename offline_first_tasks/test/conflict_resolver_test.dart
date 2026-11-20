import 'package:flutter_test/flutter_test.dart';
import 'package:offline_first_tasks/data/models/task.dart';
import 'package:offline_first_tasks/sync/conflict_resolver.dart';

Task _task({
  String id = 'a',
  String title = 'T',
  required String at,
  int version = 1,
  bool synced = true,
}) =>
    Task(
      id: id,
      title: title,
      updatedAt: DateTime.parse(at),
      createdAt: DateTime.parse('2026-11-01T00:00:00Z'),
      version: version,
      isSynced: synced,
    );

void main() {
  group('ConflictResolver (Last-Write-Wins + versión)', () {
    test('inserta si no existe localmente', () {
      final d = ConflictResolver.resolve(
          local: null, remote: _task(at: '2026-11-20T10:00:00Z'));
      expect(d.action, MergeAction.insert);
      expect(d.isConflict, isFalse);
    });

    test('local sincronizado + remoto más nuevo → sobrescribe sin colisión', () {
      final d = ConflictResolver.resolve(
        local: _task(at: '2026-11-20T10:00:00Z'),
        remote: _task(at: '2026-11-20T11:00:00Z', version: 2),
      );
      expect(d.action, MergeAction.overwrite);
      expect(d.isConflict, isFalse);
    });

    test('misma revisión → se omite', () {
      final d = ConflictResolver.resolve(
        local: _task(at: '2026-11-20T10:00:00Z'),
        remote: _task(at: '2026-11-20T10:00:00Z'),
      );
      expect(d.action, MergeAction.skip);
    });

    test('local pendiente + remoto más nuevo → gana el remoto (colisión)', () {
      final d = ConflictResolver.resolve(
        local: _task(title: 'offline', at: '2026-11-20T10:00:00Z', version: 2, synced: false),
        remote: _task(title: 'nube', at: '2026-11-20T10:05:00Z', version: 2),
      );
      expect(d.action, MergeAction.overwrite);
      expect(d.isConflict, isTrue);
    });

    test('local pendiente más nuevo → se conserva local (colisión)', () {
      final d = ConflictResolver.resolve(
        local: _task(title: 'offline', at: '2026-11-20T10:10:00Z', version: 2, synced: false),
        remote: _task(title: 'nube', at: '2026-11-20T10:05:00Z', version: 2),
      );
      expect(d.action, MergeAction.keepLocal);
      expect(d.isConflict, isTrue);
    });

    test('mismo updated_at → desempata por versión', () {
      final local = _task(at: '2026-11-20T10:00:00Z', version: 3, synced: false);
      final remote = _task(at: '2026-11-20T10:00:00Z', version: 4);
      expect(ConflictResolver.compare(remote, local), greaterThan(0));
      expect(ConflictResolver.resolve(local: local, remote: remote).action,
          MergeAction.overwrite);
    });

    test('compara en UTC aunque las zonas horarias difieran', () {
      final a = _task(at: '2026-11-20T10:00:00-06:00'); // 16:00 UTC
      final b = _task(at: '2026-11-20T15:00:00Z');
      expect(ConflictResolver.compare(a, b), greaterThan(0));
    });
  });

  group('Task', () {
    test('touch() incrementa versión y marca como pendiente', () {
      final t = _task(at: '2026-11-20T10:00:00Z', version: 1, synced: true);
      final edited = t.touch(title: 'nuevo');
      expect(edited.version, 2);
      expect(edited.isSynced, isFalse);
      expect(edited.updatedAt.isAfter(t.updatedAt), isTrue);
      expect(edited.title, 'nuevo');
    });

    test('serializa/deserializa con Firestore', () {
      final t = _task(at: '2026-11-20T10:00:00Z', version: 3, synced: false);
      final back = Task.fromFirestore(t.id, Map<String, dynamic>.from(t.toFirestore()));
      expect(back.sameContentAs(t), isTrue);
      expect(back.isSynced, isTrue, reason: 'lo que viene de la nube ya está sincronizado');
      expect(t.toFirestore()['is_completed'], isA<bool>());
    });

    test('serializa/deserializa con el esquema SQLite', () {
      final t = _task(at: '2026-11-20T10:00:00Z', synced: false);
      final back = Task.fromMap(t.toMap());
      expect(back.sameContentAs(t), isTrue);
      expect(back.isSynced, isFalse);
      expect(t.toMap()['is_synced'], 0);
    });
  });
}
