import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';

class MemeService {
  final _firestore = FirebaseFirestore.instance;
  final _uuid = const Uuid();

  // Fetch a single random meme
  Future<Map<String, dynamic>?> fetchRandomMeme() async {
    final snapshot = await _firestore.collection('memes').get();
    final docs = snapshot.docs;
    if (docs.isEmpty) return null;

    final randomDoc = docs[DateTime.now().millisecondsSinceEpoch % docs.length];
    return {'memeId': randomDoc.id, ...randomDoc.data()};
  }

  // Increment share count and notify receiver
  Future<void> shareMeme({
    required String memeId,
    required String senderUsername,
    required String receiverUsername,
    required String imageUrl,
  }) async {
    final memeRef = _firestore.collection('memes').doc(memeId);

    await memeRef.update({'shareCount': FieldValue.increment(1)});

    // Add a message in chat
    final chatId = _getChatId(senderUsername, receiverUsername);
    await _firestore.collection('chats').doc(chatId).collection('messages').add(
      {
        'text': '[Meme]',
        'memeUrl': imageUrl,
        'senderUsername': senderUsername,
        'receiverUsername': receiverUsername,
        'timestamp': Timestamp.now(),
        'expiresAt': Timestamp.fromDate(DateTime.now().add(Duration(days: 30))),
      },
    );

    // Create notification for receiver
    await _firestore
        .collection('users')
        .doc(receiverUsername)
        .collection('notifications')
        .add({
          'id': _uuid.v4(),
          'type': 'meme_share',
          'fromUsername': senderUsername,
          'memeId': memeId,
          'timestamp': FieldValue.serverTimestamp(),
        });
  }

  String _getChatId(String a, String b) {
    final sorted = [a, b]..sort();
    return '${sorted[0]}_${sorted[1]}';
  }
}
