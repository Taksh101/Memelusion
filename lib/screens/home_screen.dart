import 'dart:async';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
// import 'package:firebase_core/firebase_core.dart'; // Removed unused import
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:memelusion/screens/utils.dart' as utils;
import 'package:memelusion/services/meme_service.dart';

class FakeDocumentSnapshot {
  dynamic operator [](Object key) => null;
  bool get exists => false;
  dynamic get(Object field) => null;
  String get id => '';
  Map<String, dynamic>? data() => {};
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
  bool _useLocal = false;
  List<String> _likedByLocal = const [];

  @override
  void initState() {
    super.initState();
    final memeId = widget.currentMeme?['id'];
    final likedBy = widget.currentMeme?['likedBy'];
    if (likedBy is List) {
      // If the buffer already provided likedBy, avoid an extra read.
      _useLocal = true;
      _likedByLocal = List<String>.from(likedBy);
      // Use a dummy doc snapshot for the future
      _future =
          FirebaseFirestore.instance.collection('memes').doc('__dummy__').get();
    } else {
      _useLocal = false;
      _future =
          memeId != null
              ? FirebaseFirestore.instance.collection('memes').doc(memeId).get()
              : FirebaseFirestore.instance
                  .collection('memes')
                  .doc('__dummy__')
                  .get();
    }
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.currentMeme?['likeCount'] ?? 0;
    final uid = widget.auth.currentUser?.uid;
    final memeId = widget.currentMeme?['id'];

    if (uid == null || memeId == null) {
      return widget.badge(
        const Icon(Icons.favorite_border, size: 16, color: Colors.white70),
        count,
      );
    }

    if (_useLocal) {
      final hasLiked = _likedByLocal.contains(uid);
      return widget.badge(
        Icon(
          hasLiked ? Icons.favorite : Icons.favorite_border,
          size: 16,
          color: hasLiked ? Colors.redAccent[400] : Colors.white70,
        ),
        count,
      );
    }

    return FutureBuilder<DocumentSnapshot>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting ||
            !snapshot.hasData ||
            snapshot.data == null) {
          return widget.badge(
            const Icon(Icons.favorite_border, size: 16, color: Colors.white70),
            count,
          );
        }
        if (snapshot.hasError) {
          return widget.badge(
            const Icon(Icons.favorite_border, size: 16, color: Colors.white70),
            count,
          );
        }

        final likedBy = List<String>.from(snapshot.data?['likedBy'] ?? []);
        final hasLiked = likedBy.contains(uid);

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

class _HomePageState extends State<HomePage> with TickerProviderStateMixin {
  static const int _bufferTarget = 10; // Increased buffer size for better performance
  static const int _lowWatermark = 3; // Increased low watermark

  // int _unreadNotifCount = 0; // Removed unused field
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;
  final _memeService = MemeService();

  Map<String, dynamic>? currentMeme;
  Offset _position = Offset.zero;
  double _angle = 0;
  double _opacity = 1;
  bool _isLoading = true;

  String? _feedbackEmoji;
  Set<String> selectedFriends = {};
  Set<String> selectedCategories = {};
  List<String> savedMemes = [];

  // NEW: local buffer of upcoming memes
  final List<Map<String, dynamic>> _buffer = [];
  bool _isPrefetching = false;
  int _prefetchToken = 0; // to cancel stale fills
  bool _isBufferEmpty = false; // track if buffer is empty to prevent infinite loops
  Timer? _refillTimer; // debounced refill timer
  DateTime? _lastRefillTime; // track last refill time to prevent rapid requests
  Timer? _bufferHealthTimer; // periodic buffer health check
  Set<String> _likedMemes = {}; // track recently liked memes to prevent double-liking

  @override
  void initState() {
    super.initState();
    _loadSavedMemes();
    _primeBuffer();
    _loadUnreadNotifications();
  }

  @override
  void dispose() {
    _refillTimer?.cancel();
    _bufferHealthTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reset buffer state when returning to this screen
    if (_buffer.isEmpty && !_isLoading && !_isPrefetching) {
      _isBufferEmpty = false;
      _primeBuffer();
    }
  }

  // Add a method to force refresh the buffer
  void _forceRefreshBuffer() {
    _isBufferEmpty = false;
    _isPrefetching = false;
    _buffer.clear();
    _primeBuffer();
  }

  Future<void> _primeBuffer() async {
    setState(() => _isLoading = true);
    await _fillBuffer(clear: true);
    _popNextMeme();
    
    // Start periodic buffer health check
    _bufferHealthTimer?.cancel();
    _bufferHealthTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      if (mounted && _buffer.isEmpty && !_isLoading && !_isPrefetching) {
        // Buffer is stuck, force refresh
        _forceRefreshBuffer();
      }
    });
  }

  Future<void> _loadUnreadNotifications() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    await _firestore
        .collection('users')
        .doc(uid)
        .collection('notifications')
        .where('read', isEqualTo: false)
        .get();

    // Removed assignment to deleted _unreadNotifCount
  }

  Future<void> _loadSavedMemes() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    final userSnap = await _firestore.collection('users').doc(uid).get();
    savedMemes = List<String>.from(userSnap['savedMemes'] ?? []);
  }

  // NEW: fill/refresh buffer (category-aware)
  Future<void> _fillBuffer({bool clear = false}) async {
    if (_isPrefetching) return;
    
    // Prevent rapid refill requests
    final now = DateTime.now();
    if (_lastRefillTime != null && 
        now.difference(_lastRefillTime!).inMilliseconds < 500) {
      return;
    }
    
    _isPrefetching = true;
    _lastRefillTime = now;
    final myToken = ++_prefetchToken;

    try {
      if (clear) _buffer.clear();

      final need = _bufferTarget - _buffer.length;
      if (need <= 0) return;

      final cats = selectedCategories.toList();
      final batch = await _memeService.fetchMemesBatch(
        categories: cats.isEmpty ? null : cats,
        limit: max(need, 3), // overfetch a bit for variety
      );

      // Check if this operation was cancelled during the fetch
      if (myToken != _prefetchToken) return;

      // Prepare: precache first few & compute aspect ratio
      int prepared = 0;
      for (final meme in batch) {
        if (meme['imageUrl'] == null) continue;
        // If we already have this meme in buffer, skip duplicates
        if (_buffer.any((m) => m['id'] == meme['id'])) continue;

        final preparedMeme = Map<String, dynamic>.from(meme);
        try {
          // Compute aspect ratio and precache image
          final ratio = await _computeAspectRatioAndPrecache(meme['imageUrl']);
          preparedMeme['aspectRatio'] = ratio;
        } catch (_) {
          // If image fails to load, skip
          continue;
        }

        _buffer.add(preparedMeme);
        prepared++;
        // stop once we've met the target to avoid overfilling
        if (_buffer.length >= _bufferTarget) break;

        // If a newer fill started, stop this one
        if (myToken != _prefetchToken) break;
      }

      // Update buffer empty state
      _isBufferEmpty = _buffer.isEmpty;

      if (prepared == 0 && _buffer.isEmpty) {
        // Fallback: show loading state but avoid loops
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      }
    } finally {
      _isPrefetching = false;
    }
  }

  Future<double> _computeAspectRatioAndPrecache(String url) async {
    final image = NetworkImage(url);
    final completer = Completer<ImageInfo>();
    final stream = image.resolve(const ImageConfiguration());
    late final ImageStreamListener listener;

    listener = ImageStreamListener(
      (ImageInfo info, bool _) {
        completer.complete(info);
        stream.removeListener(listener);
      },
      onError: (dynamic error, __) {
        if (!completer.isCompleted) completer.completeError(error);
        stream.removeListener(listener);
      },
    );

    stream.addListener(listener);

    // Also precache so the next display is instant
    try {
      await precacheImage(image, context);
    } catch (_) {
      // ignore precache errors; the stream might still deliver dimensions
    }

    final info = await completer.future;
    final ratio = info.image.width / info.image.height;
    return ratio == 0 ? 1.0 : ratio.toDouble();
  }

  // NEW: pop next meme from buffer and trigger refill if low
  void _popNextMeme() {
    if (_buffer.isEmpty) {
      setState(() {
        currentMeme = null;
        _isLoading = true;
      });
      
      // Only try to fill if we're not already in an empty state
      if (!_isBufferEmpty) {
        _fillBuffer().then((_) {
          if (mounted) {
            setState(() {
              _isLoading = false;
              if (_buffer.isNotEmpty) {
                currentMeme = _buffer.removeAt(0);
                _resetCard();
              }
            });
          }
        });
      } else {
        // If buffer is empty, try to reset and fill again
        _isBufferEmpty = false;
        _fillBuffer().then((_) {
          if (mounted) {
            setState(() {
              _isLoading = false;
              if (_buffer.isNotEmpty) {
                currentMeme = _buffer.removeAt(0);
                _resetCard();
              }
            });
          }
        });
      }
      return;
    }

    setState(() {
      currentMeme = _buffer.removeAt(0);
      _isLoading = false;
      _resetCard();
    });

    // Update buffer empty state
    _isBufferEmpty = _buffer.isEmpty;

    // Low-watermark refill - be more aggressive when buffer is getting low
    if (_buffer.length < _lowWatermark) {
      // Cancel any pending refill timer
      _refillTimer?.cancel();
      // Debounce rapid refill requests
      _refillTimer = Timer(const Duration(milliseconds: 50), () {
        if (mounted && _buffer.length < _lowWatermark) {
          _fillBuffer();
        }
      });
    }
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
      // Handle like asynchronously without blocking the animation
      if (liked && currentMeme != null) {
        final memeId = currentMeme!['id'];
        // Prevent double-liking the same meme
        if (!_likedMemes.contains(memeId)) {
          _likedMemes.add(memeId);
          _handleLike().catchError((error) {
            // Silently handle errors to not block UI
            print('Like error: $error');
            // Remove from liked set on error so user can retry
            _likedMemes.remove(memeId);
          });
        }
      }
      _animateToNext();
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

  // NEW: smooth transition to next meme
  void _animateToNext() {
    // Let the current card fade a touch, then swap
    setState(() => _opacity = 0.0);
    Future.delayed(const Duration(milliseconds: 80), () {
      if (!mounted) return;
      _popNextMeme();
      setState(() => _opacity = 1.0);
    });
  }

  Future<void> _handleLike() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null || currentMeme == null) return;

    final memeId = currentMeme!['id'];
    
    // Optimistically update UI first for better responsiveness
    setState(() {
      currentMeme!['likeCount'] = (currentMeme!['likeCount'] as int) + 1;
      // Keep local likedBy in sync if it exists (helps LikeCountBadge)
      final localLiked = List<String>.from(currentMeme!['likedBy'] ?? []);
      if (!localLiked.contains(uid)) {
        localLiked.add(uid);
        currentMeme!['likedBy'] = localLiked;
      }
    });

    // Then update backend asynchronously
    try {
      final memeRef = _firestore.collection('memes').doc(memeId);
      final userRef = _firestore.collection('users').doc(uid);
      
      // Check if already liked to prevent double-liking
      final snap = await memeRef.get();
      final likedBy = List<String>.from(snap['likedBy'] ?? []);
      
      if (likedBy.contains(uid)) {
        // Revert optimistic update if already liked
        setState(() {
          currentMeme!['likeCount'] = (currentMeme!['likeCount'] as int) - 1;
          final localLiked = List<String>.from(currentMeme!['likedBy'] ?? []);
          localLiked.remove(uid);
          currentMeme!['likedBy'] = localLiked;
        });
        return;
      }

      // Update both documents concurrently
      await Future.wait([
        memeRef.update({
          'likeCount': FieldValue.increment(1),
          'likedBy': FieldValue.arrayUnion([uid]),
        }),
        userRef.update({'likedMemesCount': FieldValue.increment(1)}),
      ]);
    } catch (error) {
      // Revert optimistic update on error
      setState(() {
        currentMeme!['likeCount'] = (currentMeme!['likeCount'] as int) - 1;
        final localLiked = List<String>.from(currentMeme!['likedBy'] ?? []);
        localLiked.remove(uid);
        currentMeme!['likedBy'] = localLiked;
      });
      rethrow;
    }
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

  Future<void> _openShareBottomSheet() async {
    selectedFriends.clear();
    final currentUser = _auth.currentUser;
    if (currentUser == null || currentMeme == null) {
      return;
    }

    final userDoc =
        await _firestore.collection('users').doc(currentUser.uid).get();
    if (!userDoc.exists || userDoc.data() == null) {
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
                                        } catch (e) {
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
                                            });
                                          } else {
                                            await _primeBuffer();
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
      return const SizedBox.shrink();
    }

    final url = currentMeme!['imageUrl'];
    final isSaved = savedMemes.contains(currentMeme!['id']);
    // final shareCount = currentMeme!['shareCount'] ?? 0; // Removed unused variable
    final aspect = (currentMeme!['aspectRatio'] as double?) ?? 1.0;

    final memeCard = Padding(
      padding: const EdgeInsets.only(bottom: 90),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(15),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 460, maxWidth: 340),
              child: AspectRatio(
                aspectRatio: aspect,
                child: Image.network(url, fit: BoxFit.contain),
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

    // Smooth transition between memes
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, anim) {
        return FadeTransition(
          opacity: anim,
          child: ScaleTransition(
            scale: Tween(begin: 0.98, end: 1.0).animate(anim),
            child: child,
          ),
        );
      },
      child: GestureDetector(
        key: ValueKey(currentMeme!['id']),
        onPanUpdate: _onPanUpdate,
        onPanEnd: _onPanEnd,
        child: Opacity(
          opacity: _opacity,
          child: Transform.translate(
            offset: _position,
            child: Transform.rotate(angle: _angle, child: memeCard),
          ),
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
              onSelected: (category) async {
                setState(() {
                  if (selectedCategories.contains(category)) {
                    selectedCategories.remove(category);
                  } else {
                    selectedCategories.add(category);
                  }
                });
                // Clear buffer and refill for the selected categories
                await _fillBuffer(clear: true);
                _popNextMeme();
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
              else if (currentMeme == null)
                Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.error_outline,
                        color: Colors.grey,
                        size: 64,
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'No memes available',
                        style: TextStyle(
                          color: Colors.grey,
                          fontSize: 18,
                          fontFamily: 'Inter',
                        ),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () {
                          _forceRefreshBuffer();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.greenAccent,
                          foregroundColor: Colors.black,
                        ),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
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
