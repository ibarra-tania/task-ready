import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

import '../data/local/meta_dao.dart';

class ConnectivityStatus {
  const ConnectivityStatus({
    this.types = const [ConnectivityResult.wifi],
    this.simulatedOffline = false,
  });

  final List<ConnectivityResult> types;

  /// Modo laboratorio: fuerza el estado sin conexión sin activar modo avión.
  final bool simulatedOffline;

  bool get hasNetwork =>
      types.isNotEmpty && !types.every((t) => t == ConnectivityResult.none);

  bool get isOnline => hasNetwork && !simulatedOffline;

  String get label {
    if (simulatedOffline) return 'Sin conexión (simulado)';
    if (!hasNetwork) return 'Sin conexión';
    if (types.contains(ConnectivityResult.wifi)) return 'Wi-Fi';
    if (types.contains(ConnectivityResult.mobile)) return 'Datos móviles';
    if (types.contains(ConnectivityResult.ethernet)) return 'Ethernet';
    if (types.contains(ConnectivityResult.vpn)) return 'VPN';
    return 'En línea';
  }

  ConnectivityStatus copyWith({List<ConnectivityResult>? types, bool? simulatedOffline}) =>
      ConnectivityStatus(
        types: types ?? this.types,
        simulatedOffline: simulatedOffline ?? this.simulatedOffline,
      );
}

/// Paso 4 de la práctica: escucha reactiva con connectivity_plus.
class ConnectivityMonitor extends ValueNotifier<ConnectivityStatus> {
  ConnectivityMonitor(this._meta, [Connectivity? connectivity])
      : _connectivity = connectivity ?? Connectivity(),
        super(const ConnectivityStatus());

  final MetaDao _meta;
  final Connectivity _connectivity;
  StreamSubscription<List<ConnectivityResult>>? _sub;

  Future<void> start() async {
    final simulated = await _meta.isSimulatedOffline();
    final types = await _connectivity.checkConnectivity();
    value = ConnectivityStatus(types: types, simulatedOffline: simulated);
    // Stream continuo: monitorea Wi-Fi y datos móviles.
    _sub = _connectivity.onConnectivityChanged.listen((types) {
      value = value.copyWith(types: types);
    });
  }

  Future<void> setSimulatedOffline(bool enabled) async {
    await _meta.set(MetaDao.simulatedOffline, enabled ? '1' : '0');
    value = value.copyWith(simulatedOffline: enabled);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
