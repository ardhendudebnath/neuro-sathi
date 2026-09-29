import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'state/app_state.dart';

/// Elderly-first theme: large text, high contrast, big touch targets.
ThemeData buildTheme() {
  const seed = Color(0xFF0F6E66);
  final scheme = ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.light).copyWith(
    surface: const Color(0xFFFFFBF5),
    onSurface: const Color(0xFF1C1B19),
  );
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    scaffoldBackgroundColor: const Color(0xFFF7F5F0),
    visualDensity: VisualDensity.comfortable,
    textTheme: const TextTheme(
      displaySmall: TextStyle(fontSize: 34, fontWeight: FontWeight.w700),
      headlineMedium: TextStyle(fontSize: 26, fontWeight: FontWeight.w700),
      titleLarge: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
      bodyLarge: TextStyle(fontSize: 19, height: 1.4),
      bodyMedium: TextStyle(fontSize: 17, height: 1.4),
      labelLarge: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(88, 64),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(88, 64),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        side: const BorderSide(color: seed, width: 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(14))),
      contentPadding: EdgeInsets.symmetric(horizontal: 18, vertical: 18),
    ),
    appBarTheme: const AppBarTheme(centerTitle: false, toolbarHeight: 68, titleTextStyle: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: Color(0xFF1C1B19))),
  );
}

class NeuroSathiApp extends ConsumerStatefulWidget {
  const NeuroSathiApp({super.key});

  @override
  ConsumerState<NeuroSathiApp> createState() => _NeuroSathiAppState();
}

class _NeuroSathiAppState extends ConsumerState<NeuroSathiApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Future.microtask(() => ref.read(appProvider.notifier).start());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) {
      final app = ref.read(appProvider.notifier);
      app.logMissedReminders();
      app.syncNow();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appProvider);
    return MaterialApp(
      title: 'NEURO-SATHI',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(state.fontScale / 1.4)),
        child: child!,
      ),
      home: !state.ready
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : state.signedIn
              ? const HomeScreen()
              : const LoginScreen(),
    );
  }
}
