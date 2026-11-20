/// Error tipado de la capa remota (Firestore / Firebase Auth).
class RemoteException implements Exception {
  const RemoteException(
    this.message, {
    this.isNetworkError = false,
    this.isUnauthorized = false,
  });

  final String message;

  /// Sin respuesta de la nube (sin red, timeout, servicio no disponible).
  /// Los cambios siguen en SQLite y WorkManager reintenta.
  final bool isNetworkError;

  /// La sesión ya no es válida (token expirado / usuario deshabilitado).
  final bool isUnauthorized;

  /// Traduce los códigos de FirebaseException / FirebaseAuthException.
  factory RemoteException.fromCode(String code, [String? fallback]) {
    switch (code) {
      case 'unavailable':
      case 'deadline-exceeded':
      case 'network-request-failed':
        return const RemoteException('No hay conexión con Firebase', isNetworkError: true);
      case 'unauthenticated':
      case 'user-token-expired':
      case 'user-disabled':
      case 'requires-recent-login':
        return const RemoteException('La sesión expiró, vuelve a iniciar sesión',
            isUnauthorized: true);
      case 'permission-denied':
        return const RemoteException(
            'Permiso denegado por las reglas de seguridad de Firestore');
      case 'invalid-email':
        return const RemoteException('El correo no es válido');
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return const RemoteException('Correo o contraseña incorrectos');
      case 'email-already-in-use':
        return const RemoteException('Ese correo ya tiene cuenta: usa "Iniciar sesión"');
      case 'weak-password':
        return const RemoteException('La contraseña debe tener al menos 6 caracteres');
      case 'operation-not-allowed':
        return const RemoteException(
            'Habilita el proveedor Correo/Contraseña en Firebase Authentication');
      case 'too-many-requests':
        return const RemoteException('Demasiados intentos, espera un momento');
      default:
        return RemoteException(fallback ?? 'Error de Firebase ($code)');
    }
  }

  @override
  String toString() => message;
}
