import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../../shared/data/firestore_refs.dart';
import '../../../shared/data/validators.dart';

class OnboardingController {
  OnboardingController({required this.auth, required this.db});

  final FirebaseAuth auth;
  final FirebaseFirestore db;

  Future<void> createProfile({
    required String username,
    required String displayName,
  }) async {
    final user = auth.currentUser;
    if (user == null) throw StateError('Not logged in.');

    final usernameErr = Validators.username(username);
    final displayErr = Validators.displayName(displayName);
    if (usernameErr != null) throw Exception(usernameErr);
    if (displayErr != null) throw Exception(displayErr);

    final usernameLower = Validators.normalizeUsername(username);

    final tz = DateTime.now().timeZoneName;

    final userRef = userDocRef(user);
    final unameRef = usernameDocRef(usernameLower);

    await db.runTransaction((tx) async {
      final existing = await tx.get(unameRef);
      if (existing.exists) throw Exception('Username is taken.');

      final now = FieldValue.serverTimestamp();

      tx.set(unameRef, {
        'uid': user.uid,
        'username': username,
        'createdAt': now,
      });

      tx.set(
        userRef,
        {
          'uid': user.uid,
          'email': user.email,
          'username': username,
          'usernameLower': usernameLower,
          'displayName': displayName,
          'timezone': tz,
          'createdAt': now,
          'updatedAt': now,
          'usernameLastChangedAt': now,
          'activeCharacterId': null,
        },
        SetOptions(merge: true),
      );
    });
  }
}
