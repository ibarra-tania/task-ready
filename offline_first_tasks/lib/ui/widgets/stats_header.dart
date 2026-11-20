import 'package:flutter/material.dart';

import '../../core/app_services.dart';
import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../data/local/task_dao.dart';
import '../../sync/connectivity_monitor.dart';
import '../../sync/sync_engine.dart';

/// Tarjeta resumen: registros totales, pendientes y estado de la última
/// sincronización.
class StatsHeader extends StatelessWidget {
  const StatsHeader({super.key, required this.onTapSync});

  final VoidCallback onTapSync;

  @override
  Widget build(BuildContext context) {
    final s = AppServices.instance;
    return StreamBuilder<TaskStats>(
      stream: s.db.tasks.watchStats(),
      builder: (context, snap) {
        final stats = snap.data ?? const TaskStats(total: 0, pending: 0, completed: 0);
        return Container(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: const LinearGradient(
              colors: [AppColors.navy, Color(0xFF13294B)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text(
                    'SINGLE SOURCE OF TRUTH · SQLITE',
                    style: TextStyle(
                      color: AppColors.teal,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.1,
                    ),
                  ),
                  const Spacer(),
                  ValueListenableBuilder<ConnectivityStatus>(
                    valueListenable: s.connectivity,
                    builder: (_, c, _) => _StatusDot(online: c.isOnline, label: c.label),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  _Metric(value: stats.total, label: 'Tareas'),
                  _Metric(value: stats.completed, label: 'Completadas'),
                  _Metric(
                    value: stats.pending,
                    label: 'Pendientes sync',
                    color: stats.pending > 0 ? AppColors.amber : AppColors.teal,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              InkWell(
                onTap: onTapSync,
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: ValueListenableBuilder<SyncPhase>(
                    valueListenable: s.engine.phase,
                    builder: (context, phase, _) => StreamBuilder<DateTime?>(
                      stream: _lastSyncStream(),
                      builder: (context, last) {
                        final running = phase != SyncPhase.idle;
                        return Row(
                          children: [
                            Icon(
                              running ? Icons.sync_rounded : Icons.history_rounded,
                              color: Colors.white70,
                              size: 16,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                running
                                    ? 'Sincronizando · ${_phaseLabel(phase)}'
                                    : 'Última sincronización: ${Fmt.relative(last.data)}',
                                style: const TextStyle(color: Colors.white70, fontSize: 12.5),
                              ),
                            ),
                            const Icon(Icons.chevron_right_rounded, color: Colors.white54, size: 18),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Stream<DateTime?> _lastSyncStream() async* {
    final db = AppServices.instance.db;
    yield await db.meta.getLastSyncAt();
    await for (final t in db.changes) {
      if (t == 'sync_meta') yield await db.meta.getLastSyncAt();
    }
  }

  static String _phaseLabel(SyncPhase p) => switch (p) {
        SyncPhase.push => '01 PUSH',
        SyncPhase.ack => '02 ACK',
        SyncPhase.pull => '03 PULL',
        SyncPhase.merge => '04 MERGE',
        SyncPhase.idle => '',
      };
}

class _Metric extends StatelessWidget {
  const _Metric({required this.value, required this.label, this.color = Colors.white});

  final int value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(end: value.toDouble()),
            duration: const Duration(milliseconds: 400),
            builder: (_, v, _) => Text(
              v.round().toString(),
              style: TextStyle(
                color: color,
                fontSize: 30,
                fontWeight: FontWeight.w800,
                height: 1.1,
              ),
            ),
          ),
          Text(label, style: const TextStyle(color: Colors.white60, fontSize: 12)),
        ],
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.online, required this.label});

  final bool online;
  final String label;

  @override
  Widget build(BuildContext context) {
    final color = online ? AppColors.teal : AppColors.amber;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(online ? Icons.wifi_rounded : Icons.wifi_off_rounded, size: 13, color: color),
          const SizedBox(width: 5),
          Text(label,
              style: TextStyle(color: color, fontSize: 11.5, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
