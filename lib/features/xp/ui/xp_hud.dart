import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../domain/ascyn_stat.dart';

class XpHud extends StatelessWidget {
  const XpHud({
    super.key,
    required this.characterDocStream,
  });

  final Stream<DocumentSnapshot<Map<String, dynamic>>> characterDocStream;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: characterDocStream,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const _HudShell(child: Center(child: CircularProgressIndicator()));
        }

        final data = snap.data?.data();
        if (data == null) {
          return const _HudShell(
            child: Center(child: Text('No character data yet.')),
          );
        }

        final overallXpTotal = (data['overallXpTotal'] as num?)?.toDouble() ?? 0.0;
        final overallLevel = (data['overallLevel'] as int?) ?? 1;

        final levelsRaw = (data['statLevels'] as Map<String, dynamic>?) ?? <String, dynamic>{};

        int levelOf(AscynStat s) => (levelsRaw[s.name] as int?) ?? 1;

        // Pick top 3 stats by level (simple + readable)
        final ranked = AscynStat.values.toList()
          ..sort((a, b) => levelOf(b).compareTo(levelOf(a)));

        final top3 = ranked.take(3).toList();

        return _HudShell(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Level $overallLevel',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 4),
              Text(
                'Overall XP: ${overallXpTotal.toStringAsFixed(0)}',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final s in top3)
                    _StatChip(
                      label: s.name, // your enum names are already nice
                      level: levelOf(s),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _HudShell extends StatelessWidget {
  const _HudShell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: child,
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({required this.label, required this.level});

  final String label;
  final int level;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: () {
          // Navigate to characters overview when tapping a stat chip.
          context.go('/characters');
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            border: Border.all(color: Theme.of(context).dividerColor),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text('$label: Lv $level'),
        ),
      ),
    );
  }
}
