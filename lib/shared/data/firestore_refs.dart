import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

final _db = FirebaseFirestore.instance;

DocumentReference<Map<String, dynamic>> userDocRef(User user) =>
    _db.collection('users').doc(user.uid);

DocumentReference<Map<String, dynamic>> usernameDocRef(String usernameLower) =>
    _db.collection('usernames').doc(usernameLower);
