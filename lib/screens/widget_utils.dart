import 'package:flutter/material.dart';

Widget buildTextField({
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
          color: Colors.grey.withAlpha(128),
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
