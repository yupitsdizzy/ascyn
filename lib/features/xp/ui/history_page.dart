import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../xp/providers/xp_providers.dart';
import '../data/xp_ledger_service.dart';
import '../domain/xp_event.dart';

class HistoryPage extends ConsumerStatefulWidget {
  const HistoryPage({super.key});

  @override
  ConsumerState<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends ConsumerState<HistoryPage> {
  final List<XpEvent> _events = [];
  DocumentSnapshot<Map<String, dynamic>>? _lastDoc;
  bool _loading = false;
  bool _hasMore = true;
  static const int _pageSize = 20;
  String? _activeCharacterId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  Future<void> _findActiveCharacter(String uid) async {
    final chars = await FirebaseFirestore.instance.collection('users').doc(uid).collection('characters').get();
    if (chars.docs.isEmpty) {
      _activeCharacterId = null;
    } else {
      _activeCharacterId = chars.docs.first.id;
    }
  }

  Future<void> _refresh() async {
    setState(() {
      _events.clear();
      _lastDoc = null;
      _hasMore = true;
    });
    await _loadPage();
  }

  Future<void> _loadPage() async {
    if (_loading || !_hasMore) return;
    setState(() => _loading = true);

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      setState(() => _loading = false);
      return;
    }

    if (_activeCharacterId == null) {
      await _findActiveCharacter(uid);
      if (_activeCharacterId == null) {
        setState(() => _loading = false);
        return;
      }
    }

    Query<Map<String, dynamic>> q = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('characters')
        .doc(_activeCharacterId)
        .collection('xp_events')
        .orderBy('occurredAt', descending: true)
        .limit(_pageSize);

    if (_lastDoc != null) q = q.startAfterDocument(_lastDoc!);

    final snap = await q.get();
    if (snap.docs.isEmpty) {
      _hasMore = false;
    } else {
      _lastDoc = snap.docs.last;
      final pageEvents = snap.docs.map((d) => XpEvent.fromDoc(d)).toList();
      _events.addAll(pageEvents);
    }

    setState(() => _loading = false);
  }

  Map<String, List<XpEvent>> _groupByDay() {
    final map = <String, List<XpEvent>>{};
    for (final e in _events) {
      final dayKey = XpLedgerService.dayKeyWith3amBoundaryStatic(e.occurredAt.toLocal());
      map.putIfAbsent(dayKey, () => []).add(e);
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const Scaffold(body: Center(child: Text('Not logged in.')));

    final grouped = _groupByDay();
    final sortedKeys = grouped.keys.toList()..sort((a, b) => b.compareTo(a));

    return Scaffold(
      appBar: AppBar(title: const Text('History')),
      body: _activeCharacterId == null && _events.isEmpty
          ? const Center(child: Text('No characters.'))
          : Column(
              children: [
                Expanded(
                  child: ListView.builder(
                    itemCount: sortedKeys.length,
                    itemBuilder: (context, idx) {
                      final day = sortedKeys[idx];
                      final items = grouped[day]!;
                      return _buildDaySection(day, items);
                    },
                  ),
                ),
                if (_hasMore)
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: ElevatedButton(
                      onPressed: _loading ? null : _loadPage,
                      child: _loading ? const CircularProgressIndicator() : const Text('Load more'),
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _buildDaySection(String dayKey, List<XpEvent> items) {
    final dayTotal = items.fold<double>(0.0, (p, e) => p + e.overallXp);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(dayKey, style: const TextStyle(fontWeight: FontWeight.bold)),
              Text('${dayTotal.toStringAsFixed(0)} XP', style: const TextStyle(color: Colors.grey)),
            ],
          ),
        ),
        ...items.map((ev) => ListTile(
              title: Text(ev.note ?? ev.id),
              subtitle: Text('${ev.overallXp} XP • ${ev.occurredAt.toLocal()}'),
              trailing: ev.status == XpEventStatus.active
                  ? TextButton(
                      child: const Text('Undo'),
                      onPressed: () async {
                        final messenger = ScaffoldMessenger.of(context);
                        final confirmed = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Confirm Undo'),
                            content: Text('Undo event "${ev.note ?? ev.id}" and deduct ${ev.overallXp} XP?'),
                            actions: [
                              TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
                              TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Undo')),
                            ],
                          ),
                        );

                        if (confirmed != true) return;

                        try {
                          final ledger = ref.read(xpLedgerServiceProvider);
                          final res = await ledger.undoEvent(
                            uid: FirebaseAuth.instance.currentUser!.uid,
                            characterId: _activeCharacterId!,
                            eventIdToUndo: ev.id,
                          );
                          messenger.showSnackBar(SnackBar(content: Text('Undo ${res.eventId} ${res.created ? 'created' : 'exists'}')));
                          // Refresh list to reflect reversal
                          await _refresh();
                        } catch (e) {
                          messenger.showSnackBar(SnackBar(content: Text('Undo failed: $e')));
                        }
                      },
                    )
                  : const Text('Reversed'),
            )),
      ],
    );
  }
}
