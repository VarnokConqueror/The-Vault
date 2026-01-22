import 'package:flutter/material.dart';
import '../models/chat_thread.dart';

class ChatScreen extends StatelessWidget {
  final ChatThread chat;

  const ChatScreen({super.key, required this.chat});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(chat.title),
      ),
      body: Padding(
        padding: const EdgeInsets.all(18.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Chat created.',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 10),
            Text('Chat ID: ${chat.id}'),
            const SizedBox(height: 6),
            Text('Created: ${chat.createdAt.toLocal()}'),
            const SizedBox(height: 18),
            const Text('Messages UI coming next...'),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => Navigator.pushNamed(context, '/chats'),
                child: const Text('Go to My Chats'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
