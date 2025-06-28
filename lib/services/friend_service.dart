import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';

class FriendService {
  final CollectionReference usersCollection = FirebaseFirestore.instance
      .collection('users');

  // Send friend request (with duplicate prevention)
  Future<void> sendFriendRequest(String senderId, String receiverId) async {
    final senderDoc = await usersCollection.doc(senderId).get();
    final receiverDoc = await usersCollection.doc(receiverId).get();

    if (!senderDoc.exists || !receiverDoc.exists) {
      throw Exception("One of the users does not exist");
    }

    List senderFriends = senderDoc['friends'] ?? [];
    List receiverRequests = receiverDoc['friendRequests'] ?? [];

    if (senderFriends.contains(receiverId)) {
      throw Exception("Already friends");
    }
    if (receiverRequests.contains(senderId)) {
      throw Exception("Request already sent");
    }

    // Add friend request
    await usersCollection.doc(receiverId).update({
      'friendRequests': FieldValue.arrayUnion([senderId]),
    });

    // Get sender username
    final senderUsername = senderDoc['username'];

    // Create notification
    await usersCollection.doc(receiverId).collection("notifications").add({
      "id": const Uuid().v4(),
      "type": "friend_request",
      "fromUsername": senderUsername,
      "timestamp": FieldValue.serverTimestamp(),
    });
  }

  // Accept friend request
  Future<void> acceptFriendRequest(String receiverId, String senderId) async {
    final receiverDoc = await usersCollection.doc(receiverId).get();
    final senderDoc = await usersCollection.doc(senderId).get();

    if (!receiverDoc.exists || !senderDoc.exists) {
      throw Exception("One of the users does not exist");
    }

    await usersCollection.doc(receiverId).update({
      'friends': FieldValue.arrayUnion([senderId]),
      'friendRequests': FieldValue.arrayRemove([senderId]),
    });

    await usersCollection.doc(senderId).update({
      'friends': FieldValue.arrayUnion([receiverId]),
    });
  }

  // Reject friend request
  Future<void> rejectFriendRequest(String receiverId, String senderId) async {
    await usersCollection.doc(receiverId).update({
      'friendRequests': FieldValue.arrayRemove([senderId]),
    });
  }

  // Remove friend
  Future<void> removeFriend(String userId, String friendId) async {
    final userDoc = await usersCollection.doc(userId).get();
    final friendDoc = await usersCollection.doc(friendId).get();

    if (!userDoc.exists || !friendDoc.exists) {
      throw Exception("One of the users does not exist");
    }

    await usersCollection.doc(userId).update({
      'friends': FieldValue.arrayRemove([friendId]),
    });

    await usersCollection.doc(friendId).update({
      'friends': FieldValue.arrayRemove([userId]),
    });
  }

  // Get list of friends
  Future<List<String>> getFriends(String userId) async {
    final doc = await usersCollection.doc(userId).get();
    if (!doc.exists) return [];
    return List<String>.from(doc['friends'] ?? []);
  }

  // Get pending friend requests
  Future<List<String>> getFriendRequests(String userId) async {
    final doc = await usersCollection.doc(userId).get();
    if (!doc.exists) return [];
    return List<String>.from(doc['friendRequests'] ?? []);
  }
}
