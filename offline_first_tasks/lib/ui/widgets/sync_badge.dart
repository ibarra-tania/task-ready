import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// Indicador del estado de sincronización de un registro.
class SyncBadge extends StatelessWidget {
  const SyncBadge({super.key, required this.synced});

  final bool synced;

  @override
  Widget build(BuildContext context) {
    final color = synced ? AppColors.green : AppColors.amber;
    return Tooltip(
      message: synced
          ? 'is_synced = 1 · Confirmado por el servidor'
          : 'is_synced = 0 · Pendiente de subir',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(synced ? Icons.cloud_done_rounded : Icons.cloud_upload_outlined,
                size: 14, color: color),
            const SizedBox(width: 4),
            Text(
              synced ? 'Sincronizado' : 'Pendiente',
              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: color),
            ),
          ],
        ),
      ),
    );
  }
}
