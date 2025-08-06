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
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
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
      ..initialize().then((_) {
        if (mounted) {
          print('✅ Video initialized successfully');
          setState(() {
            _isInitialized = true;
          });
          _controller.setLooping(false); // Play once
          _controller.play().then((_) {
            print('▶️ Video playback started');
          }).catchError((error) {
            print('❌ Error playing video: $error');
            setState(() {
              _hasError = true;
            });
          });
        }
      }).catchError((error) {
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
        Navigator.pushNamedAndRemoveUntil(
          context,
          '/auth',
          (route) => false,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: _hasError
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
  bool _hasNavigated = false;

  @override
  void initState() {
    super.initState();
    _checkConnectivity();
  }

  Future<void> _checkConnectivity() async {
    try {
      final connectivityResult = await Connectivity().checkConnectivity();
      if (mounted) {
        setState(() {
          _isOnline = !connectivityResult.contains(ConnectivityResult.none);
          print('📶 Connectivity check: ${_isOnline ? 'Online' : 'Offline'}');
        });
      }
    } catch (e) {
      print('❌ Error checking connectivity: $e');
      if (mounted) {
        setState(() => _isOnline = false);
      }
    }
  }

  void _navigateTo(String route) {
    if (!_hasNavigated && mounted) {
      print('🚀 Navigating to $route');
      setState(() {
        _hasNavigated = true;
      });
      Navigator.pushNamedAndRemoveUntil(
        context,
        route,
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    print('🛠️ Building AuthWrapper');
    if (!_isOnline) {
      print('📴 Showing OfflineScreen');
      return OfflineScreen(onRetry: _checkConnectivity);
    }

    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        print('🔥 Auth state: ${snapshot.connectionState}');
        if (snapshot.connectionState == ConnectionState.waiting) {
          print('⏳ Waiting for auth state');
          return const Center(child: CircularProgressIndicator(color: Colors.greenAccent));
        }
        if (!snapshot.hasData || snapshot.data == null) {
          print('🔓 No user logged in, routing to /login');
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _navigateTo('/login');
          });
          return const Center(child: CircularProgressIndicator(color: Colors.greenAccent));
        }
        // User is signed in; check admin status
        return FutureBuilder<DocumentSnapshot>(
          future: FirebaseFirestore.instance
              .collection('users')
              .doc(snapshot.data!.uid)
              .get(const GetOptions(source: Source.serverAndCache)),
          builder: (context, docSnapshot) {
            print('📄 Firestore snapshot: ${docSnapshot.connectionState}');
            if (docSnapshot.connectionState == ConnectionState.waiting) {
              print('⏳ Waiting for Firestore user data for UID: ${snapshot.data!.uid}');
              return const Center(child: CircularProgressIndicator(color: Colors.greenAccent));
            }
            if (!docSnapshot.hasData || docSnapshot.data == null || !docSnapshot.data!.exists) {
              print('❌ No user data found for UID: ${snapshot.data!.uid}, signing out');
              FirebaseAuth.instance.signOut();
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _navigateTo('/login');
              });
              return const Center(child: CircularProgressIndicator(color: Colors.greenAccent));
            }
            final userData = docSnapshot.data!.data() as Map<String, dynamic>?;
            if (userData == null) {
              print('❌ User data is null for UID: ${snapshot.data!.uid}, signing out');
              FirebaseAuth.instance.signOut();
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _navigateTo('/login');
              });
              return const Center(child: CircularProgressIndicator(color: Colors.greenAccent));
            }
            final isAdmin = userData['isAdmin'] ?? false;
            print('🔐 User ${snapshot.data!.uid} isAdmin: $isAdmin');
            if (isAdmin) {
              print('🚨 Admin detected, signing out to require re-login');
              FirebaseAuth.instance.signOut();
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _navigateTo('/login');
              });
              return const Center(child: CircularProgressIndicator(color: Colors.greenAccent));
            }
            // Non-admin user, route to /home
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _navigateTo('/home');
            });
            return const Center(child: CircularProgressIndicator(color: Colors.greenAccent));
          },
        );
      },
    );
  }
}