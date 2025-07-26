import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:uuid/uuid.dart';

class MemeService {
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;
  final _uuid = const Uuid();

  // Fetch a single random meme
  Future<Map<String, dynamic>?> fetchRandomMeme() async {
    try {
      final snapshot = await _firestore.collection('memes').get();
      final docs = snapshot.docs;
      if (docs.isEmpty) {
        print('❌ No memes found in collection');
        return null;
      }

      final randomDoc =
          docs[DateTime.now().millisecondsSinceEpoch % docs.length];
      final data = randomDoc.data();

      final memeData = {
        'memeId': randomDoc.id,
        'imageUrl': data['imageUrl'],
        'shareCount': data['shareCount'] ?? 0,
      };
      print('✅ Fetched meme: $memeData');
      return memeData;
    } catch (e) {
      print('❌ Error fetching meme: $e');
      return null;
    }
  }

  // Increment share count and notify receiver
  Future<void> shareMeme({
    required String memeId,
    required String senderUsername,
    required String receiverUsername,
    required String imageUrl,
  }) async {
    final senderUid = _auth.currentUser?.uid;
    if (senderUid == null) {
      print('❌ No authenticated user');
      return;
    }

    // Validate usernames
    if (senderUsername.isEmpty || receiverUsername.isEmpty) {
      print(
        '❌ Empty username: sender=$senderUsername, receiver=$receiverUsername',
      );
      return;
    }
    if (receiverUsername.contains(RegExp(r'^[a-zA-Z0-9]{20,}$'))) {
      print('❌ receiverUsername appears to be a UID: $receiverUsername');
      // Attempt to fetch username from UID
      try {
        final userDoc =
            await _firestore.collection('users').doc(receiverUsername).get();
        if (userDoc.exists && userDoc['username'] != null) {
          print(
            '🔄 Converting UID $receiverUsername to username ${userDoc['username']}',
          );
          receiverUsername = userDoc['username'];
        } else {
          print('❌ No username found for UID: $receiverUsername');
          return;
        }
      } catch (e) {
        print('❌ Error fetching username for UID $receiverUsername: $e');
        return;
      }
    }

    final chatId = _getChatId(senderUsername, receiverUsername);
    // Fetch receiver's UID for notifications
    try {
      final receiverQuery =
          await _firestore
              .collection('users')
              .where('username', isEqualTo: receiverUsername)
              .limit(1)
              .get();
      final receiverUid =
          receiverQuery.docs.isNotEmpty ? receiverQuery.docs.first.id : null;
      if (receiverUid == null) {
        print('❌ Receiver UID not found for username: $receiverUsername');
        return;
      }

      // Increment share count
      final memeRef = _firestore.collection('memes').doc(memeId);
      await memeRef.update({'shareCount': FieldValue.increment(1)});
      print('✅ Incremented shareCount for memeId=$memeId');

      // Add message to chat
      final messageData = {
        'senderUid': senderUid,
        'text': '',
        'memeUrl': imageUrl,
        'timestamp': FieldValue.serverTimestamp(),
        'expiresAt': Timestamp.fromDate(
          DateTime.now().add(const Duration(hours: 24)),
        ),
      };
      print('📤 Sending meme to chats/$chatId/messages: $messageData');
      await _firestore.collection('chats').doc(chatId).set({
        'lastUpdated': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      final messageRef = await _firestore
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .add(messageData);
      print(
        '✅ Shared meme to room=$chatId, messageId=${messageRef.id}, url=$imageUrl',
      );

      // Create notification for receiver
      await _firestore
          .collection('users')
          .doc(receiverUid)
          .update({
            'notifications': FieldValue.arrayUnion([
              {
                'from': senderUsername,
                'type': 'meme_share',
                'memeId': memeId,
                'timestamp': Timestamp.fromDate(DateTime.now()),
                'seen': false,
              }
            ])
          });
      print('✅ Sent notification to $receiverUsername (uid=$receiverUid)');
    } catch (e) {
      print('❌ Error in shareMeme: $e');
      if (e.toString().contains('permission-denied')) {
        // print(
        //   '⚠️ Check Firestore rules for chats/$chatId/messages and users/$receiverUid/notifications',
        // );
      }
    }
  }

  String _getChatId(String a, String b) {
    final sorted = [a, b]..sort();
    final chatId = '${sorted[0]}_${sorted[1]}';
    print('🔗 Generated chatId: $chatId (a=$a, b=$b)');
    return chatId;
  }
}
