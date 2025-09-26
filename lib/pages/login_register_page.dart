import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import '../services/auth_service.dart';

class LoginRegisterPage extends StatefulWidget {
  const LoginRegisterPage({super.key});

  @override
  State<LoginRegisterPage> createState() => _LoginRegisterPageState();
}

class _LoginRegisterPageState extends State<LoginRegisterPage>
    with SingleTickerProviderStateMixin {
  final _loginForm = GlobalKey<FormState>();
  final _registerForm = GlobalKey<FormState>();

  // Login controllers
  final _loginEmail = TextEditingController();
  final _loginPassword = TextEditingController();

  // Register controllers
  final _regName = TextEditingController();
  final _regEmail = TextEditingController();
  final _regPassword = TextEditingController();
  final _regPassword2 = TextEditingController();

  bool _isRegisterTab = false;
  bool _busy = false;

  @override
  void dispose() {
    _loginEmail.dispose();
    _loginPassword.dispose();
    _regName.dispose();
    _regEmail.dispose();
    _regPassword.dispose();
    _regPassword2.dispose();
    super.dispose();
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _showErrorDialog(String title, String message) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  String _mapAuthError(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-email':
        return 'The email address is badly formatted.';
      case 'user-not-found':
        return 'The email or password you entered is not correct.';
      case 'wrong-password':
        return 'The email or password you entered is not correct.';
      case 'invalid-credential':
      case 'invalid-login-credentials':
        return 'The email or password you entered is not correct.';
      case 'user-disabled':
        return 'This account has been disabled.';
      case 'too-many-requests':
        return 'Too many attempts. Please try again later.';
      case 'network-request-failed':
        return 'Network error. Check your connection and try again.';
      default:
        return 'An unexpected error occurred (code: ${e.code}).';
    }
  }

  Future<void> _doLogin() async {
    if (!(_loginForm.currentState?.validate() ?? false)) return;
    setState(() => _busy = true);
    try {
      await AuthService().login(
        email: _loginEmail.text,
        password: _loginPassword.text,
      );
      // AuthGate will route to HomePage automatically
    } on FirebaseAuthException catch (e) {
      final msg = _mapAuthError(e);
      await _showErrorDialog('Login failed', msg);
    } catch (e) {
      await _showErrorDialog('Login failed', e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _doRegister() async {
    if (!(_registerForm.currentState?.validate() ?? false)) return;
    if (_regPassword.text != _regPassword2.text) {
      _showSnack('Passwords do not match');
      return;
    }
    setState(() => _busy = true);
    try {
      await AuthService().register(
        email: _regEmail.text,
        password: _regPassword.text,
        displayName: _regName.text,
      );
      await FirebaseAuth.instance.currentUser?.sendEmailVerification();
      _showSnack('Account created! You are now signed in.');
    } catch (e) {
      _showSnack('Registration failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  InputDecoration _dec(String label) =>
      InputDecoration(labelText: label, border: const OutlineInputBorder());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AbsorbPointer(
        absorbing: _busy,
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Lottie.asset(
                      'assets/animations/invest_logo.json',
                      width: 150,
                      height: 150,
                      repeat: true,
                    ),
                    // Animated logo
                    SizedBox(
                      height: 160,
                      child: Lottie.asset(
                        'assets/animations/invest_logo.json',
                        // Add a simple JSON from lottiefiles.com into assets
                        repeat: true,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ToggleButtons(
                      isSelected: [
                        _isRegisterTab == false,
                        _isRegisterTab == true,
                      ],
                      onPressed: (i) => setState(() => _isRegisterTab = i == 1),
                      direction: Axis.horizontal,
                      children: const [
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16),
                          child: Text('Login'),
                        ),
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16),
                          child: Text('Register'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    if (!_isRegisterTab)
                      _buildLoginForm()
                    else
                      _buildRegisterForm(),

                    const SizedBox(height: 12),
                    if (_busy) const CircularProgressIndicator(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoginForm() {
    return Form(
      key: _loginForm,
      child: Column(
        children: [
          TextFormField(
            controller: _loginEmail,
            decoration: _dec('Email'),
            keyboardType: TextInputType.emailAddress,
            validator: (v) {
              if (v == null || v.isEmpty) return 'Email is required';
              final ok = RegExp(r'^[^@]+@[^@]+\.[^@]+$').hasMatch(v);
              return ok ? null : 'Enter a valid email';
            },
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _loginPassword,
            decoration: _dec('Password'),
            obscureText: true,
            validator: (v) {
              if (v == null || v.isEmpty) return 'Password is required';
              if (v.length < 8) return 'Min 8 characters';
              return null;
            },
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _doLogin,
              child: const Text('Login'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRegisterForm() {
    return Form(
      key: _registerForm,
      child: Column(
        children: [
          TextFormField(
            controller: _regName,
            decoration: _dec('Display name'),
            validator: (v) {
              if (v == null || v.isEmpty) return 'Display name is required';
              return null;
            },
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _regEmail,
            decoration: _dec('Email'),
            keyboardType: TextInputType.emailAddress,
            validator: (v) {
              if (v == null || v.isEmpty) return 'Email is required';
              final ok = RegExp(r'^[^@]+@[^@]+\.[^@]+$').hasMatch(v);
              return ok ? null : 'Enter a valid email';
            },
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _regPassword,
            decoration: _dec('Password'),
            obscureText: true,
            validator: (v) {
              if (v == null || v.isEmpty) return 'Password is required';
              if (v.length < 8) return 'Min 8 characters';
              // You can add stronger policy: uppercase, number, special char, etc.
              return null;
            },
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _regPassword2,
            decoration: _dec('Confirm password'),
            obscureText: true,
            validator: (v) {
              if (v == null || v.isEmpty) return 'Confirm your password';
              return null; // We compare in _doRegister
            },
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _doRegister,
              child: const Text('Create account'),
            ),
          ),
        ],
      ),
    );
  }
}
