import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';

import 'package:ascyn/features/xp/data/xp_ledger_service.dart';

void main() {
  test('recordTaskCompletion creates event and updates character totals', () async {
    final db = FakeFirebaseFirestore();
    final uid = 'testuid';
    final characterId = 'char1';

    // create base docs
    await db.collection('users').doc(uid).set({'created': true});
    await db.collection('users').doc(uid).collection('characters').doc(characterId).set({});

    final ledger = XpLedgerService(db);

    final now = DateTime.now();

    final res1 = await ledger.recordTaskCompletion(
      uid: uid,
      characterId: characterId,
      taskId: 'test_task_1',
      overallXp: 50.0,
      primaryStatName: 'discipline',
      occurredAt: now,
    );

    expect(res1.created, true);

    final eventsSnap = await db
        .collection('users')
        .doc(uid)
        .collection('characters')
        .doc(characterId)
        .collection('xp_events')
        .get();

    expect(eventsSnap.docs.length, 1);
    final ev = eventsSnap.docs.first.data();
    expect((ev['overallXp'] as num).toDouble(), 50.0);

    final charDoc = await db
        .collection('users')
        .doc(uid)
        .collection('characters')
        .doc(characterId)
        .get();

    final charData = charDoc.data()!;
    expect((charData['overallXpTotal'] as num).toDouble(), 50.0);

    // idempotency: calling again with same taskId + day should not create a second event
    final res2 = await ledger.recordTaskCompletion(
      uid: uid,
      characterId: characterId,
      taskId: 'test_task_1',
      overallXp: 50.0,
      primaryStatName: 'discipline',
      occurredAt: now,
    );

    expect(res2.created, false);
  });
}
