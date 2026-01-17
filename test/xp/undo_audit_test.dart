import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';

import 'package:ascyn/features/xp/data/xp_ledger_service.dart';

void main() {
  test('undo writes undoNote on reversal and original event', () async {
    final db = FakeFirebaseFirestore();
    final uid = 'undoTester';
    final characterId = 'charUndo';

    await db.collection('users').doc(uid).set({'created': true});
    await db.collection('users').doc(uid).collection('characters').doc(characterId).set({});

    final ledger = XpLedgerService(db);

    final now = DateTime.now();

    final res = await ledger.recordTaskCompletion(
      uid: uid,
      characterId: characterId,
      taskId: 'audit_task_1',
      overallXp: 20.0,
      primaryStatName: 'strength',
      occurredAt: now,
    );

    expect(res.created, true);

    final undoRes = await ledger.undoEvent(
      uid: uid,
      characterId: characterId,
      eventIdToUndo: res.eventId,
      undoWindowMinutes: 60,
    );

    expect(undoRes.created, true);

    final eventsColl = db.collection('users').doc(uid).collection('characters').doc(characterId).collection('xp_events');

    final orig = await eventsColl.doc(res.eventId).get();
    expect(orig.exists, true);
    final origData = orig.data()!;
    expect(origData['status'], 'reversed');
    expect(origData['reversedBy'], undoRes.eventId);
    expect(origData['undoNote'], 'Reversed by ${undoRes.eventId}');

    final rev = await eventsColl.doc(undoRes.eventId).get();
    expect(rev.exists, true);
    final revData = rev.data()!;
    expect(revData['undoNote'], 'Undo of ${res.eventId}');
    expect(revData['reversesEventId'], res.eventId);
  });
}
