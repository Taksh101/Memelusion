import 'dart:convert';
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

  @override
  void initState() {
    super.initState();
    _loadData(); // ✅ ensures profile is fetched before anything else
  }

  Future<void> _loadData() async {
    await _fetchProfile(); // ensures userData is ready
    await _fetchSavedMemes(); // fetch saved memes
    await _fetchFriends(); // fetch friends using userData['friends']
  }

  Future<void> _fetchProfile() async {
    if (currentUser == null) return;
    final doc =
        await FirebaseFirestore.instance
            .collection('users')
            .doc(currentUser!.uid)
            .get();
    setState(() {
      userData = doc.data();
      _usernameController.text = userData?['username'] ?? '';
    });
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

  void _editUsername() {
    showDialog(
      context: context,
      builder:
          (_) => AlertDialog(
            backgroundColor: Colors.grey[900],
            title: const Text(
              "Edit Username",
              style: TextStyle(color: Colors.white),
            ),
            content: TextField(
              controller: _usernameController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Username',
                labelStyle: TextStyle(color: Colors.grey),
                border: OutlineInputBorder(),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text(
                  "Cancel",
                  style: TextStyle(color: Colors.red),
                ),
              ),
              TextButton(
                onPressed: () async {
                  final newUsername = _usernameController.text.trim();
                  if (newUsername.isEmpty) return;

                  final uid = currentUser!.uid;
                  final existing =
                      await FirebaseFirestore.instance
                          .collection('users')
                          .where('username', isEqualTo: newUsername)
                          .get();

                  if (existing.docs.isNotEmpty &&
                      existing.docs.first.id != uid) {
                    if (!mounted) return;
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("Username already exists.")),
                    );
                    return;
                  }

                  await FirebaseFirestore.instance
                      .collection('users')
                      .doc(uid)
                      .update({'username': newUsername});

                  final all =
                      await FirebaseFirestore.instance
                          .collection('users')
                          .get();
                  for (final d in all.docs) {
                    final friends = List<String>.from(d['friends'] ?? []);
                    if (friends.contains(userData?['username'])) {
                      final updated =
                          friends
                              .map(
                                (f) =>
                                    f == userData?['username']
                                        ? newUsername
                                        : f,
                              )
                              .toList();
                      await d.reference.update({'friends': updated});
                    }
                  }

                  if (!mounted) return;
                  Navigator.pop(context);
                  _fetchProfile();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Username updated.")),
                  );
                },
                child: const Text(
                  "Save",
                  style: TextStyle(color: Colors.greenAccent),
                ),
              ),
            ],
          ),
    );
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
      if (doc.exists) memes.add({'id': doc.id, 'url': doc['imageUrl']});
    }

    setState(() => savedMemes = memes);
  }

  Future<void> _unsaveMeme(String id) async {
    final uid = currentUser?.uid;
    if (uid == null) return;

    await FirebaseFirestore.instance.collection('users').doc(uid).update({
      'savedMemes': FieldValue.arrayRemove([id]),
    });

    _fetchSavedMemes();

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text("Removed from saved")));
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

      if (rawFriends.contains(docUid)) {
        print('✅ Matched by UID: $docUid');
      }

      if (rawFriends.contains(uname)) {
        print('✅ Matched by Username: $uname');
      }

      // Add if matched
      if (rawFriends.contains(docUid) || rawFriends.contains(uname)) {
        list.add({'uid': docUid, 'username': uname, 'profilePic': pic});
      }
    }

    print('✅ Final friendsList: ${list.length} items');

    setState(() => friendsList = list);
  }

  /* ------------------------------------------------------------------
   Call with the friend’s username.  Removes instantly from UI, then
   updates Firestore.  If Firestore fails the user is re-inserted.
-------------------------------------------------------------------*/
  Future<void> _unfriend(String friendUsername) async {
    if (!mounted) return;

    /// --- 1.  Optimistic-UI: remove locally first -------------
    final int idx = friendsList.indexWhere(
      (f) => f['username'] == friendUsername,
    );
    if (idx == -1) return;
    final removed = friendsList.removeAt(idx);
    setState(() {}); // <-- disappear immediately

    try {
      final meRef = FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser!.uid);

      // fetch friend’s document ref
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

      // --- 2.  Run transaction to remove each from other’s friends ----
      await FirebaseFirestore.instance.runTransaction((txn) async {
        txn.update(meRef, {
          'friends': FieldValue.arrayRemove([friendUsername]),
        });
        txn.update(friendRef, {
          'friends': FieldValue.arrayRemove([userData?['username']]),
        });
      });

      // success ✔
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Unfriended')));
    } catch (e) {
      // --- 3.  Roll-back on failure ---------------------------
      friendsList.insert(idx, removed);
      if (mounted) setState(() {});
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }

  Future<void> _searchAndAddFriend() async {
    String query = '';
    showDialog(
      context: context,
      builder: (_) {
        List<Map<String, dynamic>> results = [];

        return StatefulBuilder(
          builder:
              (context, setStateSB) => AlertDialog(
                backgroundColor: Colors.grey[900],
                title: const Text(
                  "Add Friend",
                  style: TextStyle(color: Colors.white),
                ),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      onChanged: (val) async {
                        query = val.trim();
                        if (query.isEmpty) {
                          setStateSB(() => results = []);
                          return;
                        }

                        final res =
                            await FirebaseFirestore.instance
                                .collection('users')
                                .where('username', isEqualTo: query)
                                .get();

                        results =
                            res.docs
                                .where((d) => d.id != currentUser!.uid)
                                .map(
                                  (d) => {
                                    'username': d['username'],
                                    'profilePic': d['profilePic'],
                                    'ref': d.reference,
                                    'uid': d.id,
                                    'friendRequests': List<String>.from(
                                      d['friendRequests'] ?? [],
                                    ),
                                  },
                                )
                                .toList();

                        setStateSB(() {});
                      },
                      decoration: const InputDecoration(
                        hintText: "Enter username",
                        hintStyle: TextStyle(color: Colors.white70),
                      ),
                      style: const TextStyle(color: Colors.white),
                    ),
                    const SizedBox(height: 10),
                    if (results.isNotEmpty)
                      ...results.map((user) {
                        final myUsername = userData?['username'];
                        final alreadySent =
                            myUsername != null &&
                            user['friendRequests'].contains(myUsername);

                        return ListTile(
                          leading: CircleAvatar(
                            backgroundImage:
                                user['profilePic'] != ''
                                    ? NetworkImage(user['profilePic'])
                                    : const AssetImage(
                                          'assets/img/default_profile.png',
                                        )
                                        as ImageProvider,
                          ),
                          title: Text(
                            user['username'],
                            style: const TextStyle(color: Colors.white),
                          ),
                          trailing: Builder(
                            builder: (_) {
                              final username = user['username'];
                              if ((userData?['friends'] ?? []).contains(
                                username,
                              )) {
                                return const ElevatedButton(
                                  onPressed: null,
                                  child: Text("Friend"),
                                );
                              }
                              if ((user['friendRequests'] ?? []).contains(
                                userData?['username'],
                              )) {
                                return const ElevatedButton(
                                  onPressed: null,
                                  child: Text("Sent"),
                                );
                              }

                              return ElevatedButton(
                                onPressed: () async {
                                  await user['ref'].update({
                                    'friendRequests': FieldValue.arrayUnion([
                                      userData?['username'],
                                    ]),
                                    'notifications': FieldValue.arrayUnion([
                                      {
                                        'type': 'friend_request',
                                        'from': userData?['username'],
                                        'timestamp':
                                            DateTime.now().toIso8601String(),
                                        'seen': false,
                                      },
                                    ]),
                                  });
                                  Navigator.pop(context);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text("Friend request sent"),
                                    ),
                                  );
                                },
                                child: const Text("Add"),
                              );
                            },
                          ),
                        );
                      }),
                  ],
                ),
              ),
        );
      },
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
          onPressed: () {
            if (showSaved || showFriends) {
              setState(() {
                showSaved = false;
                showFriends = false;
              });
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
                              Navigator.pushReplacementNamed(context, '/login');
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

          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                userData?['username'] ?? '',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: _editUsername,
                child: Icon(Icons.edit, size: 18, color: Colors.grey[400]),
              ),
            ],
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
          child: Stack(
            children: [
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(meme['url'], fit: BoxFit.contain),
                  ),
                ),
              ),
              Positioned(
                right: 4,
                top: 4,
                child: IconButton(
                  icon: const Icon(
                    Icons.bookmark_remove,
                    color: Colors.greenAccent,
                  ),
                  onPressed: () => _unsaveMeme(meme['id']),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFriendsList() {
    if (friendsList.isEmpty) {
      return const Center(
        child: Text(
          'No friends yet.',
          style: TextStyle(color: Colors.white70, fontSize: 16),
        ),
      );
    }

    return ListView.builder(
      itemCount: friendsList.length,
      itemBuilder: (context, index) {
        final f = friendsList[index];
        return ListTile(
          leading: CircleAvatar(
            backgroundImage:
                f['profilePic'] != ''
                    ? NetworkImage(f['profilePic'])
                    : const AssetImage('assets/img/default_profile.png')
                        as ImageProvider,
          ),
          title: Text(
            f['username'],
            style: const TextStyle(color: Colors.white),
          ),
          trailing: IconButton(
            icon: const Icon(Icons.remove_circle, color: Colors.redAccent),
            onPressed: () {
              showDialog(
                context: context,
                builder:
                    (_) => AlertDialog(
                      title: const Text("Unfriend"),
                      content: Text("Remove ${f['username']} from friends?"),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text("Cancel"),
                        ),
                        TextButton(
                          onPressed: () async {
                            Navigator.pop(context);
                            final removedUsername = f['username'];
                            await _unfriend(removedUsername);
                            setState(() {
                              friendsList.removeWhere(
                                (friend) =>
                                    friend['username'] == removedUsername,
                              );
                            });
                          },
                          child: const Text("Unfriend"),
                        ),
                      ],
                    ),
              );
            },
          ),
        );
      },
    );
  }
}
