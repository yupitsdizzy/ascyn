import 'package:flutter_test/flutter_test.dart';
import 'package:ascyn/features/xp/domain/xp_engine.dart';
import 'package:ascyn/features/xp/domain/ascyn_stat.dart';

void main() {
  test('habitCheck repeat gives 50% XP on repeat', () {
    final feeds = [AscynStat.discipline];
    final first = XpEngine.habitCheck(repeatSameDay: false, feeds: feeds);
    final repeat = XpEngine.habitCheck(repeatSameDay: true, feeds: feeds);

    expect(repeat.overallXp, equals(first.overallXp * 0.5));
    expect(repeat.statXp[feeds.first], equals(first.statXp[feeds.first]! * 0.5));
  });

  test('habitTimer caps minutes at 240 and computes XP', () {
    final feeds = [AscynStat.endurance];
    final award = XpEngine.habitTimer(minutesLogged: 300, minutesAlreadyToday: 0, feeds: feeds);
    // 300 should be capped to 240 -> xp = 240 * timerXpPerMinute (0.5)
    expect(award.overallXp, equals(240 * 0.5));
  });

  test('habitCounter honors daily cap and xp per unit', () {
    final feeds = [AscynStat.discipline];
    final award = XpEngine.habitCounter(
      amountLogged: 10,
      alreadyLoggedToday: 15,
      dailyCap: 20,
      xpPerUnit: 5.0,
      feeds: feeds,
    );
    // remaining = 5, creditedUnits = min(10,5) = 5 -> xp = 5 * 5.0 = 25
    expect(award.overallXp, equals(25));
  });
}
