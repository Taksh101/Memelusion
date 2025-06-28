import 'package:cloud_firestore/cloud_firestore.dart';

class NotificationService {
  final _firestore = FirebaseFirestore.instance;

  // Fetch all notifications for a user, ordered by timestamp descending
  Future<List<Map<String, dynamic>>> getNotifications(String username) async {
    final snapshot =
        await _firestore
            .collection('users')
            .doc(username)
            .collection('notifications')
            .orderBy('timestamp', descending: true)
            .get();

    return snapshot.docs.map((doc) {
      return {
        'id': doc['id'],
        'type': doc['type'],
        'fromUsername': doc['fromUsername'],
        'memeId': doc.data().containsKey('memeId') ? doc['memeId'] : null,
        'timestamp': doc['timestamp'],
      };
    }).toList();
  }
}
