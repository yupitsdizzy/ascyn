import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class CharacterRepo {
  CharacterRepo(this.db, this.auth);

  final FirebaseFirestore db;
  final FirebaseAuth auth;

  DocumentReference<Map<String, dynamic>> _userRef() {
    final u = auth.currentUser;
    if (u == null) throw StateError('Not logged in');
    return db.collection('users').doc(u.uid);
  }

  CollectionReference<Map<String, dynamic>> _charsRef() {
    return _userRef().collection('characters');
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> watchCharacters() {
    return _charsRef().orderBy('createdAt', descending: false).snapshots();
  }

  Future<void> createCharacter({
    required String name,
    required bool setActive,
  }) async {
    final n = name.trim();
    if (n.isEmpty) throw Exception('Enter a character name.');

    final now = FieldValue.serverTimestamp();
    final doc = await _charsRef().add({
      'name': n,
      'overallXpTotal': 0.0,
      'overallLevel': 1,
      'statLevels': <String, dynamic>{},
      'createdAt': now,
      'updatedAt': now,
    });

    if (setActive) {
      await setActiveCharacter(doc.id);
    }
  }

  Future<void> setActiveCharacter(String characterId) async {
    await _userRef().set(
      {'activeCharacterId': characterId, 'updatedAt': FieldValue.serverTimestamp()},
      SetOptions(merge: true),
    );
  }
}
