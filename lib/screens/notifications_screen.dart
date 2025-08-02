import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({Key? key}) : super(key: key);

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  final uid = FirebaseAuth.instance.currentUser!.uid;
  final _users = FirebaseFirestore.instance.collection('users');

  List<Map<String, dynamic>> _notes = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetchNotes();
  }

  /* ── read + mark-seen ─────────────────────────────────────────── */
  Future<void> _fetchNotes() async {
    final userDoc = await _users.doc(uid).get();
    final data = userDoc.data() ?? {};
    final raw = List<Map<String, dynamic>>.from(data['notifications'] ?? []);

    raw.sort(
      (a, b) {
        DateTime getTime(dynamic t) {
          if (t is Timestamp) return t.toDate();
          if (t is String) return DateTime.parse(t);
          return DateTime.now();
        }
        return getTime(b['timestamp']).compareTo(getTime(a['timestamp']));
      },
    );

    // mark unseen → seen (only the flag)
    final patched =
        raw.map((n) => n['seen'] == true ? n : {...n, 'seen': true}).toList();
    await _users.doc(uid).update({'notifications': patched});

    setState(() {
      _notes = patched;
      _loading = false;
    });
  }

  /* ── helpers ─────────────────────────────────────────────────── */
  Future<void> _delete(Map<String, dynamic> n) async {
    await _users.doc(uid).update({
      'notifications': FieldValue.arrayRemove([n]),
    });
    _fetchNotes();
  }

  Future<void> _acceptRequest(String fromUser) async {
    final meRef = _users.doc(uid);
    final meSnap = await meRef.get();
    final myUsername = meSnap['username'];

    final fromSnap =
        await _users.where('username', isEqualTo: fromUser).limit(1).get();
    if (fromSnap.docs.isEmpty) return;
    final fromRef = fromSnap.docs.first.reference;

    // find the exact notification to remove
    final toRemove = _notes.firstWhere(
      (n) => n['type'] == 'friend_request' && n['from'] == fromUser,
      orElse: () => {},
    );

    await FirebaseFirestore.instance.runTransaction((txn) async {
      txn.update(meRef, {
        'friends': FieldValue.arrayUnion([fromUser]),
        'friendRequests': FieldValue.arrayRemove([fromUser]),
        if (toRemove.isNotEmpty)
          'notifications': FieldValue.arrayRemove([toRemove]),
      });
      txn.update(fromRef, {
        'friends': FieldValue.arrayUnion([myUsername]),
        'notifications': FieldValue.arrayUnion([
          {
            'type': 'friend_accept',
            'from': myUsername,
            'timestamp': DateTime.now().toIso8601String(),
            'seen': false,
          },
        ]),
      });
    });

    // remove from local notes to update UI
    if (toRemove.isNotEmpty) {
      setState(() {
        _notes.remove(toRemove);
      });
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('You and $fromUser are now friends 🎉')),
    );
  }

  Future<void> _rejectRequest(String fromUser) async {
    await _users.doc(uid).update({
      'friendRequests': FieldValue.arrayRemove([fromUser]),
      'notifications': FieldValue.arrayRemove([
        _notes.firstWhere(
          (n) => n['type'] == 'friend_request' && n['from'] == fromUser,
        ),
      ]),
  });
    _fetchNotes();
  }

  /* ── Clear All Notifications (except friend requests) ──────────── */
  Future<void> _clearAllNotifications() async {
    // Keep only friend request notifications
    final friendRequestNotes =
        _notes.where((n) => n['type'] == 'friend_request').toList();

    try {
      await _users.doc(uid).update({
        'notifications': friendRequestNotes,
      });
      await _fetchNotes(); // Refresh UI
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'All dismissable notifications cleared',
            style: TextStyle(fontFamily: 'Inter'),
          ),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Failed to clear notifications: $e',
            style: const TextStyle(fontFamily: 'Inter'),
          ),
        ),
      );
    }
  }

  /* ── UI ───────────────────────────────────────────────────────── */
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text(
          'Notifications',
          style: TextStyle(
            color: Colors.white,
            fontSize: 28,
            fontWeight: FontWeight.bold,
            fontFamily: 'Inter',
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (_notes.any((n) => n['type'] != 'friend_request')) // Show only if dismissable notifications exist
            Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: ElevatedButton(
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (context) => AlertDialog(
                      backgroundColor: Colors.grey[900],
                      title: const Text(
                        'Clear All Notifications',
                        style: TextStyle(
                          color: Colors.white,
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      content: const Text(
                        'Are you sure you want to clear all dismissable notifications? Friend requests will remain.',
                        style: TextStyle(
                          color: Colors.white70,
                          fontFamily: 'Inter',
                        ),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text(
                            'Cancel',
                            style: TextStyle(
                              color: Colors.white70,
                              fontFamily: 'Inter',
                            ),
                          ),
                        ),
                        ElevatedButton(
                          onPressed: () async {
                            Navigator.pop(context); // Close dialog
                            await _clearAllNotifications();
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.greenAccent[400],
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: const Text(
                            'Clear',
                            style: TextStyle(
                              color: Colors.black,
                              fontFamily: 'Inter',
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.greenAccent[400],
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: const Text(
                  'Clear All',
                  style: TextStyle(
                    color: Colors.black,
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: Colors.greenAccent),
            )
          : _notes.isEmpty
              ? const Center(
                  child: Text(
                    'No notifications yet.',
                    style: TextStyle(color: Colors.white70),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: _notes.length,
                  itemBuilder: (_, i) {
                    final n = _notes[i];
                    return Dismissible(
                      key: ValueKey(n.hashCode),
                      background: Container(
                        color: Colors.red,
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 20),
                        child: const Icon(Icons.delete, color: Colors.white),
                      ),
                      direction: n['type'] == 'friend_request'
                          ? DismissDirection.none
                          : DismissDirection.endToStart,
                      onDismissed: n['type'] == 'friend_request'
                          ? null
                          : (_) => _delete(n),
                      child: Card(
                        color: Colors.grey[900],
                        child: FutureBuilder<DocumentSnapshot>(
                          future: _users
                              .where('username', isEqualTo: n['from'])
                              .limit(1)
                              .get()
                              .then((s) => s.docs.first),
                          builder: (context, snapshot) {
                            String profilePic = '';
                            if (snapshot.hasData && snapshot.data!.exists) {
                              profilePic = snapshot.data!['profilePic'] ?? '';
                            }
                            return ListTile(
                              leading: CircleAvatar(
                                radius: 20,
                                backgroundImage: profilePic.isNotEmpty
                                    ? NetworkImage(profilePic)
                                    : const AssetImage(
                                        'assets/img/default_profile.png',
                                      ) as ImageProvider,
                              ),
                              title: Text(
                                _title(n),
                                style: const TextStyle(color: Colors.white),
                              ),
                              subtitle: Text(
                                _timeAgo(n['timestamp']),
                                style: const TextStyle(color: Colors.white54),
                              ),
                              trailing: _trailing(n),
                            );
                          },
                        ),
                      ),
                    );
                  },
                ),
    );
  }

  String _title(Map<String, dynamic> n) {
    switch (n['type']) {
      case 'friend_request':
        return '${n['from']} sent you a friend request';
      case 'friend_accept':
        return '${n['from']} accepted your friend request';
      case 'message':
        return '${n['from']} sent you a message';
      case 'meme_share':
        return '${n['from']} shared a meme with you';
      default:
        return 'Unknown notification';
    }
  }

  String _timeAgo(dynamic ts) {
    DateTime dt;
    if (ts is Timestamp) {
      dt = ts.toDate();
    } else if (ts is String) {
      dt = DateTime.parse(ts);
    } else {
      return '';
    }
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  Widget? _trailing(Map<String, dynamic> n) {
    if (n['type'] != 'friend_request') return null;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.close, color: Colors.redAccent),
          onPressed: () => _rejectRequest(n['from']),
        ),
        IconButton(
          icon: const Icon(Icons.check, color: Colors.greenAccent),
          onPressed: () => _acceptRequest(n['from']),
        ),
      ],
    );
  }
}