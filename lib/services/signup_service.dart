import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class SignUpService extends StatefulWidget {
  const SignUpService({Key? key}) : super(key: key);

  @override
  SignUpServiceState createState() => SignUpServiceState();
}

class SignUpServiceState extends State<SignUpService> {
  final usernameController = TextEditingController();
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final confirmPasswordController = TextEditingController();
  bool passwordVisible = false;
  bool confirmPasswordVisible = false;
  String? usernameError;
  String? emailError;
  String? passwordError;
  String? confirmPasswordError;
  bool isLoading = false;

  Future<void> signupUser() async {
    if (isLoading) return; // Prevent duplicate taps

    setState(() {
      isLoading = true;
    });

    try {
      // Clear previous field errors
      setState(() {
        usernameError = null;
        emailError = null;
      });

      // 1. Check if username exists
      final usernameQuery =
          await FirebaseFirestore.instance
              .collection('users')
              .where('username', isEqualTo: usernameController.text.trim())
              .get();

      if (usernameQuery.docs.isNotEmpty) {
        setState(() {
          usernameError = "This username is already taken.";
          isLoading = false;
        });
        return;
      }

      // 2. Create user account
      final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: emailController.text.trim(),
        password: passwordController.text.trim(),
      );

      // 3. Save profile
      await FirebaseFirestore.instance
          .collection('users')
          .doc(cred.user!.uid)
          .set({
            'username': usernameController.text.trim(),
            'email': emailController.text.trim(),
            'uid': cred.user!.uid,
            'profilePic': '',
            'profilePicDelete': '',
            'sharedMemesCount': 0,
            'likedMemesCount': 0,
            'isAdmin': false,
            'savedMemes': [],
            'friends': [],
            'friendRequests': [],
            'createdAt': Timestamp.now(),
          });

      if (!mounted) return;

      // 4. Show success
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Account created successfully.")));

      // 5. Sign out user so they can log in manually
      await FirebaseAuth.instance.signOut();

      // 6. Navigate to Login
      Navigator.pushReplacementNamed(context, '/login');
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() {
        if (e.code == 'email-already-in-use') {
          emailError = "This email is already registered.";
        } else if (e.code == 'weak-password') {
          passwordError = "The password is too weak.";
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Signup failed: ${e.message}")),
          );
        }
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Error: ${e.toString()}")));
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  void validateFields() {
    setState(() {
      usernameError = null;
      emailError = null;
      passwordError = null;
      confirmPasswordError = null;
    });

    // Validation flags
    bool isValid = true;

    // Username
    if (usernameController.text.isEmpty) {
      usernameError = "Enter username";
      isValid = false;
    } else if (!RegExp(
      r'^[a-zA-Z0-9]{3,20}$',
    ).hasMatch(usernameController.text)) {
      usernameError =
          "Username should only contain letters and numbers (3-20 characters)";
      isValid = false;
    }

    // Email
    if (emailController.text.isEmpty) {
      emailError = "Enter email";
      isValid = false;
    } else if (!RegExp(r'^\S+@\S+\.\S+$').hasMatch(emailController.text)) {
      emailError = "Enter valid email";
      isValid = false;
    }

    // Password
    if (passwordController.text.isEmpty) {
      passwordError = "Enter password";
      isValid = false;
    } else if (passwordController.text.length < 6) {
      passwordError = "At least 6 characters";
      isValid = false;
    } else if (!RegExp(
      r'^(?=.*[A-Za-z])(?=.*\d)(?=.*[@$!%*?&]).{6,}$',
    ).hasMatch(passwordController.text)) {
      passwordError = "Include letter, number, special char";
      isValid = false;
    }

    // Confirm Password
    if (confirmPasswordController.text != passwordController.text) {
      confirmPasswordError = "Passwords don't match";
      isValid = false;
    }

    if (isValid) {
      signupUser();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container();
  }
}
