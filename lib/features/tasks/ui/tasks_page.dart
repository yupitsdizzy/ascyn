import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../xp/providers/xp_providers.dart';

class TasksPage extends ConsumerStatefulWidget {
  const TasksPage({super.key});

  @override
  ConsumerState<TasksPage> createState() => _TasksPageState();
}

class _TasksPageState extends ConsumerState<TasksPage> {
  final _nameCtrl = TextEditingController();
  final _xpCtrl = TextEditingController(text: '50');

  @override
  void dispose() {
    _nameCtrl.dispose();
    _xpCtrl.dispose();
    super.dispose();
  }

  Future<void> _createTask(String uid, String characterId) async {
    final name = _nameCtrl.text.trim();
    final xp = double.tryParse(_xpCtrl.text) ?? 50.0;
    if (name.isEmpty) return;

    final col = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('characters')
        .doc(characterId)
        .collection('tasks');

    await col.add({'name': name, 'xp': xp, 'createdAt': Timestamp.now()});
    _nameCtrl.clear();
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const Scaffold(body: Center(child: Text('Not logged in.')));

    final charsRef = FirebaseFirestore.instance.collection('users').doc(uid).collection('characters');

    return Scaffold(
      appBar: AppBar(title: const Text('Tasks')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: charsRef.snapshots(),
        builder: (context, snap) {
          final docs = snap.data?.docs ?? [];
          if (docs.isEmpty) return const Center(child: Text('No characters.'));

          final characterId = docs.first.id;
          final tasksRef = charsRef.doc(characterId).collection('tasks').orderBy('createdAt', descending: true);

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12.0),
                child: Row(
                  children: [
                    Expanded(child: TextField(controller: _nameCtrl, decoration: const InputDecoration(hintText: 'Task name'))),
                    const SizedBox(width: 8),
                    SizedBox(width: 80, child: TextField(controller: _xpCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(hintText: 'XP'))),
                    const SizedBox(width: 8),
                    ElevatedButton(onPressed: () => _createTask(uid, characterId), child: const Text('Add')),
                  ],
                ),
              ),
              Expanded(
                child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: tasksRef.snapshots(),
                  builder: (context, tsnap) {
                    final tasks = tsnap.data?.docs ?? [];
                    if (tasks.isEmpty) return const Center(child: Text('No tasks')); 

                    return ListView.builder(
                      itemCount: tasks.length,
                      itemBuilder: (context, i) {
                        final doc = tasks[i];
                        final data = doc.data();
                        final name = data['name'] as String? ?? 'Unnamed';
                        final xp = (data['xp'] as num?)?.toDouble() ?? 50.0;

                        return ListTile(
                          title: Text(name),
                          subtitle: Text('${xp.toStringAsFixed(0)} XP'),
                          trailing: Wrap(spacing: 8, children: [
                            ElevatedButton(
                              child: const Text('Complete'),
                              onPressed: () async {
                                final messenger = ScaffoldMessenger.of(context);
                                try {
                                  final ledger = ref.read(xpLedgerServiceProvider);
                                  final res = await ledger.recordTaskCompletion(
                                    uid: uid,
                                    characterId: characterId,
                                    taskId: doc.id,
                                    overallXp: xp,
                                    primaryStatName: 'discipline',
                                  );
                                  messenger.showSnackBar(SnackBar(content: Text('Recorded ${res.eventId}')));
                                } catch (e) {
                                  messenger.showSnackBar(SnackBar(content: Text('Complete failed: $e')));
                                }
                              },
                            ),
                            TextButton(
                              child: const Text('Undo Last'),
                              onPressed: () async {
                                final messenger = ScaffoldMessenger.of(context);
                                final navigator = Navigator.of(context);
                                try {
                                  // find latest xp_event for this task
                                  final eventsRef = FirebaseFirestore.instance
                                      .collection('users')
                                      .doc(uid)
                                      .collection('characters')
                                      .doc(characterId)
                                      .collection('xp_events')
                                      .where('sourceType', isEqualTo: 'taskComplete')
                                      .where('sourceId', isEqualTo: doc.id)
                                      .orderBy('occurredAt', descending: true)
                                      .limit(1);

                                  final snap = await eventsRef.get();
                                  if (snap.docs.isEmpty) {
                                    messenger.showSnackBar(const SnackBar(content: Text('No task event to undo')));
                                    return;
                                  }

                                  final lastId = snap.docs.first.id;

                                  // ensure widget still mounted before using navigator.context
                                  if (!mounted) return;

                                  // capture messenger before awaiting dialog to avoid context across async gap
                                  final confirmed = await showDialog<bool>(
                                    context: navigator.context,
                                    builder: (ctx) => AlertDialog(
                                      title: const Text('Confirm Undo'),
                                      content: Text('Undo last completion for "$name"?'),
                                      actions: [
                                        TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
                                        TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Undo')),
                                      ],
                                    ),
                                  );

                                  if (confirmed != true) return;

                                  final ledger = ref.read(xpLedgerServiceProvider);
                                  final res = await ledger.undoEvent(
                                    uid: uid,
                                    characterId: characterId,
                                    eventIdToUndo: lastId,
                                  );

                                  messenger.showSnackBar(SnackBar(content: Text('Undo ${res.eventId} ${res.created ? 'created' : 'exists'}')));
                                } catch (e) {
                                  messenger.showSnackBar(SnackBar(content: Text('Undo failed: $e')));
                                }
                              },
                            ),
                          ]),
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
  }
}
