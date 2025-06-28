import 'package:cloud_firestore/cloud_firestore.dart';

class UserProfileService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Create a new user profile in Firestore
  Future<void> createUserProfile({
    required String uid,
    required String username,
  }) async {
    await _firestore.collection('users').doc(uid).set({
      'uid': uid,
      'username': username,
      'profilePic': '',
      'friends': [],
      'friendRequests': [],
      'isAdmin': false,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  // Fetch a user profile
  Future<DocumentSnapshot> getUserProfile(String uid) async {
    return await _firestore.collection('users').doc(uid).get();
  }

  // Update username or profile pic
  Future<void> updateUserProfile({
    required String uid,
    String? username,
    String? profilePic,
  }) async {
    Map<String, dynamic> updates = {};
    if (username != null) updates['username'] = username;
    if (profilePic != null) updates['profilePic'] = profilePic;

    await _firestore.collection('users').doc(uid).update(updates);
  }
}
