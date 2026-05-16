import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vestimate/features/wardrobe/presentation/screens/main_shell.dart';
import 'package:vestimate/features/auth/presentation/login_screen.dart';

part 'router.g.dart';

/// Set to [true] to bypass auth in local dev mode.
/// When true, a "Skip Login" button appears on the login screen.
const bool kDevAuthBypass = true;

@riverpod
GoRouter router(RouterRef ref) {
  return GoRouter(
    initialLocation: '/',
    redirect: (context, state) {
      // Epic 6 — Auth redirect logic
      if (kDevAuthBypass) return null; // In dev mode, always allow through

      final session = Supabase.instance.client.auth.currentSession;
      final isLoggedIn = session != null;
      final isOnLogin = state.matchedLocation == '/login';

      // Not logged in and not already on login page → redirect to login
      if (!isLoggedIn && !isOnLogin) return '/login';
      // Logged in and on login page → redirect to home
      if (isLoggedIn && isOnLogin) return '/';
      return null;
    },
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const MainShell(),
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
    ],
  );
}
