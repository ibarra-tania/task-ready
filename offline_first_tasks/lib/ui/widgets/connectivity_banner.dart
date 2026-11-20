import 'package:flutter/material.dart';

import '../../core/app_services.dart';
import '../../core/theme.dart';
import '../../sync/connectivity_monitor.dart';

/// Indicador visual del estado offline (Paso 4 de la práctica).
class ConnectivityBanner extends StatelessWidget {
  const ConnectivityBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final services = AppServices.instance;
    return ValueListenableBuilder<ConnectivityStatus>(
      valueListenable: services.connectivity,
      builder: (context, status, _) {
        return AnimatedSize(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
          child: status.isOnline
              ? const SizedBox(width: double.infinity)
              : Material(
                  color: AppColors.amber,
                  child: SafeArea(
                    bottom: false,
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      child: Row(
                        children: [
                          const Icon(Icons.cloud_off_rounded, color: AppColors.navy, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              status.simulatedOffline
                                  ? 'Modo sin conexión simulado · Todo se guarda en SQLite'
                                  : 'Sin conexión · Tus cambios se guardan localmente y se subirán al volver la red',
                              style: const TextStyle(
                                color: AppColors.navy,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          if (status.simulatedOffline)
                            TextButton(
                              style: TextButton.styleFrom(foregroundColor: AppColors.navy),
                              onPressed: () => services.connectivity.setSimulatedOffline(false),
                              child: const Text('Reconectar'),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
        );
      },
    );
  }
}
