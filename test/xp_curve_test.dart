import 'package:flutter_test/flutter_test.dart';
import 'package:ascyn/features/xp/domain/xp_curve.dart';

void main() {
  test('levelFromTotalXp is monotonic and within bounds', () {
    final levels = <int>[];
    for (var xp = 0.0; xp <= 100000.0; xp += 1234.5) {
      final level = XpCurve.levelFromTotalXp(xp);
      levels.add(level);
    }
    // non-decreasing
    for (var i = 1; i < levels.length; i++) {
      expect(levels[i] >= levels[i - 1], true);
    }
    // within 1..maxLevel
    for (final l in levels) {
      expect(l >= 1 && l <= XpCurve.maxLevel, true);
    }
  });
}
