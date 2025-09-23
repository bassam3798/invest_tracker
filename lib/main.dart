// lib/main.dart
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:go_router/go_router.dart';
import 'services/auth_gate.dart';
import 'home_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const MyApp());
}


class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final router = GoRouter(
      initialLocation: '/', // AuthGate decides what to show
      routes: [
        GoRoute(path: '/', builder: (_, __) => const AuthGate()),
        GoRoute(path: '/home', builder: (_, __) => const HomePage()),
      ],
    );

    return MaterialApp.router(
      title: 'invest_tracker',
      theme: ThemeData(colorSchemeSeed: Colors.blue, useMaterial3: true),
      routerConfig: router,
    );
  }
}