import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../data/character_repo.dart';

class CharactersPage extends StatelessWidget {
  const CharactersPage({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = FirebaseAuth.instance;
    final uid = auth.currentUser?.uid;

    if (uid == null) {
      return const Scaffold(body: Center(child: Text('Not logged in.')));
    }

    final db = FirebaseFirestore.instance;
    final repo = CharacterRepo(db, auth);

    final userStream = db.collection('users').doc(uid).snapshots();
    final charsStream = repo.watchCharacters();

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: userStream,
      builder: (context, userSnap) {
        final activeId = userSnap.data?.data()?['activeCharacterId'] as String?;

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: charsStream,
          builder: (context, charsSnap) {
            final docs = charsSnap.data?.docs ?? [];

            return Scaffold(
              appBar: AppBar(
                title: const Text('Characters'),
                actions: [
                  IconButton(
                    tooltip: 'Home',
                    onPressed: () => context.go('/home'),
                    icon: const Icon(Icons.home),
                  ),
                  IconButton(
                    tooltip: 'Habits',
                    onPressed: () => context.go('/habits'),
                    icon: const Icon(Icons.list),
                  ),
                  IconButton(
                    tooltip: 'New',
                    onPressed: () => context.go('/characters/create'),
                    icon: const Icon(Icons.add),
                  ),
                ],
              ),
              body: docs.isEmpty
                  ? Center(
                      child: ElevatedButton(
                        onPressed: () => context.go('/characters/create'),
                        child: const Text('Create your first character'),
                      ),
                    )
                  : ListView.separated(
                      itemCount: docs.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final doc = docs[i];
                        final data = doc.data();
                        final id = doc.id;
                        final name = (data['name'] as String?) ?? 'Unnamed';

                        final isActive = activeId == id;

                        return ListTile(
                          title: Text(name),
                          subtitle: Text(isActive ? 'Active' : 'Tap to set active'),
                          trailing: isActive ? const Icon(Icons.check_circle) : null,
                          onTap: () async {
                            try {
                              await repo.setActiveCharacter(id);
                              if (!context.mounted) return;

                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Active character: $name')),
                              );
                            } catch (e) {
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(e.toString())),
                              );
                            }
                          },
                        );
                      },
                    ),
            );
          },
        );
      },
    );
  }
}
