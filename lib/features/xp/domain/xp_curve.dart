import 'dart:math';

/// Overall account/character level curve (1..99) based on total XP.
/// Simple smooth scaling: fast early, steeper after ~15-20.
class XpCurve {
  static const int maxLevel = 99;

  // XP required to go from (level) -> (level+1)
  static double xpForNextLevel(int level) {
    // level is current level (1..98)
    // Tuned to feel quick early and scale smoothly.
    final l = level.toDouble();
    return 60.0 + (35.0 * pow(l, 1.35));
  }

  static double totalXpToReachLevel(int level) {
    // total XP required to be at `level` (level 1 requires 0)
    if (level <= 1) return 0.0;
    double sum = 0.0;
    for (int l = 1; l < level; l++) {
      sum += xpForNextLevel(l);
    }
    return sum;
  }

  static int levelFromTotalXp(double totalXp) {
    if (totalXp <= 0) return 1;
    int level = 1;
    while (level < maxLevel) {
      final nextReq = totalXpToReachLevel(level + 1);
      if (totalXp + 1e-9 >= nextReq) {
        level++;
      } else {
        break;
      }
    }
    return level;
  }
}

/// Stat curve per-stat (1..99) based on total stat XP.
class StatCurve {
  static const int maxLevel = 99;

  static double xpForNextStatLevel(int statLevel) {
    // Slightly lighter than overall leveling.
    final l = statLevel.toDouble();
    return 30.0 + (18.0 * pow(l, 1.30));
  }

  static double totalXpToReachStatLevel(int statLevel) {
    if (statLevel <= 1) return 0.0;
    double sum = 0.0;
    for (int l = 1; l < statLevel; l++) {
      sum += xpForNextStatLevel(l);
    }
    return sum;
  }

  static int statLevelFromXp(double statXp) {
    if (statXp <= 0) return 1;
    int level = 1;
    while (level < maxLevel) {
      final nextReq = totalXpToReachStatLevel(level + 1);
      if (statXp + 1e-9 >= nextReq) {
        level++;
      } else {
        break;
      }
    }
    return level;
  }
}
