import 'package:flutter/material.dart';

Future<bool> showExitConfirmationDialog(BuildContext context) async {
  return await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: Colors.grey[850],
          contentPadding: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          content: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Exit App',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Inter',
                ),
              ),
              SizedBox(height: 12),
              Text(
                'Are you sure you want to exit the app?',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 18,
                  fontFamily: 'Inter',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text(
                'Cancel',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontFamily: 'Inter',
                ),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text(
                'Exit',
                style: TextStyle(
                  color: Colors.redAccent,
                  fontSize: 16,
                  fontFamily: 'Inter',
                ),
              ),
            ),
          ],
        ),
      ) ??
      false;
}