import 'package:cloud_firestore/cloud_firestore.dart';

class UserModel {
  final String uid;
  final String username;
  final String profilePic;
  final List<String> friends;
  final List<String> friendRequests;
  final bool isAdmin;
  final DateTime createdAt;

  UserModel({
    required this.uid,
    required this.username,
    required this.profilePic,
    required this.friends,
    required this.friendRequests,
    required this.isAdmin,
    required this.createdAt,
  });

  factory UserModel.fromMap(Map<String, dynamic> map) {
    return UserModel(
      uid: map['uid'] ?? '',
      username: map['username'] ?? '',
      profilePic: map['profilePic'] ?? '',
      friends: List<String>.from(map['friends'] ?? []),
      friendRequests: List<String>.from(map['friendRequests'] ?? []),
      isAdmin: map['isAdmin'] ?? false,
      createdAt: (map['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }
}
