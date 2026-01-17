import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../xp/data/xp_ledger_service.dart';
import '../../xp/domain/ascyn_stat.dart';
import '../data/habit_repo.dart';

class HabitsPage extends StatefulWidget {
  const HabitsPage({super.key});

  @override
  State<HabitsPage> createState() => _HabitsPageState();
}

class _HabitsPageState extends State<HabitsPage> {
  late final HabitRepo repo;

  @override
  void initState() {
    super.initState();
    final db = FirebaseFirestore.instance;
    repo = HabitRepo(db, FirebaseAuth.instance, XpLedgerService(db));
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> _activeCharacterStream({
    required String uid,
    required String characterId,
  }) {
    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('characters')
        .doc(characterId)
        .snapshots();
  }

  Future<int?> _askForNumber(
    BuildContext context, {
    required String title,
    required String hint,
    int min = 1,
    int max = 240,
  }) async {
    int? value;

    final result = await showDialog<int?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextFormField(
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(hintText: hint),
          onChanged: (txt) => value = int.tryParse(txt.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final v = value;
              if (v == null) {
                Navigator.pop(ctx, null);
                return;
              }
              Navigator.pop(ctx, v.clamp(min, max));
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );

    return result;
  }

  Future<void> _logHabit({
    required String charId,
    required String habitId,
    required HabitType type,
  }) async {
    try {
      int? addCount;
      int? addMinutes;

      if (type == HabitType.counter) {
        addCount = await _askForNumber(
          context,
          title: 'Log counter',
          hint: 'How many?',
          min: 1,
          max: 9999,
        );
        if (!mounted) return;
        if (addCount == null) return;
      }

      if (type == HabitType.timer) {
        addMinutes = await _askForNumber(
          context,
          title: 'Log timer',
          hint: 'Minutes (max 240 stored)',
          min: 1,
          max: 240,
        );
        if (!mounted) return;
        if (addMinutes == null) return;
      }

      final warning = await repo.logHabit(
        charId: charId,
        habitId: habitId,
        addCount: addCount,
        addMinutes: addMinutes,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(warning ?? 'Logged ✅')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }

  Widget _xpHud(Map<String, dynamic> charData) {
    final overallXp = (charData['overallXpTotal'] as num?)?.toDouble() ?? 0.0;
    final overallLevel = (charData['overallLevel'] as num?)?.toInt() ?? 1;

    final statLevelsRaw = (charData['statLevels'] as Map<String, dynamic>?) ?? {};
    int statLevel(AscynStat s) => (statLevelsRaw[s.name] as num?)?.toInt() ?? 1;

    String prettyStat(AscynStat s) {
      final n = s.name;
      if (n.isEmpty) return n;
      return n[0].toUpperCase() + n.substring(1);
    }

    // Display a small subset first to keep it clean.
    final shownStats = <AscynStat>[
      AscynStat.strength,
      AscynStat.endurance,
      AscynStat.discipline,
      AscynStat.creativity,
      AscynStat.focus,
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'XP Snapshot',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                _pill('Overall Lvl', '$overallLevel'),
                _pill('Overall XP', overallXp.toStringAsFixed(1)),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                for (final s in shownStats) _pill(prettyStat(s), '${statLevel(s)}'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _pill(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text('$label: $value'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    if (uid == null) {
      return const Scaffold(body: Center(child: Text('Not logged in.')));
    }

    final userStream =
        FirebaseFirestore.instance.collection('users').doc(uid).snapshots();

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: userStream,
      builder: (context, userSnap) {
        final activeId = userSnap.data?.data()?['activeCharacterId'] as String?;

        if (activeId == null || activeId.isEmpty) {
          return Scaffold(
            appBar: AppBar(title: const Text('Habits')),
            body: Center(
              child: ElevatedButton(
                onPressed: () => context.go('/character-builder'),
                child: const Text('Create a character first'),
              ),
            ),
          );
        }

        return Scaffold(
          appBar: AppBar(
            title: const Text('Habits'),
            actions: [
              IconButton(
                tooltip: 'Home',
                onPressed: () => context.go('/home'),
                icon: const Icon(Icons.home),
              ),
              IconButton(
                tooltip: 'Characters',
                onPressed: () => context.go('/characters'),
                icon: const Icon(Icons.person),
              ),
              IconButton(
                tooltip: 'New habit',
                onPressed: () => context.go('/habits/create?cid=$activeId'),
                icon: const Icon(Icons.add),
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton(
            onPressed: () => context.go('/habits/create?cid=$activeId'),
            child: const Icon(Icons.add),
          ),
          body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: _activeCharacterStream(uid: uid, characterId: activeId),
            builder: (context, charSnap) {
              final charData = charSnap.data?.data() ?? <String, dynamic>{};

              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                    child: _xpHud(charData),
                  ),
                  const SizedBox(height: 6),
                  Expanded(
                    child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: repo.watchHabits(activeId),
                      builder: (context, snap) {
                        if (snap.connectionState == ConnectionState.waiting) {
                          return const Center(child: CircularProgressIndicator());
                        }

                        final docs = snap.data?.docs ?? const [];
                        if (docs.isEmpty) {
                          return const Center(
                            child: Text('No habits yet. Tap + to create one.'),
                          );
                        }

                        return ListView.separated(
                          padding: const EdgeInsets.all(12),
                          itemCount: docs.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
                          itemBuilder: (context, i) {
                            final doc = docs[i];
                            final data = doc.data();

                            final title = (data['title'] as String?) ?? 'Untitled';
                            final typeStr = (data['type'] as String?) ?? 'check';

                            final type = HabitType.values.firstWhere(
                              (e) => e.name == typeStr,
                              orElse: () => HabitType.check,
                            );

                            final streak = (data['streak'] as Map<String, dynamic>?) ?? {};
                            final streakCount = (streak['count'] as int?) ?? 0;

                            return Card(
                              child: ListTile(
                                title: Text(title),
                                subtitle: Text('Type: ${type.name}   Streak: $streakCount'),
                                trailing: ElevatedButton(
                                  onPressed: () => _logHabit(
                                    charId: activeId,
                                    habitId: doc.id,
                                    type: type,
                                  ),
                                  child: const Text('Log'),
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}
