import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/auth_gate.dart';
import '../features/auth/ui/login_page.dart';
import '../features/auth/ui/signup_page.dart';
import '../features/home/ui/home_page.dart';
import '../features/onboarding/ui/onboarding_page.dart';
import '../features/onboarding/ui/character_builder_page.dart';

import '../features/characters/ui/characters_page.dart';
import '../features/characters/ui/create_character_page.dart';

import '../features/habits/ui/habits_page.dart';
import '../features/habits/ui/create_habit_page.dart';
import '../features/xp/ui/history_page.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final auth = FirebaseAuth.instance;

  return GoRouter(
    initialLocation: '/',
    refreshListenable: _GoRouterRefreshStream(auth.authStateChanges()),
    redirect: (context, state) {
      final loggedIn = auth.currentUser != null;

      final isLoggingIn =
          state.matchedLocation == '/login' || state.matchedLocation == '/signup';

      if (!loggedIn) {
        return isLoggingIn ? null : '/login';
      }

      if (isLoggingIn) return '/';

      return null;
    },
    routes: [
      GoRoute(path: '/', builder: (context, state) => const AuthGate()),
      GoRoute(path: '/login', builder: (context, state) => const LoginPage()),
      GoRoute(path: '/signup', builder: (context, state) => const SignupPage()),
      GoRoute(path: '/onboarding', builder: (context, state) => OnboardingPage()),
      GoRoute(path: '/character-builder', builder: (context, state) => const CharacterBuilderPage()),
      GoRoute(path: '/home', builder: (context, state) => const HomePage()),

      GoRoute(path: '/characters', builder: (context, state) => const CharactersPage()),
      GoRoute(path: '/characters/create', builder: (context, state) => const CreateCharacterPage()),

      GoRoute(path: '/habits', builder: (context, state) => const HabitsPage()),
      GoRoute(path: '/history', builder: (context, state) => const HistoryPage()),
      GoRoute(
        path: '/habits/create',
        builder: (context, state) {
          final cid = state.uri.queryParameters['cid'] ?? '';
          return CreateHabitPage(characterId: cid);
        },
      ),
    ],
  );
});

class _GoRouterRefreshStream extends ChangeNotifier {
  _GoRouterRefreshStream(Stream<dynamic> stream) {
    _sub = stream.listen((_) => notifyListeners());
  }

  late final StreamSubscription<dynamic> _sub;

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}
