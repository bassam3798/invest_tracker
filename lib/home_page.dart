import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'pages/input_page.dart';
import 'pages/active_trades.dart';
import 'pages/page_three.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  void _open(BuildContext context, Widget page) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => page),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Invest Tracker'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
              // No manual navigation needed: AuthGate listens to authStateChanges()
              // and will show LoginRegisterPage when the user becomes null.
            },
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                'Welcome, ${user?.displayName ?? user?.email ?? 'User'}',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () => _open(context, const PageOne()),
                // Increase padding and font size to make the button bigger and higher
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
                  textStyle: const TextStyle(fontSize: 18),
                ),
                child: const Text('Add Stock'),
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: () => _open(context, const PageTwo()),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
                  textStyle: const TextStyle(fontSize: 18),
                ),
                child: const Text('Open Page Two'),
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: () => _open(context, const PageThree()),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
                  textStyle: const TextStyle(fontSize: 18),
                ),
                child: const Text('Open Page Three'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}