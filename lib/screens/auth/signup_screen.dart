import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:ui';

class SignupPage extends StatefulWidget {
  @override
  _SignupPageState createState() => _SignupPageState();
}

class _SignupPageState extends State<SignupPage> {
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _passwordVisible = false;
  bool _confirmPasswordVisible = false;
  bool _isLoading = false;

  String? _usernameError;
  String? _emailError;
  String? _passwordError;
  String? _confirmPasswordError;

  Future<void> _signupUser() async {
    if (_isLoading) return; // Prevent duplicate taps

    setState(() {
      _isLoading = true;
    });

    try {
      // Clear previous field errors
      setState(() {
        _usernameError = null;
        _emailError = null;
      });

      // 1. Check if username exists
      final usernameQuery =
          await FirebaseFirestore.instance
              .collection('users')
              .where('username', isEqualTo: _usernameController.text.trim())
              .get();

      if (usernameQuery.docs.isNotEmpty) {
        setState(() {
          _usernameError = "This username is already taken.";
          _isLoading = false;
        });
        return;
      }

      // 2. Create user account
      final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      // 3. Save profile
      await FirebaseFirestore.instance
          .collection('users')
          .doc(cred.user!.uid)
          .set({
            'username': _usernameController.text.trim(),
            'email': _emailController.text.trim(),
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
          _emailError = "This email is already registered.";
        } else if (e.code == 'weak-password') {
          _passwordError = "The password is too weak.";
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
        _isLoading = false;
      });
    }
  }

  void _validateFields() {
    setState(() {
      _usernameError = null;
      _emailError = null;
      _passwordError = null;
      _confirmPasswordError = null;
    });

    // Validation flags
    bool isValid = true;

    // Username
    if (_usernameController.text.isEmpty) {
      _usernameError = "Enter username";
      isValid = false;
    } else if (!RegExp(
      r'^[a-zA-Z0-9]{3,20}$',
    ).hasMatch(_usernameController.text)) {
      _usernameError =
          "Username should only contain letters and numbers (3-20 characters)";
      isValid = false;
    }

    // Email
    if (_emailController.text.isEmpty) {
      _emailError = "Enter email";
      isValid = false;
    } else if (!RegExp(r'^\S+@\S+\.\S+$').hasMatch(_emailController.text)) {
      _emailError = "Enter valid email";
      isValid = false;
    }

    // Password
    if (_passwordController.text.isEmpty) {
      _passwordError = "Enter password";
      isValid = false;
    } else if (_passwordController.text.length < 6) {
      _passwordError = "At least 6 characters";
      isValid = false;
    } else if (!RegExp(
      r'^(?=.*[A-Za-z])(?=.*\d)(?=.*[@$!%*?&]).{6,}$',
    ).hasMatch(_passwordController.text)) {
      _passwordError = "Include letter, number, special char";
      isValid = false;
    }

    // Confirm Password
    if (_confirmPasswordController.text != _passwordController.text) {
      _confirmPasswordError = "Passwords don't match";
      isValid = false;
    }

    if (isValid) {
      _signupUser();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset('assets/img/background.jpg', fit: BoxFit.cover),
          BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 2, sigmaY: 2),
            child: Container(color: Colors.black.withOpacity(0.3)),
          ),
          SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 80),
            child: Column(
              children: [
                Text(
                  "Signup",
                  style: TextStyle(
                    fontSize: 36,
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  "Create your account",
                  style: TextStyle(fontSize: 16, color: Colors.white70),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 40),
                Column(
                  children: [
                    _buildTextField(
                      controller: _usernameController,
                      hint: "Username",
                      icon: Icons.person,
                      errorText: _usernameError,
                    ),
                    SizedBox(height: 20),
                    _buildTextField(
                      controller: _emailController,
                      hint: "Email",
                      icon: Icons.email,
                      errorText: _emailError,
                    ),
                    SizedBox(height: 20),
                    _buildTextField(
                      controller: _passwordController,
                      hint: "Password",
                      icon: Icons.lock,
                      obscureText: !_passwordVisible,
                      suffixIcon: IconButton(
                        icon: Icon(
                          _passwordVisible
                              ? Icons.visibility
                              : Icons.visibility_off,
                          color: Colors.greenAccent,
                        ),
                        onPressed: () {
                          setState(() {
                            _passwordVisible = !_passwordVisible;
                          });
                        },
                      ),
                      errorText: _passwordError,
                    ),
                    SizedBox(height: 20),
                    _buildTextField(
                      controller: _confirmPasswordController,
                      hint: "Confirm Password",
                      icon: Icons.lock_outline,
                      obscureText: !_confirmPasswordVisible,
                      suffixIcon: IconButton(
                        icon: Icon(
                          _confirmPasswordVisible
                              ? Icons.visibility
                              : Icons.visibility_off,
                          color: Colors.greenAccent,
                        ),
                        onPressed: () {
                          setState(() {
                            _confirmPasswordVisible = !_confirmPasswordVisible;
                          });
                        },
                      ),
                      errorText: _confirmPasswordError,
                    ),
                    SizedBox(height: 40),
                    ElevatedButton(
                      onPressed: _isLoading ? null : _validateFields,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.greenAccent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
                        ),
                        padding: EdgeInsets.symmetric(
                          horizontal: 80,
                          vertical: 15,
                        ),
                      ),
                      child:
                          _isLoading
                              ? SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  color: Colors.black,
                                  strokeWidth: 2,
                                ),
                              )
                              : Text(
                                "Signup",
                                style: TextStyle(
                                  color: Colors.black,
                                  fontSize: 16,
                                ),
                              ),
                    ),
                  ],
                ),
                SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      "Already have an account?",
                      style: TextStyle(color: Colors.white),
                    ),
                    TextButton(
                      onPressed:
                          () =>
                              Navigator.pushReplacementNamed(context, '/login'),
                      child: Text(
                        "Login",
                        style: TextStyle(
                          color: Colors.greenAccent,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    bool obscureText = false,
    Widget? suffixIcon,
    String? errorText,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          decoration: BoxDecoration(
            color: Colors.grey.withOpacity(0.5),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: Colors.greenAccent, width: 2),
          ),
          child: TextField(
            controller: controller,
            obscureText: obscureText,
            style: TextStyle(color: Colors.white),
            decoration: InputDecoration(
              prefixIcon: Icon(icon, color: Colors.greenAccent),
              suffixIcon: suffixIcon,
              hintText: hint,
              hintStyle: TextStyle(color: Colors.white),
              border: InputBorder.none,
            ),
          ),
        ),
        if (errorText != null)
          Padding(
            padding: const EdgeInsets.only(left: 16, top: 4),
            child: Text(
              errorText,
              style: TextStyle(color: Colors.redAccent, fontSize: 13),
            ),
          ),
      ],
    );
  }
}
