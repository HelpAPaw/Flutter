import 'package:flutter/material.dart';

class Answer extends StatelessWidget {
  final String text;
  Answer({required this.text});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 16,
        color: Colors.orange,
      ),
    );
  }
}
