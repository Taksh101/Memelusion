import 'package:animated_splash_screen/animated_splash_screen.dart';
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

  @override
  Widget build(BuildContext context) {
    if (!_isOnline) {
      return OfflineScreen(onRetry: _checkConnectivity);
    }

    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          print('⏳ Waiting for auth state');
          return const SplashScreen();
        }
        if (!snapshot.hasData || snapshot.data == null) {
          print('🔓 No user logged in, routing to /login');
          WidgetsBinding.instance.addPostFrameCallback((_) {
            Navigator.pushNamedAndRemoveUntil(
              context,
              '/login',
              (route) => false,
            );
          });
          return const SplashScreen();
        }
        // User is signed in; check admin status
        return FutureBuilder<DocumentSnapshot>(
          future: FirebaseFirestore.instance
              .collection('users')
              .doc(snapshot.data!.uid)
              .get(const GetOptions(source: Source.serverAndCache)),
          builder: (context, docSnapshot) {
            if (docSnapshot.connectionState == ConnectionState.waiting) {
              print(
                '⏳ Waiting for Firestore user data for UID: ${snapshot.data!.uid}',
              );
              return const SplashScreen();
            }
            if (!docSnapshot.hasData ||
                docSnapshot.data == null ||
                !docSnapshot.data!.exists) {
              print(
                '❌ No user data found for UID: ${snapshot.data!.uid}, signing out',
              );
              FirebaseAuth.instance.signOut();
              WidgetsBinding.instance.addPostFrameCallback((_) {
                Navigator.pushNamedAndRemoveUntil(
                  context,
                  '/login',
                  (route) => false,
                );
              });
              return const SplashScreen();
            }
            final userData = docSnapshot.data!.data() as Map<String, dynamic>?;
            if (userData == null) {
              print(
                '❌ User data is null for UID: ${snapshot.data!.uid}, signing out',
              );
              FirebaseAuth.instance.signOut();
              WidgetsBinding.instance.addPostFrameCallback((_) {
                Navigator.pushNamedAndRemoveUntil(
                  context,
                  '/login',
                  (route) => false,
                );
              });
              return const SplashScreen();
            }
            final isAdmin = userData['isAdmin'] ?? false;
            print('🔐 User ${snapshot.data!.uid} isAdmin: $isAdmin');
            if (isAdmin) {
              print('🚨 Admin detected, signing out to require re-login');
              FirebaseAuth.instance.signOut();
              WidgetsBinding.instance.addPostFrameCallback((_) {
                Navigator.pushNamedAndRemoveUntil(
                  context,
                  '/login',
                  (route) => false,
                );
              });
              return const SplashScreen();
            }
            // Non-admin user, route to /home
            WidgetsBinding.instance.addPostFrameCallback((_) {
              Navigator.pushNamedAndRemoveUntil(
                context,
                '/home',
                (route) => false,
              );
            });
            return const SplashScreen();
          },
        );
      },
    );
  }
}

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedSplashScreen(
      splash: Center(
        child: Transform.scale(
          scale: 2, // Increase or decrease this value as needed
          child: Image.asset('assets/img/logo.png', fit: BoxFit.contain),
        ),
      ),
      nextScreen: SignupPage(),
      splashTransition: SplashTransition.fadeTransition,
      duration: 3000,
      backgroundColor: Colors.black,
    );
  }
}
