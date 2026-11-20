import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/app_services.dart';
import '../../core/theme.dart';
import '../../data/models/task.dart';
import '../../sync/sync_engine.dart';
import '../widgets/connectivity_banner.dart';
import '../widgets/stats_header.dart';
import '../widgets/sync_button.dart';
import '../widgets/task_editor_sheet.dart';
import '../widgets/task_tile.dart';
import 'settings_screen.dart';
import 'sync_center_screen.dart';

enum TaskFilter { all, pending, completed }

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _services = AppServices.instance;
  late final Stream<List<Task>> _tasks = _services.tasks.watchTasks();
  StreamSubscription<SyncReport>? _reportSub;
  TaskFilter _filter = TaskFilter.all;

  @override
  void initState() {
    super.initState();
    // Notifica colisiones resueltas y errores de sesión.
    _reportSub = _services.engine.reports.listen((r) {
      if (!mounted) return;
      if (r.conflicts > 0) {
        _snack(
          '${r.conflicts} colisión(es) resuelta(s) con Last-Write-Wins',
          icon: Icons.merge_type_rounded,
          action: SnackBarAction(label: 'Ver', onPressed: _openSyncCenter),
        );
      } else if (r.unauthorized) {
        _snack('Tu sesión expiró en el servidor. Cierra sesión y vuelve a entrar.',
            icon: Icons.lock_clock_rounded);
      }
    });
  }

  @override
  void dispose() {
    _reportSub?.cancel();
    super.dispose();
  }

  void _snack(String msg, {IconData? icon, SnackBarAction? action}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Row(children: [
          if (icon != null) ...[Icon(icon, color: Colors.white, size: 20), const SizedBox(width: 10)],
          Expanded(child: Text(msg)),
        ]),
        action: action,
      ));
  }

  Future<void> _syncNow() async {
    if (!_services.connectivity.value.isOnline) {
      _snack('Sin conexión: los cambios se subirán al recuperar la red',
          icon: Icons.cloud_off_rounded);
      return;
    }
    final r = await _services.coordinator.syncNow('Manual');
    if (!mounted || r == null) return;
    if (r.ok && r.conflicts == 0) {
      _snack(r.summary, icon: Icons.cloud_done_rounded);
    } else if (!r.ok) {
      _snack('No se pudo sincronizar: ${r.error}', icon: Icons.error_outline_rounded);
    }
  }

  void _openSyncCenter() => Navigator.push(
      context, MaterialPageRoute(builder: (_) => const SyncCenterScreen()));

  void _openSettings() =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()));

  Future<void> _delete(Task task) async {
    final deleted = await _services.tasks.delete(task);
    if (!mounted) return;
    _snack(
      '"${task.title}" eliminada (borrado lógico)',
      icon: Icons.delete_outline_rounded,
      action: SnackBarAction(
        label: 'Deshacer',
        onPressed: () => _services.tasks.restore(deleted),
      ),
    );
  }

  List<Task> _apply(List<Task> tasks) => switch (_filter) {
        TaskFilter.all => tasks,
        TaskFilter.pending => tasks.where((t) => !t.isSynced).toList(),
        TaskFilter.completed => tasks.where((t) => t.isCompleted).toList(),
      };

  @override
  Widget build(BuildContext context) {
    final session = _services.auth.session.value;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Mis tareas'),
            if (session != null)
              Text(
                session.email,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
          ],
        ),
        actions: [
          SyncButton(onPressed: _syncNow),
          IconButton(
            tooltip: 'Centro de sincronización',
            onPressed: _openSyncCenter,
            icon: const Icon(Icons.hub_outlined),
          ),
          IconButton(
            tooltip: 'Ajustes',
            onPressed: _openSettings,
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      body: Column(
        children: [
          const ConnectivityBanner(),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _syncNow,
              child: StreamBuilder<List<Task>>(
                stream: _tasks,
                builder: (context, snap) {
                  final all = snap.data ?? const <Task>[];
                  final visible = _apply(all);
                  return CustomScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                        sliver: SliverToBoxAdapter(
                          child: StatsHeader(onTapSync: _openSyncCenter),
                        ),
                      ),
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                        sliver: SliverToBoxAdapter(child: _filters()),
                      ),
                      if (!snap.hasData)
                        const SliverFillRemaining(
                          child: Center(child: CircularProgressIndicator()),
                        )
                      else if (visible.isEmpty)
                        SliverFillRemaining(
                          hasScrollBody: false,
                          child: _EmptyState(filter: _filter),
                        )
                      else
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                          sliver: SliverList.separated(
                            itemCount: visible.length,
                            separatorBuilder: (_, _) => const SizedBox(height: 10),
                            itemBuilder: (context, i) {
                              final t = visible[i];
                              return TaskTile(
                                task: t,
                                onToggle: () => _services.tasks.toggleCompleted(t),
                                onTap: () => TaskEditorSheet.show(context, task: t),
                                onDelete: () => _delete(t),
                              );
                            },
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => TaskEditorSheet.show(context),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Nueva tarea'),
      ),
    );
  }

  Widget _filters() {
    return SizedBox(
      width: double.infinity,
      child: SegmentedButton<TaskFilter>(
        showSelectedIcon: false,
        segments: const [
          ButtonSegment(value: TaskFilter.all, label: Text('Todas'), icon: Icon(Icons.list_rounded)),
          ButtonSegment(
              value: TaskFilter.pending,
              label: Text('Sin subir'),
              icon: Icon(Icons.cloud_upload_outlined)),
          ButtonSegment(
              value: TaskFilter.completed,
              label: Text('Hechas'),
              icon: Icon(Icons.check_circle_outline_rounded)),
        ],
        selected: {_filter},
        onSelectionChanged: (s) => setState(() => _filter = s.first),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.filter});

  final TaskFilter filter;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (icon, title, subtitle) = switch (filter) {
      TaskFilter.all => (
          Icons.inbox_rounded,
          'Aún no hay tareas',
          'Crea tu primera tarea. Funciona igual con o sin conexión.'
        ),
      TaskFilter.pending => (
          Icons.cloud_done_rounded,
          'Todo está sincronizado',
          'No hay registros con is_synced = 0.'
        ),
      TaskFilter.completed => (
          Icons.task_alt_rounded,
          'Sin tareas completadas',
          'Marca una tarea para verla aquí.'
        ),
    };
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.blue.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 44, color: AppColors.blue),
          ),
          const SizedBox(height: 16),
          Text(title,
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(subtitle,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}
