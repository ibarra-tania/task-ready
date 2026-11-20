/// Sesión autenticada. El token se guarda cifrado con flutter_secure_storage
/// (Android Keystore / iOS Keychain), nunca en SQLite ni en texto plano.
class Session {
  const Session({required this.token, required this.uid, required this.email});

  final String token;
  final String uid;
  final String email;

  String get maskedToken =>
      token.length <= 8 ? '••••' : '••••••••${token.substring(token.length - 6)}';

  factory Session.fromJson(Map<String, dynamic> json) => Session(
        token: json['token'] as String,
        uid: json['uid'] as String,
        email: json['email'] as String,
      );
}
