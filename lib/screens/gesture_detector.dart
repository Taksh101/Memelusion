import 'dart:async';
import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

class GestureTutorialScreen extends StatefulWidget {
  final VoidCallback onTutorialComplete;
  const GestureTutorialScreen({Key? key, required this.onTutorialComplete})
    : super(key: key);
  @override
  _GestureTutorialScreenState createState() => _GestureTutorialScreenState();
}

class _GestureTutorialScreenState extends State<GestureTutorialScreen> {
  final PageController _pageController = PageController();
  int _currentIndex = 0;

  final List<Map<String, String>> gestureAnimations = [
    {
      'animation': 'assets/animations/gestures/swipe.json',
      'title': 'Swipe Left',
      'desc': 'Skip to the next meme instantly',
    },
    {
      'animation': 'assets/animations/gestures/swipe_left.json',
      'title': 'Swipe Right',
      'desc': 'Like memes to see more like them!',
    },
    {
      'animation': 'assets/animations/gestures/share.json',
      'title': 'Swipe Up',
      'desc': 'Share the best memes with your friends',
    },
  ];

  @override
  void initState() {
    super.initState();

    Timer.periodic(const Duration(seconds: 4), (Timer timer) {
      if (_currentIndex < gestureAnimations.length - 1) {
        _currentIndex++;
        _pageController.animateToPage(
          _currentIndex,
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeInOut,
        );
      } else {
        timer.cancel();
        _completeTutorial();
      }
    });

    _pageController.addListener(() {
      final index = _pageController.page?.round() ?? 0;
      if (_currentIndex != index) {
        setState(() => _currentIndex = index);
      }
    });
  }

  Future<void> _completeTutorial() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('hasSeenGestures', true);
    widget.onTutorialComplete(); // 👈 call the callback
  }

  Future<void> skipTutorial() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('hasSeenGestures', true);
    Navigator.pushReplacementNamed(context, '/home');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF0f2027), Color(0xFF203a43), Color(0xFF2c5364)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Stack(
          children: [
            PageView.builder(
              controller: _pageController,

              itemCount: gestureAnimations.length,
              itemBuilder: (context, index) {
                final gesture = gestureAnimations[index];
                return Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Expanded(
                      flex: 6,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20.0),
                        child: Lottie.asset(
                          gesture['animation']!,
                          repeat: true,
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 500),
                      transitionBuilder: (
                        Widget child,
                        Animation<double> animation,
                      ) {
                        return FadeTransition(
                          opacity: animation,
                          child: SlideTransition(
                            position: Tween<Offset>(
                              begin: const Offset(0.0, 0.3),
                              end: Offset.zero,
                            ).animate(animation),
                            child: child,
                          ),
                        );
                      },
                      child: Column(
                        key: ValueKey(_currentIndex),
                        children: [
                          Text(
                            gesture['title']!,
                            style: GoogleFonts.montserrat(
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 30),
                            child: Text(
                              gesture['desc']!,
                              style: GoogleFonts.montserrat(
                                fontSize: 16,
                                color: Colors.white70,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    if (index == gestureAnimations.length - 1)
                      ElevatedButton(
                        onPressed: _completeTutorial,
                        style: ElevatedButton.styleFrom(
                          foregroundColor: Colors.white,
                          backgroundColor: Colors.greenAccent.shade700,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 30,
                            vertical: 14,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                          elevation: 5,
                        ),
                        child: const Text(
                          "Get Started",
                          style: TextStyle(fontSize: 18),
                        ),
                      ),
                    const SizedBox(height: 50),
                  ],
                );
              },
            ),
            Positioned(
              top: 50,
              right: 20,
              child: ElevatedButton(
                onPressed: skipTutorial,
                style: ElevatedButton.styleFrom(
                  foregroundColor: Colors.white,
                  backgroundColor: Colors.greenAccent.shade700,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 10,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                  elevation: 5,
                ),
                child: const Text("Skip", style: TextStyle(fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
