import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';

import '../firebase_options.dart';

/// Inicializa Firebase (UI y también el isolate de WorkManager).
Future<void> initFirebase() async {
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  }
  try {
    // Se desactiva la caché offline propia de Firestore: en esta
    // arquitectura SQLite es la ÚNICA fuente de verdad local y el ciclo
    // PUSH/PULL es explícito y auditable.
    FirebaseFirestore.instance.settings = const Settings(persistenceEnabled: false);
  } catch (_) {
    // Ya configurado en este proceso (p. ej. desde otro isolate).
  }
}

String get firebaseProjectId => Firebase.app().options.projectId;
