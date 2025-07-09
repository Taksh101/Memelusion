import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:memelusion/screens/auth/signup_screen.dart';
import 'package:memelusion/screens/auth/login_screen.dart';
import 'package:memelusion/screens/home_screen.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

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
      },
    );
  }
}
