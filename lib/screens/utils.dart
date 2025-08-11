import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

Future<bool> showExitConfirmationDialog(BuildContext context) async {
  return await showDialog<bool>(
        context: context,
        builder:
            (_) => AlertDialog(
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
                  onPressed: () => SystemNavigator.pop(),
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

void showFullScreenImageDialog(BuildContext context, String imageUrl) {
  showDialog(
    context: context,
    builder:
        (context) => GestureDetector(
          onTap: () => Navigator.of(context).pop(), // Tap outside to close
          child: Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.all(16), // Increased from 10
            child: Stack(
              children: [
                // Blur background
                Positioned.fill(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                    child: Container(
                      color: Colors.black.withOpacity(
                        0.7,
                      ), // Semi-transparent black
                    ),
                  ),
                ),
                Center(
                  child: GestureDetector(
                    onTap:
                        () => Navigator.of(context).pop(), // Tap image to close
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.3),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Hero(
                        tag: imageUrl,
                        child: InteractiveViewer(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.network(
                              imageUrl,
                              fit: BoxFit.contain,
                              loadingBuilder: (
                                context,
                                child,
                                loadingProgress,
                              ) {
                                if (loadingProgress == null) return child;
                                return const Center(
                                  child: CircularProgressIndicator(
                                    color:
                                        Colors
                                            .greenAccent, // Match app's accent
                                  ),
                                );
                              },
                              errorBuilder:
                                  (context, error, stackTrace) => const Center(
                                    child: Icon(
                                      Icons.error,
                                      color:
                                          Colors
                                              .redAccent, // Match app's accent
                                      size: 40,
                                    ),
                                  ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 5,
                  right: 5,
                  child: IconButton(
                    icon: const Icon(
                      Icons.close,
                      color: Colors.redAccent, // Changed to redAccent
                      size: 32, // Slightly larger
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
              ],
            ),
          ),
        ),
  );
}
