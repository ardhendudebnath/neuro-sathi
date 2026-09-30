import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'data/database.dart';
import 'services/background_sync.dart';
import 'state/app_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await BackgroundSync.initialize(); // registers the entry point; the job is scheduled once signed in
  final db = await openEncryptedDb();
  runApp(ProviderScope(overrides: [dbProvider.overrideWithValue(db)], child: const NeuroSathiApp()));
}
