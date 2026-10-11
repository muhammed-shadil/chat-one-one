import 'package:flutter/material.dart';

import '../config.dart';
import '../models/message.dart';
import '../services/chat_service.dart';
import '../services/identity.dart';
import 'chat_screen.dart';

/// First launch only: pick which of the two people this phone belongs to.
/// This is the app's whole "login".
class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final _name = TextEditingController();
  Map<String, Member>? _members;
  Object? _error;
  String? _selected;

  @override
  void initState() {
    super.initState();
    _name.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _error = null;
      _members = null;
    });
    try {
      final members = await ChatService.fetchMembers();
      if (mounted) setState(() => _members = members);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  void _select(String id) {
    setState(() {
      _selected = id;
      _name.text = _members?[id]?.name ?? '';
    });
  }

  Future<void> _continue() async {
    final me = _selected!;
    ChatService.saveName(me, _name.text.trim()).ignore();
    await Identity.save(me);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => ChatScreen(me: me)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final canContinue = _selected != null && _name.text.trim().isNotEmpty;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(Icons.forum_rounded, size: 64, color: scheme.primary),
                  const SizedBox(height: 16),
                  Text('Just the two of you',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Text(
                    'No account needed. Tell this phone who you are — '
                    'you only do this once.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 32),
                  if (_error != null)
                    _ErrorBox(error: _error!, onRetry: _load)
                  else if (_members == null)
                    const Center(child: CircularProgressIndicator())
                  else ...[
                    _personCard(kPerson1, 'Person 1'),
                    const SizedBox(height: 10),
                    _personCard(kPerson2, 'Person 2'),
                    const SizedBox(height: 20),
                    TextField(
                      controller: _name,
                      enabled: _selected != null,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Your name',
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => canContinue ? _continue() : null,
                    ),
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: canContinue ? _continue : null,
                      style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(50)),
                      child: const Text('Start chatting'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _personCard(String id, String label) {
    final scheme = Theme.of(context).colorScheme;
    final name = _members?[id]?.name;
    final selected = _selected == id;
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: selected ? scheme.primary : scheme.outlineVariant,
          width: selected ? 2 : 1,
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: CircleAvatar(
          backgroundColor:
              selected ? scheme.primary : scheme.surfaceContainerHighest,
          foregroundColor: selected ? scheme.onPrimary : scheme.onSurfaceVariant,
          child: Text(id == kPerson1 ? '1' : '2'),
        ),
        title: Text(name ?? label,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(name == null ? 'Not set up yet' : 'I am $name'),
        trailing:
            selected ? Icon(Icons.check_circle, color: scheme.primary) : null,
        onTap: () => _select(id),
      ),
    );
  }
}

class _ErrorBox extends StatelessWidget {
  const _ErrorBox({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(
            "Couldn't reach the chat. Check your internet connection, and "
            'that the Firestore rules have been deployed.\n\n$error',
            style: TextStyle(color: scheme.onErrorContainer),
          ),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
        ],
      ),
    );
  }
}
