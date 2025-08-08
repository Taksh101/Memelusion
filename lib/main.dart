import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_options.dart'; // Make sure you generated this with flutterfire configure

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Memelusion Home')),
      body: Center(
        child: ElevatedButton(
          onPressed: () async {
            await FirebaseFirestore.instance
                .collection('users')
                .doc('testuser')
                .set({
              'username': 'Test User',
              'profilePictureUrl': '',
              'friends': [],
            });

            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Test user created in Firestore!')),
            );
          },
          child: const Text('Create Test User'),
        ),
      ),
    );
  }
}
