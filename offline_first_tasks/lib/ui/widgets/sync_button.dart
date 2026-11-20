import 'package:flutter/material.dart';

import '../../core/app_services.dart';
import '../../sync/sync_engine.dart';

/// Botón de sincronización manual con animación mientras corre el ciclo.
class SyncButton extends StatefulWidget {
  const SyncButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  State<SyncButton> createState() => _SyncButtonState();
}

class _SyncButtonState extends State<SyncButton> with SingleTickerProviderStateMixin {
  late final _controller =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900));

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<SyncPhase>(
      valueListenable: AppServices.instance.engine.phase,
      builder: (context, phase, _) {
        final running = phase != SyncPhase.idle;
        if (running && !_controller.isAnimating) {
          _controller.repeat();
        } else if (!running && _controller.isAnimating) {
          _controller.forward(from: _controller.value).then((_) => _controller.reset());
        }
        return IconButton(
          tooltip: 'Sincronizar ahora',
          onPressed: running ? null : widget.onPressed,
          icon: RotationTransition(
            turns: Tween(begin: 0.0, end: -1.0).animate(_controller),
            child: const Icon(Icons.sync_rounded),
          ),
        );
      },
    );
  }
}
