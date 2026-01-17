import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/xp_ledger_service.dart';

final firestoreProvider = Provider<FirebaseFirestore>((ref) {
  return FirebaseFirestore.instance;
});

final xpLedgerServiceProvider = Provider<XpLedgerService>((ref) {
  final db = ref.read(firestoreProvider);
  return XpLedgerService(db);
});
