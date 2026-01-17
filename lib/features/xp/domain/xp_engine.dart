import 'ascyn_stat.dart';
import 'xp_award.dart';

class XpEngine {
  static const double habitCheckBase = 25.0;
  static const double timerXpPerMinute = 0.5; // linear
  static const int timerCapMin = 240;

  static double _repeatModifier(double xp, bool repeatSameDay) {
    return repeatSameDay ? (xp * 0.5) : xp;
  }

  static Map<AscynStat, double> _splitToFeeds(double xp, List<AscynStat> feeds) {
    final safeFeeds = feeds.isEmpty ? [AscynStat.discipline] : feeds;
    if (safeFeeds.length == 1) {
      return {safeFeeds.first: xp};
    }
    // Primary gets 70%, secondary gets 30%
    final primary = safeFeeds[0];
    final secondary = safeFeeds[1];
    return {
      primary: xp * 0.7,
      secondary: xp * 0.3,
    };
  }

  /// Check habit: done/not done.
  static XpAward habitCheck({
    required bool repeatSameDay,
    required List<AscynStat> feeds,
  }) {
    final xp = _repeatModifier(habitCheckBase, repeatSameDay);
    return XpAward(
      overallXp: xp,
      statXp: _splitToFeeds(xp, feeds),
      note: repeatSameDay ? 'Habit check (repeat 50%)' : 'Habit check',
    );
  }

  /// Counter habit: times per day, with a daily cap.
  static XpAward habitCounter({
    required int amountLogged,
    required int alreadyLoggedToday,
    required int dailyCap,
    required double xpPerUnit,
    required List<AscynStat> feeds,
  }) {
    final remaining = (dailyCap - alreadyLoggedToday).clamp(0, dailyCap);
    final creditedUnits = amountLogged.clamp(0, remaining);
    final xp = creditedUnits * xpPerUnit;

    return XpAward(
      overallXp: xp,
      statXp: _splitToFeeds(xp, feeds),
      note: 'Habit counter +$creditedUnits (cap $dailyCap)',
    );
  }

  /// Timer habit: minutes, linear XP, max credit 240 minutes/day.
  static XpAward habitTimer({
    required int minutesLogged,
    required int minutesAlreadyToday,
    required List<AscynStat> feeds,
  }) {
    final remaining = (timerCapMin - minutesAlreadyToday).clamp(0, timerCapMin);
    final credited = minutesLogged.clamp(0, remaining);
    final xp = credited * timerXpPerMinute;

    return XpAward(
      overallXp: xp,
      statXp: _splitToFeeds(xp, feeds),
      note: 'Habit timer +$credited min (cap $timerCapMin)',
    );
  }
}
