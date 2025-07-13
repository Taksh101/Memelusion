import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:ui';

class LoginPage extends StatefulWidget {
  @override
  _LoginPageState createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();

  String? _usernameError;
  String? _passwordError;

  bool _passwordVisible = false;
  bool _isAdminLogin = false;

  Future<void> _loginUser() async {
    try {
      print("🔍 Fetching user by username: ${_usernameController.text.trim()}");

      final snapshot =
          await FirebaseFirestore.instance
              .collection('users')
              .where('username', isEqualTo: _usernameController.text.trim())
              .get();

      print("📄 Documents found: ${snapshot.docs.length}");

      if (snapshot.docs.isEmpty) {
        if (!mounted) return;
        setState(() {
          _usernameError =
              _isAdminLogin ? "Invalid admin username" : "Invalid username";
          _passwordError = null;
        });
        return;
      }

      final userData = snapshot.docs.first.data();
      final email = userData['email'];
      final isAdmin = userData['isAdmin'] ?? false;

      if (_isAdminLogin && !isAdmin) {
        setState(() {
          _usernameError = "Not an admin account";
          _passwordError = null;
        });
        return;
      }

      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: _passwordController.text.trim(),
      );

      if (!mounted) return;
      Navigator.pushReplacementNamed(
        context,
        _isAdminLogin ? '/admin' : '/home',
      );
    } on FirebaseAuthException catch (e) {
      print("❌ FirebaseAuthException: ${e.code}");

      if (!mounted) return;
      setState(() {
        _usernameError = null;
        _passwordError = null;

        if (e.code == 'wrong-password') {
          _passwordError =
              _isAdminLogin ? "Invalid admin password" : "Invalid password";
        } else if (e.code == 'user-not-found') {
          _usernameError =
              _isAdminLogin ? "Invalid admin username" : "Invalid username";
        } else if (e.code == 'invalid-credential') {
          _passwordError =
              _isAdminLogin ? "Invalid admin password" : "Invalid password";
        } else {
          _passwordError = "Something went wrong";
        }
      });
    } catch (e) {
      print("❗Unexpected error: $e");

      if (!mounted) return;
      setState(() {
        _usernameError = null;
        _passwordError = "Something went wrong";
      });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }

  void _validateFields() {
    setState(() {
      _usernameError = null;
      _passwordError = null;

      if (_usernameController.text.isEmpty) {
        _usernameError = "Enter username";
      }
      if (_passwordController.text.isEmpty) {
        _passwordError = "Enter password";
      }
    });

    if (_usernameError == null && _passwordError == null) {
      _loginUser();
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
                  "Login",
                  style: TextStyle(
                    fontSize: 36,
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  "Welcome back! Log in to continue.",
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
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Checkbox(
                          value: _isAdminLogin,
                          onChanged: (val) {
                            setState(() {
                              _isAdminLogin = val ?? false;
                            });
                          },
                          activeColor: Colors.greenAccent,
                        ),
                        const Text(
                          "Login as admin",
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: _validateFields,
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
                      child: const Text(
                        "Login",
                        style: TextStyle(color: Colors.black, fontSize: 16),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      "Don't have an account?",
                      style: TextStyle(color: Colors.white),
                    ),
                    TextButton(
                      onPressed:
                          () => Navigator.pushReplacementNamed(
                            context,
                            '/signup',
                          ),
                      child: const Text(
                        "Signup",
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
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              prefixIcon: Icon(icon, color: Colors.greenAccent),
              suffixIcon: suffixIcon,
              hintText: hint,
              hintStyle: const TextStyle(color: Colors.white),
              border: InputBorder.none,
            ),
          ),
        ),
        if (errorText != null)
          Padding(
            padding: const EdgeInsets.only(left: 16, top: 4),
            child: Text(
              errorText,
              style: const TextStyle(color: Colors.redAccent, fontSize: 13),
            ),
          ),
      ],
    );
  }
}
