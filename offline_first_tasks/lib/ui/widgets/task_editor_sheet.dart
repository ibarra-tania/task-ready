import 'package:flutter/material.dart';

import '../../core/app_services.dart';
import '../../core/formatters.dart';
import '../../data/models/task.dart';
import '../../sync/connectivity_monitor.dart';

/// Hoja inferior para crear o editar una tarea.
class TaskEditorSheet extends StatefulWidget {
  const TaskEditorSheet({super.key, this.task});

  final Task? task;

  static Future<void> show(BuildContext context, {Task? task}) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (_) => TaskEditorSheet(task: task),
    );
  }

  @override
  State<TaskEditorSheet> createState() => _TaskEditorSheetState();
}

class _TaskEditorSheetState extends State<TaskEditorSheet> {
  final _formKey = GlobalKey<FormState>();
  late final _title = TextEditingController(text: widget.task?.title);
  late final _description = TextEditingController(text: widget.task?.description);
  bool _saving = false;

  bool get _isEdit => widget.task != null;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final repo = AppServices.instance.tasks;
    if (_isEdit) {
      await repo.update(widget.task!, title: _title.text, description: _description.text);
    } else {
      await repo.create(title: _title.text, description: _description.text);
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final task = widget.task;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.viewInsetsOf(context).bottom + 20),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(_isEdit ? 'Editar tarea' : 'Nueva tarea',
                style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            ValueListenableBuilder<ConnectivityStatus>(
              valueListenable: AppServices.instance.connectivity,
              builder: (_, c, _) => Text(
                c.isOnline
                    ? 'Se guarda en SQLite al instante y se sube a la nube en segundo plano.'
                    : 'Estás sin conexión: se guarda en SQLite y se subirá automáticamente al reconectar.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
            const SizedBox(height: 18),
            TextFormField(
              controller: _title,
              autofocus: !_isEdit,
              maxLength: 80,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Título',
                prefixIcon: Icon(Icons.title_rounded),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'El título es obligatorio' : null,
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _description,
              maxLines: 3,
              minLines: 2,
              maxLength: 300,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Descripción (opcional)',
                alignLabelWithHint: true,
                prefixIcon: Icon(Icons.notes_rounded),
              ),
            ),
            if (task != null) ...[
              const SizedBox(height: 4),
              _MetadataPanel(task: task),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: const Icon(Icons.save_rounded),
              label: Text(_isEdit ? 'Guardar cambios' : 'Crear tarea'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Muestra los metadatos de sincronización del registro (útil en la
/// revisión de laboratorio).
class _MetadataPanel extends StatelessWidget {
  const _MetadataPanel({required this.task});

  final Task task;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace');
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Metadatos de sincronización',
              style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text('id          ${task.id}', style: style),
          Text('is_synced   ${task.isSynced ? 1 : 0}', style: style),
          Text('version     ${task.version}', style: style),
          Text('updated_at  ${task.updatedAt.toIso8601String()}', style: style),
          Text('creada      ${Fmt.dateTime(task.createdAt)}', style: style),
        ],
      ),
    );
  }
}
