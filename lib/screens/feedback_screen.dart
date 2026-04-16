import 'dart:io';

import 'package:flutter/material.dart';

import '../core/feedback/feedback_client.dart';
import '../models/vault_theme.dart';
import '../state/push_runtime_store.dart';
import '../state/vault_store.dart';
import '../state/vault_theme_store.dart';

class FeedbackScreen extends StatefulWidget {
  const FeedbackScreen({super.key});

  @override
  State<FeedbackScreen> createState() => _FeedbackScreenState();
}

class _FeedbackScreenState extends State<FeedbackScreen> {
  final TextEditingController _controller = TextEditingController();

  String _category = 'general';
  bool _includeDiagnostics = false;
  bool _sending = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Map<String, dynamic> _buildDiagnostics() {
    return <String, dynamic>{
      'platform': Platform.isAndroid
          ? 'android'
          : Platform.isIOS
          ? 'ios'
          : Platform.operatingSystem,
      'firebaseStatus': PushRuntimeStore.firebaseStatus,
      'permissionStatus': PushRuntimeStore.permissionStatus,
      if (Platform.isIOS) 'apnsStatus': PushRuntimeStore.apnsStatus,
      'fcmStatus': PushRuntimeStore.fcmStatus,
      'relayStatus': PushRuntimeStore.relayStatus,
      'vaultReady': VaultStore.deviceId != null,
      'prekeysUploaded': VaultStore.lastPreKeyUploadAtMs != null,
    };
  }

  Future<void> _submit() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;

    setState(() => _sending = true);
    final ok = await FeedbackClient.submitAnonymousFeedback(
      message: text,
      category: _category,
      diagnostics: _includeDiagnostics ? _buildDiagnostics() : null,
    );
    if (!mounted) return;
    setState(() => _sending = false);
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Feedback could not be sent right now.')),
      );
      return;
    }
    _controller.clear();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Feedback sent to the Court.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme =
        Theme.of(context).extension<VaultThemeColors>() ??
        VaultThemeStore.config.activePalette.colors;
    return Scaffold(
      appBar: AppBar(title: const Text('Feedback'), centerTitle: true),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: theme.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: theme.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Anonymous by default',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: theme.text,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Write directly inside the Vault. No name or email is required. The Vault sends feedback through its own relay so you do not have to leave the app.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: theme.textSoft,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: _category,
                  decoration: const InputDecoration(
                    labelText: 'Category',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'general', child: Text('General')),
                    DropdownMenuItem(value: 'bug', child: Text('Bug')),
                    DropdownMenuItem(value: 'feature', child: Text('Feature')),
                    DropdownMenuItem(value: 'privacy', child: Text('Privacy')),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => _category = value);
                  },
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _controller,
                  minLines: 8,
                  maxLines: 14,
                  style: TextStyle(color: theme.text),
                  decoration: const InputDecoration(
                    labelText: 'Write your feedback',
                    alignLabelWithHint: true,
                    hintText:
                        'Tell the Court what is working, what is broken, or what needs to change.',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  value: _includeDiagnostics,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Include app diagnostics'),
                  subtitle: const Text(
                    'Adds push and Vault readiness status, but not your name or message history.',
                  ),
                  onChanged: (value) {
                    setState(() => _includeDiagnostics = value);
                  },
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 46,
                  child: ElevatedButton(
                    onPressed: _sending ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: theme.accent,
                      foregroundColor: theme.buttonText,
                      shape: const StadiumBorder(),
                    ),
                    child: Text(_sending ? 'Sending...' : 'Send Feedback'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
