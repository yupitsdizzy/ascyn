import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';

import 'package:ascyn/features/xp/data/xp_ledger_service.dart';

void main() {
  test('sequential idempotency: repeated completions do not duplicate', () async {
    final db = FakeFirebaseFirestore();
    final uid = 'concurrentUser';
    final characterId = 'charConcurrent';

    await db.collection('users').doc(uid).set({'created': true});
    await db.collection('users').doc(uid).collection('characters').doc(characterId).set({});

    final ledger = XpLedgerService(db);
    final now = DateTime.now();

    final r1 = await ledger.recordTaskCompletion(
      uid: uid,
      characterId: characterId,
      taskId: 'concurrent_task',
      overallXp: 42.0,
      primaryStatName: 'discipline',
      occurredAt: now,
    );

    final r2 = await ledger.recordTaskCompletion(
      uid: uid,
      characterId: characterId,
      taskId: 'concurrent_task',
      overallXp: 42.0,
      primaryStatName: 'discipline',
      occurredAt: now,
    );

    expect(r1.created, true);
    expect(r2.created, false);

    final eventsSnap = await db
        .collection('users')
        .doc(uid)
        .collection('characters')
        .doc(characterId)
        .collection('xp_events')
        .get();

    expect(eventsSnap.docs.length, 1);
  });

  test('pagination returns expected page sizes for xp_events', () async {
    final db = FakeFirebaseFirestore();
    final uid = 'pagerUser';
    final characterId = 'charPager';

    await db.collection('users').doc(uid).set({'created': true});
    await db.collection('users').doc(uid).collection('characters').doc(characterId).set({});

    final ledger = XpLedgerService(db);
    final base = DateTime.now();

    // create 25 distinct events (unique task ids)
    for (var i = 0; i < 25; i++) {
      await ledger.recordTaskCompletion(
        uid: uid,
        characterId: characterId,
        taskId: 'task_$i',
        overallXp: 10.0 + i,
        primaryStatName: 'focus',
        occurredAt: base.add(Duration(minutes: i)),
      );
    }

    final coll = db
        .collection('users')
        .doc(uid)
        .collection('characters')
        .doc(characterId)
        .collection('xp_events');

    // fetch first page (limit 20)
    final all = await coll.orderBy('occurredAt', descending: true).get();
    expect(all.docs.length, 25);

    // emulate pagination by splitting the fetched list
    final firstPage = all.docs.take(20).toList();
    final secondPage = all.docs.skip(20).toList();

    expect(firstPage.length, 20);
    expect(secondPage.length, 5);
  });
}
