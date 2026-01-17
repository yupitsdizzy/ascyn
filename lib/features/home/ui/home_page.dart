import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../xp/ui/xp_hud.dart';
import '../../xp/providers/xp_providers.dart';

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return const Scaffold(body: Center(child: Text('Not logged in.')));
    }

    final userDocStream =
        FirebaseFirestore.instance.collection('users').doc(uid).snapshots();

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: userDocStream,
      builder: (context, userSnap) {
        final activeId = userSnap.data?.data()?['activeCharacterId'] as String?;

        if (activeId == null || activeId.isEmpty) {
          return Scaffold(
            appBar: AppBar(title: const Text('Home')),
            body: const Center(child: Text('No active character yet.')),
          );
        }

        final characterDocStream = FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .collection('characters')
            .doc(activeId)
            .snapshots();

        return Scaffold(
          appBar: AppBar(
            title: const Text('Home'),
            actions: [
              IconButton(
                tooltip: 'Characters',
                onPressed: () => context.go('/characters'),
                icon: const Icon(Icons.person),
              ),
              IconButton(
                tooltip: 'Habits',
                onPressed: () => context.go('/habits'),
                icon: const Icon(Icons.list),
              ),
              IconButton(
                tooltip: 'History',
                onPressed: () => context.go('/history'),
                icon: const Icon(Icons.history),
              ),
              IconButton(
                tooltip: 'Complete Test Task',
                icon: const Icon(Icons.check_circle),
                onPressed: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  try {
                    final ledger = ref.read(xpLedgerServiceProvider);
                    final res = await ledger.recordTaskCompletion(
                      uid: uid,
                      characterId: activeId,
                      taskId: 'test_task_1',
                      overallXp: 50.0,
                      primaryStatName: 'discipline',
                    );
                    messenger.showSnackBar(
                      SnackBar(content: Text('Task event ${res.eventId} ${res.created ? 'created' : 'exists'}')),
                    );
                  } catch (e) {
                    messenger.showSnackBar(
                      SnackBar(content: Text('Task record failed: $e')),
                    );
                  }
                },
              ),
            ],
          ),
          body: ListView(
            children: [
              XpHud(characterDocStream: characterDocStream),

              // Your other home sections below
              const SizedBox(height: 8),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Text('Home content goes here...'),
              ),

              // (test buttons removed)
            ],
          ),
          // floatingActionButton removed — top AppBar has the add action.
        );
      },
    );
  }
}
