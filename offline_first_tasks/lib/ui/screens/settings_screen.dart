import 'package:flutter/material.dart';

import '../../core/app_services.dart';
import '../../core/theme.dart';
import '../../core/firebase_setup.dart';
import '../../data/remote/remote_exception.dart';
import '../../sync/connectivity_monitor.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _s = AppServices.instance;
  bool _testing = false;

  void _snack(String msg) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _testFirestore() async {
    setState(() => _testing = true);
    try {
      final ms = await _s.auth.ping();
      _snack('Firestore responde en $ms ms');
    } on RemoteException catch (e) {
      _snack('Sin respuesta: ${e.message}');
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _logout() async {
    final pending = (await _s.db.tasks.stats()).pending;
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.cleaning_services_rounded),
        title: const Text('Cerrar sesión'),
        content: Text(
          'Se purgará la base SQLite de este dispositivo y se borrará el token cifrado.'
          '${pending > 0 ? '\n\n⚠️ Tienes $pending cambio(s) sin sincronizar que se perderán.' : ''}',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.red,
              minimumSize: const Size(0, 44),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Cerrar sesión'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    _s.coordinator.enabled = false;
    await _s.auth.signOut();
    if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final session = _s.auth.session.value;

    return Scaffold(
      appBar: AppBar(title: const Text('Ajustes')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _Section('Cuenta y seguridad'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.person_outline_rounded),
                  title: Text(session?.email ?? '—'),
                  subtitle: Text('UID: ${session?.uid ?? '—'}'),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.lock_outline_rounded, color: AppColors.green),
                  title: const Text('ID token de Firebase cifrado en reposo'),
                  subtitle: Text(
                      '${session?.maskedToken ?? '—'}\nflutter_secure_storage · Android Keystore'),
                  isThreeLine: true,
                ),
                const Divider(height: 1),
                const ListTile(
                  leading: Icon(Icons.verified_user_outlined, color: AppColors.blue),
                  title: Text('Idempotencia y reglas de backend'),
                  subtitle: Text(
                      'IDs UUID v4 generados en el cliente (documento = UUID). Las reglas de '
                      'Firestore solo permiten leer/escribir users/{uid} a ese mismo usuario.'),
                ),
              ],
            ),
          ),
          _Section('Modo laboratorio'),
          Card(
            child: ValueListenableBuilder<ConnectivityStatus>(
              valueListenable: _s.connectivity,
              builder: (_, c, _) => SwitchListTile(
                secondary: Icon(
                  c.simulatedOffline ? Icons.airplanemode_active_rounded : Icons.airplanemode_inactive_rounded,
                  color: c.simulatedOffline ? AppColors.amber : null,
                ),
                title: const Text('Simular sin conexión'),
                subtitle: const Text(
                    'Equivale a modo avión para la app: nada se envía a la red y todo se guarda en SQLite.'),
                value: c.simulatedOffline,
                onChanged: _s.connectivity.setSimulatedOffline,
              ),
            ),
          ),
          _Section('Backend en la nube'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.local_fire_department_rounded, color: AppColors.amber),
                  title: const Text('Cloud Firestore'),
                  subtitle: Text(
                      'Proyecto: $firebaseProjectId\nRuta: users/${session?.uid ?? '{uid}'}/tasks'),
                  isThreeLine: true,
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46)),
                    onPressed: _testing ? null : _testFirestore,
                    icon: _testing
                        ? const SizedBox(
                            width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.network_check_rounded),
                    label: const Text('Probar conexión con Firestore'),
                  ),
                ),
              ],
            ),
          ),
          _Section('Escenarios obligatorios de prueba'),
          const _Scenario(
            icon: Icons.airplanemode_active_rounded,
            color: AppColors.blue,
            title: '1. Modo avión',
            steps: [
              'Activa el modo avión (o "Simular sin conexión").',
              'Crea 3 tareas y edita al menos una.',
              'Verifica la etiqueta "Pendiente" y el contador "Pendientes sync".',
            ],
          ),
          const _Scenario(
            icon: Icons.power_settings_new_rounded,
            color: AppColors.teal,
            title: '2. Cierre forzado',
            steps: [
              'Sin conexión, cierra la app desde Recientes (deslizar).',
              'Vuelve a abrirla: las tareas siguen ahí (persistencia SQLite).',
              'La sesión se restaura desde el almacenamiento cifrado.',
            ],
          ),
          const _Scenario(
            icon: Icons.wifi_rounded,
            color: AppColors.blue,
            title: '3. Reconexión',
            steps: [
              'Desactiva el modo avión.',
              'connectivity_plus detecta la red y dispara PUSH → ACK → PULL → MERGE.',
              'En la consola de Firebase (Firestore › users › tu UID › tasks) verás llegar los documentos.',
              'Bonus: edita un documento en la consola subiendo "version" y edita la misma tarea offline para provocar una colisión.',
            ],
          ),
          _Section('Arquitectura'),
          const _ArchitectureCard(),
          const SizedBox(height: 24),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: AppColors.red),
            onPressed: _logout,
            icon: const Icon(Icons.logout_rounded),
            label: const Text('Cerrar sesión y purgar datos locales'),
          ),
          const SizedBox(height: 12),
          Text(
            'Desarrollo Móvil Integral · Semana 11 · UTXJ',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title);

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 22, 4, 10),
        child: Text(
          title.toUpperCase(),
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: AppColors.blue,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
              ),
        ),
      );
}

class _Scenario extends StatelessWidget {
  const _Scenario({
    required this.icon,
    required this.color,
    required this.title,
    required this.steps,
  });

  final IconData icon;
  final Color color;
  final String title;
  final List<String> steps;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: ExpansionTile(
          shape: const Border(),
          leading: Icon(icon, color: color),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          children: [
            for (final (i, s) in steps.indexed)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 10,
                      backgroundColor: color.withValues(alpha: 0.15),
                      child: Text('${i + 1}',
                          style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w800)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: Text(s)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ArchitectureCard extends StatelessWidget {
  const _ArchitectureCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget node(IconData icon, String title, String sub, Color color) => Expanded(
          child: Column(
            children: [
              Icon(icon, color: color, size: 30),
              const SizedBox(height: 6),
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
              Text(sub,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ],
          ),
        );
    const arrow = Icon(Icons.swap_horiz_rounded, color: AppColors.teal);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                node(Icons.phone_android_rounded, 'UI Flutter', 'Escucha streams locales', AppColors.blue),
                const Padding(padding: EdgeInsets.only(top: 6), child: arrow),
                node(Icons.storage_rounded, 'SQLite', 'Fuente única de verdad', AppColors.teal),
                const Padding(padding: EdgeInsets.only(top: 6), child: arrow),
                node(Icons.local_fire_department_rounded, 'Firestore', 'Sync en segundo plano', AppColors.amber),
              ],
            ),
            const Divider(height: 28),
            for (final (layer, pkg) in const [
              ('Base de datos local', 'sqflite'),
              ('Tareas en segundo plano', 'workmanager'),
              ('Monitor de conectividad', 'connectivity_plus'),
              ('Identificadores únicos', 'uuid'),
              ('Cifrado en reposo', 'flutter_secure_storage'),
              ('Autenticación', 'firebase_auth'),
              ('Backend en la nube', 'cloud_firestore'),
            ])
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    Expanded(child: Text(layer)),
                    Text(pkg,
                        style: const TextStyle(
                            color: AppColors.blue, fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
