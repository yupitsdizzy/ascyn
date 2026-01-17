import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../shared/data/firestore_refs.dart';
import 'data/auth_controller.dart';

final userDocProvider = StreamProvider<DocumentSnapshot<Map<String, dynamic>>?>((ref) {
  final authAsync = ref.watch(authStateProvider);

  return authAsync.when(
    data: (user) {
      if (user == null)return Stream<DocumentSnapshot<Map<String, dynamic>>?>.value(null);
      return userDocRef(user).snapshots();
    },
    loading: () => const Stream.empty(),
    // ignore: unnecessary_underscores
    error: (_, __) => const Stream.empty(),
  );
});

class AuthGate extends ConsumerWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authStateProvider);

    return auth.when(
      loading: () => const _Splash(),
      error: (e, _) => _ErrorView(message: e.toString()),
      data: (user) {
        if (user == null) return const _Splash();

        final userDoc = ref.watch(userDocProvider);

        return userDoc.when(
          loading: () => const _Splash(),
          error: (e, _) => _ErrorView(message: e.toString()),
          data: (snap) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!context.mounted) return;

              // No profile doc yet
              if (snap == null || !snap.exists) {
                context.go('/onboarding');
                return;
              }

              final data = snap.data() ?? {};
              final activeCharacterId = data['activeCharacterId'] as String?;

              // Profile exists but no character created yet
              if (activeCharacterId == null || activeCharacterId.isEmpty) {
                context.go('/character-builder');
                return;
              }

              context.go('/home');
            });

            return const _Splash();
          },
        );
      },
    );
  }
}

class _Splash extends StatelessWidget {
  const _Splash();
  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) {
    return Scaffold(body: Center(child: Text('Error: $message')));
  }
}
