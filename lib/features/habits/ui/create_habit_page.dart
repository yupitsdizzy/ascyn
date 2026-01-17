import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../xp/data/xp_ledger_service.dart';
import '../data/habit_repo.dart';

class CreateHabitPage extends StatefulWidget {
  const CreateHabitPage({super.key, required this.characterId});
  final String characterId;

  @override
  State<CreateHabitPage> createState() => _CreateHabitPageState();
}

class _CreateHabitPageState extends State<CreateHabitPage> {
  final TextEditingController titleCtrl = TextEditingController();

  HabitType type = HabitType.check;
  bool isDaily = true;
  final Set<int> days = {1, 2, 3, 4, 5};

  final List<String> statOptions = const [
    'strength',
    'endurance',
    'discipline',
    'creativity',
    'focus',
    'intelligence',
    'wellbeing',
  ];

  String primary = 'discipline';
  String? secondary;

  bool busy = false;

  @override
  void dispose() {
    titleCtrl.dispose();
    super.dispose();
  }

  String _dayLabel(int d) {
    switch (d) {
      case 1:
        return 'Mon';
      case 2:
        return 'Tue';
      case 3:
        return 'Wed';
      case 4:
        return 'Thu';
      case 5:
        return 'Fri';
      case 6:
        return 'Sat';
      case 7:
        return 'Sun';
      default:
        return '?';
    }
  }

  Future<void> _save() async {
    setState(() => busy = true);
    try {
      final db = FirebaseFirestore.instance;
      final repo = HabitRepo(db, FirebaseAuth.instance, XpLedgerService(db));

      await repo.createHabit(
        charId: widget.characterId,
        title: titleCtrl.text,
        type: type,
        isDaily: isDaily,
        daysOfWeek: days.toList()..sort(),
        primaryStat: primary,
        secondaryStat: secondary,
      );

      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('New habit'),
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
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: titleCtrl,
            decoration: const InputDecoration(labelText: 'Habit name'),
          ),
          const SizedBox(height: 16),

          DropdownButtonFormField<HabitType>(
            initialValue: type,
            decoration: const InputDecoration(labelText: 'Type'),
            items: const [
              DropdownMenuItem(value: HabitType.check, child: Text('Checkbox')),
              DropdownMenuItem(value: HabitType.counter, child: Text('Counter')),
              DropdownMenuItem(value: HabitType.timer, child: Text('Timer (minutes)')),
            ],
            onChanged: (v) => setState(() => type = v ?? HabitType.check),
          ),

          const SizedBox(height: 16),
          SwitchListTile(
            value: isDaily,
            onChanged: (v) => setState(() => isDaily = v),
            title: const Text('Daily'),
            subtitle: const Text('Turn off to choose specific days'),
          ),

          if (!isDaily) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: List.generate(7, (i) {
                final day = i + 1;
                final selected = days.contains(day);
                return FilterChip(
                  label: Text(_dayLabel(day)),
                  selected: selected,
                  onSelected: (on) {
                    setState(() {
                      if (on) {
                        days.add(day);
                      } else {
                        days.remove(day);
                      }
                    });
                  },
                );
              }),
            ),
          ],

          const SizedBox(height: 20),
          DropdownButtonFormField<String>(
            initialValue: primary,
            decoration: const InputDecoration(labelText: 'Primary stat'),
            items: statOptions
                .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                .toList(),
            onChanged: (v) => setState(() => primary = v ?? primary),
          ),

          const SizedBox(height: 12),
          SwitchListTile(
            value: secondary != null,
            onChanged: (v) => setState(() => secondary = v ? 'focus' : null),
            title: const Text('Use secondary stat (70/30)'),
          ),

          if (secondary != null) ...[
            DropdownButtonFormField<String>(
              initialValue: secondary,
              decoration: const InputDecoration(labelText: 'Secondary stat'),
              items: statOptions
                  .where((s) => s != primary)
                  .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                  .toList(),
              onChanged: (v) => setState(() => secondary = v),
            ),
          ],

          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: busy ? null : _save,
            child: const Text('Save habit'),
          ),
        ],
      ),
    );
  }
}
