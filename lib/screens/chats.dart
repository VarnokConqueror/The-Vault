import 'package:flutter/material.dart';

class ChatsScreen extends StatelessWidget {
  const ChatsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("My Chats"),
      ),
      body: const SafeArea(
        child: Center(
          child: Text(
            "My Chats — placeholder",
            style: TextStyle(fontSize: 18),
          ),
        ),
      ),
    );
  }
}
