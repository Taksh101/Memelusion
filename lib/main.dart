import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:memelusion/screens/auth/signup_screen.dart';
import 'package:memelusion/screens/auth/login_screen.dart';
import 'package:memelusion/screens/home_screen.dart';
import 'package:memelusion/screens/admin_panel.dart';
import 'package:memelusion/screens/notifications_screen.dart';
import 'package:memelusion/screens/profile_screen.dart';
import 'package:memelusion/screens/chat_screen.dart';
import 'package:memelusion/screens/settings_screen.dart';
import 'package:memelusion/screens/offline_screen.dart';
import 'package:video_player/video_player.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:memelusion/screens/gesture_detector.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  final prefs = await SharedPreferences.getInstance();
  final isFirstLaunch = prefs.getBool('isFirstLaunch') ?? true;
  if (isFirstLaunch) {
    await prefs.setBool('isFirstLaunch', false);
    await prefs.remove('hasSeenGestures');
    print("First launch detected – gesture tutorial will be shown.");
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
      initialRoute: '/splash',
      routes: {
        '/splash': (context) => const SplashScreen(),
        '/auth': (context) => const AuthWrapper(),
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

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  late VideoPlayerController _controller;
  bool _hasError = false;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    print('🎥 Initializing SplashScreen video');
    _controller = VideoPlayerController.asset('assets/splashscreen.mp4')
      ..initialize()
          .then((_) {
            if (mounted) {
              print('✅ Video initialized successfully');
              setState(() {
                _isInitialized = true;
              });
              _controller.setLooping(false); // Play once
              _controller
                  .play()
                  .then((_) {
                    print('▶️ Video playback started');
                  })
                  .catchError((error) {
                    print('❌ Error playing video: $error');
                    setState(() {
                      _hasError = true;
                    });
                  });
            }
          })
          .catchError((error) {
            print('❌ Error initializing video: $error');
            if (mounted) {
              setState(() {
                _hasError = true;
              });
            }
          });

    // Navigate to auth after 3 seconds
    Future.delayed(const Duration(milliseconds: 3000), () {
      if (mounted) {
        print('🚀 Navigating to /auth after 3 seconds');
        Navigator.pushNamedAndRemoveUntil(context, '/auth', (route) => false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child:
            _hasError
                ? const Text(
                  'Failed to load splash video',
                  style: TextStyle(color: Colors.black87, fontSize: 18),
                )
                : _isInitialized
                ? Center(
                  child: AspectRatio(
                    aspectRatio: _controller.value.aspectRatio,
                    child: VideoPlayer(_controller),
                  ),
                )
                : const CircularProgressIndicator(color: Colors.greenAccent),
      ),
    );
  }

  @override
  void dispose() {
    print('🗑️ Disposing VideoPlayerController');
    _controller.dispose();
    super.dispose();
  }
}

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  bool _isOnline = true;
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
      return;
    }

    final user = FirebaseAuth.instance.currentUser;

    // Step 1 — No user? Show login screen.
    if (user == null) {
      setState(() {
        _showLogin = true;
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
      });
      return;
    }

    final userData = doc.data();
    // Admin check FIRST
    if (userData == null || userData['isAdmin'] == true) {
      await FirebaseAuth.instance.signOut();
      setState(() {
        _showLogin = true;
        _showTutorial = false;
      });
      return; // Prevent any further logic from running
    }

    // Step 3 — Check if tutorial should be shown (only for non-admin)
    final prefs = await SharedPreferences.getInstance();
    final hasSeenTutorial = prefs.getBool('hasSeenGestures') ?? false;
    if (!hasSeenTutorial && userData['isAdmin'] != true) {
      setState(() {
        _showTutorial = true;
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
    if (!_isOnline) {
      return OfflineScreen(onRetry: _handleStartup);
    }

    // Always prioritize login over tutorial
    if (_showLogin) {
      return LoginPage(
        onLoginSuccess: () async {
          // After login, run startup again so tutorial check happens now
          setState(() {
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
