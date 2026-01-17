import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/auth_controller.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final TextEditingController _email = TextEditingController();
  final TextEditingController _password = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() fn) async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await fn();
    } catch (e) {
      if (!mounted) return;
      messenger?.showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Login')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'Email'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _password,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Password'),
          ),
          const SizedBox(height: 16),

          ElevatedButton(
            onPressed: _busy
                ? null
                : () => _run(
                      () => auth.signInWithEmail(
                        _email.text.trim(),
                        _password.text,
                      ),
                    ),
            child: const Text('Login'),
          ),

          TextButton(
            onPressed: _busy ? null : () => context.go('/signup'),
            child: const Text('Create account'),
          ),

          const Divider(height: 32),

          ElevatedButton(
            onPressed: _busy ? null : () => _run(auth.signInWithGoogle),
            child: const Text('Continue with Google'),
          ),

          ElevatedButton(
            onPressed: _busy ? null : () => _run(auth.signInWithApple),
            child: const Text('Continue with Apple'),
          ),

          const SizedBox(height: 16),

          TextButton(
            onPressed: _busy
                ? null
                : () async {
                    final messenger = ScaffoldMessenger.maybeOf(context);
                    final email = _email.text.trim();
                    if (email.isEmpty) {
                      messenger?.showSnackBar(
                        const SnackBar(content: Text('Enter your email first.')),
                      );
                      return;
                    }

                    await _run(() => auth.sendPasswordReset(email));
                    if (!mounted) return;

                    messenger?.showSnackBar(
                      const SnackBar(content: Text('Password reset email sent.')),
                    );
                  },
            child: const Text('Forgot password?'),
          ),
        ],
      ),
    );
  }
}
