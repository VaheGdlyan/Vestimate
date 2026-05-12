import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vestimate/core/theme/theme.dart';
import 'package:vestimate/features/auth/data/auth_repository.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;

  Future<void> _signIn() async {
    if (_emailController.text.isEmpty || _passwordController.text.isEmpty) {
      _showSnackbar('Please enter email and password', isError: true);
      return;
    }
    setState(() => _isLoading = true);
    try {
      await ref.read(authRepositoryProvider).signInWithEmail(
            email: _emailController.text.trim(),
            password: _passwordController.text.trim(),
          );
    } catch (e) {
      if (mounted) _showSnackbar('Login failed: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _signUp() async {
    final email = _emailController.text;
    final password = _passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      _showSnackbar('Please enter email and password to sign up', isError: true);
      return;
    }

    setState(() => _isLoading = true);
    try {
      await Supabase.instance.client.auth.signUp(
        email: email,
        password: password,
      );
      if (mounted) _showSnackbar('Sign up successful! Please check your email.');
    } catch (e) {
      if (mounted) _showSnackbar('Sign up error: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSnackbar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? V.danger : V.bgElevated,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: V.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: V.s24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Logo & Title ────────────────────────────────────────────────
              Center(
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(V.r16),
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [V.accent, V.accentSoft],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: V.accent.withOpacity(0.15),
                        blurRadius: 30,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: const Center(
                    child: Text(
                      'V',
                      style: TextStyle(
                        fontFamily: V.fontFamily,
                        fontSize: 32,
                        fontWeight: FontWeight.w800,
                        color: V.bg,
                        letterSpacing: -1,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: V.s32),
              const Text(
                'Welcome to Vestimate',
                textAlign: TextAlign.center,
                style: V.h1,
              ),
              const SizedBox(height: V.s8),
              Text(
                'Your personal AI stylist and wardrobe manager.',
                textAlign: TextAlign.center,
                style: V.bodySmall.copyWith(color: V.textSecondary),
              ),
              const SizedBox(height: V.s48),

              // ── Inputs ──────────────────────────────────────────────────────
              TextField(
                controller: _emailController,
                style: V.body,
                decoration: const InputDecoration(
                  labelText: 'EMAIL',
                  prefixIcon: Icon(Icons.email_outlined, color: V.textMuted, size: 20),
                ),
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: V.s16),
              TextField(
                controller: _passwordController,
                obscureText: true,
                style: V.body,
                decoration: const InputDecoration(
                  labelText: 'PASSWORD',
                  prefixIcon: Icon(Icons.lock_outline_rounded, color: V.textMuted, size: 20),
                ),
              ),
              const SizedBox(height: V.s32),

              // ── Buttons ─────────────────────────────────────────────────────
              ElevatedButton(
                onPressed: _isLoading
                    ? null
                    : () {
                        HapticFeedback.mediumImpact();
                        _signIn();
                      },
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: V.bg,
                        ),
                      )
                    : const Text('Sign In'),
              ),
              const SizedBox(height: V.s16),
              OutlinedButton(
                onPressed: _isLoading
                    ? null
                    : () {
                        HapticFeedback.mediumImpact();
                        _signUp();
                      },
                child: const Text('Create Account'),
              ),
              const SizedBox(height: V.s48),

              // ── Social Login ────────────────────────────────────────────────
              Row(
                children: [
                  const Expanded(child: Divider()),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: V.s16),
                    child: Text('OR CONTINUE WITH', style: V.label),
                  ),
                  const Expanded(child: Divider()),
                ],
              ),
              const SizedBox(height: V.s24),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _socialButton(Icons.apple),
                  const SizedBox(width: V.s16),
                  _socialButton(Icons.g_mobiledata_rounded),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _socialButton(IconData icon) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: V.bgSurface,
        borderRadius: BorderRadius.circular(V.r16),
        border: Border.all(color: V.border, width: 0.5),
      ),
      child: Center(
        child: Icon(icon, size: 28, color: V.textPrimary),
      ),
    );
  }
}
