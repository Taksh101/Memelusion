import 'package:flutter/material.dart';
import '../services/message_service.dart';

class TestChatScreen extends StatefulWidget {
  const TestChatScreen({Key? key}) : super(key: key);

  @override
  _TestChatScreenState createState() => _TestChatScreenState();
}

class _TestChatScreenState extends State<TestChatScreen> {
  final ChatService _chatService = ChatService();

  final TextEditingController _controller = TextEditingController();

  final String currentUser = 'taksh';
  final String otherUser = 'raj';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Realtime Chat Test')),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: _chatService.streamMessages(
                username1: currentUser,
                username2: otherUser,
              ),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Center(child: CircularProgressIndicator());
                }
                final messages = snapshot.data ?? [];
                return ListView.builder(
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final msg = messages[index];
                    return ListTile(
                      title: Text(msg['text']),
                      subtitle: Text('From: ${msg['senderUsername']}'),
                    );
                  },
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration: InputDecoration(
                      hintText: 'Type a message...',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.send),
                  onPressed: () async {
                    final text = _controller.text.trim();
                    if (text.isEmpty) return;
                    await _chatService.sendMessage(
                      senderUsername: currentUser,
                      receiverUsername: otherUser,
                      text: text,
                    );
                    _controller.clear();
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
