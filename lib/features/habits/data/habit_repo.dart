import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../xp/data/xp_ledger_service.dart';
import '../../xp/domain/ascyn_stat.dart';
import '../../xp/domain/xp_award.dart';
import '../../xp/domain/xp_engine.dart';
import '../../xp/domain/xp_event.dart';

enum HabitType { check, counter, timer }

class HabitRepo {
  HabitRepo(this.db, this.auth, this.xpLedger);

  final FirebaseFirestore db;
  final FirebaseAuth auth;
  final XpLedgerService xpLedger;

  DocumentReference<Map<String, dynamic>> _userRef() {
    final u = auth.currentUser;
    if (u == null) throw StateError('Not logged in');
    return db.collection('users').doc(u.uid);
  }

  Future<String> getActiveCharacterId() async {
    final snap = await _userRef().get();
    final id = snap.data()?['activeCharacterId'] as String?;
    if (id == null || id.isEmpty) {
      throw Exception('No active character selected.');
    }
    return id;
  }

  CollectionReference<Map<String, dynamic>> _habitsRef(String charId) {
    return _userRef().collection('characters').doc(charId).collection('habits');
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> watchHabits(String charId) {
    return _habitsRef(charId).orderBy('createdAt', descending: false).snapshots();
  }

  Future<void> createHabit({
    required String charId,
    required String title,
    required HabitType type,
    required bool isDaily,
    required List<int> daysOfWeek, // 1..7 (Mon..Sun) if !isDaily
    required String primaryStat,
    String? secondaryStat,
  }) async {
    final t = title.trim();
    if (t.isEmpty) throw Exception('Enter a habit name.');
    if (t.length > 40) throw Exception('Max 40 characters.');

    final now = FieldValue.serverTimestamp();

    await _habitsRef(charId).add({
      'title': t,
      'type': type.name,
      'schedule': {
        'isDaily': isDaily,
        'daysOfWeek': isDaily ? <int>[] : daysOfWeek,
      },
      'stats': {
        'primary': primaryStat,
        'secondary': secondaryStat,
      },
      'streak': {
        'count': 0,
        'lastDoneDate': null,
        'graceUsedDate': null,
      },
      'createdAt': now,
      'updatedAt': now,
    });
  }

  String dateKeyLocal(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  bool _scheduledForToday(Map<String, dynamic> habit, DateTime now) {
    final schedule = (habit['schedule'] ?? {}) as Map<String, dynamic>;
    final isDaily = (schedule['isDaily'] ?? true) as bool;
    if (isDaily) return true;

    final days = (schedule['daysOfWeek'] ?? []) as List<dynamic>;
    final set = days.map((e) => e as int).toSet(); // 1..7
    return set.contains(now.weekday);
  }

  int _daysBetween(DateTime a, DateTime b) {
    final aa = DateTime(a.year, a.month, a.day);
    final bb = DateTime(b.year, b.month, b.day);
    return bb.difference(aa).inDays;
  }

  DateTime? _parseDateKey(String? key) {
    if (key == null) return null;
    final parts = key.split('-');
    if (parts.length != 3) return null;
    return DateTime(
      int.parse(parts[0]),
      int.parse(parts[1]),
      int.parse(parts[2]),
    );
  }

  bool _graceAvailable(String? graceUsedDateKey, DateTime now) {
    final used = _parseDateKey(graceUsedDateKey);
    if (used == null) return true;
    return _daysBetween(used, now) >= 7;
  }

  List<AscynStat> _feedsFromHabit(Map<String, dynamic> habit) {
    final stats = (habit['stats'] ?? {}) as Map<String, dynamic>;
    final p = (stats['primary'] as String?)?.trim().toLowerCase();
    final s = (stats['secondary'] as String?)?.trim().toLowerCase();

    AscynStat? parse(String? raw) {
      if (raw == null || raw.isEmpty) return null;
      for (final st in AscynStat.values) {
        if (st.name == raw) return st;
      }
      return null;
    }

    final primary = parse(p) ?? AscynStat.discipline;
    final secondary = parse(s);

    return secondary == null ? [primary] : [primary, secondary];
  }

  /// Logs habit for today.
  /// Returns a warning string if grace was used.
  Future<String?> logHabit({
    required String charId,
    required String habitId,
    int? addCount,
    int? addMinutes,
  }) async {
    final habitRef = _habitsRef(charId).doc(habitId);
    final today = DateTime.now();
    final todayKey = dateKeyLocal(today);

    final u = auth.currentUser;
    if (u == null) throw StateError('Not logged in');
    final uid = u.uid;

    return db.runTransaction((tx) async {
      // ---------- READS FIRST ----------
      final habitSnap = await tx.get(habitRef);
      if (!habitSnap.exists) throw Exception('Habit not found.');
      final habit = habitSnap.data()!;

      if (!_scheduledForToday(habit, today)) {
        throw Exception('This habit is not scheduled for today.');
      }

      final typeStr = (habit['type'] ?? 'check') as String;
      final type = HabitType.values.firstWhere(
        (e) => e.name == typeStr,
        orElse: () => HabitType.check,
      );

      final logRef = habitRef.collection('logs').doc(todayKey);
      final logSnap = await tx.get(logRef);

      final streak = (habit['streak'] ?? {}) as Map<String, dynamic>;
      final lastDoneKey = streak['lastDoneDate'] as String?;
      final graceUsedKey = streak['graceUsedDate'] as String?;

      // streak math
      String? warning;
      final lastDoneDate = _parseDateKey(lastDoneKey);
      final isDaily = ((habit['schedule'] ?? {}) as Map<String, dynamic>)['isDaily'] as bool? ?? true;

      int newStreak = (streak['count'] as int?) ?? 0;

      if (lastDoneDate == null) {
        newStreak = 1;
      } else {
        final daysDiff = _daysBetween(lastDoneDate, today);
        final missed = isDaily ? (daysDiff >= 2) : (daysDiff >= 8);

        if (daysDiff == 0) {
          // same day
        } else if (!missed) {
          newStreak += 1;
        } else {
          if (_graceAvailable(graceUsedKey, today)) {
            newStreak += 1;
            warning = 'Grace used: miss another scheduled day in the next 7 days and your streak will reset.';
          } else {
            newStreak = 1;
          }
        }
      }

      final logData = logSnap.data() ?? <String, dynamic>{};
      final alreadyCount = (logData['count'] as int?) ?? 0;
      final alreadyMinutes = (logData['minutes'] as int?) ?? 0;

      final repeatSameDay = logSnap.exists;
      final feeds = _feedsFromHabit(habit);

      late final XpAward award;
      late final XpSourceType sourceType;

      if (type == HabitType.check) {
        sourceType = XpSourceType.habitCheck;
        award = XpEngine.habitCheck(
          repeatSameDay: repeatSameDay,
          feeds: feeds,
        );
      } else if (type == HabitType.counter) {
        sourceType = XpSourceType.habitCounter;
        award = XpEngine.habitCounter(
          amountLogged: (addCount ?? 1),
          alreadyLoggedToday: alreadyCount,
          dailyCap: 20,
          xpPerUnit: 5.0,
          feeds: feeds,
        );
      } else {
        sourceType = XpSourceType.habitTimer;
        award = XpEngine.habitTimer(
          minutesLogged: (addMinutes ?? 0),
          minutesAlreadyToday: alreadyMinutes,
          feeds: feeds,
        );
      }

      // Idempotent event id for NO double XP.
      // For check habits: event blocks repeats entirely.
      // For counter/timer: we still want multiple logs to credit remaining units,
      // so we include the day + sourceType ONLY (single event) would block.
      // Therefore we make counter/timer event id include a rolling index using log totals AFTER write is messy.
      //
      // SIMPLE RULE for now (A): block repeat XP for CHECK only.
      // Counter/timer rely on engine caps and are meant to be incremental.
      final shouldBlockRepeatXp = (type == HabitType.check);

      // Delegate event id selection and idempotency policy to ledger.
      await xpLedger.recordHabitEventInTransaction(
        tx: tx,
        uid: uid,
        characterId: charId,
        habitId: habitId,
        sourceType: sourceType,
        award: award,
        occurredAt: today,
        blockRepeatForCheck: shouldBlockRepeatXp,
      );

      // ---------- WRITES AFTER READS ----------
      final nowTs = FieldValue.serverTimestamp();

      if (!logSnap.exists) {
        final data = <String, dynamic>{
          'date': todayKey,
          'type': type.name,
          'createdAt': nowTs,
          'updatedAt': nowTs,
        };

        if (type == HabitType.check) {
          data['done'] = true;
        } else if (type == HabitType.counter) {
          data['count'] = (addCount ?? 1);
        } else {
          final minutes = (addMinutes ?? 0);
          data['minutes'] = minutes.clamp(0, 240);
        }

        tx.set(logRef, data);
      } else {
        final log = logSnap.data()!;
        if (type == HabitType.check) {
          tx.set(logRef, {'done': true, 'updatedAt': nowTs}, SetOptions(merge: true));
        } else if (type == HabitType.counter) {
          final current = (log['count'] as int?) ?? 0;
          tx.set(
            logRef,
            {'count': current + (addCount ?? 1), 'updatedAt': nowTs},
            SetOptions(merge: true),
          );
        } else {
          final current = (log['minutes'] as int?) ?? 0;
          final next = (current + (addMinutes ?? 0)).clamp(0, 240);
          tx.set(logRef, {'minutes': next, 'updatedAt': nowTs}, SetOptions(merge: true));
        }
      }

      tx.set(
        habitRef,
        {
          'streak': {
            'count': newStreak,
            'lastDoneDate': todayKey,
            'graceUsedDate': warning != null ? todayKey : graceUsedKey,
          },
          'updatedAt': nowTs,
        },
        SetOptions(merge: true),
      );

      return warning;
    });
  }
}
