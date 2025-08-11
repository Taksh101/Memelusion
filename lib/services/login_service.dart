import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class LoginService extends StatefulWidget {
  const LoginService({Key? key}) : super(key: key);

  @override
  LoginServiceState createState() => LoginServiceState();
}

class LoginServiceState extends State<LoginService> {
  final usernameController = TextEditingController();
  final passwordController = TextEditingController();

  String? usernameError;
  String? passwordError;

  bool passwordVisible = false;
  bool isAdminLogin = false;
  bool isLoggingIn = false;

  Future<void> loginUser() async {
    try {
      print("🔍 Fetching user by username: ${usernameController.text.trim()}");

      final snapshot =
          await FirebaseFirestore.instance
              .collection('users')
              .where('username', isEqualTo: usernameController.text.trim())
              .get();

      print("📄 Documents found: ${snapshot.docs.length}");

      if (snapshot.docs.isEmpty) {
        if (!mounted) return;
        setState(() {
          usernameError =
              isAdminLogin ? "Invalid admin username" : "Invalid username";
          passwordError = null;
        });
        return;
      }

      final userData = snapshot.docs.first.data();
      final email = userData['email'];
      final isAdmin = userData['isAdmin'] ?? false;

      if (isAdminLogin && !isAdmin) {
        setState(() {
          usernameError = "Not an admin account";
          passwordError = null;
        });
        return;
      }

      // New check: Block admin login if checkbox is unchecked
      if (isAdmin && !isAdminLogin) {
        setState(() {
          usernameError = "Check 'Login as admin' for admin accounts";
          passwordError = null;
        });
        return;
      }

      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: passwordController.text.trim(),
      );

      if (!mounted) return;
      Navigator.pushReplacementNamed(
        context,
        isAdminLogin ? '/admin' : '/home',
      );
    } on FirebaseAuthException catch (e) {
      print("❌ FirebaseAuthException: ${e.code}");

      if (!mounted) return;
      setState(() {
        usernameError = null;
        passwordError = null;

        if (e.code == 'wrong-password') {
          passwordError =
              isAdminLogin ? "Invalid admin password" : "Invalid password";
        } else if (e.code == 'user-not-found') {
          usernameError =
              isAdminLogin ? "Invalid admin username" : "Invalid username";
        } else if (e.code == 'invalid-credential') {
          passwordError =
              isAdminLogin ? "Invalid admin password" : "Invalid password";
        } else {
          passwordError = "Something went wrong";
        }
      });
    } catch (e) {
      print("❗Unexpected error: $e");

      if (!mounted) return;
      setState(() {
        usernameError = null;
        passwordError = "Something went wrong";
      });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }

  void validateFields() {
    setState(() {
      usernameError = null;
      passwordError = null;

      if (usernameController.text.isEmpty) {
        usernameError = "Enter username";
      }
      if (passwordController.text.isEmpty) {
        passwordError = "Enter password";
      }
    });

    if (usernameError == null && passwordError == null && !isLoggingIn) {
      setState(() => isLoggingIn = true); // Start spinner
      loginUser().then((_) {
        if (mounted) {
          setState(() => isLoggingIn = false); // Stop spinner
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container();
  }
}
