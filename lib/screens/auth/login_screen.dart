import 'package:flutter/material.dart';
import 'package:memelusion/screens/widget_utils.dart';
import 'package:memelusion/services/login_service.dart';
import 'dart:ui';

class LoginPage extends StatefulWidget {
  @override
  _LoginPageState createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  LoginServiceState _LoginService = LoginServiceState();
  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async => true, // Exit app on back button
      child: Scaffold(
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
                      buildTextField(
                        controller: _LoginService.usernameController,
                        hint: "Username",
                        icon: Icons.person,
                        errorText: _LoginService.usernameError,
                      ),
                      SizedBox(height: 20),
                      buildTextField(
                        controller: _LoginService.passwordController,
                        hint: "Password",
                        icon: Icons.lock,
                        obscureText: !_LoginService.passwordVisible,
                        suffixIcon: IconButton(
                          icon: Icon(
                            _LoginService.passwordVisible
                                ? Icons.visibility
                                : Icons.visibility_off,
                            color: Colors.greenAccent,
                          ),
                          onPressed: () {
                            setState(() {
                              _LoginService.passwordVisible =
                                  !_LoginService.passwordVisible;
                            });
                          },
                        ),
                        errorText: _LoginService.passwordError,
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Checkbox(
                            value: _LoginService.isAdminLogin,
                            onChanged: (val) {
                              setState(() {
                                _LoginService.isAdminLogin = val ?? false;
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
                        onPressed:
                            _LoginService.isLoggingIn
                                ? null
                                : _LoginService.validateFields,
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
                            _LoginService.isLoggingIn
                                ? const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    color: Colors.black,
                                    strokeWidth: 2,
                                  ),
                                )
                                : const Text(
                                  "Login",
                                  style: TextStyle(
                                    color: Colors.black,
                                    fontSize: 16,
                                  ),
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
      ),
    );
  }
}
