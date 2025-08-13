import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:memelusion/screens/auth/signup_screen.dart';
import 'package:memelusion/screens/auth/login_screen.dart';
import 'package:memelusion/screens/gesture_detector.dart';
import 'package:memelusion/screens/home_screen.dart';
import 'package:memelusion/screens/admin_panel.dart';
import 'package:memelusion/screens/notifications_screen.dart';
import 'package:memelusion/screens/profile_screen.dart';
import 'package:memelusion/screens/chat_screen.dart';
import 'package:memelusion/screens/settings_screen.dart';
import 'package:memelusion/screens/offline_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'firebase_options.dart';
import 'package:flutter_offline/flutter_offline.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  final prefs = await SharedPreferences.getInstance(); // ⬅ Added
  final isFirstLaunch = prefs.getBool('isFirstLaunch') ?? true; // ⬅ Added

  if (isFirstLaunch) {
    // ⬅ Added
    await prefs.setBool('isFirstLaunch', false); // ⬅ Added
    await prefs.remove('hasSeenGestures'); // ⬅ Added
    print("First launch detected – gesture tutorial will be shown."); // ⬅ Added
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Memelusion',
      theme: ThemeData(
        brightness: Brightness.dark,
        primaryColor: Colors.greenAccent,
        scaffoldBackgroundColor: Colors.black,
        textTheme: const TextTheme(
          bodyLarge: TextStyle(color: Colors.white, fontFamily: 'Inter'),
          bodyMedium: TextStyle(color: Colors.white70, fontFamily: 'Inter'),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.greenAccent,
            foregroundColor: Colors.black,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6),
            ),
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.white70),
      ),
      initialRoute: '/',
      routes: {
        '/': (context) => const AuthWrapper(),
        '/signup': (context) => SignupPage(),
        '/login': (context) => LoginPage(),
        '/home': (context) => HomePage(),
        '/profile': (context) => ProfileScreen(),
        '/admin': (context) => AdminPanel(),
        '/notifications': (context) => NotificationsPage(),
        '/chat': (context) => ChatScreen(),
        '/settings': (context) => SettingsScreen(),
        '/gestureTutorial':
            (context) => GestureTutorialScreen(
              onTutorialComplete: () {
                Navigator.pushReplacementNamed(context, '/home');
              },
            ),
      },
    );
  }
}

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  bool _isOnline = true;
  bool _isLoading = true;
  bool _showTutorial = false;
  bool _showLogin = false;

  @override
  void initState() {
    super.initState();
    _handleStartup();
  }

  Future<void> _handleStartup() async {
    await _checkConnectivity();

    if (!_isOnline) {
      setState(() => _isLoading = false);
      return;
    }

    final user = FirebaseAuth.instance.currentUser;

    // Step 1 — No user? Show login screen.
    if (user == null) {
      setState(() {
        _showLogin = true;
        _isLoading = false;
      });
      return;
    }

    // Step 2 — Verify user exists in Firestore
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get(const GetOptions(source: Source.serverAndCache));

    if (!doc.exists) {
      await FirebaseAuth.instance.signOut();
      setState(() {
        _showLogin = true;
        _isLoading = false;
      });
      return;
    }

    final userData = doc.data() as Map<String, dynamic>?;
    if (userData == null || userData['isAdmin'] == true) {
      await FirebaseAuth.instance.signOut();
      setState(() {
        _showLogin = true;
        _isLoading = false;
      });
      return;
    }

    // Step 3 — Check if tutorial should be shown
    final prefs = await SharedPreferences.getInstance();
    final hasSeenTutorial = prefs.getBool('hasSeenGestures') ?? false;

    if (!hasSeenTutorial) {
      setState(() {
        _showTutorial = true;
        _isLoading = false;
      });
    } else {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _checkConnectivity() async {
    try {
      final connectivityResult = await Connectivity().checkConnectivity();
      if (mounted) {
        setState(() {
          _isOnline = !connectivityResult.contains(ConnectivityResult.none);
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isOnline = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const SplashScreen();
    }

    if (!_isOnline) {
      return OfflineScreen(onRetry: _handleStartup);
    }

    if (_showLogin) {
      return LoginPage(
        onLoginSuccess: () async {
          // After login, run startup again so tutorial check happens now
          setState(() {
            _isLoading = true;
            _showLogin = false;
          });
          await _handleStartup();
        },
      );
    }

    if (_showTutorial) {
      return GestureTutorialScreen(
        onTutorialComplete: () async {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool('hasSeenGestures', true);
          Navigator.pushReplacementNamed(context, '/home');
        },
      );
    }

    return HomePage();
  }
}

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.black,
      body: Center(child: CircularProgressIndicator(color: Colors.greenAccent)),
    );
  }
}
