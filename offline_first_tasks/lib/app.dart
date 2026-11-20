import 'package:flutter/material.dart';

import 'core/app_config.dart';
import 'core/app_services.dart';
import 'core/theme.dart';
import 'data/models/session.dart';
import 'sync/background_sync.dart';
import 'ui/screens/home_screen.dart';
import 'ui/screens/login_screen.dart';

class OfflineFirstApp extends StatelessWidget {
  const OfflineFirstApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      home: const AuthGate(),
    );
  }
}

/// Decide entre Login y Home según la sesión cifrada, y gestiona el ciclo
/// de vida de la sincronización.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> with WidgetsBindingObserver {
  final _s = AppServices.instance;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _s.auth.session.addListener(_onSessionChanged);
    _onSessionChanged();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _s.auth.session.removeListener(_onSessionChanged);
    super.dispose();
  }

  void _onSessionChanged() {
    final loggedIn = _s.auth.session.value != null;
    _s.coordinator.enabled = loggedIn;
    if (loggedIn) {
      BackgroundSync.registerPeriodic();
      _s.coordinator.syncNow('Inicio');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _s.auth.session.value != null) {
      // WorkManager pudo haber escrito en SQLite mientras la app estaba en
      // segundo plano: refrescamos los streams y sincronizamos.
      _s.db.tasks.notifyChanged();
      _s.db.notify('sync_log');
      _s.db.notify('sync_meta');
      _s.coordinator.syncNow('App reanudada');
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Session?>(
      valueListenable: _s.auth.session,
      builder: (_, session, _) => AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: session == null
            ? const LoginScreen(key: ValueKey('login'))
            : const HomeScreen(key: ValueKey('home')),
      ),
    );
  }
}
