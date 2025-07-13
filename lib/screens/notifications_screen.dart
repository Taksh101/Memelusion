// ────────────────────────────────────────────
// notifications_screen.dart
// route: '/notifications'  ->  const NotificationsPage()
// ────────────────────────────────────────────
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
      (a, b) => DateTime.parse(
        b['timestamp'],
      ).compareTo(DateTime.parse(a['timestamp'])),
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

  /* ── UI ───────────────────────────────────────────────────────── */
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text('Notifications'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body:
          _loading
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
                    direction: DismissDirection.endToStart,
                    onDismissed: (_) => _delete(n),
                    child: Card(
                      color: Colors.grey[900],
                      child: ListTile(
                        title: Text(
                          _title(n),
                          style: const TextStyle(color: Colors.white),
                        ),
                        subtitle: Text(
                          _timeAgo(n['timestamp']),
                          style: const TextStyle(color: Colors.white54),
                        ),
                        trailing: _trailing(n),
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
      default:
        return 'Unknown notification';
    }
  }

  String _timeAgo(String iso) {
    final dt = DateTime.parse(iso);
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
