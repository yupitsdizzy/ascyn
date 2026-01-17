import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';

import 'package:ascyn/features/xp/data/xp_ledger_service.dart';
import 'package:ascyn/features/xp/domain/xp_event.dart';

void main() {
  test('undo reverses event and is idempotent across days', () async {
    final db = FakeFirebaseFirestore();
    final uid = 'testuid2';
    final characterId = 'charA';

    await db.collection('users').doc(uid).set({'created': true});
    await db.collection('users').doc(uid).collection('characters').doc(characterId).set({});

    final ledger = XpLedgerService(db);
    final now = DateTime.now();

    // Create a task event today
    final res1 = await ledger.recordTaskCompletion(
      uid: uid,
      characterId: characterId,
      taskId: 'undo_task_1',
      overallXp: 30.0,
      primaryStatName: 'focus',
      occurredAt: now,
    );

    expect(res1.created, true);

    // Verify character totals updated
    final charDoc = await db
        .collection('users')
        .doc(uid)
        .collection('characters')
        .doc(characterId)
        .get();
    expect((charDoc.data()!['overallXpTotal'] as num).toDouble(), 30.0);

    // Undo the event
    final undoRes = await ledger.undoEvent(
      uid: uid,
      characterId: characterId,
      eventIdToUndo: res1.eventId,
      undoWindowMinutes: 60,
    );

    expect(undoRes.created, true);

    // After undo, overall total should be back to 0
    final charDoc2 = await db
        .collection('users')
        .doc(uid)
        .collection('characters')
        .doc(characterId)
        .get();
    expect((charDoc2.data()!['overallXpTotal'] as num).toDouble(), 0.0);

    // Original event should be marked reversed
    final origEvent = await db
        .collection('users')
        .doc(uid)
        .collection('characters')
        .doc(characterId)
        .collection('xp_events')
        .doc(res1.eventId)
        .get();
    expect(origEvent.exists, true);
    expect(origEvent.data()!['status'], XpEventStatus.reversed.name);

    // Idempotency: same task on next day should create a new event
    final tomorrow = now.add(const Duration(days: 1));
    final resNextDay = await ledger.recordTaskCompletion(
      uid: uid,
      characterId: characterId,
      taskId: 'undo_task_1',
      overallXp: 30.0,
      primaryStatName: 'focus',
      occurredAt: tomorrow,
    );

    expect(resNextDay.created, true);
  });
}
