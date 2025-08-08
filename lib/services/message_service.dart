import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';

class ChatService {
  final _firestore = FirebaseFirestore.instance;
  final _uuid = const Uuid();

  /// Send a message from senderUsername to receiverUsername
  Future<void> sendMessage({
    required String senderUsername,
    required String receiverUsername,
    required String text,
    String? memeUrl, // Optional meme URL
  }) async {
    try {
      final sorted = _getChatId(senderUsername, receiverUsername);
      final chatRef = _firestore
          .collection('chats')
          .doc(sorted)
          .collection('messages');

      final timestamp = Timestamp.now();
      final expiresAt = Timestamp.fromDate(
        DateTime.now().add(Duration(hours: 24)),
      ); // 24 hours expiration

      // Save the message
      await chatRef.add({
        'text': text,
        'senderUsername': senderUsername,
        'receiverUsername': receiverUsername,
        'timestamp': timestamp,
        'expiresAt': expiresAt,
        'memeUrl': memeUrl, // Store meme URL if provided
      });

      // Add a notification to the receiver
      await _firestore
          .collection('users')
          .doc(receiverUsername)
          .collection('notifications')
          .add({
            "id": _uuid.v4(),
            "type": "new_message",
            "fromUsername": senderUsername,
            "timestamp": FieldValue.serverTimestamp(),
          });

      print('✅ Message sent and notification created.');
    } catch (e) {
      print('❌ Error sending message: $e');
      rethrow;
    }
  }

  /// Get messages between two users, ordered by timestamp descending
  Future<List<Map<String, dynamic>>> getMessages({
    required String user1,
    required String user2,
  }) async {
    final snapshot =
        await _firestore
            .collection('chats')
            .doc(_getChatId(user1, user2))
            .collection('messages')
            .where(
              'expiresAt',
              isGreaterThan: Timestamp.now(),
            ) // Only get messages that haven't expired
            .orderBy('timestamp', descending: true)
            .get();

    return snapshot.docs.map((doc) {
      final data = doc.data();
      return {
        'messageId': doc.id, // Use document ID as messageId
        'from': data['senderUsername'],
        'to': data['receiverUsername'],
        'text': data['text'],
        'timestamp': data['timestamp'],
        'memeUrl': data['memeUrl'], // Include meme URL if available
      };
    }).toList();
  }

  /// Stream messages between two users in real-time
  Stream<List<Map<String, dynamic>>> streamMessages({
    required String username1,
    required String username2,
  }) {
    final sorted = _getChatId(username1, username2);

    return _firestore
        .collection('chats')
        .doc(sorted)
        .collection('messages')
        .where(
          'expiresAt',
          isGreaterThan: Timestamp.now(),
        ) // Only stream messages that haven't expired
        .orderBy('timestamp', descending: false)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs.map((doc) {
            final data = doc.data();
            return {
              'text': data['text'] ?? '',
              'senderUsername': data['senderUsername'] ?? '',
              'receiverUsername': data['receiverUsername'] ?? '',
              'timestamp': data['timestamp'] ?? Timestamp.now(),
              'expiresAt': data['expiresAt'] ?? Timestamp.now(),
              'memeUrl': data['memeUrl'], // Include meme URL if available
            };
          }).toList();
        });
  }

  /// Generate consistent chat ID
  String _getChatId(String a, String b) {
    final sorted = [a, b]..sort();
    return '${sorted[0]}_${sorted[1]}';
  }
}
