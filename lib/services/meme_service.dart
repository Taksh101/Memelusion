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

    // Log call to track invocations with unique call ID
    final callId = DateTime.now().millisecondsSinceEpoch;
    print(
      '🔄 shareMeme called [$callId]: memeId=$memeId, sender=$senderUsername, receiver=$receiverUsername',
    );

    // Validate usernames
    if (senderUsername.isEmpty || receiverUsername.isEmpty) {
      print(
        '❌ [$callId] Empty username: sender=$senderUsername, receiver=$receiverUsername',
      );
      return;
    }
    if (senderUsername == receiverUsername) {
      print(
        '❌ [$callId] Cannot share meme to self: sender=$senderUsername, receiver=$receiverUsername',
      );
      return;
    }

    String updatedReceiverUsername = receiverUsername;
    if (receiverUsername.contains(RegExp(r'^[a-zA-Z0-9]{20,}$'))) {
      print(
        '❌ [$callId] receiverUsername appears to be a UID: $receiverUsername',
      );
      try {
        final userDoc =
            await _firestore.collection('users').doc(receiverUsername).get();
        if (userDoc.exists && userDoc['username'] != null) {
          print(
            '🔄 [$callId] Converting UID $receiverUsername to username ${userDoc['username']}',
          );
          updatedReceiverUsername = userDoc['username'];
        } else {
          print('❌ [$callId] No username found for UID: $receiverUsername');
          return;
        }
      } catch (e) {
        print(
          '❌ [$callId] Error fetching username for UID $receiverUsername: $e',
        );
        return;
      }
    }

    if (senderUsername == updatedReceiverUsername) {
      print(
        '❌ [$callId] Cannot share meme to self after UID conversion: sender=$senderUsername, receiver=$updatedReceiverUsername',
      );
      return;
    }

    final chatId = _getChatId(senderUsername, updatedReceiverUsername);
    try {
      // Fetch receiver's UID for notifications
      final receiverQuery =
          await _firestore
              .collection('users')
              .where('username', isEqualTo: updatedReceiverUsername)
              .limit(1)
              .get();
      final receiverUid =
          receiverQuery.docs.isNotEmpty ? receiverQuery.docs.first.id : null;
      if (receiverUid == null) {
        print(
          '❌ [$callId] Receiver UID not found for username: $updatedReceiverUsername',
        );
        return;
      }
      if (receiverUid == senderUid) {
        print(
          '❌ [$callId] Cannot share meme to self: senderUid=$senderUid, receiverUid=$receiverUid',
        );
        return;
      }

      // Initialize shareCount if it doesn't exist
      final memeRef = _firestore.collection('memes').doc(memeId);
      final memeSnap = await memeRef.get();
      if (!memeSnap.exists || memeSnap['shareCount'] == null) {
        print('🔧 [$callId] Initializing shareCount for memeId=$memeId');
        await memeRef.set({'shareCount': 0}, SetOptions(merge: true));
      }

      // Increment shareCount
      await memeRef.update({'shareCount': FieldValue.increment(1)});
      print('✅ [$callId] Incremented shareCount for memeId=$memeId');

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
      print(
        '📤 [$callId] Sending meme to chats/$chatId/messages: $messageData',
      );
      await _firestore.collection('chats').doc(chatId).set({
        'lastUpdated': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      final messageRef = await _firestore
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .add(messageData);
      print(
        '✅ [$callId] Shared meme to room=$chatId, messageId=${messageRef.id}, url=$imageUrl',
      );

      // Create notification for receiver
      await _firestore.collection('users').doc(receiverUid).update({
        'notifications': FieldValue.arrayUnion([
          {
            'from': senderUsername,
            'type': 'meme_share',
            'memeId': memeId,
            'timestamp': Timestamp.fromDate(DateTime.now()),
            'seen': false,
          },
        ]),
      });
      print(
        '✅ [$callId] Sent notification to $updatedReceiverUsername (uid=$receiverUid)',
      );
    } catch (e) {
      print('❌ [$callId] Error in shareMeme: $e');
    }
  }

  String _getChatId(String a, String b) {
    final sorted = [a, b]..sort();
    final chatId = '${sorted[0]}_${sorted[1]}';
    print('🔗 Generated chatId: $chatId (a=$a, b=$b)');
    return chatId;
  }
}
