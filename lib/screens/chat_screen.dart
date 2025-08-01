import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;
  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  final _textNotifier = ValueNotifier<bool>(false); // Tracks text input state
  List<String> friends = [];
  List<String> filteredFriends = [];
  Map<String, String> friendProfilePics = {}; // username -> profilePic
  String? selectedFriend; // username
  bool _isLoadingFriends = true;
  String? _currentUserUsername;
  Map<String, String> friendUids = {}; // username -> uid
  int _lastMessageCount = 0; // Tracks message count for scrolling
  bool _isInitialChatLoad = true; // Tracks initial chat load for scrolling
  final ItemScrollController _itemScrollController = ItemScrollController();

  @override
  void initState() {
    super.initState();
    _loadCurrentUser();
    _loadFriends();
    // Update text state for send button
    _textController.addListener(() {
      _textNotifier.value = _textController.text.trim().isNotEmpty;
    });
  }

  Future<void> _loadCurrentUser() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      setState(() => _isLoadingFriends = false);
      return;
    }
    try {
      final userDoc = await _firestore.collection('users').doc(uid).get();
      if (userDoc.exists && mounted) {
        setState(() {
          _currentUserUsername = userDoc['username'] as String? ?? uid;
        });
      } else {
        setState(() => _currentUserUsername = uid);
      }
    } catch (e) {
      setState(() => _currentUserUsername = uid);
    }
  }

  Future<void> _loadFriends() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      setState(() => _isLoadingFriends = false);
      return;
    }
    try {
      final userDoc = await _firestore.collection('users').doc(uid).get();
      if (!userDoc.exists) {
        setState(() => _isLoadingFriends = false);
        return;
      }
      final friendUsernamesList = List<String>.from(userDoc['friends'] ?? []);
      final profilePics = <String, String>{};
      final uids = <String, String>{};
      for (final username in friendUsernamesList) {
        try {
          final query =
              await _firestore
                  .collection('users')
                  .where('username', isEqualTo: username)
                  .limit(1)
                  .get();
          if (query.docs.isNotEmpty) {
            final doc = query.docs.first;
            profilePics[username] = doc['profilePic'] as String? ?? '';
            uids[username] = doc['uid'] as String? ?? '';
          } else {
            profilePics[username] = '';
            uids[username] = '';
          }
        } catch (e) {
          profilePics[username] = '';
          uids[username] = '';
        }
      }
      if (mounted) {
        setState(() {
          friends = friendUsernamesList;
          filteredFriends = friends;
          friendProfilePics = profilePics;
          friendUids = uids;
          _isLoadingFriends = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingFriends = false);
      }
    }
  }

  void showFullScreenImageDialog(BuildContext context, String imageUrl) {
    showDialog(
      context: context,
      builder:
          (context) => Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.all(10),
            child: GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Stack(
                children: [
                  Center(
                    child: Hero(
                      tag: imageUrl,
                      child: InteractiveViewer(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.network(
                            imageUrl,
                            fit: BoxFit.contain,
                            loadingBuilder: (context, child, loadingProgress) {
                              if (loadingProgress == null) return child;
                              return const Center(
                                child: CircularProgressIndicator(),
                              );
                            },
                            errorBuilder:
                                (context, error, stackTrace) =>
                                    const Center(child: Icon(Icons.error)),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 10,
                    right: 10,
                    child: IconButton(
                      icon: const Icon(
                        Icons.close,
                        color: Colors.white,
                        size: 30,
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

  void _filterFriends(String query) {
    setState(() {
      if (query.isEmpty) {
        filteredFriends = friends;
      } else {
        filteredFriends =
            friends
                .where(
                  (username) =>
                      username.toLowerCase().contains(query.toLowerCase()),
                )
                .toList();
      }
    });
  }

  Widget _buildFriendTile(String username) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16.0,
          vertical: 8.0,
        ),
        leading: CircleAvatar(
          radius: 28,
          backgroundImage:
              friendProfilePics[username]?.isNotEmpty == true
                  ? NetworkImage(friendProfilePics[username]!)
                  : null,
          child:
              friendProfilePics[username]?.isEmpty != false
                  ? const Icon(Icons.person, color: Colors.white70, size: 28)
                  : null,
        ),
        title: Text(
          username,
          style: const TextStyle(
            color: Colors.white,
            fontFamily: 'Inter',
            fontSize: 18,
            fontWeight: FontWeight.w500,
          ),
        ),
        onTap: () {
          setState(() {
            selectedFriend = username;
            _lastMessageCount = 0;
            _isInitialChatLoad = true; // Reset for new chat
          });
          // Reset scroll position to top to avoid old scroll position
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_scrollController.hasClients) {
              _scrollController.jumpTo(0);
            }
          });
        },
      ),
    );
  }

  String _getChatId(String username1, String username2) {
    return username1.compareTo(username2) < 0
        ? '${username1}_${username2}'
        : '${username2}_${username1}';
  }

  Future<void> _sendMessage(String messageText, {String? memeUrl, int? currentMessageCount}) async {
    if (selectedFriend == null || _currentUserUsername == null) return;
    final senderUid = _auth.currentUser?.uid;
    if (senderUid == null) return;
    final chatId = _getChatId(_currentUserUsername!, selectedFriend!);

    // Validate message word count
    final words = messageText.trim().split(RegExp(r'\s+')).length;
    if (messageText.isNotEmpty && words > 100) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Message exceeds 100 words',
            style: TextStyle(fontFamily: 'Inter'),
          ),
        ),
      );
      return;
    }

    final messageData = {
      'senderUid': senderUid,
      'text': messageText.isNotEmpty ? messageText : null,
      'memeUrl': memeUrl,
      'timestamp': FieldValue.serverTimestamp(),
      'expiresAt': Timestamp.fromDate(
        DateTime.now().add(const Duration(hours: 24)),
      ),
    };

    try {
      await _firestore.collection('chats').doc(chatId).set({
        'lastUpdated': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      final messageRef = await _firestore
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .add(messageData);
      _textController.clear();

      // Optimistically scroll to the bottom immediately
      if (_itemScrollController.isAttached && currentMessageCount != null && currentMessageCount > 0) {
        _itemScrollController.scrollTo(
          index: currentMessageCount, // This is the new message's index
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }

      // Add notification to recipient
      final recipientUsername = selectedFriend!;
      final recipientQuery =
          await _firestore
              .collection('users')
              .where('username', isEqualTo: recipientUsername)
              .limit(1)
              .get();
      if (recipientQuery.docs.isNotEmpty) {
        final recipientDoc = recipientQuery.docs.first;
        final now = DateTime.now();
        await _firestore.collection('users').doc(recipientDoc['uid']).update({
          'notifications': FieldValue.arrayUnion([
            {
              'from': _currentUserUsername!,
              'seen': false,
              'timestamp': Timestamp.fromDate(now),
              'type': 'message',
            },
          ]),
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed to send message: $e',
              style: const TextStyle(fontFamily: 'Inter'),
            ),
          ),
        );
      }
    }
  }

  Widget _buildMessageTile(DocumentSnapshot message) {
    final data = message.data() as Map<String, dynamic>? ?? {};
    final isMe = data['senderUid'] == _auth.currentUser?.uid;
    final timestamp =
        (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now();
    final expiresAt =
        (data['expiresAt'] as Timestamp?)?.toDate() ?? DateTime.now();
    final isMeme =
        data['memeUrl'] != null && data['memeUrl'].toString().isNotEmpty;
    if (expiresAt.isBefore(DateTime.now())) return const SizedBox.shrink();

    final formattedTime = DateFormat('h:mm a').format(timestamp);

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress:
            !isMeme && data['text']?.isNotEmpty == true
                ? () => _showCopyMenu(context, data['text'] as String)
                : null,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.75,
          ),
          decoration: BoxDecoration(
            color:
                isMe
                    ? const Color.fromARGB(255, 109, 232, 100)
                    : Colors.grey[850],
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            crossAxisAlignment:
                isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              if (isMeme)
                GestureDetector(
                  onTap:
                      () => showFullScreenImageDialog(
                        context,
                        data['memeUrl'] as String,
                      ),
                  child: Image.network(
                    data['memeUrl'] as String,
                    width: 200,
                    height: 200,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) {
                      return const Text(
                        'Failed to load meme',
                        style: TextStyle(
                          color: Colors.redAccent,
                          fontFamily: 'Inter',
                          fontSize: 16,
                        ),
                      );
                    },
                  ),
                )
              else
                Text(
                  data['text'] as String? ?? '',
                  style: TextStyle(
                    color: isMe ? Colors.black : Colors.white,
                    fontFamily: 'Inter',
                    fontSize: 16,
                  ),
                ),
              const SizedBox(height: 4),
              Text(
                formattedTime,
                style: TextStyle(
                  color: isMe ? Colors.black54 : Colors.white54,
                  fontFamily: 'Inter',
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showCopyMenu(BuildContext context, String messageText) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder:
          (context) => Container(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.copy, color: Colors.white),
                  title: const Text(
                    'Copy',
                    style: TextStyle(color: Colors.white, fontFamily: 'Inter'),
                  ),
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: messageText));
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Message copied to clipboard',
                          style: TextStyle(fontFamily: 'Inter'),
                        ),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_auth.currentUser == null) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Please log in to access chats',
                style: TextStyle(
                  color: Colors.redAccent,
                  fontFamily: 'Inter',
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 10),
              ElevatedButton(
                onPressed:
                    () => Navigator.pushReplacementNamed(context, '/login'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.greenAccent[400],
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: const Text(
                  'Go to Login',
                  style: TextStyle(color: Colors.black, fontFamily: 'Inter'),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (selectedFriend != null && _currentUserUsername != null) {
      final chatId = _getChatId(_currentUserUsername!, selectedFriend!);

      return Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.black,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(
              Icons.arrow_back_ios,
              color: Colors.white,
              size: 28,
            ),
            onPressed: () {
              setState(() {
                selectedFriend = null;
                _textController.clear();
                _textNotifier.value = false;
                _lastMessageCount = 0;
                _isInitialChatLoad = true;
              });
            },
          ),
          title: Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundImage:
                    friendProfilePics[selectedFriend!]?.isNotEmpty == true
                        ? NetworkImage(friendProfilePics[selectedFriend!]!)
                        : null,
                child:
                    friendProfilePics[selectedFriend!]?.isEmpty != false
                        ? const Icon(
                          Icons.person,
                          color: Colors.white70,
                          size: 18,
                        )
                        : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  selectedFriend!,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'Inter',
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          centerTitle: false,
        ),
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.black, Color(0xFF212121)],
            ),
          ),
          child: Column(
            children: [
              // Info message about message expiry
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  vertical: 8,
                  horizontal: 16,
                ),
                decoration: BoxDecoration(
                  color: Colors.grey[900]?.withOpacity(0.3),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.access_time, color: Colors.grey[400], size: 14),
                    const SizedBox(width: 6),
                    Text(
                      'Messages expire in 24h',
                      style: TextStyle(
                        color: Colors.grey[400],
                        fontFamily: 'Inter',
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: StreamBuilder<QuerySnapshot>(
                  stream:
                      _firestore
                          .collection('chats')
                          .doc(chatId)
                          .collection('messages')
                          .orderBy('timestamp', descending: false)
                          .snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(
                        child: CircularProgressIndicator(
                          color: Colors.greenAccent,
                        ),
                      );
                    }
                    if (snapshot.hasError) {
                      return const Center(
                        child: Text(
                          'Error loading messages',
                          style: TextStyle(
                            color: Colors.redAccent,
                            fontFamily: 'Inter',
                            fontSize: 16,
                          ),
                        ),
                      );
                    }
                    if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                      _isInitialChatLoad =
                          false; // No messages, no need for initial scroll
                      return const Center(
                        child: Text(
                          'No messages yet.',
                          style: TextStyle(
                            color: Colors.white70,
                            fontFamily: 'Inter',
                            fontSize: 18,
                          ),
                        ),
                      );
                    }
                    final messages = snapshot.data!.docs;

                    // Scroll to bottom ONLY on initial chat load
                    if (_isInitialChatLoad) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (_scrollController.hasClients) {
                          _scrollController.jumpTo(
                            _scrollController.position.maxScrollExtent,
                          );
                          _isInitialChatLoad = false;
                        }
                      });
                    }

                    return Column(
                      children: [
                        Expanded(
                          child: ScrollablePositionedList.builder(
                            itemScrollController: _itemScrollController,
                            initialScrollIndex: messages.length > 0 ? messages.length - 1 : 0,
                            itemCount: messages.length,
                            itemBuilder: (context, index) => _buildMessageTile(messages[index]),
                            padding: const EdgeInsets.symmetric(vertical: 8),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _textController,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontFamily: 'Inter',
                                  ),
                                  decoration: InputDecoration(
                                    hintText: 'Type a message...',
                                    hintStyle: const TextStyle(
                                      color: Colors.white70,
                                      fontFamily: 'Inter',
                                    ),
                                    filled: true,
                                    fillColor: Colors.grey[850],
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      borderSide: BorderSide.none,
                                    ),
                                    contentPadding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                      horizontal: 16,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              ValueListenableBuilder<bool>(
                                valueListenable: _textNotifier,
                                builder: (context, hasText, child) {
                                  return IconButton(
                                    icon: Icon(
                                      Icons.send,
                                      color: hasText ? Colors.greenAccent[400] : Colors.grey,
                                      size: 28,
                                    ),
                                    onPressed: hasText
                                        ? () => _sendMessage(
                                              _textController.text,
                                              currentMessageCount: messages.length,
                                            )
                                        : null,
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.black, Color(0xFF212121)],
          ),
        ),
        child: Column(
          children: [
            AppBar(
              backgroundColor: Colors.black,
              elevation: 0,
              leading: IconButton(
                icon: const Icon(
                  Icons.arrow_back_ios,
                  color: Colors.white,
                  size: 28,
                ),
                onPressed:
                    () => Navigator.pushReplacementNamed(context, '/home'),
              ),
              title: const Text(
                'Chats',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Inter',
                ),
              ),
              centerTitle: true,
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                decoration: InputDecoration(
                  hintText: 'Search friends...',
                  hintStyle: const TextStyle(
                    color: Colors.white70,
                    fontFamily: 'Inter',
                  ),
                  filled: true,
                  fillColor: Colors.grey[850],
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                  prefixIcon: const Icon(Icons.search, color: Colors.white70),
                  contentPadding: const EdgeInsets.symmetric(
                    vertical: 12,
                    horizontal: 16,
                  ),
                ),
                style: const TextStyle(
                  color: Colors.white,
                  fontFamily: 'Inter',
                ),
                onChanged: _filterFriends,
              ),
            ),
            Expanded(
              child:
                  _isLoadingFriends
                      ? const Center(
                        child: CircularProgressIndicator(
                          color: Colors.greenAccent,
                        ),
                      )
                      : filteredFriends.isEmpty
                      ? const Center(
                        child: Text(
                          'No friends found.',
                          style: TextStyle(
                            color: Colors.white70,
                            fontFamily: 'Inter',
                            fontSize: 18,
                          ),
                        ),
                      )
                      : ListView.builder(
                        padding: const EdgeInsets.only(bottom: 16),
                        itemCount: filteredFriends.length,
                        itemBuilder:
                            (context, index) =>
                                _buildFriendTile(filteredFriends[index]),
                      ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _textController.dispose();
    _textNotifier.dispose();
    _scrollController.dispose();
    super.dispose();
  }
}