import 'package:cloud_firestore/cloud_firestore.dart';

import '../domain/ascyn_stat.dart';
import '../domain/xp_award.dart';
import '../domain/xp_curve.dart';
import '../domain/xp_event.dart';

class EnsureEventResult {
  const EnsureEventResult({
    required this.eventId,
    required this.created,
  });

  final String eventId;
  final bool created;
}

class XpLedgerService {
  XpLedgerService(this.db);

  final FirebaseFirestore db;

  DocumentReference<Map<String, dynamic>> _characterRef(String uid, String characterId) {
    return db.collection('users').doc(uid).collection('characters').doc(characterId);
  }

  CollectionReference<Map<String, dynamic>> _eventsRef(String uid, String characterId) {
    return db
        .collection('users')
        .doc(uid)
        .collection('characters')
        .doc(characterId)
        .collection('xp_events');
  }

  String _dateKeyLocal(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  /// Use a 3:00 AM local boundary for day keys (returns YYYY-MM-DD).
  /// If the local time is before 3:00, we treat it as the previous day.
  String dayKeyWith3amBoundary(DateTime localDt) {
    final adjusted = (localDt.hour < 3) ? localDt.subtract(const Duration(days: 1)) : localDt;
    return _dateKeyLocal(adjusted);
  }

  /// Static variant usable in tests without instantiating the service.
  static String dayKeyWith3amBoundaryStatic(DateTime localDt) {
    final adjusted = (localDt.hour < 3) ? localDt.subtract(const Duration(days: 1)) : localDt;
    final y = adjusted.year.toString().padLeft(4, '0');
    final m = adjusted.month.toString().padLeft(2, '0');
    final d = adjusted.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  /// Record a task completion as a single xp_event and update aggregates.
  /// `overallXp` is the total XP awarded for the task. `primary` and
  /// optional `secondary` control stat XP distribution (70/30 split).
  /// Returns the EnsureEventResult for the created event (or existing event).
  Future<EnsureEventResult> recordTaskCompletion({
    required String uid,
    required String characterId,
    required String taskId,
    required double overallXp,
    required String primaryStatName,
    String? secondaryStatName,
    DateTime? occurredAt,
  }) async {
    final now = occurredAt ?? DateTime.now();
    final eventId = 'task_${taskId}_${_dateKeyLocal(now)}';

    final statMap = <dynamic, double>{};
    // Simple stat split: primary gets 100% if no secondary; else 70/30.
    if (secondaryStatName == null || secondaryStatName.isEmpty) {
      statMap[primaryStatName] = overallXp;
    } else {
      statMap[primaryStatName] = overallXp * 0.7;
      statMap[secondaryStatName] = overallXp * 0.3;
    }

    final award = XpAward(
      overallXp: overallXp,
      statXp: statMap.map((k, v) {
        // Convert stat keys to AscynStat where possible; store as dynamic map
        // and let ensureEventInTransaction convert via names later.
        return MapEntry(k.toString(), v);
      }).cast(),
      note: 'Task complete',
    );

    // run transaction and use existing ensureEventInTransaction
    return await db.runTransaction((tx) async {
      // ensureEventInTransaction expects AscynStat keys in award.statXp,
      // but here we have string keys; convert within a tiny wrapper call.

      // Build a new XpAward with AscynStat keys where possible.
      // Map string stat names to AscynStat where possible; fall back to discipline.
      AscynStat parseStat(String name) {
        for (final s in AscynStat.values) {
          if (s.name == name) return s;
        }
        return AscynStat.discipline;
      }

      final statXpFinal = <AscynStat, double>{};
      for (final e in statMap.entries) {
        final st = parseStat(e.key.toString());
        statXpFinal[st] = (statXpFinal[st] ?? 0.0) + e.value;
      }

      final awardFinal = XpAward(
        overallXp: award.overallXp,
        statXp: statXpFinal,
        note: award.note,
      );

      final res = await ensureEventInTransaction(
        tx: tx,
        uid: uid,
        characterId: characterId,
        eventId: eventId,
        sourceType: XpSourceType.taskComplete,
        sourceId: taskId,
        award: awardFinal,
        occurredAt: occurredAt,
      );

      return res;
    });
  }

  /// Undo an event by creating a compensating negative xp_event inside a
  /// transaction. Undo is only allowed within [undoWindowMinutes].
  Future<EnsureEventResult> undoEvent({
    required String uid,
    required String characterId,
    required String eventIdToUndo,
    int undoWindowMinutes = 15,
  }) async {
    final events = _eventsRef(uid, characterId);
    final targetRef = events.doc(eventIdToUndo);

    return await db.runTransaction((tx) async {
      final targetSnap = await tx.get(targetRef);
      if (!targetSnap.exists) throw Exception('Event not found');
      final target = XpEvent.fromDoc(targetSnap);

      // Only active events can be undone.
      if (target.status != XpEventStatus.active) {
        throw Exception('Event not undoable (not active)');
      }

      final age = DateTime.now().difference(target.occurredAt);
      if (age.inMinutes > undoWindowMinutes) {
        throw Exception('Undo window expired');
      }

      // Build reversal award with negative values.
      final negStat = <AscynStat, double>{};
      for (final e in target.statXp.entries) {
        negStat[e.key] = -e.value;
      }

      final reversalAward = XpAward(
        overallXp: -target.overallXp,
        statXp: negStat,
        note: 'Undo of $eventIdToUndo',
      );

      // reversal event id should be unique and descriptive.
      final reversalId = 'undo_${eventIdToUndo}_${DateTime.now().millisecondsSinceEpoch}';

      final res = await ensureEventInTransaction(
        tx: tx,
        uid: uid,
        characterId: characterId,
        eventId: reversalId,
        sourceType: XpSourceType.undoReversal,
        sourceId: eventIdToUndo,
        award: reversalAward,
        occurredAt: DateTime.now(),
      );

      // Annotate the reversal event and the original event with an undo note
      final events = _eventsRef(uid, characterId);
      final reversalRef = events.doc(reversalId);
      tx.set(
        reversalRef,
        {
          'undoNote': 'Undo of $eventIdToUndo',
          'reversesEventId': eventIdToUndo,
        },
        SetOptions(merge: true),
      );

      // mark original event as reversed for bookkeeping
      tx.set(
        targetRef,
        {
          'status': XpEventStatus.reversed.name,
          'reversedBy': reversalId,
          'undoNote': 'Reversed by $reversalId',
        },
        SetOptions(merge: true),
      );

      return res;
    });
  }

  /// Idempotent transaction write:
  /// If event doc with [eventId] already exists, no XP is added.
  Future<EnsureEventResult> ensureEventInTransaction({
    required Transaction tx,
    required String uid,
    required String characterId,
    required String eventId,
    required XpSourceType sourceType,
    required String sourceId,
    required XpAward award,
    DateTime? occurredAt,
  }) async {
    final charRef = _characterRef(uid, characterId);
    final eventsRef = _eventsRef(uid, characterId);

    final now = occurredAt ?? DateTime.now();
    final eventRef = eventsRef.doc(eventId);

    // ---------- READS FIRST ----------
    final existingEventSnap = await tx.get(eventRef);
    if (existingEventSnap.exists) {
      return EnsureEventResult(eventId: eventId, created: false);
    }

    final charSnap = await tx.get(charRef);
    final charData = charSnap.data() ?? <String, dynamic>{};

    final overallXpTotal = (charData['overallXpTotal'] as num?)?.toDouble() ?? 0.0;

    final statXpRaw =
        (charData['statXpTotals'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    final statXpTotals = <AscynStat, double>{
      for (final s in AscynStat.values) s: (statXpRaw[s.name] as num?)?.toDouble() ?? 0.0,
    };

    // ---------- APPLY AWARD ----------
    final newOverallXpTotal = overallXpTotal + award.overallXp;

    final newStatXpTotals = Map<AscynStat, double>.from(statXpTotals);
    for (final entry in award.statXp.entries) {
      final current = newStatXpTotals[entry.key] ?? 0.0;
      newStatXpTotals[entry.key] = current + entry.value;
    }

    final newOverallLevel = XpCurve.levelFromTotalXp(newOverallXpTotal);

    // If you later add a separate stat curve, swap this line out.
    final newStatLevels = <AscynStat, int>{
      for (final s in AscynStat.values)
        s: XpCurve.levelFromTotalXp(newStatXpTotals[s] ?? 0.0),
    };

    // ---------- WRITE EVENT ----------
    final event = XpEvent(
      id: eventId,
      uid: uid,
      characterId: characterId,
      sourceType: sourceType,
      sourceId: sourceId,
      occurredAt: now,
      overallXp: award.overallXp,
      statXp: award.statXp,
      status: XpEventStatus.active,
      reversesEventId: null,
      note: award.note,
    );

    tx.set(eventRef, event.toMap());

    // ---------- UPDATE CHARACTER CACHE ----------
    tx.set(
      charRef,
      {
        'overallXpTotal': newOverallXpTotal,
        'overallLevel': newOverallLevel,
        'statXpTotals': newStatXpTotals.map((k, v) => MapEntry(k.name, v)),
        'statLevels': newStatLevels.map((k, v) => MapEntry(k.name, v)),
        'lastEventAt': Timestamp.fromDate(now),
        'lastEventNote': award.note, // cached for UI
        'lastEventId': eventId, // handy for debugging
      },
      SetOptions(merge: true),
    );

    return EnsureEventResult(eventId: eventId, created: true);
  }

  /// Habit event id: habit_{habitId}_{yyyy-mm-dd}_{sourceType}
  String habitEventId({
    required String habitId,
    required DateTime occurredAt,
    required XpSourceType sourceType,
  }) {
    final dayKey = _dateKeyLocal(occurredAt);
    return 'habit_${habitId}_${dayKey}_${sourceType.name}';
  }

  /// Convenience wrapper that chooses an event id for habit logs and
  /// delegates to `ensureEventInTransaction`.
  ///
  /// If [blockRepeatForCheck] is true, the method will use the deterministic
  /// habit event id to prevent double-awarding for check-type habits.
  /// Otherwise, a unique id will be generated so multiple events may be
  /// recorded in the same day (useful for counter/timer incremental logs).
  Future<EnsureEventResult> recordHabitEventInTransaction({
    required Transaction tx,
    required String uid,
    required String characterId,
    required String habitId,
    required XpSourceType sourceType,
    required XpAward award,
    required DateTime occurredAt,
    bool blockRepeatForCheck = false,
  }) async {
    final eventId = blockRepeatForCheck
        ? habitEventId(habitId: habitId, occurredAt: occurredAt, sourceType: sourceType)
        : db.collection('_').doc().id;

    return await ensureEventInTransaction(
      tx: tx,
      uid: uid,
      characterId: characterId,
      eventId: eventId,
      sourceType: sourceType,
      sourceId: habitId,
      award: award,
      occurredAt: occurredAt,
    );
  }
}
