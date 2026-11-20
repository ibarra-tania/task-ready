import 'package:flutter/material.dart';

import '../../core/app_services.dart';
import '../../core/theme.dart';
import '../../core/firebase_setup.dart';
import '../../data/remote/remote_exception.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _s = AppServices.instance;
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _register = false;
  bool _loading = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _s.auth.signIn(
        email: _email.text,
        password: _password.text,
        register: _register,
      );
      // La navegación la resuelve el AuthGate al cambiar la sesión.
    } on RemoteException catch (e) {
      setState(() => _error = e.isNetworkError
          ? '${e.message}. El primer inicio de sesión requiere internet.'
          : e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SingleChildScrollView(
        child: Column(
          children: [
            _Hero(),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(value: false, label: Text('Iniciar sesión')),
                        ButtonSegment(value: true, label: Text('Crear cuenta')),
                      ],
                      selected: {_register},
                      showSelectedIcon: false,
                      onSelectionChanged: (s) => setState(() {
                        _register = s.first;
                        _error = null;
                      }),
                    ),
                    const SizedBox(height: 20),
                    TextFormField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Correo electrónico',
                        prefixIcon: Icon(Icons.alternate_email_rounded),
                      ),
                      validator: (v) => RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v?.trim() ?? '')
                          ? null
                          : 'Ingresa un correo válido',
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _password,
                      obscureText: _obscure,
                      autofillHints: const [AutofillHints.password],
                      onFieldSubmitted: (_) => _submit(),
                      decoration: InputDecoration(
                        labelText: 'Contraseña',
                        prefixIcon: const Icon(Icons.lock_outline_rounded),
                        suffixIcon: IconButton(
                          onPressed: () => setState(() => _obscure = !_obscure),
                          icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                        ),
                      ),
                      validator: (v) =>
                          (v ?? '').length < 6 ? 'Mínimo 6 caracteres' : null,
                    ),
                    const SizedBox(height: 6),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      child: Row(
                        children: [
                          const Icon(Icons.local_fire_department_rounded,
                              size: 18, color: AppColors.amber),
                          const SizedBox(width: 8),
                          Text('Firebase · proyecto $firebaseProjectId',
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                        ],
                      ),
                    ),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      child: _error == null
                          ? const SizedBox.shrink()
                          : Container(
                              key: ValueKey(_error),
                              margin: const EdgeInsets.only(bottom: 12),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AppColors.red.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.error_outline_rounded, color: AppColors.red),
                                  const SizedBox(width: 10),
                                  Expanded(
                                      child: Text(_error!,
                                          style: const TextStyle(color: AppColors.red))),
                                ],
                              ),
                            ),
                    ),
                    FilledButton(
                      onPressed: _loading ? null : _submit,
                      child: _loading
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                            )
                          : Text(_register ? 'Crear cuenta' : 'Entrar'),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        const Icon(Icons.shield_outlined, size: 16, color: AppColors.teal),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Tu token se guarda cifrado en el dispositivo. Después del primer acceso '
                            'la app funciona sin conexión.',
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(24, MediaQuery.paddingOf(context).top + 40, 24, 32),
      decoration: const BoxDecoration(
        color: AppColors.navy,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.teal.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.cloud_sync_rounded, color: AppColors.teal, size: 32),
          ),
          const SizedBox(height: 20),
          const Text(
            'DESARROLLO MÓVIL INTEGRAL · SEMANA 11',
            style: TextStyle(
              color: AppColors.teal,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Tareas Offline-First',
            style: TextStyle(
              color: Colors.white,
              fontSize: 30,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Persistencia SQLite, tareas en segundo plano y sincronización bidireccional.',
            style: TextStyle(color: Colors.white70, fontSize: 14),
          ),
        ],
      ),
    );
  }
}
