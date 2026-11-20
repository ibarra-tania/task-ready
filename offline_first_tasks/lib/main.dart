import 'package:flutter/material.dart';

import 'app.dart';
import 'core/app_services.dart';
import 'core/firebase_setup.dart';
import 'sync/background_sync.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initFirebase();
  await BackgroundSync.initialize();
  await AppServices.init();
  runApp(const OfflineFirstApp());
}
