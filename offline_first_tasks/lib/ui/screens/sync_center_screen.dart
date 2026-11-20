import 'package:flutter/material.dart';

import '../../core/app_services.dart';
import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../data/local/task_dao.dart';
import '../../data/models/sync_log_entry.dart';
import '../../core/firebase_setup.dart';
import '../../data/remote/remote_exception.dart';
import '../../sync/background_sync.dart';
import '../../sync/connectivity_monitor.dart';
import '../../sync/sync_engine.dart';

/// Panel técnico: estado de red, pipeline PUSH→ACK→PULL→MERGE, WorkManager
/// y bitácora persistente de sincronización.
class SyncCenterScreen extends StatefulWidget {
  const SyncCenterScreen({super.key});

  @override
  State<SyncCenterScreen> createState() => _SyncCenterScreenState();
}

class _SyncCenterScreenState extends State<SyncCenterScreen> {
  final _s = AppServices.instance;
  late final _logs = _s.db.log.watchRecent();
  late final _stats = _s.db.tasks.watchStats();
  String _serverStatus = 'Sin verificar';
  bool? _serverOk;
  int _remoteCount = 0;

  @override
  void initState() {
    super.initState();
    _refreshMeta();
    _ping();
  }

  Future<void> _refreshMeta() async {
    final c = await _s.db.meta.getRemoteCount();
    if (mounted) setState(() => _remoteCount = c);
  }

  Future<void> _ping() async {
    setState(() => _serverStatus = 'Verificando…');
    try {
      final ms = await _s.auth.ping();
      if (!mounted) return;
      setState(() {
        _serverOk = true;
        _serverStatus = 'En línea · $ms ms';
      });
    } on RemoteException catch (e) {
      if (!mounted) return;
      setState(() {
        _serverOk = false;
        _serverStatus = e.message;
      });
    }
  }

  Future<void> _sync() async {
    final r = await _s.coordinator.syncNow('Manual');
    await _refreshMeta();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(r == null
          ? 'Sin conexión: no es posible sincronizar ahora'
          : r.ok
              ? r.summary
              : 'Error: ${r.error}'),
    ));
    _ping();
  }

  Future<void> _enqueueWorkManager() async {
    await BackgroundSync.enqueueOneOff();
    await _s.db.log.add(LogLevel.info, 'WorkManager',
        'Tarea única "${'bidirectionalSync'}" registrada con NetworkType.connected.');
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Sincronización programada en WorkManager (se ejecuta al haber red, incluso con la app cerrada)'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Centro de sincronización'),
        actions: [
          IconButton(
            tooltip: 'Limpiar bitácora',
            onPressed: () => _s.db.log.clear(),
            icon: const Icon(Icons.delete_sweep_outlined),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _section(theme, 'Estado'),
          Card(
            child: Column(
              children: [
                ValueListenableBuilder<ConnectivityStatus>(
                  valueListenable: _s.connectivity,
                  builder: (_, c, _) => _StatusRow(
                    icon: c.isOnline ? Icons.wifi_rounded : Icons.wifi_off_rounded,
                    color: c.isOnline ? AppColors.green : AppColors.amber,
                    title: 'Red (connectivity_plus)',
                    value: c.label,
                  ),
                ),
                const Divider(height: 1),
                _StatusRow(
                  icon: Icons.dns_rounded,
                  color: _serverOk == null
                      ? Colors.grey
                      : _serverOk!
                          ? AppColors.green
                          : AppColors.red,
                  title: 'Cloud Firestore ($firebaseProjectId)',
                  value: _serverStatus,
                  trailing: TextButton(onPressed: _ping, child: const Text('Probar')),
                ),
                const Divider(height: 1),
                StreamBuilder<TaskStats>(
                  stream: _stats,
                  builder: (_, snap) => _StatusRow(
                    icon: Icons.cloud_upload_outlined,
                    color: (snap.data?.pending ?? 0) > 0 ? AppColors.amber : AppColors.green,
                    title: 'Cola local (is_synced = 0)',
                    value: '${snap.data?.pending ?? 0} registro(s)',
                  ),
                ),
                const Divider(height: 1),
                _StatusRow(
                  icon: Icons.cloud_download_outlined,
                  color: AppColors.blue,
                  title: 'Documentos en Firestore (último PULL)',
                  value: '$_remoteCount',
                ),
              ],
            ),
          ),
          _section(theme, 'Ciclo bidireccional'),
          ValueListenableBuilder<SyncPhase>(
            valueListenable: _s.engine.phase,
            builder: (_, phase, _) {
              final r = _s.engine.lastReport;
              return Column(
                children: [
                  Row(children: [
                    _PhaseCard(n: '01', title: 'PUSH', detail: 'Envía is_synced = 0',
                        value: r?.pushed, active: phase == SyncPhase.push, color: AppColors.blue),
                    const SizedBox(width: 10),
                    _PhaseCard(n: '02', title: 'ACK', detail: 'Marca is_synced = 1',
                        value: r?.acked, active: phase == SyncPhase.ack, color: AppColors.teal),
                  ]),
                  const SizedBox(height: 10),
                  Row(children: [
                    _PhaseCard(n: '03', title: 'PULL', detail: 'Descarga remotos',
                        value: r?.pulled, active: phase == SyncPhase.pull, color: AppColors.blue),
                    const SizedBox(width: 10),
                    _PhaseCard(n: '04', title: 'MERGE', detail: 'LWW por updated_at',
                        value: r?.conflicts, valueLabel: 'colisiones',
                        active: phase == SyncPhase.merge, color: AppColors.teal),
                  ]),
                  if (r != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(
                        'Último ciclo (${r.source}) · ${Fmt.time(r.startedAt)} · '
                        '${r.finishedAt!.difference(r.startedAt).inMilliseconds} ms · '
                        '${r.ok ? 'OK' : 'Error: ${r.error}'}',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          ValueListenableBuilder<SyncPhase>(
            valueListenable: _s.engine.phase,
            builder: (_, phase, _) => FilledButton.icon(
              onPressed: phase == SyncPhase.idle ? _sync : null,
              icon: const Icon(Icons.sync_rounded),
              label: Text(phase == SyncPhase.idle ? 'Sincronizar ahora' : 'Sincronizando…'),
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: _enqueueWorkManager,
            icon: const Icon(Icons.schedule_send_rounded),
            label: const Text('Programar en WorkManager'),
          ),
          _section(theme, 'Bitácora'),
          StreamBuilder<List<SyncLogEntry>>(
            stream: _logs,
            builder: (context, snap) {
              final logs = snap.data ?? const [];
              if (logs.isEmpty) {
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text('Sin eventos todavía.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
                  ),
                );
              }
              return Card(
                child: Column(
                  children: [
                    for (var i = 0; i < logs.length; i++) ...[
                      if (i > 0) const Divider(height: 1, indent: 52),
                      _LogTile(entry: logs[i]),
                    ],
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _section(ThemeData theme, String title) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 22, 4, 10),
        child: Text(
          title.toUpperCase(),
          style: theme.textTheme.labelMedium?.copyWith(
            color: AppColors.blue,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
          ),
        ),
      );
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.icon,
    required this.color,
    required this.title,
    required this.value,
    this.trailing,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String value;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: CircleAvatar(
        radius: 18,
        backgroundColor: color.withValues(alpha: 0.12),
        child: Icon(icon, color: color, size: 19),
      ),
      title: Text(title, style: const TextStyle(fontSize: 13)),
      subtitle: Text(value,
          style: TextStyle(fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.onSurface)),
      trailing: trailing,
    );
  }
}

class _PhaseCard extends StatelessWidget {
  const _PhaseCard({
    required this.n,
    required this.title,
    required this.detail,
    required this.value,
    required this.active,
    required this.color,
    this.valueLabel = 'registros',
  });

  final String n;
  final String title;
  final String detail;
  final int? value;
  final String valueLabel;
  final bool active;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: active ? color.withValues(alpha: 0.12) : theme.cardTheme.color,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: active ? color : theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
            width: active ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('$n. $title',
                    style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 15)),
                const Spacer(),
                if (active)
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2, color: color),
                  ),
              ],
            ),
            const SizedBox(height: 2),
            Text(detail,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 8),
            Text(
              value == null ? '—' : '$value $valueLabel',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}

class _LogTile extends StatelessWidget {
  const _LogTile({required this.entry});

  final SyncLogEntry entry;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (entry.level) {
      LogLevel.success => (Icons.check_circle_rounded, AppColors.green),
      LogLevel.warning => (Icons.warning_amber_rounded, AppColors.amber),
      LogLevel.error => (Icons.error_rounded, AppColors.red),
      LogLevel.info => (Icons.info_outline_rounded, AppColors.blue),
    };
    final theme = Theme.of(context);
    return ListTile(
      dense: true,
      leading: Icon(icon, color: color),
      title: Text(entry.message, style: const TextStyle(fontSize: 13)),
      subtitle: Text('${Fmt.time(entry.createdAt)} · ${entry.source}',
          style: TextStyle(fontSize: 11.5, color: theme.colorScheme.onSurfaceVariant)),
    );
  }
}
