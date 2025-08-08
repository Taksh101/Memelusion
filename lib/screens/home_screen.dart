import 'dart:async';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:memelusion/screens/chat_screen.dart';
import 'package:memelusion/screens/utils.dart' as utils;
import 'package:memelusion/services/meme_service.dart';

class HomePage extends StatefulWidget {
  const HomePage({Key? key}) : super(key: key);
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _unreadNotifCount = 0;
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;
  final _memeService = MemeService();

  Map<String, dynamic>? currentMeme;
  Offset _position = Offset.zero;
  double _angle = 0;
  double _opacity = 1;
  bool _isLoading = true;
  double? _aspectRatio;

  String? _feedbackEmoji;
  Set<String> selectedFriends = {};
  Set<String> selectedCategories = {};
  List<String> savedMemes = [];

  @override
  void initState() {
    super.initState();
    _loadSavedMemes();
    _getRandomMeme();
    _loadUnreadNotifications();
  }

  Future<void> _loadUnreadNotifications() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    final snap =
        await _firestore
            .collection('users')
            .doc(uid)
            .collection('notifications')
            .where('read', isEqualTo: false)
            .get();

    setState(() {
      _unreadNotifCount = snap.docs.length;
    });
  }

  Future<void> _loadSavedMemes() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    final userSnap = await _firestore.collection('users').doc(uid).get();
    savedMemes = List<String>.from(userSnap['savedMemes'] ?? []);
  }

  Future<void> _getRandomMeme() async {
    setState(() => _isLoading = true);

    final snapshot = await _firestore.collection('memes').get();
    List<DocumentSnapshot> allMemes = snapshot.docs;

    if (selectedCategories.isNotEmpty) {
      allMemes =
          allMemes
              .where((doc) => selectedCategories.contains(doc['category']))
              .toList();
    }

    if (allMemes.isEmpty) {
      await Future.delayed(const Duration(seconds: 2));
      return _getRandomMeme();
    }

    final randomDoc = allMemes[Random().nextInt(allMemes.length)];
    final imageUrl = randomDoc['imageUrl'];

    final image = NetworkImage(imageUrl);
    final completer = Completer<void>();
    image
        .resolve(const ImageConfiguration())
        .addListener(
          ImageStreamListener((ImageInfo info, _) {
            _aspectRatio = info.image.width / info.image.height;
            completer.complete();
          }),
        );
    await completer.future;

    setState(() {
      currentMeme = {
        'id': randomDoc.id,
        'imageUrl': imageUrl,
        'shareCount': randomDoc['shareCount'] ?? 0,
        'likeCount': randomDoc['likeCount'] ?? 0,
      };
      _isLoading = false;
      _resetCard();
    });
  }

  void _showFeedback(String emoji) {
    setState(() => _feedbackEmoji = emoji);
    Future.delayed(const Duration(milliseconds: 900), () {
      if (mounted) setState(() => _feedbackEmoji = null);
    });
  }

  void _onPanUpdate(DragUpdateDetails details) {
    setState(() {
      _position += Offset(details.delta.dx, 0);
      if (details.delta.dy < 0) _position += Offset(0, details.delta.dy);
      _angle = 0.001 * _position.dx;
    });
  }

  void _onPanEnd(DragEndDetails details) async {
    final dx = _position.dx;
    final dy = _position.dy;

    if (dx.abs() > 150) {
      final liked = dx > 0;
      _showFeedback(liked ? '❤' : '');
      if (liked) await _handleLike();
      _getRandomMeme();
    } else if (dy < -150) {
      _openShareBottomSheet();
      _resetCard();
    } else if (dy > 150) {
      _showFeedback('📩');
      _resetCard();
    } else {
      _resetCard();
    }
  }

  Future<void> _handleLike() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    final memeRef = _firestore.collection('memes').doc(currentMeme!['id']);
    final userRef = _firestore.collection('users').doc(uid);
    final snap = await memeRef.get();
    final likedBy = List<String>.from(snap['likedBy'] ?? []);

    if (likedBy.contains(uid)) return;

    await memeRef.update({
      'likeCount': FieldValue.increment(1),
      'likedBy': FieldValue.arrayUnion([uid]),
    });

    await userRef.update({'likedMemesCount': FieldValue.increment(1)});

    setState(() {
      currentMeme!['likeCount'] = (currentMeme!['likeCount'] as int) + 1;
    });
  }

  void _resetCard() {
    _position = Offset.zero;
    _angle = 0;
    _opacity = 1;
  }

  Future<void> _toggleSave() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null || currentMeme == null) return;

    final memeId = currentMeme!['id'];
    final userRef = _firestore.collection('users').doc(uid);
    final isSaved = savedMemes.contains(memeId);

    if (isSaved) {
      await userRef.update({
        'savedMemes': FieldValue.arrayRemove([memeId]),
      });
      savedMemes.remove(memeId);
    } else {
      await userRef.update({
        'savedMemes': FieldValue.arrayUnion([memeId]),
      });
      savedMemes.add(memeId);
    }

    setState(() {});

  }

  Widget _buildCard() {
    final url = currentMeme!['imageUrl'];
    final isSaved = savedMemes.contains(currentMeme!['id']);

    final memeCard = Padding(
      padding: const EdgeInsets.only(bottom: 90),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(15),
            child:
                _aspectRatio != null
                    ? ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxHeight: 460,
                        maxWidth: 340,
                      ),
                      child: AspectRatio(
                        aspectRatio: _aspectRatio!,
                        child: Image.network(url, fit: BoxFit.contain),
                      ),
                    )
                    : const SizedBox(
                      height: 300,
                      child: Center(
                        child: CircularProgressIndicator(
                          color: Colors.greenAccent,
                        ),
                      ),
                    ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildLikeCountBadge(),
              const SizedBox(width: 8),
              _buildShareCountBadge(),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: _toggleSave,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black,
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isSaved
                            ? Icons.bookmark
                            : Icons.bookmark_border_outlined,
                        size: 16,
                        color: isSaved ? Colors.yellowAccent : Colors.white70,
                      ),
                      const SizedBox(width: 5),
                      const Text(
                        'Save',
                        style: TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );

    return GestureDetector(
      onPanUpdate: _onPanUpdate,
      onPanEnd: _onPanEnd,
      child: Opacity(
        opacity: _opacity,
        child: Transform.translate(
          offset: _position,
          child: Transform.rotate(angle: _angle, child: memeCard),
        ),
      ),
    );
  }

  Widget _buildLikeCountBadge() {
    final count = currentMeme?['likeCount'] ?? 0;
    return _badge(
      Icon(Icons.favorite, size: 16, color: Colors.redAccent[400]),
      count,
    );
  }

  Widget _buildShareCountBadge() {
    final count = currentMeme?['shareCount'] ?? 0;
    return _badge(Icon(Icons.share, size: 16, color: Colors.white70), count);
  }

  Widget _badge(Icon icon, int count) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: Colors.black,
      border: Border.all(color: Colors.grey.shade300),
      borderRadius: BorderRadius.circular(15),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        icon,
        const SizedBox(width: 5),
        Text(
          '$count',
          style: const TextStyle(color: Colors.white70, fontSize: 13),
        ),
      ],
    ),
  );

  Widget _buildProfileButton() => Positioned(
    bottom: 12,
    child: MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => Navigator.pushNamed(context, '/profile'),
        child: const CircleAvatar(
          radius: 30,
          backgroundColor: Colors.greenAccent,
          child: Icon(Icons.person, color: Colors.black, size: 32),
        ),
      ),
    ),
  );

  Future<void> _openShareBottomSheet() async {
    selectedFriends.clear();
    final currentUser = _auth.currentUser;
    if (currentUser == null) return;

    final userDoc =
        await _firestore.collection('users').doc(currentUser.uid).get();
    final List<String> friends = List<String>.from(
      userDoc.data()?['friends'] ?? [],
    );

    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      isScrollControlled: true,
      builder:
          (_) => StatefulBuilder(
            builder:
                (context, setModalState) => Padding(
                  padding: const EdgeInsets.only(
                    left: 16,
                    right: 16,
                    top: 16,
                    bottom: 32,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        "Share Meme",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontFamily: 'Inter',
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (friends.isEmpty)
                        const Text(
                          "No friends found.",
                          style: TextStyle(
                            color: Colors.white70,
                            fontFamily: 'Inter',
                          ),
                        )
                      else
                        ...friends.map(
                          (friend) => CheckboxListTile(
                            title: Text(
                              friend,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontFamily: 'Inter',
                              ),
                            ),
                            value: selectedFriends.contains(friend),
                            onChanged: (val) {
                              setModalState(() {
                                val == true
                                    ? selectedFriends.add(friend)
                                    : selectedFriends.remove(friend);
                              });
                            },
                            activeColor: Colors.greenAccent[400],
                          ),
                        ),
                      const SizedBox(height: 14),
                      if (friends.isNotEmpty)
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.greenAccent[400],
                            foregroundColor: Colors.black,
                            minimumSize: const Size(double.infinity, 46),
                          ),
                          icon: const Icon(Icons.send),
                          label: const Text(
                            'Send',
                            style: TextStyle(fontFamily: 'Inter'),
                          ),
                          onPressed:
                              selectedFriends.isEmpty
                                  ? null
                                  : () async {
                                    for (final friend in selectedFriends) {
                                      await _memeService.shareMeme(
                                        memeId: currentMeme!['id'],
                                        senderUsername: await _firestore
                                            .collection('users')
                                            .doc(currentUser.uid)
                                            .get()
                                            .then((doc) => doc['username']),
                                        receiverUsername: friend,
                                        imageUrl: currentMeme!['imageUrl'],
                                      );
                                    }
                                    await _firestore
                                        .collection('memes')
                                        .doc(currentMeme!['id'])
                                        .update({
                                          'shareCount': FieldValue.increment(1),
                                        });
                                    await _firestore
                                        .collection('users')
                                        .doc(currentUser.uid)
                                        .update({
                                          'sharedMemesCount':
                                              FieldValue.increment(1),
                                        });
                                    setState(() {
                                      currentMeme!['shareCount'] =
                                          (currentMeme!['shareCount'] as int) +
                                          1;
                                    });
                                    Navigator.pop(context);
                                    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("Meme Shared"),
        duration: const Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
                                  },
                        ),
                    ],
                  ),
                ),
          ),
    );

    setState(_resetCard);
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
    onWillPop: () async => await utils.showExitConfirmationDialog(context),
    child : Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        centerTitle: true,
        title: const Text(
          "Memelusion",
          style: TextStyle(
            color: Colors.greenAccent,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.2,
            fontFamily: 'Inter',
          ),
        ),
        leading: IconButton(
          icon: const Icon(
            Icons.chat_bubble_outline,
            color: Colors.greenAccent,
          ),
          onPressed: () {
            Navigator.pushNamed(context, '/chat');
          },
        ),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(
              Icons.filter_alt_outlined,
              color: Colors.greenAccent,
            ),
            onSelected: (category) {
              setState(() {
                selectedCategories.contains(category)
                    ? selectedCategories.remove(category)
                    : selectedCategories.add(category);
                _getRandomMeme();
              });
            },
            itemBuilder:
                (context) =>
                    ['Animal', 'Corporate', 'Sarcastic', 'Dark']
                        .map(
                          (cat) => CheckedPopupMenuItem<String>(
                            value: cat,
                            checked: selectedCategories.contains(cat),
                            child: Text(
                              cat,
                              style: const TextStyle(fontFamily: 'Inter'),
                            ),
                          ),
                        )
                        .toList(),
          ),
          StreamBuilder<DocumentSnapshot>(
            stream:
                FirebaseFirestore.instance
                    .collection('users')
                    .doc(FirebaseAuth.instance.currentUser!.uid)
                    .snapshots(),
            builder: (context, snapshot) {
              int unreadCount = 0;
              if (snapshot.hasData) {
                final data =
                    snapshot.data!.data() as Map<String, dynamic>? ?? {};
                final notifs = List<Map<String, dynamic>>.from(
                  data['notifications'] ?? [],
                );
                unreadCount = notifs.where((n) => n['seen'] == false).length;
              }

              return Stack(
                children: [
                  IconButton(
                    icon: const Icon(
                      Icons.notifications_none_rounded,
                      color: Colors.greenAccent,
                    ),
                    onPressed: () async {
                      await Navigator.pushNamed(context, '/notifications');
                    },
                  ),
                  if (unreadCount > 0)
                    Positioned(
                      right: 6,
                      top: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.redAccent,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 16,
                          minHeight: 16,
                        ),
                        child: Text(
                          '$unreadCount',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            height: 1.2,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: SafeArea(
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (_isLoading)
              const Center(
                child: CircularProgressIndicator(color: Colors.greenAccent),
              )
            else
              Center(child: _buildCard()),
            if (_feedbackEmoji != null)
              AnimatedOpacity(
                opacity: 1,
                duration: const Duration(milliseconds: 200),
                child: Center(
                  child: Text(
                    _feedbackEmoji!,
                    style: const TextStyle(fontSize: 80),
                  ),
                ),
              ),
            _buildProfileButton(),
          ],
        ),
      ),
    ),
    );
  }
}
