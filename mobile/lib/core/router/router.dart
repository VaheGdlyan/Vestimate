import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:vestimate/features/wardrobe/presentation/screens/wardrobe_gallery_screen.dart';
import 'package:vestimate/features/auth/presentation/login_screen.dart';
import 'package:vestimate/features/auth/data/auth_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

part 'router.g.dart';

@riverpod
GoRouter router(RouterRef ref) {
  final authState = ref.watch(authStateProvider).value;

  return GoRouter(
    initialLocation: '/',
    redirect: (context, state) {
      final loggedIn = authState != null;
      final loggingIn = state.matchedLocation == '/login';

      if (!loggedIn && !loggingIn) return '/login';
      if (loggedIn && loggingIn) return '/';
      return null;
    },
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const WardrobeGalleryScreen(),
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
    ],
  );
}
