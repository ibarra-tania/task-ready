import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/local/app_database.dart';
import '../data/local/meta_dao.dart';
import '../data/models/sync_log_entry.dart';
import '../data/models/task.dart';
import '../data/remote/remote_exception.dart';
import '../data/remote/task_remote_data_source.dart';
import 'conflict_resolver.dart';

enum SyncPhase { idle, push, ack, pull, merge }

/// Resultado de un ciclo de sincronización.
class SyncReport {
  SyncReport({required this.source}) : startedAt = DateTime.now();

  final String source;
  final DateTime startedAt;
  DateTime? finishedAt;

  int pushed = 0;
  int acked = 0;
  int pulled = 0;
  int applied = 0;
  int conflicts = 0;

  String? error;
  bool unauthorized = false;
  bool networkError = false;

  bool get ok => error == null;

  String get summary => ok
      ? 'Subidos $acked/$pushed · Descargados $pulled (aplicados $applied)'
          '${conflicts > 0 ? ' · $conflicts colisión(es) resuelta(s)' : ''}'
      : error!;
}

typedef RemoteFactory = Future<TaskRemoteDataSource?> Function();

/// Paso 6 de la práctica: ciclo bidireccional PUSH → ACK → PULL → MERGE.
///
/// Se usa tanto en primer plano (UI) como en el isolate de WorkManager.
class SyncEngine {
  SyncEngine({required this.db, required this.remoteFactory});

  final AppDatabase db;
  final RemoteFactory remoteFactory;

  final ValueNotifier<SyncPhase> phase = ValueNotifier(SyncPhase.idle);
  final _reports = StreamController<SyncReport>.broadcast();
  Stream<SyncReport> get reports => _reports.stream;
  SyncReport? lastReport;

  Future<SyncReport>? _running;

  bool get isRunning => _running != null;

  /// Si ya hay un ciclo en curso se reutiliza (evita subidas duplicadas).
  Future<SyncReport> sync({required String source}) {
    return _running ??= _run(source).whenComplete(() => _running = null);
  }

  Future<void> _log(LogLevel level, String source, String msg) =>
      db.log.add(level, source, msg);

  Future<SyncReport> _run(String source) async {
    final report = SyncReport(source: source);
    final remote = await remoteFactory();
    if (remote == null) {
      report.error = 'No hay sesión activa';
      return _finish(report);
    }

    try {
      await _pushAndAck(remote, report);
      await _pullAndMerge(remote, report);
      await db.meta.set(MetaDao.lastSyncAt, DateTime.now().toUtc().toIso8601String());
      await _log(
        report.conflicts > 0 ? LogLevel.warning : LogLevel.success,
        source,
        'Sincronización completa · ${report.summary}',
      );
    } on RemoteException catch (e) {
      report
        ..error = e.message
        ..unauthorized = e.isUnauthorized
        ..networkError = e.isNetworkError;
      await _log(LogLevel.error, source,
          'Sincronización fallida: $e. Los cambios siguen a salvo en SQLite.');
    } catch (e) {
      report.error = 'Error inesperado: $e';
      await _log(LogLevel.error, source, report.error!);
    }
    return _finish(report);
  }

  SyncReport _finish(SyncReport report) {
    report.finishedAt = DateTime.now();
    phase.value = SyncPhase.idle;
    lastReport = report;
    if (!_reports.isClosed) _reports.add(report);
    return report;
  }

  // ------------------------------------------------------ 01 PUSH · 02 ACK

  Future<void> _pushAndAck(TaskRemoteDataSource remote, SyncReport report) async {
    phase.value = SyncPhase.push;
    final pending = await db.tasks.getPending();
    if (pending.isEmpty) return;

    final results = await remote.push(pending);
    report.pushed = pending.length;

    phase.value = SyncPhase.ack;
    final byId = {for (final t in pending) t.id: t};

    for (final r in results) {
      final local = byId[r.id];
      if (local == null) continue;
      switch (r.status) {
        case PushStatus.applied:
          if (await db.tasks.markSynced(local)) report.acked++;
        case PushStatus.conflict:
          // La nube tiene una escritura más reciente (LWW): gana la nube.
          final server = r.serverTask!;
          final current = await db.tasks.getById(local.id);
          if (current != null && current.sameContentAs(local)) {
            await db.tasks.upsertFromRemote(server);
          }
          report.conflicts++;
          await _log(
            LogLevel.warning,
            report.source,
            'Colisión en "${local.title}" (local v${local.version}) vs nube '
            '"${server.title}" (v${server.version}). La nube es más reciente → '
            'gana Last-Write-Wins.',
          );
      }
    }
    db.tasks.notifyChanged();
    await _log(LogLevel.info, report.source,
        'PUSH: ${report.pushed} registro(s) con is_synced = 0 → ACK: ${report.acked} marcado(s) is_synced = 1');
  }

  // ---------------------------------------------------- 03 PULL · 04 MERGE

  Future<void> _pullAndMerge(TaskRemoteDataSource remote, SyncReport report) async {
    phase.value = SyncPhase.pull;
    final remoteTasks = await remote.fetchAll();
    report.pulled = remoteTasks.length;

    phase.value = SyncPhase.merge;
    final conflictMessages = <String>[];
    await db.db.transaction((txn) async {
      for (final r in remoteTasks) {
        final rows = await txn.query('tasks', where: 'id = ?', whereArgs: [r.id], limit: 1);
        final local = rows.isEmpty ? null : Task.fromMap(rows.first);
        final decision = ConflictResolver.resolve(local: local, remote: r);

        if (decision.isConflict) {
          report.conflicts++;
          conflictMessages.add(decision.action == MergeAction.overwrite
              ? 'Colisión en "${local!.title}": la nube (v${r.version}) es más reciente que tu edición offline (v${local.version}) → gana la nube.'
              : 'Colisión en "${local!.title}": tu edición offline (v${local.version}) es más reciente que la nube (v${r.version}) → gana local y se subirá.');
        }
        switch (decision.action) {
          case MergeAction.insert:
          case MergeAction.overwrite:
            await db.tasks.upsertFromRemote(r, executor: txn);
            if (!(local?.sameContentAs(r) ?? false)) report.applied++;
          case MergeAction.keepLocal:
          case MergeAction.skip:
            break;
        }
      }
    });
    await db.meta.set(MetaDao.remoteCount, '${remoteTasks.length}');
    db.tasks.notifyChanged();

    for (final m in conflictMessages) {
      await _log(LogLevel.warning, report.source, m);
    }
    await _log(LogLevel.info, report.source,
        'PULL: ${report.pulled} documento(s) en Firestore → MERGE: ${report.applied} cambio(s) aplicado(s)');
  }

  void dispose() {
    _reports.close();
    phase.dispose();
  }
}
