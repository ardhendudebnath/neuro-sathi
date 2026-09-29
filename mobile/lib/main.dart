import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'data/database.dart';
import 'state/app_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final db = await openEncryptedDb();
  runApp(ProviderScope(overrides: [dbProvider.overrideWithValue(db)], child: const NeuroSathiApp()));
}
