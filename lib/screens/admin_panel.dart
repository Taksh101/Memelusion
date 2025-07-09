import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AdminPanel extends StatefulWidget {
  const AdminPanel({super.key});

  @override
  State<AdminPanel> createState() => _AdminPanelState();
}

class _AdminPanelState extends State<AdminPanel> {
  final TextEditingController _urlController = TextEditingController();
  bool _isLoading = false;

  Future<void> _uploadMeme(String url) async {
    setState(() => _isLoading = true);
    final memeId = const Uuid().v4();
    await FirebaseFirestore.instance.collection('memes').doc(memeId).set({
      'memeId': memeId,
      'imageUrl': url,
      'shareCount': 0,
      'uploadTime': FieldValue.serverTimestamp(),
    });
    setState(() => _isLoading = false);
    _urlController.clear();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('✅ Meme uploaded!')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Admin Panel - Upload Meme')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _urlController,
              decoration: const InputDecoration(
                labelText: 'Image URL',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            _isLoading
                ? const CircularProgressIndicator()
                : ElevatedButton(
                  onPressed: () {
                    final url = _urlController.text.trim();
                    if (url.isNotEmpty) {
                      _uploadMeme(url);
                    }
                  },
                  child: const Text('Upload Meme'),
                ),
          ],
        ),
      ),
    );
  }
}
