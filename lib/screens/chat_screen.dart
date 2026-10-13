import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../config.dart';
import '../models/message.dart';
import '../services/chat_service.dart';
import '../services/identity.dart';
import '../services/push.dart';
import '../services/voice_player.dart';
import '../services/voice_recorder.dart';
import '../theme.dart';
import '../utils/format.dart';
import '../widgets/message_bubble.dart';
import '../widgets/presence_title.dart';
import '../widgets/reply_quote.dart';
import '../widgets/voice_message.dart';
import 'image_preview_screen.dart';
import 'setup_screen.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, required this.me});

  final String me;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

/// A photo or file I'm sending that hasn't finished uploading.
class _PendingUpload {
  _PendingUpload(this.label, {this.preview});

  final String label;
  final Uint8List? preview;
  final progress = ValueNotifier<double>(0);
}

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  late final ChatService _chat = ChatService(widget.me, onError: _showError);
  final _input = TextEditingController();
  final _inputFocus = FocusNode();
  final _scroll = ScrollController();

  /// Lets a tap on a quote find and scroll to the quoted message.
  final _itemKeys = <String, GlobalKey>{};
  final _uploads = <_PendingUpload>[];
  final _subs = <StreamSubscription<Object?>>[];
  StreamSubscription<List<Message>>? _messagesSub;

  List<Message> _messages = const [];
  bool _loaded = false;
  int _limit = kPageSize;
  bool _loadingMore = false;

  String? _myName;
  String? _otherName;

  bool _visible = true;
  bool _hasText = false;
  bool _typing = false;
  Timer? _typingTimer;
  Timer? _heartbeat;

  /// The message I'm replying to or editing, shown above the input.
  Message? _replyingTo;
  Message? _editing;

  /// Non-null while recording a voice message.
  VoiceRecorder? _recorder;

  /// The message flashed after jumping to it from a quote.
  String? _highlightId;
  Timer? _highlightTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scroll.addListener(_onScroll);
    _listenMessages();
    _subs
      ..add(_chat.watchMember(widget.me).listen(
          (m) => setState(() => _myName = m.name),
          onError: (_) {}))
      ..add(_chat.watchMember(_chat.other).listen(
          (m) => setState(() => _otherName = m.name),
          onError: (_) {}));
    _goOnline();
    if (!kUseEmulators) Push.register(widget.me);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _goOffline();
    _messagesSub?.cancel();
    for (final sub in _subs) {
      sub.cancel();
    }
    final recorder = _recorder;
    if (recorder != null) recorder.cancel().whenComplete(recorder.dispose);
    VoicePlayer.instance.stop();
    _highlightTimer?.cancel();
    _input.dispose();
    _inputFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------- messages

  void _listenMessages() {
    _messagesSub?.cancel();
    _messagesSub = _chat.watchMessages(_limit).listen(
      (messages) {
        setState(() {
          _messages = messages;
          _loaded = true;
          _loadingMore = false;
        });
        if (_visible) _chat.markSeen(messages);
      },
      onError: (Object e) {
        setState(() => _loaded = true);
        _showError(e);
      },
    );
  }

  /// The list is reversed, so the max scroll extent is the oldest message.
  void _onScroll() {
    final pos = _scroll.position;
    if (!_loadingMore &&
        _messages.length >= _limit &&
        pos.pixels > pos.maxScrollExtent - 400) {
      _loadingMore = true;
      _limit += kPageSize;
      _listenMessages();
    }
  }

  void _scrollToBottom() {
    if (_scroll.hasClients) {
      _scroll.animateTo(0,
          duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    }
  }

  // ------------------------------------------------------------- presence

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _visible = true;
        _goOnline();
        _chat.markSeen(_messages);
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        _visible = false;
        // Never keep the microphone on in the background.
        _finishRecording(send: false);
        _goOffline();
      case AppLifecycleState.inactive:
        break;
    }
  }

  void _goOnline() {
    _chat.setOnline(true);
    _heartbeat?.cancel();
    _heartbeat = Timer.periodic(
        const Duration(minutes: 1), (_) => _chat.setOnline(true));
  }

  void _goOffline() {
    if (_heartbeat == null) return;
    _heartbeat!.cancel();
    _heartbeat = null;
    _stopTyping();
    _chat.setOnline(false);
  }

  void _onInputChanged(String value) {
    final hasText = value.trim().isNotEmpty;
    if (hasText != _hasText) setState(() => _hasText = hasText);
    if (!hasText) {
      _stopTyping();
      return;
    }
    if (!_typing) {
      _typing = true;
      _chat.setTyping(true);
    }
    _typingTimer?.cancel();
    _typingTimer = Timer(const Duration(seconds: 4), _stopTyping);
  }

  void _stopTyping() {
    _typingTimer?.cancel();
    if (_typing) {
      _typing = false;
      _chat.setTyping(false);
    }
  }

  // -------------------------------------------------------------- sending

  void _sendText() {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    final editing = _editing;
    _input.clear();
    setState(() {
      _hasText = false;
      _editing = null;
    });
    _stopTyping();
    if (editing != null) {
      if (text != editing.text) _chat.editText(editing, text);
      return;
    }
    _chat.sendText(text, replyTo: _takeReply());
    _scrollToBottom();
  }

  /// The quote for the message being replied to, which is now sent.
  ReplyRef? _takeReply() {
    final m = _replyingTo;
    if (m == null) return null;
    setState(() => _replyingTo = null);
    return ReplyRef.of(m);
  }

  void _startReply(Message m) {
    if (_editing != null) _input.clear();
    setState(() {
      _replyingTo = m;
      _editing = null;
      _hasText = _input.text.trim().isNotEmpty;
    });
    _inputFocus.requestFocus();
  }

  void _startEdit(Message m) {
    _input.value = TextEditingValue(
      text: m.text ?? '',
      selection: TextSelection.collapsed(offset: (m.text ?? '').length),
    );
    setState(() {
      _editing = m;
      _replyingTo = null;
      _hasText = _input.text.trim().isNotEmpty;
    });
    _inputFocus.requestFocus();
  }

  void _cancelCompose() {
    if (_editing != null) _input.clear();
    setState(() {
      _editing = null;
      _replyingTo = null;
      _hasText = _input.text.trim().isNotEmpty;
    });
  }

  Future<void> _startRecording() async {
    final recorder = VoiceRecorder();
    try {
      if (!await recorder.start()) {
        await recorder.dispose();
        _showError('Allow the microphone to send voice messages.');
        return;
      }
    } catch (e) {
      await recorder.dispose();
      _showError(e);
      return;
    }
    if (!mounted) {
      await recorder.cancel();
      await recorder.dispose();
      return;
    }
    VoicePlayer.instance.stop();
    setState(() => _recorder = recorder);
    _chat.setRecording(true);
  }

  /// Stops recording, then sends the voice message or throws it away.
  Future<void> _finishRecording({required bool send}) async {
    final recorder = _recorder;
    if (recorder == null) return;
    setState(() => _recorder = null);
    _chat.setRecording(false);
    try {
      if (!send) {
        await recorder.cancel();
        return;
      }
      final note = await recorder.stop();
      if (note == null) {
        _showError('Too short to send. Record for at least a second.');
        return;
      }
      final replyTo = _takeReply();
      await _runUpload(
        _PendingUpload('Voice message'),
        (onProgress) => _chat.sendAudio(
          bytes: note.bytes,
          mimeType: note.mimeType,
          extension: note.extension,
          duration: note.duration,
          waveform: note.waveform,
          replyTo: replyTo,
          onProgress: onProgress,
        ),
      );
    } catch (e) {
      _showError(e);
    } finally {
      await recorder.dispose();
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    final XFile? picked;
    try {
      picked = await ImagePicker().pickImage(
        source: source,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 80,
      );
    } catch (e) {
      _showError(e);
      return;
    }
    if (picked == null) return;
    final name = picked.name;
    final bytes = await picked.readAsBytes();
    if (!mounted) return;

    final options = await Navigator.of(context).push<ImageSendOptions>(
      MaterialPageRoute(builder: (_) => ImagePreviewScreen(bytes: bytes)),
    );
    if (options == null) return;

    var width = 0, height = 0;
    try {
      final decoded = await decodeImageFromList(bytes);
      width = decoded.width;
      height = decoded.height;
      decoded.dispose();
    } catch (_) {
      // Unknown size: the bubble falls back to a square.
    }

    final replyTo = _takeReply();
    await _runUpload(
      _PendingUpload(options.viewOnce ? 'View once photo' : 'Photo',
          preview: bytes),
      (onProgress) => _chat.sendImage(
        bytes: bytes,
        name: name,
        width: width,
        height: height,
        caption: options.caption,
        viewOnce: options.viewOnce,
        replyTo: replyTo,
        onProgress: onProgress,
      ),
    );
  }

  Future<void> _pickFile() async {
    final PlatformFile file;
    try {
      final picked = await FilePicker.pickFile();
      if (picked == null) return;
      file = picked;
    } catch (e) {
      _showError(e);
      return;
    }

    final size = file.lengthSync() ?? await file.length() ?? 0;
    if (size > kMaxUploadBytes) {
      _showError('Files must be smaller than ${formatBytes(kMaxUploadBytes)}.');
      return;
    }
    final replyTo = _takeReply();
    await _runUpload(
      _PendingUpload(file.name),
      (onProgress) => _chat.sendFile(file,
          size: size, replyTo: replyTo, onProgress: onProgress),
    );
  }

  Future<void> _runUpload(
    _PendingUpload item,
    Future<void> Function(ProgressCallback onProgress) send,
  ) async {
    setState(() => _uploads.add(item));
    _scrollToBottom();
    try {
      await send((p) => item.progress.value = p);
    } catch (e) {
      _showError(e);
    } finally {
      if (mounted) setState(() => _uploads.remove(item));
      // Dispose after the bubble listening to it has been removed.
      WidgetsBinding.instance
          .addPostFrameCallback((_) => item.progress.dispose());
    }
  }

  void _showAttachSheet() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheet) {
        void pick(VoidCallback action) {
          Navigator.of(sheet).pop();
          action();
        }

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _AttachOption(
                  icon: Icons.insert_drive_file,
                  label: 'Document',
                  color: const Color(0xFF7F66FF),
                  onTap: () => pick(_pickFile),
                ),
                _AttachOption(
                  icon: Icons.camera_alt,
                  label: 'Camera',
                  color: const Color(0xFFFF2E74),
                  onTap: () => pick(() => _pickImage(ImageSource.camera)),
                ),
                _AttachOption(
                  icon: Icons.photo,
                  label: 'Gallery',
                  color: const Color(0xFFC861F9),
                  onTap: () => pick(() => _pickImage(ImageSource.gallery)),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // -------------------------------------------------------------- actions

  void _showActions(Message m) {
    final mine = m.senderId == widget.me;
    final text = m.text ?? '';
    final myReaction = m.reactions[widget.me];

    showModalBottomSheet<void>(
      context: context,
      builder: (sheet) {
        void then(VoidCallback action) {
          Navigator.of(sheet).pop();
          action();
        }

        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    for (final emoji in kReactions)
                      _ReactionChoice(
                        emoji: emoji,
                        selected: emoji == myReaction,
                        // Picking my current reaction again removes it.
                        onTap: () => then(() => _chat.react(
                            m, emoji == myReaction ? null : emoji)),
                      ),
                  ],
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.reply),
                title: const Text('Reply'),
                onTap: () => then(() => _startReply(m)),
              ),
              if (text.isNotEmpty)
                ListTile(
                  leading: const Icon(Icons.copy),
                  title: const Text('Copy text'),
                  onTap: () => then(
                      () => Clipboard.setData(ClipboardData(text: text))),
                ),
              if (mine && m.type == MessageType.text)
                ListTile(
                  leading: const Icon(Icons.edit_outlined),
                  title: const Text('Edit'),
                  onTap: () => then(() => _startEdit(m)),
                ),
              if (mine)
                ListTile(
                  leading: const Icon(Icons.delete_outline),
                  title: const Text('Delete for everyone'),
                  onTap: () => then(() => _confirmDelete(m)),
                ),
            ],
          ),
        );
      },
    );
  }

  /// Scrolls to a quoted message and flashes it.
  Future<void> _jumpTo(String id) async {
    if (_messages.any((m) => m.id == id)) {
      // The list only builds what's near the screen, so move up through the
      // loaded messages until the quoted one has been built.
      for (var i = 0; i < 50; i++) {
        if (!mounted) return;
        final target = _itemKeys[id]?.currentContext;
        if (target != null && target.mounted) {
          await Scrollable.ensureVisible(target,
              alignment: 0.5, duration: const Duration(milliseconds: 300));
          _highlightTimer?.cancel();
          setState(() => _highlightId = id);
          _highlightTimer = Timer(const Duration(milliseconds: 1200),
              () => mounted ? setState(() => _highlightId = null) : null);
          return;
        }
        final pos = _scroll.position;
        if (pos.pixels >= pos.maxScrollExtent) break;
        _scroll.jumpTo((pos.pixels + pos.viewportDimension * 0.8)
            .clamp(0.0, pos.maxScrollExtent));
        await WidgetsBinding.instance.endOfFrame;
      }
    }
    _showError("Can't show that message. It was deleted, or it's further "
        'back: scroll up to load older messages.');
  }

  String _nameOf(String personId) =>
      personId == widget.me ? 'You' : (_otherName ?? 'Them');

  Future<void> _confirmDelete(Message m) async {
    final ok = await _confirm(
      title: 'Delete message?',
      body: 'It will be removed for both of you.',
      action: 'Delete',
    );
    if (ok) _chat.deleteMessage(m);
  }

  Future<void> _rename() async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _NameDialog(initial: _myName ?? ''),
    );
    if (name == null || name.trim().isEmpty) return;
    ChatService.saveName(widget.me, name.trim())
        .then((_) {}, onError: _showError);
  }

  Future<void> _switchPerson() async {
    final ok = await _confirm(
      title: 'Switch person?',
      body: 'This phone will forget who you are and ask again. '
          'No messages are deleted.',
      action: 'Switch',
    );
    if (!ok) return;
    _goOffline();
    // This phone shouldn't get the old person's notifications any more.
    if (!kUseEmulators) await Push.unregister(widget.me);
    await Identity.clear();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const SetupScreen()),
      (_) => false,
    );
  }

  Future<bool> _confirm({
    required String title,
    required String body,
    required String action,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialog).pop(true),
            child: Text(action),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  void _showError(Object error) {
    if (!mounted) return;
    final text = switch (error) {
      FirebaseException(:final message?) => message,
      String() => error,
      _ => error.toString(),
    };
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  // ---------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final colors = ChatColors.of(context);
    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        titleSpacing: 12,
        title: PresenceTitle(chat: _chat),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              switch (value) {
                case 'rename':
                  _rename();
                case 'switch':
                  _switchPerson();
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'rename', child: Text('Change my name')),
              PopupMenuItem(value: 'switch', child: Text('Switch person')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(child: _buildMessages(colors)),
          _buildInputBar(colors),
        ],
      ),
    );
  }

  Widget _buildMessages(ChatColors colors) {
    if (!_loaded) return const Center(child: CircularProgressIndicator());

    if (_messages.isEmpty && _uploads.isEmpty) {
      return Center(
        child: Container(
          margin: const EdgeInsets.all(32),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: colors.chip,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            'Only the two of you can see these messages.\n'
            'Say hi${_otherName == null ? '' : ' to $_otherName'} 👋',
            textAlign: TextAlign.center,
            style: TextStyle(color: colors.meta, height: 1.4),
          ),
        ),
      );
    }

    final otherName = _otherName ?? 'Them';
    return ListView.builder(
      controller: _scroll,
      reverse: true,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _uploads.length + _messages.length,
      itemBuilder: (context, i) {
        if (i < _uploads.length) {
          final upload = _uploads[_uploads.length - 1 - i];
          return UploadingBubble(
            key: ObjectKey(upload),
            label: upload.label,
            preview: upload.preview,
            progress: upload.progress,
          );
        }

        final index = i - _uploads.length;
        final m = _messages[index];
        final older = index + 1 < _messages.length ? _messages[index + 1] : null;
        final newDay = older == null || !isSameDay(older.time, m.time);
        final mine = m.senderId == widget.me;

        final bubble = KeyedSubtree(
          key: _itemKeys.putIfAbsent(m.id, GlobalKey.new),
          child: MessageBubble(
            message: m,
            isMine: mine,
            chat: _chat,
            senderName: mine ? 'You' : otherName,
            replyName: m.replyTo == null ? null : _nameOf(m.replyTo!.senderId),
            highlighted: m.id == _highlightId,
            gapAbove: newDay || older.senderId != m.senderId ? 8 : 2,
            onLongPress: () => _showActions(m),
            onReply: () => _startReply(m),
            onTapReply: _jumpTo,
          ),
        );
        if (!newDay) return bubble;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [DayChip(day: m.time), bubble],
        );
      },
    );
  }

  Widget _buildInputBar(ChatColors colors) {
    final recorder = _recorder;
    final editing = _editing;
    final replyingTo = _replyingTo;

    final Widget action;
    if (recorder != null) {
      action = _roundButton(
          'Send voice message', Icons.send, () => _finishRecording(send: true));
    } else if (editing != null) {
      action = _roundButton('Save edit', Icons.check, _hasText ? _sendText : null);
    } else if (_hasText) {
      action = _roundButton('Send', Icons.send, _sendText);
    } else {
      action = _roundButton('Record voice message', Icons.mic, _startRecording);
    }

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(6, 4, 6, 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (recorder != null)
              IconButton(
                tooltip: 'Cancel recording',
                color: Colors.redAccent,
                onPressed: () => _finishRecording(send: false),
                icon: const Icon(Icons.delete_outline),
              ),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: colors.inputBar,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: const [
                    BoxShadow(
                        color: Colors.black12,
                        blurRadius: 1,
                        offset: Offset(0, 1)),
                  ],
                ),
                child: recorder != null
                    ? _RecordingIndicator(recorder: recorder)
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (replyingTo != null)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(6, 6, 6, 0),
                              child: ReplyQuote(
                                reply: ReplyRef.of(replyingTo),
                                name: _nameOf(replyingTo.senderId),
                                fromMe: replyingTo.senderId == widget.me,
                                onClose: _cancelCompose,
                              ),
                            ),
                          if (editing != null)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(6, 6, 6, 0),
                              child: QuoteBox(
                                title: 'Edit message',
                                text: editing.text ?? '',
                                icon: Icons.edit_outlined,
                                accent: Theme.of(context).colorScheme.primary,
                                onClose: _cancelCompose,
                                closeTooltip: 'Cancel edit',
                              ),
                            ),
                          _buildTextRow(colors, editing: editing != null),
                        ],
                      ),
              ),
            ),
            const SizedBox(width: 6),
            action,
          ],
        ),
      ),
    );
  }

  Widget _buildTextRow(ChatColors colors, {required bool editing}) {
    final field = TextField(
      controller: _input,
      focusNode: _inputFocus,
      onChanged: _onInputChanged,
      minLines: 1,
      maxLines: 6,
      keyboardType: TextInputType.multiline,
      textCapitalization: TextCapitalization.sentences,
      decoration: const InputDecoration(
        hintText: 'Message',
        border: InputBorder.none,
        contentPadding: EdgeInsets.symmetric(vertical: 12),
      ),
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        const SizedBox(width: 16),
        Expanded(
          // On the website, Enter sends and Shift+Enter starts a new line.
          child: kIsWeb
              ? CallbackShortcuts(
                  bindings: {
                    const SingleActivator(LogicalKeyboardKey.enter): _sendText,
                    const SingleActivator(LogicalKeyboardKey.escape): _cancelCompose,
                  },
                  child: field,
                )
              : field,
        ),
        if (!editing) ...[
          IconButton(
            tooltip: 'Attach',
            color: colors.meta,
            onPressed: _showAttachSheet,
            icon: Transform.rotate(
                angle: -0.7, child: const Icon(Icons.attach_file)),
          ),
          if (!_hasText)
            IconButton(
              tooltip: 'Camera',
              color: colors.meta,
              onPressed: () => _pickImage(ImageSource.camera),
              icon: const Icon(Icons.camera_alt),
            ),
        ],
      ],
    );
  }

  Widget _roundButton(String tooltip, IconData icon, VoidCallback? onPressed) {
    final scheme = Theme.of(context).colorScheme;
    return IconButton.filled(
      tooltip: tooltip,
      onPressed: onPressed,
      style: IconButton.styleFrom(
        fixedSize: const Size(48, 48),
        backgroundColor: scheme.primary,
        foregroundColor: Colors.white,
        disabledBackgroundColor: scheme.primary.withValues(alpha: 0.45),
        disabledForegroundColor: Colors.white70,
      ),
      icon: Icon(icon),
    );
  }
}

/// While recording: a blinking red dot, the time, and the live waveform.
class _RecordingIndicator extends StatefulWidget {
  const _RecordingIndicator({required this.recorder});

  final VoiceRecorder recorder;

  @override
  State<_RecordingIndicator> createState() => _RecordingIndicatorState();
}

class _RecordingIndicatorState extends State<_RecordingIndicator>
    with SingleTickerProviderStateMixin {
  late final _blink = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 600))
    ..repeat(reverse: true);

  @override
  void dispose() {
    _blink.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = ChatColors.of(context);
    final recorder = widget.recorder;
    return SizedBox(
      height: 48,
      child: Row(
        children: [
          const SizedBox(width: 16),
          FadeTransition(
            opacity: _blink,
            child: const Icon(Icons.fiber_manual_record,
                color: Colors.redAccent, size: 14),
          ),
          const SizedBox(width: 8),
          ValueListenableBuilder<Duration>(
            valueListenable: recorder.elapsed,
            builder: (context, elapsed, _) => Text(
              formatDuration(elapsed),
              style: const TextStyle(
                  fontSize: 15, fontFeatures: [FontFeature.tabularFigures()]),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ValueListenableBuilder<List<double>>(
              valueListenable: recorder.levels,
              builder: (context, levels, _) => Waveform(
                // Newest on the right; pad on the left until there's enough.
                bars: [
                  ...List.filled(40 - levels.length, 0),
                  for (final l in levels) (l * 100).round(),
                ],
                progress: 1,
                activeColor: Colors.redAccent.withValues(alpha: 0.8),
                idleColor: colors.meta,
                height: 26,
              ),
            ),
          ),
          const SizedBox(width: 16),
        ],
      ),
    );
  }
}

class _ReactionChoice extends StatelessWidget {
  const _ReactionChoice({
    required this.emoji,
    required this.selected,
    required this.onTap,
  });

  final String emoji;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: selected ? 'Remove $emoji' : 'React $emoji',
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: selected ? scheme.primary.withValues(alpha: 0.2) : null,
          ),
          child: Text(emoji, style: const TextStyle(fontSize: 26)),
        ),
      ),
    );
  }
}

class _AttachOption extends StatelessWidget {
  const _AttachOption({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: color,
              foregroundColor: Colors.white,
              child: Icon(icon, size: 26),
            ),
            const SizedBox(height: 8),
            Text(label, style: const TextStyle(fontSize: 13)),
          ],
        ),
      ),
    );
  }
}

class _NameDialog extends StatefulWidget {
  const _NameDialog({required this.initial});

  final String initial;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    void save() => Navigator.of(context).pop(_controller.text);
    return AlertDialog(
      title: const Text('Your name'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textCapitalization: TextCapitalization.words,
        onSubmitted: (_) => save(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: save, child: const Text('Save')),
      ],
    );
  }
}
