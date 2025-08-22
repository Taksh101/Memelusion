import 'dart:convert';
import 'dart:ui';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:memelusion/screens/utils.dart' as utils;

import 'package:firebase_auth/firebase_auth.dart';

class AdminPanel extends StatefulWidget {
  const AdminPanel({super.key});

  @override
  State<AdminPanel> createState() => _AdminPanelState();
}

class _AdminPanelState extends State<AdminPanel> {
  XFile? _pickedImage;
  String? _selectedCategory;
  bool _isLoading = false;
  bool _showMemeList = false;
  bool _showUserList = false;
  String _filterCategory = 'All';

  final List<String> _categories = ['Animal', 'Sarcastic', 'Dark', 'Corporate'];
  final ImagePicker _picker = ImagePicker();

  Future<void> _uploadMeme() async {
    if (_pickedImage == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("⚠️ Please select a meme image")),
      );
      return;
    }

    if (_selectedCategory == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("⚠️ Please select a category")),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final memeId = const Uuid().v4();
      final bytes = await _pickedImage!.readAsBytes();
      final base64Img = base64Encode(bytes);

      const imgbbApiKey = 'a1940b393d27a0d52676bbfa98d0bece'; // Replace this
      final res = await http.post(
        Uri.parse('https://api.imgbb.com/1/upload?key=$imgbbApiKey'),
        body: {'image': base64Img, 'name': memeId},
      );

      final json = jsonDecode(res.body);
      if (json['status'] != 200) throw 'Upload failed: ${json['error']}';

      final imageUrl = json['data']['url'];

      await FirebaseFirestore.instance.collection('memes').doc(memeId).set({
        'memeId': memeId,
        'imageUrl': imageUrl,
        'category': _selectedCategory,
        'shareCount': 0,
        'likeCount': 0,
        'likedBy': [],
        'uploadTime': FieldValue.serverTimestamp(),
      });

      setState(() {
        _pickedImage = null;
        _selectedCategory = null;
        _isLoading = false;
      });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('✅ Meme uploaded!')));
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Upload failed: $e")));
    }
  }

  Future<int> _getCount(String collection) async {
    final snap = await FirebaseFirestore.instance.collection(collection).get();
    return snap.docs.length;
  }

  Future<void> _deleteMeme(String memeId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text("Confirm Delete"),
            content: const Text("Are you sure you want to delete this meme?"),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text("Cancel"),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text(
                  "Delete",
                  style: TextStyle(color: Colors.red),
                ),
              ),
            ],
          ),
    );

    if (confirm == true) {
      await FirebaseFirestore.instance.collection('memes').doc(memeId).delete();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("🗑️ Meme deleted")));
      setState(() {});
    }
  }

  void showFullScreenImageDialog(BuildContext context, String imageUrl) {
    showDialog(
      context: context,
      builder:
          (context) => GestureDetector(
            onTap: () => Navigator.of(context).pop(), // Tap outside to close
            child: Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: const EdgeInsets.all(16), // Increased from 10
              child: Stack(
                children: [
                  // Blur background
                  Positioned.fill(
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                      child: Container(
                        color: Colors.black.withOpacity(
                          0.7,
                        ), // Semi-transparent black
                      ),
                    ),
                  ),
                  Center(
                    child: GestureDetector(
                      onTap:
                          () =>
                              Navigator.of(context).pop(), // Tap image to close
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.3),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Hero(
                          tag: imageUrl,
                          child: InteractiveViewer(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.network(
                                imageUrl,
                                fit: BoxFit.contain,
                                loadingBuilder: (
                                  context,
                                  child,
                                  loadingProgress,
                                ) {
                                  if (loadingProgress == null) return child;
                                  return const Center(
                                    child: CircularProgressIndicator(
                                      color:
                                          Colors
                                              .greenAccent, // Match app's accent
                                    ),
                                  );
                                },
                                errorBuilder:
                                    (
                                      context,
                                      error,
                                      stackTrace,
                                    ) => const Center(
                                      child: Icon(
                                        Icons.error,
                                        color:
                                            Colors
                                                .redAccent, // Match app's accent
                                        size: 40,
                                      ),
                                    ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 5,
                    right: 5,
                    child: IconButton(
                      icon: const Icon(
                        Icons.close,
                        color: Colors.redAccent, // Changed to redAccent
                        size: 32, // Slightly larger
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                ],
              ),
            ),
          ),
    );
  }

  Future<void> _deleteUser(String userId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text("Confirm Delete"),
            content: const Text("Are you sure you want to delete this user?"),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text("Cancel"),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text(
                  "Delete",
                  style: TextStyle(color: Colors.red),
                ),
              ),
            ],
          ),
    );

    if (confirm == true) {
      try {
        // Get the username of the user being deleted
        final userDoc =
            await FirebaseFirestore.instance
                .collection('users')
                .doc(userId)
                .get();
        final userData = userDoc.data();
        if (userData == null || !userData.containsKey('username')) {
          throw 'User has no username';
        }
        final username = userData['username'] as String;

        // Start a batch for atomic operations
        final batch = FirebaseFirestore.instance.batch();

        // Get all users to update their friends and friendRequests arrays
        final usersSnapshot =
            await FirebaseFirestore.instance.collection('users').get();

        for (var userDoc in usersSnapshot.docs) {
          if (userDoc.id != userId) {
            final data = userDoc.data();
            // Remove username from friends array if it exists
            if (data.containsKey('friends') &&
                data['friends'] is List &&
                (data['friends'] as List).contains(username)) {
              batch.update(
                FirebaseFirestore.instance.collection('users').doc(userDoc.id),
                {
                  'friends': FieldValue.arrayRemove([username]),
                },
              );
            }

            // Remove username from friendRequests array if it exists
            if (data.containsKey('friendRequests') &&
                data['friendRequests'] is List &&
                (data['friendRequests'] as List).contains(username)) {
              batch.update(
                FirebaseFirestore.instance.collection('users').doc(userDoc.id),
                {
                  'friendRequests': FieldValue.arrayRemove([username]),
                },
              );
            }
          }
        }

        // Delete the user document
        batch.delete(
          FirebaseFirestore.instance.collection('users').doc(userId),
        );

        // Commit the batch
        await batch.commit();

        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("🗑️ User deleted")));
        setState(() {});
      } catch (e) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Failed to delete user: $e")));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async => await utils.showExitConfirmationDialog(context),
      child: Scaffold(
        appBar: AppBar(
          title: const Text("Admin Panel"),
          backgroundColor: Colors.black,
          automaticallyImplyLeading: false,
          actions: [
            IconButton(
              icon: const Icon(
                Icons.logout,
                color: Color.fromARGB(255, 255, 255, 255),
              ),
              onPressed: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder:
                      (context) => AlertDialog(
                        title: const Text("Confirm Logout"),
                        content: const Text("Are you sure you want to logout?"),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text("Cancel"),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text(
                              "Logout",
                              style: TextStyle(color: Colors.red),
                            ),
                          ),
                        ],
                      ),
                );

                if (confirm == true) {
                  await FirebaseAuth.instance.signOut();
                  if (!mounted) return;
                  Navigator.pushReplacementNamed(context, '/login');
                }
              },
            ),
          ],
        ),
        backgroundColor: Colors.black,
        body: Padding(
          padding: const EdgeInsets.all(16),
          child:
              _showMemeList
                  ? _buildMemeListView()
                  : _showUserList
                  ? _buildUserListView()
                  : _buildUploadView(),
        ),
      ),
    );
  }

  Widget _buildUploadView() {
    return ListView(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            FutureBuilder<int>(
              future: _getCount('users'),
              builder: (_, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return _buildStatCard("Users", null);
                }
                if (snap.hasError || snap.data == null) {
                  return _buildStatCard("Users", null);
                }
                return GestureDetector(
                  onTap: () => setState(() => _showUserList = true),
                  child: _buildStatCard("Users", snap.data! - 1),
                );
              },
            ),
            FutureBuilder<int>(
              future: _getCount('memes'),
              builder: (_, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return _buildStatCard("Memes", null);
                }
                if (snap.hasError || snap.data == null) {
                  return _buildStatCard("Memes", null);
                }
                return GestureDetector(
                  onTap: () => setState(() => _showMemeList = true),
                  child: _buildStatCard("Memes", snap.data),
                );
              },
            ),
          ],
        ),
        const SizedBox(height: 20),
        if (_pickedImage != null)
          FutureBuilder<Uint8List>(
            future: _pickedImage!.readAsBytes(),
            builder: (_, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const CircularProgressIndicator();
              }
              if (snap.hasError || !snap.hasData) {
                return const Text("Error loading image");
              }
              return ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.memory(snap.data!, height: 200),
              );
            },
          ),
        const SizedBox(height: 20),
        DropdownButtonFormField<String>(
          value: _selectedCategory,
          dropdownColor: Colors.grey[900],
          decoration: InputDecoration(
            labelText: "Select Category",
            labelStyle: const TextStyle(color: Colors.white),
            border: const OutlineInputBorder(),
          ),
          items:
              _categories
                  .map(
                    (cat) => DropdownMenuItem(
                      value: cat,
                      child: Text(
                        cat,
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                  )
                  .toList(),
          onChanged: (val) => setState(() => _selectedCategory = val),
        ),
        const SizedBox(height: 20),
        ElevatedButton(
          onPressed: () async {
            final image = await _picker.pickImage(source: ImageSource.gallery);
            if (image != null) setState(() => _pickedImage = image);
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.greenAccent,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          child: const Text(
            "Pick Meme Image",
            style: TextStyle(color: Colors.black),
          ),
        ),
        const SizedBox(height: 14),
        _isLoading
            ? const Center(child: CircularProgressIndicator())
            : ElevatedButton(
              onPressed: _uploadMeme,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.greenAccent,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: const Text(
                "Upload Meme",
                style: TextStyle(color: Colors.black),
              ),
            ),
      ],
    );
  }

  Widget _buildMemeListView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButton<String>(
          value: _filterCategory,
          dropdownColor: Colors.grey[900],
          style: const TextStyle(color: Colors.white),
          items:
              ['All', ..._categories].map((cat) {
                return DropdownMenuItem(value: cat, child: Text(cat));
              }).toList(),
          onChanged: (val) {
            if (val != null) setState(() => _filterCategory = val);
          },
        ),
        const SizedBox(height: 10),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream:
                FirebaseFirestore.instance
                    .collection('memes')
                    .orderBy('uploadTime', descending: true)
                    .snapshots(),
            builder: (_, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final docs = snap.data?.docs ?? [];
              final filtered =
                  _filterCategory == 'All'
                      ? docs
                      : docs
                          .where((d) => d['category'] == _filterCategory)
                          .toList();

              if (filtered.isEmpty) {
                return const Center(
                  child: Text(
                    "No memes found",
                    style: TextStyle(color: Colors.white70),
                  ),
                );
              }

              return ListView.builder(
                itemCount: filtered.length,
                itemBuilder: (_, i) {
                  final meme = filtered[i];
                  return Card(
                    color: Colors.grey[850],
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          GestureDetector(
                            onTap:
                                () => showFullScreenImageDialog(
                                  context,
                                  meme['imageUrl'],
                                ),
                            child: Image.network(
                              meme['imageUrl'],
                              height: 80,
                              width: 80,
                              fit: BoxFit.cover,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  meme['category'],
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                  ),
                                ),
                                Text(
                                  "Likes: ${meme['likeCount']}",
                                  style: const TextStyle(color: Colors.white60),
                                ),
                                Text(
                                  "Shares: ${meme['shareCount']}",
                                  style: const TextStyle(color: Colors.white60),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.delete,
                              color: Colors.redAccent,
                            ),
                            onPressed: () => _deleteMeme(meme['memeId']),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
        const SizedBox(height: 10),
        ElevatedButton.icon(
          onPressed: () => setState(() => _showMemeList = false),
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          label: const Text("Back", style: TextStyle(color: Colors.black)),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.greenAccent),
        ),
      ],
    );
  }

  Widget _buildUserListView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 10),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream:
                FirebaseFirestore.instance
                    .collection('users')
                    .orderBy('createdAt', descending: true)
                    .snapshots(),
            builder: (_, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final docs = snap.data?.docs ?? [];

              if (docs.isEmpty) {
                return const Center(
                  child: Text(
                    "No users found",
                    style: TextStyle(color: Colors.white70),
                  ),
                );
              }

              return ListView.builder(
                itemCount: docs.length,
                itemBuilder: (_, i) {
                  final user = docs[i];
                  return Card(
                    color: Colors.grey[850],
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          user['profilePic'] != null &&
                                  user['profilePic'].isNotEmpty
                              ? GestureDetector(
                                onTap:
                                    () => showFullScreenImageDialog(
                                      context,
                                      user['profilePic'],
                                    ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(40),
                                  child: Image.network(
                                    user['profilePic'],
                                    height: 80,
                                    width: 80,
                                    fit: BoxFit.cover,
                                    errorBuilder:
                                        (context, error, stackTrace) =>
                                            const Icon(
                                              Icons.person,
                                              size: 80,
                                              color: Colors.white60,
                                            ),
                                  ),
                                ),
                              )
                              : const Icon(
                                Icons.person,
                                size: 80,
                                color: Colors.white60,
                              ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  user['username'] ?? 'Unknown',
                                  style: const TextStyle(fontSize: 16),
                                ),
                                Text(
                                  user['email'] ?? 'No email',
                                  style: const TextStyle(color: Colors.white60),
                                ),
                              ],
                            ),
                          ),
                          Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              IconButton(
                                icon: const Icon(
                                  Icons.delete,
                                  color: Colors.redAccent,
                                ),
                                onPressed: () => _deleteUser(user['uid']),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
        const SizedBox(height: 10),
        ElevatedButton.icon(
          onPressed: () => setState(() => _showUserList = false),
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          label: const Text("Back", style: TextStyle(color: Colors.black)),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.greenAccent),
        ),
      ],
    );
  }

  Widget _buildStatCard(String label, int? count) {
    return Card(
      color: Colors.grey[850],
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        padding: const EdgeInsets.all(16),
        width: 140,
        child: Column(
          children: [
            Text(
              label,
              style: const TextStyle(color: Colors.white70, fontSize: 16),
            ),
            const SizedBox(height: 6),
            Text(
              count?.toString() ?? '...',
              style: const TextStyle(
                color: Colors.greenAccent,
                fontWeight: FontWeight.bold,
                fontSize: 22,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
