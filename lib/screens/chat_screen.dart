import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'dart:async'; // Added for Timer

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
  List<String> friends = [];
  List<String> filteredFriends = [];
  Map<String, String> friendProfilePics = {}; // username -> profilePic
  String? selectedFriend; // username
  bool _isLoadingFriends = true;
  String? _currentUserUsername;
  Map<String, String> friendUids = {}; // username -> uid
  bool _isTyping = false;
  bool _isFriendTyping = false; // Add this to prevent flicker
  Timer? _typingTimer; // Add timer for typing indicator

  @override
  void initState() {
    super.initState();
    _loadCurrentUser();
    _loadFriends();
    _textController.addListener(_onTyping);
  }

  void _onTyping() {
    final newIsTyping = _textController.text.isNotEmpty;
    if (newIsTyping != _isTyping &&
        selectedFriend != null &&
        _currentUserUsername != null) {
      setState(() => _isTyping = newIsTyping);
      final chatId = _getChatId(_currentUserUsername!, selectedFriend!);
      print('🖊️ Typing status changed: $_currentUserUsername is now ${newIsTyping ? "typing" : "not typing"}');
      
      // Cancel previous timer if exists
      _typingTimer?.cancel();
      
      if (newIsTyping) {
        // Start typing
        _firestore
            .collection('chats')
            .doc(chatId)
            .set({
              'typing_${_currentUserUsername!}': true,
              'lastUpdated': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true))
            .catchError((e) {
              print('❌ Error updating typing status: $e');
            });
      } else {
        // Stop typing immediately
        _firestore
            .collection('chats')
            .doc(chatId)
            .set({
              'typing_${_currentUserUsername!}': false,
              'lastUpdated': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true))
            .catchError((e) {
              print('❌ Error updating typing status: $e');
            });
      }
    } else if (newIsTyping && _isTyping) {
      // User is still typing, reset the timer
      _typingTimer?.cancel();
      _typingTimer = Timer(const Duration(seconds: 3), () {
        if (_textController.text.isEmpty && selectedFriend != null && _currentUserUsername != null) {
          setState(() => _isTyping = false);
          final chatId = _getChatId(_currentUserUsername!, selectedFriend!);
          print('⏰ Typing timeout: $_currentUserUsername stopped typing');
          _firestore
              .collection('chats')
              .doc(chatId)
              .set({
                'typing_${_currentUserUsername!}': false,
                'lastUpdated': FieldValue.serverTimestamp(),
              }, SetOptions(merge: true))
              .catchError((e) {
                print('❌ Error updating typing status: $e');
              });
        }
      });
    }
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
          _currentUserUsername = userDoc['username'] ?? uid;
          print('🔍 Current user: $_currentUserUsername (uid=$uid)');
        });
      }
    } catch (e) {
      print('❌ Error loading current user: $e');
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
          final query = await _firestore.collection('users').where('username', isEqualTo: username).limit(1).get();
          if (query.docs.isNotEmpty) {
            final doc = query.docs.first;
            profilePics[username] = doc['profilePic'] ?? '';
            uids[username] = doc['uid'] ?? '';
          } else {
            profilePics[username] = '';
            uids[username] = '';
          }
        } catch (e) {
          print('❌ Error loading friend $username: $e');
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
      print('❌ Error loading friends: $e');
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
            insetPadding: EdgeInsets.all(10),
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
        filteredFriends = friends.where((username) => username.toLowerCase().contains(query.toLowerCase())).toList();
      }
    });
  }

  Widget _buildFriendTile(String username) {
    final chatId = _getChatId(_currentUserUsername!, username);
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .orderBy('timestamp', descending: true)
          .limit(1)
          .snapshots(),
      builder: (context, lastMsgSnap) {
        String lastMsg = '';
        String lastMsgTime = '';
        bool isMeme = false;
        String lastMsgId = '';
        if (lastMsgSnap.hasData && lastMsgSnap.data!.docs.isNotEmpty) {
          final msg = lastMsgSnap.data!.docs.first.data() as Map<String, dynamic>;
          isMeme = msg['memeUrl'] != null && msg['memeUrl'].toString().isNotEmpty;
          lastMsg = isMeme ? 'Shared a meme' : (msg['text'] ?? '');
          if (lastMsg.length > 30) lastMsg = lastMsg.substring(0, 30) + '...';
          final ts = (msg['timestamp'] as Timestamp?)?.toDate();
          if (ts != null) {
            final now = DateTime.now();
            final diff = now.difference(ts);
            if (diff.inDays > 0) {
              lastMsgTime = '${diff.inDays}d ago';
            } else if (diff.inHours > 0) {
              lastMsgTime = '${diff.inHours}h ago';
            } else if (diff.inMinutes > 0) {
              lastMsgTime = '${diff.inMinutes}m ago';
            } else {
              lastMsgTime = 'now';
            }
          }
          lastMsgId = lastMsgSnap.data!.docs.first.id;
        }
        return StreamBuilder<QuerySnapshot>(
          stream: _firestore
              .collection('chats')
              .doc(chatId)
              .collection('messages')
              .where('senderUid', isEqualTo: friendUids[username])
              .where('seenAt', isNull: true)
              .snapshots(),
          builder: (context, unseenSnap) {
            int unseenCount = 0;
            bool isLastMsgUnseen = false;
            if (unseenSnap.hasData) {
              unseenCount = unseenSnap.data!.docs.length;
              if (unseenSnap.data!.docs.isNotEmpty && lastMsgId.isNotEmpty) {
                isLastMsgUnseen = unseenSnap.data!.docs.any((doc) => doc.id == lastMsgId);
              }
            }
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16.0,
                  vertical: 8.0,
                ),
                leading: CircleAvatar(
                  radius: 28,
                  backgroundImage: friendProfilePics[username]?.isNotEmpty == true ? NetworkImage(friendProfilePics[username]!) : null,
                  child: friendProfilePics[username]?.isEmpty != false ? const Icon(Icons.person, color: Colors.white70, size: 28) : null,
                ),
                title: Text(
                  username,
                  style: TextStyle(
                    color: Colors.white,
                    fontFamily: 'Inter',
                    fontSize: 18,
                    fontWeight: unseenCount > 0 ? FontWeight.bold : FontWeight.w500,
                  ),
                ),
                subtitle: lastMsg.isNotEmpty
                    ? Row(
                        children: [
                          if (unseenCount > 0)
                            Container(
                              margin: const EdgeInsets.only(right: 8),
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.greenAccent[400],
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                unseenCount > 99 ? '99+' : unseenCount.toString(),
                                style: const TextStyle(
                                  color: Colors.black,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11,
                                  fontFamily: 'Inter',
                                ),
                              ),
                            ),
                          Flexible(
                            child: Text(
                              lastMsg,
                              style: TextStyle(
                                color: unseenCount > 0 ? Colors.greenAccent[100] : Colors.white70,
                                fontFamily: 'Inter',
                                fontSize: 15,
                                fontWeight: isLastMsgUnseen ? FontWeight.bold : FontWeight.normal,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (lastMsgTime.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(left: 8.0),
                              child: Text(
                                lastMsgTime,
                                style: const TextStyle(
                                  color: Colors.white38,
                                  fontSize: 12,
                                  fontFamily: 'Inter',
                                ),
                              ),
                            ),
                        ],
                      )
                    : null,
                onTap: () {
                  setState(() {
                    selectedFriend = username;
                    _isFriendTyping = false; // Reset typing state
                    _typingTimer?.cancel(); // Cancel any existing timer
                    print('👥 Selected friend: $username');
                  });
                  // Mark messages as seen when chat is opened
                  if (_currentUserUsername != null) {
                    final chatId = _getChatId(_currentUserUsername!, username);
                    _markMessagesAsSeen(chatId, username);
                  }
                },
              ),
            );
          },
        );
      },
    );
  }

  String _getChatId(String username1, String username2) {
    return username1.compareTo(username2) < 0 ? '${username1}_${username2}' : '${username2}_${username1}';
  }

  Future<void> _markMessagesAsSeen(String chatId, String friendUsername) async {
    try {
      print('Calling _markMessagesAsSeen for chatId=$chatId, friendUsername=$friendUsername, friendUid=${friendUids[friendUsername]}');
      // Print all messages in the chat for debugging
      final allMessages = await _firestore
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .get();
      for (final msg in allMessages.docs) {
        final d = msg.data();
        print('ALL MSGS: id=${msg.id}, senderUid=${d['senderUid']}, text=${d['text']}');
      }
      final messages = await _firestore
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .where('senderUid', isEqualTo: friendUids[friendUsername])
          .where('seenAt', isNull: true)
          .get();
      print('Found ${messages.docs.length} unseen messages from friendUid=${friendUids[friendUsername]}');
      final batch = _firestore.batch();
      for (final message in messages.docs) {
        final msgData = message.data();
        print('Checking message ${message.id}: senderUid=${msgData['senderUid']} seenAt=${msgData['seenAt']}');
        batch.update(message.reference, {
          'seenAt': FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();
      print('✅ Marked ${messages.docs.length} messages as seen in chatId=$chatId');
    } catch (e) {
      print('❌ Error marking messages as seen: $e');
    }
  }

  Future<void> _sendMessage(String messageText, {String? memeUrl}) async {
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
      'seenAt': null,
    };

    try {
      print('📤 Sending message to chats/$chatId/messages: $messageData');
      await _firestore.collection('chats').doc(chatId).set({
        'lastUpdated': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      final messageRef = await _firestore
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .add(messageData);
      print('✅ Message sent, messageId=${messageRef.id}');
      _textController.clear();
      setState(() => _isTyping = false);

      // Add notification to recipient (use Dart timestamp, not serverTimestamp)
      final recipientUsername = selectedFriend!;
      final recipientQuery = await _firestore.collection('users').where('username', isEqualTo: recipientUsername).limit(1).get();
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
            }
          ])
        });
        print('✅ Notification sent to ${recipientDoc['uid']} at $now');
      }

      await Future.delayed(const Duration(milliseconds: 100));
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    } catch (e) {
      print('❌ Error sending message: $e');
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
    final data = message.data() as Map<String, dynamic>;
    final isMe = data['senderUid'] == _auth.currentUser?.uid;
    final timestamp =
        (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now();
    final expiresAt =
        (data['expiresAt'] as Timestamp?)?.toDate() ?? DateTime.now();
    final seenAt = data['seenAt'] as Timestamp?;
    final isMeme =
        data['memeUrl'] != null && data['memeUrl'].toString().isNotEmpty;
    if (expiresAt.isBefore(DateTime.now())) return const SizedBox.shrink();

    final formattedTime = DateFormat('h:mm a').format(timestamp);

    print(
      'Rendering message: isMeme=$isMeme, memeUrl=${data['memeUrl']}, text=${data['text']}, seenAt=$seenAt',
    );
    
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: !isMeme && data['text']?.isNotEmpty == true ? () {
          _showCopyMenu(context, data['text']);
        } : null,
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
                      () => showFullScreenImageDialog(context, data['memeUrl']),
                  child: Image.network(
                    data['memeUrl'],
                    width: 200,
                    height: 200,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) {
                      print('❌ Failed to load meme: $error');
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
                  data['text'] ?? '',
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
      builder: (context) => Container(
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

  Widget _buildSeenIndicator() {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore
          .collection('chats')
          .doc(_getChatId(_currentUserUsername!, selectedFriend!))
          .collection('messages')
          .orderBy('timestamp', descending: true)
          .limit(1)
          .snapshots(),
      builder: (context, lastMsgSnap) {
        if (!lastMsgSnap.hasData || lastMsgSnap.data!.docs.isEmpty) {
          return const SizedBox.shrink();
        }
        
        final lastMsg = lastMsgSnap.data!.docs.first.data() as Map<String, dynamic>;
        final isLastMsgByMe = lastMsg['senderUid'] == _auth.currentUser?.uid;
        final seenAt = lastMsg['seenAt'] as Timestamp?;
        
        // Only show seen indicator if I sent the last message and it has been seen
        if (!isLastMsgByMe || seenAt == null) {
          return const SizedBox.shrink();
        }
        
        final seenTime = seenAt.toDate();
        final diff = DateTime.now().difference(seenTime);
        String seenText;
        
        if (diff.inSeconds < 60) {
          seenText = 'Seen just now';
        } else if (diff.inMinutes < 60) {
          seenText = 'Seen ${diff.inMinutes}m ago';
        } else if (diff.inHours < 24) {
          seenText = 'Seen ${diff.inHours}h ago';
        } else {
          seenText = 'Seen ${diff.inDays}d ago';
        }
        
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Align(
            alignment: Alignment.centerRight,
            child: Text(
              seenText,
              style: const TextStyle(
                color: Colors.white54,
                fontFamily: 'Inter',
                fontSize: 12,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildTypingIndicator() {
    return StreamBuilder<DocumentSnapshot>(
      stream: _firestore.collection('chats').doc(_getChatId(_currentUserUsername!, selectedFriend!)).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.hasError) {
          return const SizedBox.shrink();
        }
        final data = snapshot.data!.data() as Map<String, dynamic>?;
        final friendUsername = selectedFriend;
        final isFriendTyping = data?['typing_$friendUsername'] == true;
        
        // Update state only if changed to prevent unnecessary rebuilds
        if (isFriendTyping != _isFriendTyping) {
          print('👀 Friend typing status: ${selectedFriend} is now ${isFriendTyping ? "typing" : "not typing"}');
          WidgetsBinding.instance.addPostFrameCallback((_) {
            setState(() {
              _isFriendTyping = isFriendTyping;
            });
          });
        }
        
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          height: _isFriendTyping ? 30 : 0,
          child: _isFriendTyping
              ? const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Typing...',
                      style: TextStyle(
                        color: Colors.white70,
                        fontFamily: 'Inter',
                        fontSize: 14,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                )
              : const SizedBox.shrink(),
        );
      },
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

    if (selectedFriend != null) {
      final chatId = _getChatId(_currentUserUsername!, selectedFriend!);
      print('🔄 Opening chat room: chatId=$chatId');

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
                _isTyping = false;
              });
            },
          ),
          title: Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundImage: friendProfilePics[selectedFriend!]?.isNotEmpty == true 
                    ? NetworkImage(friendProfilePics[selectedFriend!]!) 
                    : null,
                child: friendProfilePics[selectedFriend!]?.isEmpty != false 
                    ? const Icon(Icons.person, color: Colors.white70, size: 18) 
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
              // Info message about message expiry - made less distracting
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                decoration: BoxDecoration(
                  color: Colors.grey[900]?.withOpacity(0.3),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.access_time,
                      color: Colors.grey[400],
                      size: 14,
                    ),
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
                      print('❌ Stream error: ${snapshot.error}');
                      return Center(
                        child: Text(
                          'Error: ${snapshot.error}',
                          style: const TextStyle(
                            color: Colors.redAccent,
                            fontFamily: 'Inter',
                            fontSize: 16,
                          ),
                        ),
                      );
                    }
                    if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
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
                    print(
                      '📥 Received ${messages.length} messages for chatId=$chatId',
                    );
                    
                    // Only auto-scroll if user is at the bottom
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (_scrollController.hasClients && 
                          _scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 100) {
                        _scrollController.animateTo(
                          _scrollController.position.maxScrollExtent,
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeOut,
                        );
                      }
                    });
                    
                    return ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: messages.length + 2, // +1 for seen indicator, +1 for typing indicator
                      itemBuilder: (context, index) {
                        if (index == messages.length) {
                          // Second to last item is the seen indicator
                          return _buildSeenIndicator();
                        } else if (index == messages.length + 1) {
                          // Last item is the typing indicator
                          return _buildTypingIndicator();
                        }
                        return _buildMessageTile(messages[index]);
                      },
                    );
                  },
                ),
              ),
              // Optimized typing indicator with separate state
              // StreamBuilder<DocumentSnapshot>(
              //   stream: _firestore.collection('chats').doc(chatId).snapshots(),
              //   builder: (context, snapshot) {
              //     if (!snapshot.hasData || snapshot.hasError) {
              //       return const SizedBox(height: 0);
              //     }
              //     final data = snapshot.data!.data() as Map<String, dynamic>?;
              //     final friendUsername = selectedFriend;
              //     final isFriendTyping = data?['typing_$friendUsername'] == true;
                  
              //     // Update state only if changed to prevent unnecessary rebuilds
              //     if (isFriendTyping != _isFriendTyping) {
              //       print('👀 Friend typing status: ${selectedFriend} is now ${isFriendTyping ? "typing" : "not typing"}');
              //       WidgetsBinding.instance.addPostFrameCallback((_) {
              //         setState(() {
              //           _isFriendTyping = isFriendTyping;
              //         });
              //       });
              //     }
                  
              //     return AnimatedContainer(
              //       duration: const Duration(milliseconds: 200),
              //       height: _isFriendTyping ? 30 : 0,
              //       child: _isFriendTyping
              //           ? const Padding(
              //               padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              //               child: Align(
              //                 alignment: Alignment.centerLeft,
              //                 child: Text(
              //                   'Typing...',
              //                   style: TextStyle(
              //                     color: Colors.white70,
              //                     fontFamily: 'Inter',
              //                     fontSize: 14,
              //                     fontStyle: FontStyle.italic,
              //                   ),
              //                 ),
              //               ),
              //             )
              //           : const SizedBox.shrink(),
              //     );
              //   },
              // ),
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
                    IconButton(
                      icon: Icon(
                        Icons.send,
                        color:
                            _isTyping ? Colors.greenAccent[400] : Colors.grey,
                        size: 28,
                      ),
                      onPressed:
                          _isTyping
                              ? () => _sendMessage(_textController.text)
                              : null,
                    ),
                  ],
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
    _textController.removeListener(_onTyping);
    _textController.dispose();
    _scrollController.dispose();
    _typingTimer?.cancel(); // Cancel the timer on dispose
    super.dispose();
  }
}