import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:uuid/uuid.dart';
import 'dart:math';

class MemeService {
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;
  final _uuid = const Uuid();

  // Kept for compatibility (not used by Home now, but safe to keep)
  Future<Map<String, dynamic>?> fetchRandomMeme() async {
    try {
      final snapshot = await _firestore.collection('memes').limit(25).get();
      final docs = snapshot.docs;
      if (docs.isEmpty) {
        return null;
      }
      final randomDoc =
          docs[DateTime.now().millisecondsSinceEpoch % docs.length];
      final data = randomDoc.data();

      final memeData = {
        'id': randomDoc.id,
        'imageUrl': data['imageUrl'],
        'shareCount': data['shareCount'] ?? 0,
        'likeCount': data['likeCount'] ?? 0,
        'likedBy': List<String>.from(data['likedBy'] ?? const []),
      };
      return memeData;
    } catch (e) {
      return null;
    }
  }

  // NEW: Batched fetch for buffering, category-aware.
  Future<List<Map<String, dynamic>>> fetchMemesBatch({
    List<String>? categories,
    int limit = 7,
  }) async {
    try {
      Query<Map<String, dynamic>> q = _firestore
          .collection('memes')
          .withConverter<Map<String, dynamic>>(
            fromFirestore: (snap, _) => snap.data() ?? {},
            toFirestore: (data, _) => data,
          );

      if (categories != null && categories.isNotEmpty) {
        // Firestore whereIn limit is 10; your list is small.
        final within =
            categories.length > 10 ? categories.sublist(0, 10) : categories;
        q = q.where('category', whereIn: within);
      }

      // Overfetch for variety and shuffle client-side
      final snap = await q.limit(max(limit * 3, limit)).get();
      final docs =
          snap.docs
              .where((d) => (d.data()['imageUrl'] ?? '').toString().isNotEmpty)
              .toList();

      if (docs.isEmpty) return [];

      docs.shuffle(Random());
      final take =
          docs.take(limit).map((d) {
            final data = d.data();
            return {
              'id': d.id,
              'imageUrl': data['imageUrl'],
              'shareCount': data['shareCount'] ?? 0,
              'likeCount': data['likeCount'] ?? 0,
              'likedBy': List<String>.from(data['likedBy'] ?? const []),
              // aspectRatio is computed client-side in Home and appended
            };
          }).toList();

      return take;
    } catch (e) {
      return [];
    }
  }

  // Increment share count and notify receiver (unchanged behavior)
  Future<void> shareMeme({
    required String memeId,
    required String senderUsername,
    required String receiverUsername,
    required String imageUrl,
  }) async {
    final senderUid = _auth.currentUser?.uid;
    if (senderUid == null) {
      return;
    }

    final callId = DateTime.now().millisecondsSinceEpoch;

    if (senderUsername.isEmpty || receiverUsername.isEmpty) {
      return;
    }
    if (senderUsername == receiverUsername) {
      return;
    }

    String updatedReceiverUsername = receiverUsername;
    if (receiverUsername.contains(RegExp(r'^[a-zA-Z0-9]{20,}$'))) {
      try {
        final userDoc =
            await _firestore.collection('users').doc(receiverUsername).get();
        if (userDoc.exists && userDoc['username'] != null) {
          updatedReceiverUsername = userDoc['username'];
        } else {
          return;
        }
      } catch (e) {
        return;
      }
    }

    if (senderUsername == updatedReceiverUsername) {
      return;
    }

    final chatId = _getChatId(senderUsername, updatedReceiverUsername);
    try {
      final receiverQuery =
          await _firestore
              .collection('users')
              .where('username', isEqualTo: updatedReceiverUsername)
              .limit(1)
              .get();
      final receiverUid =
          receiverQuery.docs.isNotEmpty ? receiverQuery.docs.first.id : null;
      if (receiverUid == null) {
        return;
      }
      if (receiverUid == senderUid) {
        return;
      }

      final memeRef = _firestore.collection('memes').doc(memeId);
      final memeSnap = await memeRef.get();
      if (!memeSnap.exists || memeSnap['shareCount'] == null) {
        await memeRef.set({'shareCount': 0}, SetOptions(merge: true));
      }

      await memeRef.update({'shareCount': FieldValue.increment(1)});

      final messageData = {
        'senderUid': senderUid,
        'text': '',
        'memeUrl': imageUrl,
        'timestamp': FieldValue.serverTimestamp(),
        'expiresAt': Timestamp.fromDate(
          DateTime.now().add(const Duration(hours: 24)),
        ),
      };
      await _firestore.collection('chats').doc(chatId).set({
        'lastUpdated': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      await _firestore
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .add(messageData);

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
    } catch (e) {
      // swallow
    }
  }

  String _getChatId(String a, String b) {
    final sorted = [a, b]..sort();
    return '${sorted[0]}_${sorted[1]}';
  }
}
