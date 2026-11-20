import 'dart:io';
import 'dart:math';

import 'package:cloud_server/cloud_server.dart';
import 'package:shelf/shelf_io.dart' as io;

/// Backend de la práctica Offline-First.
///
///   dart run bin/cloud_server.dart            (puerto 8080)
///   PORT=9090 ADMIN_KEY=secreto dart run bin/cloud_server.dart
Future<void> main() async {
  final port = int.tryParse(Platform.environment['PORT'] ?? '') ?? 8080;
  final adminKey = Platform.environment['ADMIN_KEY'] ??
      List.generate(6, (_) => Random.secure().nextInt(36).toRadixString(36)).join();

  final store = CloudStore(File('data/cloud_db.json'));
  await store.load();

  final api = CloudApi(store, adminKey: adminKey);
  final server = await io.serve(api.handler, InternetAddress.anyIPv4, port);

  print('');
  print('  Backend Offline-First escuchando en el puerto ${server.port}');
  print('  Consola nube:        http://localhost:${server.port}/?key=$adminKey');
  print('  Emulador Android:    http://10.0.2.2:${server.port}');
  print('  Dispositivo físico:  http://<IP-de-tu-PC>:${server.port}');
  print('');
}
