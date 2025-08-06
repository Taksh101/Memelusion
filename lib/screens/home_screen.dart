import 'dart:async';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:memelusion/screens/utils.dart' as utils;
import 'package:memelusion/services/meme_service.dart';

class FakeDocumentSnapshot implements DocumentSnapshot {
  @override
  dynamic operator [](Object key) => null;

  @override
  bool get exists => false;

  @override
  dynamic get(Object field) => null;

  @override
  String get id => '';

  @override
  DocumentReference get reference => throw UnimplementedError();

  @override
  Map<String, dynamic>? data() => {};

  @override
  SnapshotMetadata get metadata => throw UnimplementedError();
}

class LikeCountBadge extends StatefulWidget {
  final Map<String, dynamic>? currentMeme;
  final FirebaseAuth auth;
  final Widget Function(Icon, int) badge;

  const LikeCountBadge({
    super.key,
    required this.currentMeme,
    required this.auth,
    required this.badge,
  });

  @override
  _LikeCountBadgeState createState() => _LikeCountBadgeState();
}

class _LikeCountBadgeState extends State<LikeCountBadge> {
  late final Future<DocumentSnapshot> _future;

  @override
  void initState() {
    super.initState();
    final memeId = widget.currentMeme?['id'];
    _future =
        memeId != null
            ? FirebaseFirestore.instance.collection('memes').doc(memeId).get()
            : Future.value(
              FakeDocumentSnapshot(),
            ); // Fix: Use FakeDocumentSnapshot
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.currentMeme?['likeCount'] ?? 0;
    final uid = widget.auth.currentUser?.uid;
    final memeId = widget.currentMeme?['id'];

    if (uid == null || memeId == null) {
      print('❌ LikeCountBadge: uid=$uid, memeId=$memeId');
      return widget.badge(
        Icon(Icons.favorite_border, size: 16, color: Colors.white70),
        count,
      );
    }

    return FutureBuilder<DocumentSnapshot>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return widget.badge(
            Icon(Icons.favorite_border, size: 16, color: Colors.white70),
            count,
          );
        }
        if (snapshot.hasError) {
          print('❌ LikeCountBadge error: ${snapshot.error}');
          return widget.badge(
            Icon(Icons.favorite_border, size: 16, color: Colors.white70),
            count,
          );
        }

        final likedBy = List<String>.from(snapshot.data?['likedBy'] ?? []);
        final hasLiked = likedBy.contains(uid);
        print(
          '🔍 LikeCountBadge: uid=$uid, memeId=$memeId, likedBy=$likedBy, hasLiked=$hasLiked',
        );

        return widget.badge(
          Icon(
            hasLiked ? Icons.favorite : Icons.favorite_border,
            size: 16,
            color: hasLiked ? Colors.redAccent[400] : Colors.white70,
          ),
          count,
        );
      },
    );
  }
}

class ShareCountBadge extends StatelessWidget {
  final Map<String, dynamic>? currentMeme;
  final Widget Function(Icon, int) badge;

  const ShareCountBadge({
    super.key,
    required this.currentMeme,
    required this.badge,
  });

  @override
  Widget build(BuildContext context) {
    final shareCount = currentMeme?['shareCount'] ?? 0;
    print(
      '🔍 ShareCountBadge: memeId=${currentMeme?['id']}, shareCount=$shareCount',
    );
    return badge(
      Icon(Icons.share, size: 16, color: Colors.greenAccent[400]),
      shareCount,
    );
  }
}

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
      print('❌ No memes found, retrying...');
      await Future.delayed(const Duration(seconds: 2));
      return _getRandomMeme();
    }

    final randomDoc = allMemes[Random().nextInt(allMemes.length)];
    if (!randomDoc.exists || randomDoc['imageUrl'] == null) {
      print('❌ Invalid meme document: id=${randomDoc.id}');
      return _getRandomMeme();
    }

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
      print(
        '✅ Loaded meme: id=${currentMeme!['id']}, shareCount=${currentMeme!['shareCount']}',
      );
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
      await _getRandomMeme();
    } else if (dy < -150) {
      await _openShareBottomSheet();
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
    if (uid == null || currentMeme == null) return;

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
    setState(() {
      _position = Offset.zero;
      _angle = 0;
      _opacity = 1;
    });
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

  Future<void> _openShareBottomSheet() async {
    selectedFriends.clear();
    final currentUser = _auth.currentUser;
    if (currentUser == null || currentMeme == null) {
      print('❌ No user or meme: user=$currentUser, meme=$currentMeme');
      return;
    }

    final userDoc =
        await _firestore.collection('users').doc(currentUser.uid).get();
    if (!userDoc.exists || userDoc.data() == null) {
      print('❌ User document not found: uid=${currentUser.uid}');
      return;
    }
    final List<String> friends = List<String>.from(
      userDoc.data()!['friends'] ?? [],
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
            builder: (context, setModalState) {
              bool isSending = false;
              return Padding(
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
                      StatefulBuilder(
                        builder: (context, setSendState) {
                          return ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.greenAccent[400],
                              foregroundColor: Colors.black,
                              minimumSize: const Size(double.infinity, 46),
                            ),
                            icon:
                                isSending
                                    ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        color: Colors.black,
                                        strokeWidth: 2.5,
                                      ),
                                    )
                                    : const Icon(Icons.send),
                            label: Text(
                              isSending ? 'Sending...' : 'Send',
                              style: const TextStyle(fontFamily: 'Inter'),
                            ),
                            onPressed:
                                selectedFriends.isEmpty || isSending
                                    ? null
                                    : () async {
                                      setSendState(() => isSending = true);
                                      final senderUsername =
                                          userDoc.data()!['username']
                                              as String?;
                                      if (senderUsername == null) {
                                        print(
                                          '❌ No sender username: uid=${currentUser.uid}',
                                        );
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              "Error: User profile not found",
                                            ),
                                            duration: const Duration(
                                              seconds: 2,
                                            ),
                                            behavior: SnackBarBehavior.floating,
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                          ),
                                        );
                                        setSendState(() => isSending = false);
                                        return;
                                      }
                                      int shares = 0;
                                      for (final friend in selectedFriends) {
                                        try {
                                          await _memeService.shareMeme(
                                            memeId: currentMeme!['id'],
                                            senderUsername: senderUsername,
                                            receiverUsername: friend,
                                            imageUrl: currentMeme!['imageUrl'],
                                          );
                                          shares++;
                                          print('✅ Shared meme to $friend');
                                        } catch (e) {
                                          print(
                                            '❌ Error sharing to $friend: $e',
                                          );
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                "Error sharing with $friend",
                                              ),
                                              duration: const Duration(
                                                seconds: 2,
                                              ),
                                              behavior:
                                                  SnackBarBehavior.floating,
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                              ),
                                            ),
                                          );
                                        }
                                      }
                                      if (shares > 0) {
                                        try {
                                          await _firestore
                                              .collection('users')
                                              .doc(currentUser.uid)
                                              .update({
                                                'sharedMemesCount':
                                                    FieldValue.increment(1),
                                              });
                                          final memeDoc =
                                              await _firestore
                                                  .collection('memes')
                                                  .doc(currentMeme!['id'])
                                                  .get();
                                          if (memeDoc.exists &&
                                              memeDoc.data() != null) {
                                            setState(() {
                                              currentMeme!['shareCount'] =
                                                  memeDoc['shareCount'] ?? 0;
                                              print(
                                                '🔄 Updated shareCount: ${currentMeme!['shareCount']}',
                                              );
                                            });
                                          } else {
                                            print(
                                              '❌ Meme document not found: id=${currentMeme!['id']}',
                                            );
                                            await _getRandomMeme();
                                          }
                                          Navigator.pop(context);
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                "Meme shared with $shares friend${shares > 1 ? 's' : ''}",
                                              ),
                                              duration: const Duration(
                                                seconds: 2,
                                              ),
                                              behavior:
                                                  SnackBarBehavior.floating,
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                              ),
                                            ),
                                          );
                                        } catch (e) {
                                          print('❌ Error updating data: $e');
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                "Error updating data",
                                              ),
                                              duration: const Duration(
                                                seconds: 2,
                                              ),
                                              behavior:
                                                  SnackBarBehavior.floating,
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                              ),
                                            ),
                                          );
                                        }
                                      }
                                      setSendState(() => isSending = false);
                                    },
                          );
                        },
                      ),
                  ],
                ),
              );
            },
          ),
    );

    setState(_resetCard);
  }

  Widget _buildCard() {
    if (currentMeme == null || currentMeme!['imageUrl'] == null) {
      return const SizedBox.shrink(); // Prevent rendering until meme is loaded
    }

    final url = currentMeme!['imageUrl'];
    final isSaved = savedMemes.contains(currentMeme!['id']);
    final shareCount = currentMeme!['shareCount'] ?? 0;

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
              LikeCountBadge(
                key: ValueKey('like_${currentMeme!['id']}'),
                currentMeme: currentMeme,
                auth: _auth,
                badge: _badge,
              ),
              const SizedBox(width: 8),
              ShareCountBadge(
                key: ValueKey('share_${currentMeme!['id']}'),
                currentMeme: currentMeme,
                badge: _badge,
              ),
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

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async => await utils.showExitConfirmationDialog(context),
      child: Scaffold(
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
