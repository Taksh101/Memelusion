import 'dart:convert';
import 'dart:ui';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final currentUser = FirebaseAuth.instance.currentUser;
  Map<String, dynamic>? userData;
  final _usernameController = TextEditingController();
  final _picker = ImagePicker();

  bool showSaved = false;
  bool showFriends = false;
  List<Map<String, dynamic>> savedMemes = [];
  List<Map<String, dynamic>> friendsList = [];
  String? _currentUsername; // Local state for instant UI updates

  @override
  void initState() {
    super.initState();
    _loadData(); // Ensures profile is fetched before anything else
  }

  Future<void> _loadData() async {
    await _fetchProfile(); // Ensures userData is ready
    await _fetchSavedMemes(); // Fetch saved memes
    await _fetchFriends(); // Fetch friends using userData['friends']
  }

  Future<void> _fetchProfile() async {
    if (currentUser == null) {
      print('❌ No current user logged in');
      return;
    }
    try {
      final doc =
          await FirebaseFirestore.instance
              .collection('users')
              .doc(currentUser!.uid)
              .get();
      if (!doc.exists) {
        print('❌ User document does not exist for UID: ${currentUser!.uid}');
        return;
      }
      setState(() {
        userData = doc.data();
        _currentUsername = userData?['username'] ?? '';
        _usernameController.text = _currentUsername ?? '';
        print('✅ Fetched userData: $userData');
      });
    } catch (e) {
      print('❌ Error fetching profile: $e');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to load profile: $e')));
    }
  }

  Future<void> _editProfilePicture() async {
    try {
      final picked = await _picker.pickImage(source: ImageSource.gallery);
      if (picked == null) return;

      final uid = currentUser!.uid;
      final userRef = FirebaseFirestore.instance.collection('users').doc(uid);
      final bytes = await picked.readAsBytes();
      final base64Img = base64Encode(bytes);
      const imgbbApiKey = 'a1940b393d27a0d52676bbfa98d0bece';

      final uploadRes = await http.post(
        Uri.parse('https://api.imgbb.com/1/upload?key=$imgbbApiKey'),
        body: {'image': base64Img, 'name': uid},
      );

      final json = jsonDecode(uploadRes.body);
      if (json['status'] != 200) throw 'ImgBB upload failed: ${json['error']}';

      final newUrl = json['data']['url'] as String;
      final newDeleteUrl = json['data']['delete_url'] as String;

      await userRef.update({
        'profilePic': newUrl,
        'profilePicDelete': newDeleteUrl,
      });

      final userSnap = await userRef.get();
      final prevDeleteUrl = userSnap.data()?['profilePicDelete'] as String?;
      if (prevDeleteUrl != null &&
          prevDeleteUrl.isNotEmpty &&
          prevDeleteUrl != newDeleteUrl) {
        try {
          await http.get(Uri.parse(prevDeleteUrl));
        } catch (_) {}
      }

      await _fetchProfile();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Profile picture updated ✅")),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Upload failed: $e")));
    }
  }
  Future<void> _fetchSavedMemes() async {
    final uid = currentUser?.uid;
    if (uid == null) return;

    final userDoc =
        await FirebaseFirestore.instance.collection('users').doc(uid).get();
    final savedIds = List<String>.from(userDoc.data()?['savedMemes'] ?? []);
    final List<Map<String, dynamic>> memes = [];

    for (final id in savedIds) {
      if (id.trim().isEmpty) continue;
      final doc =
          await FirebaseFirestore.instance.collection('memes').doc(id).get();
      if (doc.exists) {
        memes.add({
          'id': doc.id,
          'url': doc['imageUrl'],
          'likeCount': doc['likeCount'] ?? 0,
          'shareCount': doc['shareCount'] ?? 0,
        });
      }
    }

    setState(() => savedMemes = memes);
    print('✅ Fetched ${memes.length} saved memes');
  }

  Future<void> _unsaveMeme(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder:
          (_) => AlertDialog(
            backgroundColor: Colors.grey[900],
            title: const Text(
              "Unsave Meme",
              style: TextStyle(color: Colors.white),
            ),
            content: const Text(
              "Are you sure you want to unsave this meme?",
              style: TextStyle(color: Colors.white70),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text(
                  "Cancel",
                  style: TextStyle(color: Colors.red),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text(
                  "Unsave",
                  style: TextStyle(color: Colors.greenAccent),
                ),
              ),
            ],
          ),
    );

    if (confirm != true) return;

    final uid = currentUser?.uid;
    if (uid == null) return;

    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'savedMemes': FieldValue.arrayRemove([id]),
      });

      await _fetchSavedMemes();

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Removed from saved")));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Failed to unsave meme: $e")));
    }
  }

  Future<void> _fetchFriends() async {
    final uid = currentUser?.uid;
    if (uid == null) {
      print('❌ Current user is null');
      return;
    }

    // Grab friends from userData
    final rawFriends = List<String>.from(userData?['friends'] ?? []);
    print('👥 Raw friends list from Firestore: $rawFriends');

    if (rawFriends.isEmpty) {
      print('📭 No friends to fetch.');
      setState(() => friendsList = []);
      return;
    }

    final snap = await FirebaseFirestore.instance.collection('users').get();
    print('📄 Total users in DB: ${snap.docs.length}');

    final List<Map<String, dynamic>> list = [];

    for (final doc in snap.docs) {
      final data = doc.data();
      final docUid = doc.id;
      final uname = data['username'] ?? '';
      final pic = data['profilePic'] ?? '';

      print('🔍 Checking user: $uname (UID: $docUid)');

      if (rawFriends.contains(uname)) {
        print('✅ Matched by Username: $uname');
        list.add({'uid': docUid, 'username': uname, 'profilePic': pic});
      }
    }

    print('✅ Final friendsList: ${list.length} items');

    setState(() => friendsList = list);
  }

  Future<void> _unfriend(String friendUsername) async {
    if (!mounted) return;

    // Optimistic UI: remove locally first
    final int idx = friendsList.indexWhere(
      (f) => f['username'] == friendUsername,
    );
    if (idx == -1) return;
    final removed = friendsList.removeAt(idx);
    setState(() {}); // Trigger UI update
    print('🗑️ Optimistically removed friend: $friendUsername');

    try {
      final meRef = FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser!.uid);

      // Fetch friend's document ref
      final fSnap =
          await FirebaseFirestore.instance
              .collection('users')
              .where('username', isEqualTo: friendUsername)
              .limit(1)
              .get();

      if (fSnap.docs.isEmpty) {
        throw 'User not found';
      }
      final friendRef = fSnap.docs.first.reference;

      // Run transaction to remove each from other’s friends
      await FirebaseFirestore.instance.runTransaction((txn) async {
        txn.update(meRef, {
          'friends': FieldValue.arrayRemove([friendUsername]),
        });
        txn.update(friendRef, {
          'friends': FieldValue.arrayRemove([userData?['username']]),
        });
      });

      // Refresh userData to update friends count
      await _fetchProfile();
      print('✅ Unfriend successful, refreshed profile');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Unfriended')));
    } catch (e) {
      // Roll back on failure
      friendsList.insert(idx, removed);
      if (mounted) setState(() {});
      print('❌ Error unfriending: $e');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }

  Future<void> _searchAndAddFriend() async {
    String query = '';
    showDialog(
      context: context,
      builder: (dialogContext) {
        List<Map<String, dynamic>> results = [];

        return StatefulBuilder(
          builder:
              (context, setStateSB) => SizedBox(
                width:
                    MediaQuery.of(dialogContext).size.width *
                    0.98, // Very wide dialog
                child: AlertDialog(
                  backgroundColor: Colors.grey[900],
                  title: const Text(
                    "Add Friend",
                    style: TextStyle(color: Colors.white),
                  ),
                  content: Container(
                    constraints: const BoxConstraints(
                      maxWidth: 600,
                    ), // Extra room for long usernames
                    padding: const EdgeInsets.symmetric(horizontal: 12.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextField(
                          onChanged: (val) async {
                            query = val.trim();
                            print(
                              '🔍 Searching for username starting with: $query',
                            );
                            if (query.isEmpty) {
                              setStateSB(() => results = []);
                              print('📭 Empty query, cleared results');
                              return;
                            }

                            try {
                              // Query for both lowercase and uppercase first letter
                              final lowerQuery = query.toLowerCase();
                              final upperQuery =
                                  query.isNotEmpty
                                      ? query[0].toUpperCase() +
                                          (query.length > 1
                                              ? query.substring(1).toLowerCase()
                                              : '')
                                      : '';
                              final queries = <Future<QuerySnapshot>>[];

                              // Add query for lowercase (e.g., "a" or "alex")
                              queries.add(
                                FirebaseFirestore.instance
                                    .collection('users')
                                    .where(
                                      'username',
                                      isGreaterThanOrEqualTo: lowerQuery,
                                    )
                                    .where(
                                      'username',
                                      isLessThanOrEqualTo: '$lowerQuery\uf8ff',
                                    )
                                    .get(),
                              );

                              // Add query for uppercase first letter (e.g., "A" or "Alex")
                              if (upperQuery != lowerQuery) {
                                queries.add(
                                  FirebaseFirestore.instance
                                      .collection('users')
                                      .where(
                                        'username',
                                        isGreaterThanOrEqualTo: upperQuery,
                                      )
                                      .where(
                                        'username',
                                        isLessThanOrEqualTo:
                                            '$upperQuery\uf8ff',
                                      )
                                      .get(),
                                );
                              }

                              // Execute both queries
                              final queryResults = await Future.wait(queries);

                              // Combine and filter results
                              results =
                                  queryResults
                                      .expand((res) => res.docs)
                                      .where((d) => d.id != currentUser!.uid)
                                      .where(
                                        (d) => (d['username'] as String)
                                            .toLowerCase()
                                            .startsWith(query.toLowerCase()),
                                      )
                                      .map(
                                        (d) => {
                                          'username': d['username'] ?? '',
                                          'profilePic': d['profilePic'] ?? '',
                                          'ref': d.reference,
                                          'uid': d.id,
                                          'friendRequests': List<String>.from(
                                            d['friendRequests'] ?? [],
                                          ),
                                        },
                                      )
                                      .toSet() // Remove duplicates
                                      .toList();

                              print(
                                '✅ Found ${results.length} users: ${results.map((u) => u['username']).toList()}',
                              );
                              setStateSB(() {});
                            } catch (e) {
                              print('❌ Error searching users: $e');
                              setStateSB(() => results = []);
                            }
                          },
                          decoration: const InputDecoration(
                            hintText: "Enter username",
                            hintStyle: TextStyle(color: Colors.white70),
                            border: OutlineInputBorder(),
                            filled: true,
                            fillColor: Color.fromRGBO(33, 33, 33, 1),
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 16.0,
                              vertical: 14.0,
                            ),
                          ),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 16),
                        if (results.isNotEmpty)
                          ...results.map((user) {
                            final myUsername = userData?['username'];
                            final alreadySent =
                                myUsername != null &&
                                user['friendRequests'].contains(myUsername);

                            return Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: 8.0,
                                horizontal: 12.0,
                              ),
                              child: Row(
                                children: [
                                  // Profile picture
                                  Padding(
                                    padding: const EdgeInsets.only(right: 16.0),
                                    child: CircleAvatar(
                                      backgroundImage:
                                          user['profilePic'] != ''
                                              ? NetworkImage(user['profilePic'])
                                              : const AssetImage(
                                                    'assets/img/default_profile.png',
                                                  )
                                                  as ImageProvider,
                                      radius: 22,
                                    ),
                                  ),
                                  // Username (horizontally scrollable)
                                  Expanded(
                                    child: SingleChildScrollView(
                                      scrollDirection: Axis.horizontal,
                                      child: Text(
                                        user['username'],
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 16,
                                          fontFamily: 'Inter',
                                        ),
                                        softWrap: false,
                                        overflow: TextOverflow.clip,
                                      ),
                                    ),
                                  ),
                                  // Button
                                  Padding(
                                    padding: const EdgeInsets.only(left: 16.0),
                                    child: Builder(
                                      builder: (_) {
                                        final username = user['username'];
                                        if ((userData?['friends'] ?? [])
                                            .contains(username)) {
                                          return ElevatedButton(
                                            onPressed: null,
                                            style: ElevatedButton.styleFrom(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal:
                                                        8.0, // Reduced from 16.0
                                                  ),
                                            ),
                                            child: const Text("Friend"),
                                          );
                                        }
                                        if ((user['friendRequests'] ?? [])
                                            .contains(myUsername)) {
                                          return ElevatedButton(
                                            onPressed: null,
                                            style: ElevatedButton.styleFrom(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal:
                                                        8.0, // Reduced from 16.0
                                                  ),
                                            ),
                                            child: const Text("Sent"),
                                          );
                                        }

                                        return ElevatedButton(
                                          onPressed: () async {
                                            try {
                                              await user['ref'].update({
                                                'friendRequests':
                                                    FieldValue.arrayUnion([
                                                      myUsername,
                                                    ]),
                                                'notifications':
                                                    FieldValue.arrayUnion([
                                                      {
                                                        'type':
                                                            'friend_request',
                                                        'from': myUsername,
                                                        'timestamp':
                                                            DateTime.now()
                                                                .toIso8601String(),
                                                        'seen': false,
                                                      },
                                                    ]),
                                              });
                                              print(
                                                '✅ Friend request sent to: $username',
                                              );
                                              Navigator.pop(context);
                                              ScaffoldMessenger.of(
                                                context,
                                              ).showSnackBar(
                                                const SnackBar(
                                                  content: Text(
                                                    "Friend request sent",
                                                  ),
                                                ),
                                              );
                                            } catch (e) {
                                              print(
                                                '❌ Error sending friend request: $e',
                                              );
                                              ScaffoldMessenger.of(
                                                context,
                                              ).showSnackBar(
                                                SnackBar(
                                                  content: Text(
                                                    "Failed to send friend request: $e",
                                                  ),
                                                ),
                                              );
                                            }
                                          },
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.greenAccent,
                                            foregroundColor: Colors.black,
                                            padding: const EdgeInsets.symmetric(
                                              horizontal:
                                                  8.0, // Reduced from 16.0
                                            ),
                                          ),
                                          child: const Text("Add"),
                                        );
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }),
                        if (results.isEmpty && query.isNotEmpty)
                          const Text(
                            'No results found',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 16,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
        );
      },
    );
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text(
          showSaved ? 'Saved Memes' : (showFriends ? 'Friends' : 'Profile'),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () async {
            if (showSaved || showFriends) {
              setState(() {
                showSaved = false;
                showFriends = false;
                print(
                  '🔄 Exiting friends or saved memes view, refreshing profile',
                );
              });
              await _fetchProfile(); // Refresh userData to update friends count
            } else {
              Navigator.pop(context);
            }
          },
        ),
        actions: [
          if (!(showSaved || showFriends))
            IconButton(
              icon: const Icon(Icons.logout),
              onPressed: () {
                showDialog(
                  context: context,
                  builder:
                      (_) => AlertDialog(
                        title: const Text("Confirm Logout"),
                        content: const Text(
                          "Are you sure you want to log out?",
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text("Cancel"),
                          ),
                          TextButton(
                            onPressed: () async {
                              await FirebaseAuth.instance.signOut();
                              if (!mounted) return;
                              Navigator.pushNamedAndRemoveUntil(
                                context,
                                '/login',
                                (route) => false,
                              );
                            },
                            child: const Text(
                              "Logout",
                              style: TextStyle(color: Colors.red),
                            ),
                          ),
                        ],
                      ),
                );
              },
            ),
        ],
      ),
      body:
          userData == null
              ? const Center(
                child: CircularProgressIndicator(color: Colors.greenAccent),
              )
              : showSaved
              ? _buildSavedMemes()
              : showFriends
              ? _buildFriendsList()
              : _buildProfileBody(),
    );
  }

  Widget _buildProfileBody() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Profile Picture
          Stack(
            alignment: Alignment.bottomRight,
            children: [
              CircleAvatar(
                radius: 50,
                backgroundImage:
                    (userData?['profilePic'] ?? '').toString().isNotEmpty
                        ? NetworkImage(userData!['profilePic'])
                        : const AssetImage('assets/img/default_profile.png')
                            as ImageProvider,
              ),
              GestureDetector(
                onTap: _editProfilePicture,
                child: CircleAvatar(
                  radius: 16,
                  backgroundColor: Colors.grey[800],
                  child: const Icon(Icons.edit, size: 17, color: Colors.white),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
              Text(
                _currentUsername ?? userData?['username'] ?? '',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
          const SizedBox(height: 6),

          Text(
            userData?['email'] ?? '',
            style: TextStyle(fontSize: 14, color: Colors.grey[500]),
          ),
          const SizedBox(height: 30),

          // Friend count
          GestureDetector(
            onTap: () => setState(() => showFriends = true),
            child: Text(
              "Friends: ${userData?['friends']?.length ?? 0}",
              style: const TextStyle(color: Colors.greenAccent, fontSize: 16),
            ),
          ),
          const SizedBox(height: 20),

          // Menu Buttons
          ListView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              ListTile(
                leading: const Icon(Icons.bookmark, color: Colors.white),
                title: const Text(
                  'Saved',
                  style: TextStyle(color: Colors.white),
                ),
                onTap: () => setState(() => showSaved = true),
                tileColor: Colors.grey[900],
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              const SizedBox(height: 10),
              ListTile(
                leading: const Icon(
                  Icons.person_add_alt_1,
                  color: Colors.white,
                ),
                title: const Text(
                  'Add Friend',
                  style: TextStyle(color: Colors.white),
                ),
                onTap: _searchAndAddFriend,
                tileColor: Colors.grey[900],
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              const SizedBox(height: 10),
              ListTile(
                leading: const Icon(Icons.settings, color: Colors.white),
                title: const Text(
                  'Settings',
                  style: TextStyle(color: Colors.white),
                ),
                onTap: () => Navigator.pushNamed(context, '/settings'),
                tileColor: Colors.grey[900],
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSavedMemes() {
    if (savedMemes.isEmpty) {
      return const Center(
        child: Text(
          'No saved memes yet.',
          style: TextStyle(color: Colors.white70, fontSize: 16),
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(14),
      itemCount: savedMemes.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 14,
        crossAxisSpacing: 14,
        childAspectRatio: 0.8,
      ),
      itemBuilder: (ctx, i) {
        final meme = savedMemes[i];
        return Material(
          color: Colors.grey[900],
          borderRadius: BorderRadius.circular(12),
          elevation: 4, // Subtle shadow for depth
          child: Stack(
            children: [
              // Meme image with gradient overlay
              Positioned.fill(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(
                          8,
                        ), // Restored original padding
                        child: GestureDetector(
                          onTap:
                              () => showFullScreenImageDialog(
                                context,
                                meme['url'],
                              ),
                          child: Image.network(
                            meme['url'],
                            fit:
                                BoxFit
                                    .contain, // Restored to ensure full image visibility
                            errorBuilder:
                                (context, error, stackTrace) => const Icon(
                                  Icons.broken_image,
                                  color: Colors.white70,
                                  size: 50,
                                ),
                          ),
                        ),
                      ),
                      // Gradient overlay for better text/icon contrast
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        child: Container(
                          height: 60,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.bottomCenter,
                              end: Alignment.topCenter,
                              colors: [
                                Colors.black.withOpacity(0.7),
                                Colors.transparent,
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // Unsave button
              Positioned(
                right: 8,
                top: 8,
                child: IconButton(
                  icon: const Icon(
                    Icons.bookmark_remove,
                    color: Colors.greenAccent,
                    size: 28,
                  ),
                  onPressed: () => _unsaveMeme(meme['id']),
                ),
              ),
              // Likes and Shares with icons
              Positioned(
                left: 8,
                bottom: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.6),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Likes
                      Row(
                        children: [
                          const Icon(
                            Icons.favorite,
                            color: Colors.redAccent,
                            size: 16,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${meme['likeCount']}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 12),
                      // Shares
                      Row(
                        children: [
                          const Icon(
                            Icons.share,
                            color: Colors.blueAccent,
                            size: 16,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${meme['shareCount']}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFriendsList() {
    String _searchQuery = ''; // Local state for search query

    return StatefulBuilder(
      builder: (context, setStateSB) {
        // Filter friendsList based on search query
        final filteredFriends =
            _searchQuery.isEmpty
                ? friendsList
                : friendsList
                    .where(
                      (f) => f['username'].toString().toLowerCase().contains(
                        _searchQuery.toLowerCase(),
                      ),
                    )
                    .toList();

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 16.0,
                vertical: 8.0,
              ),
              child: TextField(
                onChanged: (val) {
                  setStateSB(() {
                    _searchQuery = val.trim();
                    print('🔍 Filtering friends with query: $_searchQuery');
                  });
                },
                decoration: const InputDecoration(
                  hintText: "Search friends",
                  hintStyle: TextStyle(color: Colors.white70),
                  border: OutlineInputBorder(),
                  filled: true,
                  fillColor: Color.fromRGBO(33, 33, 33, 1),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 16.0,
                    vertical: 14.0,
                  ),
                  suffixIcon: Icon(Icons.search, color: Colors.white70),
                ),
                style: const TextStyle(color: Colors.white, fontSize: 16),
              ),
            ),
            if (filteredFriends.isEmpty)
              const Expanded(
                child: Center(
                  child: Text(
                    'No friends found.',
                    style: TextStyle(color: Colors.white70, fontSize: 16),
                  ),
                ),
              )
            else
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16.0,
                    vertical: 8.0,
                  ),
                  itemCount: filteredFriends.length,
                  itemBuilder: (context, index) {
                    final f = filteredFriends[index];
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8.0),
                      child: Row(
                        children: [
                          // Profile picture
                          Padding(
                            padding: const EdgeInsets.only(right: 16.0),
                            child: CircleAvatar(
                              backgroundImage:
                                  f['profilePic'] != ''
                                      ? NetworkImage(f['profilePic'])
                                      : const AssetImage(
                                            'assets/img/default_profile.png',
                                          )
                                          as ImageProvider,
                              radius: 22,
                            ),
                          ),
                          // Username
                          Expanded(
                            child: Text(
                              f['username'],
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                              ),
                              softWrap: false, // Prevent wrapping
                            ),
                          ),
                          // Unfriend button
                          Padding(
                            padding: const EdgeInsets.only(left: 16.0),
                            child: IconButton(
                              icon: const Icon(
                                Icons.remove_circle,
                                color: Colors.redAccent,
                              ),
                              onPressed: () {
                                showDialog(
                                  context: context,
                                  builder:
                                      (_) => AlertDialog(
                                        backgroundColor: Colors.grey[900],
                                        title: const Text(
                                          "Unfriend",
                                          style: TextStyle(color: Colors.white),
                                        ),
                                        content: Text(
                                          "Remove ${f['username']} from friends?",
                                          style: const TextStyle(
                                            color: Colors.white70,
                                          ),
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed:
                                                () => Navigator.pop(context),
                                            child: const Text(
                                              "Cancel",
                                              style: TextStyle(
                                                color: Colors.grey,
                                              ),
                                            ),
                                          ),
                                          TextButton(
                                            onPressed: () async {
                                              Navigator.pop(context);
                                              await _unfriend(f['username']);
                                            },
                                            child: const Text(
                                              "Unfriend",
                                              style: TextStyle(
                                                color: Colors.redAccent,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
          ],
        );
      },
    );
  }
}
