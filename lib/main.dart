import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:memelusion/screens/auth/signup_screen.dart';
import 'package:memelusion/screens/auth/login_screen.dart';
import 'package:memelusion/screens/home_screen.dart';
import 'package:memelusion/screens/admin_panel.dart';
import 'package:memelusion/screens/notifications_screen.dart';
import 'package:memelusion/screens/profile_screen.dart';
import 'package:memelusion/screens/chat_screen.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Memelusion',
      theme: ThemeData.dark(),
      initialRoute: '/signup',
      routes: {
        '/signup': (context) => SignupPage(),
        '/login': (context) => LoginPage(),
        '/home': (context) => HomePage(),
        '/profile': (context) => ProfileScreen(),
        '/admin': (context) => AdminPanel(),
        '/notifications': (context) => NotificationsPage(),
        '/chat': (context) => ChatScreen(),
      },
    );
  }
}
