import 'package:flutter/material.dart';
import 'package:memelusion/screens/widget_utils.dart';
import 'package:memelusion/services/signup_service.dart';
import 'dart:ui';

class SignupPage extends StatefulWidget {
  @override
  _SignupPageState createState() => _SignupPageState();
}

class _SignupPageState extends State<SignupPage> {
  final SignUpServiceState _SignupService = SignUpServiceState();
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset('assets/img/background.jpg', fit: BoxFit.cover),
          BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 2, sigmaY: 2),
            child: Container(color: Colors.black.withAlpha(76)),
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
                    buildTextField(
                      controller: _SignupService.usernameController,
                      hint: "Username",
                      icon: Icons.person,
                      errorText: _SignupService.usernameError,
                    ),
                    SizedBox(height: 20),
                    buildTextField(
                      controller: _SignupService.emailController,
                      hint: "Email",
                      icon: Icons.email,
                      errorText: _SignupService.emailError,
                    ),
                    SizedBox(height: 20),
                    buildTextField(
                      controller: _SignupService.passwordController,
                      hint: "Password",
                      icon: Icons.lock,
                      obscureText: !_SignupService.passwordVisible,
                      suffixIcon: IconButton(
                        icon: Icon(
                          _SignupService.passwordVisible
                              ? Icons.visibility
                              : Icons.visibility_off,
                          color: Colors.greenAccent,
                        ),
                        onPressed: () {
                          setState(() {
                            _SignupService.passwordVisible =
                                !_SignupService.passwordVisible;
                          });
                        },
                      ),
                      errorText: _SignupService.passwordError,
                    ),
                    SizedBox(height: 20),
                    buildTextField(
                      controller: _SignupService.confirmPasswordController,
                      hint: "Confirm Password",
                      icon: Icons.lock_outline,
                      obscureText: !_SignupService.confirmPasswordVisible,
                      suffixIcon: IconButton(
                        icon: Icon(
                          _SignupService.confirmPasswordVisible
                              ? Icons.visibility
                              : Icons.visibility_off,
                          color: Colors.greenAccent,
                        ),
                        onPressed: () {
                          setState(() {
                            _SignupService.confirmPasswordVisible =
                                !_SignupService.confirmPasswordVisible;
                          });
                        },
                      ),
                      errorText: _SignupService.confirmPasswordError,
                    ),
                    SizedBox(height: 40),
                    ElevatedButton(
                      onPressed:
                          _SignupService.isLoading
                              ? null
                              : _SignupService.validateFields,
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
                          _SignupService.isLoading
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
}
