import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import '../../../core/services/voice_note_service.dart';
import '../widgets/media_message_bubbles.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../../notes/models/note_item.dart';
import '../../notes/screens/note_editor_screen.dart';
import '../../notes/services/notes_service.dart';
import '../../../core/ui/mesh_widgets.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../../core/services/routing_service.dart';
import '../../../core/models/user.dart';
import '../../../core/models/message.dart';
import '../../../core/services/call_service.dart';
import '../../call/screens/call_screen.dart';
import '../../../core/security/contact_security_model.dart';
import '../../../core/transport/transport_type.dart';
import '../../../core/services/friend_service.dart';
import '../../../core/services/presence_service.dart';

class ChatScreen extends StatefulWidget {
  final UserProfile friend;
  final RoutingService routingService;
  final CallService callService;
  final FriendService? friendService;

  const ChatScreen({
    super.key,
    required this.friend,
    required this.routingService,
    required this.callService,
    this.friendService,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with TickerProviderStateMixin {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();

  String _searchQuery = '';
  bool _searchOpen = false;
  Timer? _draftTimer;
  final _voiceNoteService = VoiceNoteService();
  SharedPreferences? _draftPrefs;
  String get _draftKey =>
      'draft:${widget.routingService.messageService.baseUrl}:${widget.routingService.wifiMessagingService.currentUser.offlineMeshId}:${widget.friend.offlineMeshId}';

  Future<void> _restoreDraft() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    _draftPrefs = prefs;
    if (_controller.text.isEmpty) {
      _controller.text = prefs.getString(_draftKey) ?? '';
    }
  }

  Future<void> _saveDraft() async {
    final prefs = _draftPrefs;
    if (prefs == null) return;
    if (_controller.text.isEmpty) {
      await prefs.remove(_draftKey);
    } else {
      await prefs.setString(_draftKey, _controller.text);
    }
  }

  Future<void> _saveMessageToNotes(Message message) async {
    try {
      final service = NotesService();
      await service.initialize();
      final note = NoteItem(
          id: const Uuid().v4(),
          title: 'Chat with ${widget.friend.username}',
          content: message.content,
          labels: ['Chat']);
      await service.saveNote(note);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('Saved to Notes on this device'),
          action: SnackBarAction(
              label: 'Open',
              onPressed: () {
                Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => NoteEditorScreen(initialNote: note)));
              })));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Could not save the note. Please try again.')));
      }
    }
  }

  List<Message> _messages = [];
  bool _isLoading = true;
  String? _errorMessage;
  bool _isSending = false;
  ContactSecurityInfo? _contactSecurity;
  StreamSubscription? _incomingSub;

  // WhatsApp Features State
  Message? _replyingToMessage;
  bool _hasInputText = false;
  bool _isRecordingVoiceNote = false;
  int _voiceRecordDurationSeconds = 0;
  Timer? _voiceTimer;

  // Reaction Bar
  static const List<String> _quickEmojis = ['👍', '❤️', '😂', '😮', '😢', '🙏'];

  // Presence & Social State
  UserPresence? _peerPresence;
  StreamSubscription<UserPresence>? _presenceSubscription;
  Timer? _typingDebounce;
  bool _isBlocked = false;
  late final FriendService _friendService;

  @override
  void initState() {
    super.initState();
    _friendService = widget.friendService ??
        FriendService(
          baseUrl: widget.routingService.messageService.baseUrl,
          jwtToken: widget.routingService.messageService.jwtToken,
        );
    _checkBlockedStatus();
    _initPresence();
    _controller.addListener(_onTextChanged);
    _restoreDraft();
    _loadMessages();
    _loadContactSecurity();

    // Mark unread messages from this friend as read immediately
    widget.routingService.sendReadReceipt(widget.friend.offlineMeshId);

    // Subscribe to real-time incoming messages with strict recipient & sender isolation
    _incomingSub = widget.routingService.incomingMessages.listen((message) {
      final myId =
          widget.routingService.wifiMessagingService.currentUser.offlineMeshId;
      final friendId = widget.friend.offlineMeshId;

      // 1. Is this a message from this friend to me?
      final isFromFriendToMe = message.senderOfflineMeshId == friendId &&
          (message.recipientOfflineMeshId == null ||
              message.recipientOfflineMeshId == myId);

      // 2. Is this a message from me to this friend?
      final isFromMeToFriend = message.senderOfflineMeshId == myId &&
          (message.recipientOfflineMeshId == friendId);

      // 3. Or is this an existing message update (e.g. reaction or status change)?
      final isExistingUpdate = _messages.any((m) => m.id == message.id);

      if (isFromFriendToMe || isFromMeToFriend || isExistingUpdate) {
        if (mounted) {
          setState(() {
            _messages.removeWhere((m) => m.id == message.id);
            _messages.add(message);
            _messages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
          });
          _scrollToBottom();
          if (isFromFriendToMe) {
            widget.routingService.sendReadReceipt(widget.friend.offlineMeshId);
          }
        }
      }
    });
  }

  void _onTextChanged() {
    _draftTimer?.cancel();
    _draftTimer = Timer(const Duration(milliseconds: 400), _saveDraft);
    final hasText = _controller.text.trim().isNotEmpty;
    if (hasText != _hasInputText) {
      setState(() {
        _hasInputText = hasText;
      });
    }

    if (hasText) {
      widget.routingService.messageService.presenceService.sendTyping(true);
      _typingDebounce?.cancel();
      _typingDebounce = Timer(const Duration(seconds: 3), () {
        widget.routingService.messageService.presenceService.sendTyping(false);
      });
    } else {
      _typingDebounce?.cancel();
      widget.routingService.messageService.presenceService.sendTyping(false);
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _loadMessages() async {
    setState(() {
      _errorMessage = null;
    });

    final myId =
        widget.routingService.wifiMessagingService.currentUser.offlineMeshId;
    final friendId = widget.friend.offlineMeshId;

    // 1. Load locally persisted messages with strict recipient isolation
    try {
      final localMsgs = await widget.routingService.localStorageService
          .loadConversation(widget.friend.offlineMeshId);
      final filteredLocal = localMsgs.where((m) {
        if (m.content == '[Encrypted sent message]' ||
            m.content == 'Unable to decrypt message.') {
          return false;
        }
        // Strict isolation: must be between myId and friendId
        final isFromFriend = m.senderOfflineMeshId == friendId &&
            (m.recipientOfflineMeshId == null ||
                m.recipientOfflineMeshId == myId);
        final isFromMe = m.senderOfflineMeshId == myId &&
            (m.recipientOfflineMeshId == null ||
                m.recipientOfflineMeshId == friendId);
        return isFromFriend || isFromMe;
      }).toList();

      if (mounted && filteredLocal.isNotEmpty) {
        setState(() {
          _messages = filteredLocal;
          _isLoading = false;
        });
        _scrollToBottom();
      }
    } catch (e) {
      debugPrint('Error loading local messages: $e');
    }

    // 2. Fetch remote history from backend when online and merge
    try {
      final remoteMessages = await widget.routingService.messageService
          .getConversationHistory(widget.friend.offlineMeshId);
      final filteredRemote = remoteMessages.where((m) {
        if (m.content == '[Encrypted sent message]' ||
            m.content == 'Unable to decrypt message.') {
          return false;
        }
        final isFromFriend = m.senderOfflineMeshId == friendId &&
            (m.recipientOfflineMeshId == null ||
                m.recipientOfflineMeshId == myId);
        final isFromMe = m.senderOfflineMeshId == myId &&
            (m.recipientOfflineMeshId == null ||
                m.recipientOfflineMeshId == friendId);
        return isFromFriend || isFromMe;
      }).toList();

      await widget.routingService.localStorageService
          .saveMessages(widget.friend.offlineMeshId, filteredRemote);

      final merged = await widget.routingService.localStorageService
          .loadConversation(widget.friend.offlineMeshId);
      final cleanedMerged = merged.where((m) {
        if (m.content == '[Encrypted sent message]' ||
            m.content == 'Unable to decrypt message.') {
          return false;
        }
        final isFromFriend = m.senderOfflineMeshId == friendId &&
            (m.recipientOfflineMeshId == null ||
                m.recipientOfflineMeshId == myId);
        final isFromMe = m.senderOfflineMeshId == myId &&
            (m.recipientOfflineMeshId == null ||
                m.recipientOfflineMeshId == friendId);
        return isFromFriend || isFromMe;
      }).toList();

      if (mounted) {
        setState(() {
          _messages = cleanedMerged;
          _isLoading = false;
        });
        _scrollToBottom();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          if (_messages.isEmpty) {
            _errorMessage = 'Offline mode: no local history found';
          }
        });
      }
    }
  }

  Future<void> _sendMessage(
      {String? customContent, String mediaType = 'text'}) async {
    final text = customContent ?? _controller.text.trim();
    if (text.isEmpty || _isSending) return;

    final myId =
        widget.routingService.wifiMessagingService.currentUser.offlineMeshId;
    final quotedMsg = _replyingToMessage;

    setState(() {
      _isSending = true;
      _replyingToMessage = null;
    });

    try {
      final msg = await widget.routingService.sendMessage(
        widget.friend.offlineMeshId,
        text,
        replyToId: quotedMsg?.id,
        replyToContent: quotedMsg?.content,
        replyToSender: quotedMsg != null
            ? (quotedMsg.senderOfflineMeshId == myId
                ? 'You'
                : widget.friend.username)
            : null,
        mediaType: mediaType,
      );

      if (customContent == null) {
        _controller.clear();
      }

      if (mounted) {
        setState(() {
          _messages.removeWhere((m) => m.id == msg.id);
          _messages.add(msg);
          _messages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
        });
        _scrollToBottom();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSending = false;
        });
      }
    }
  }

  Future<void> _startVoiceNoteRecording() async {
    final started = await _voiceNoteService.startRecording();
    if (!started) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Microphone permission required for voice notes.')),
        );
      }
      return;
    }
    HapticFeedback.mediumImpact();
    widget.routingService.messageService.presenceService.sendRecording(true);
    setState(() {
      _isRecordingVoiceNote = true;
      _voiceRecordDurationSeconds = 0;
    });
    _voiceTimer?.cancel();
    _voiceTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _voiceRecordDurationSeconds++;
        });
      }
    });
  }

  Future<void> _cancelVoiceNoteRecording() async {
    widget.routingService.messageService.presenceService.sendRecording(false);
    _voiceTimer?.cancel();
    await _voiceNoteService.cancelRecording();
    if (mounted) {
      setState(() {
        _isRecordingVoiceNote = false;
        _voiceRecordDurationSeconds = 0;
      });
    }
  }

  Future<void> _sendVoiceNote() async {
    widget.routingService.messageService.presenceService.sendRecording(false);
    _voiceTimer?.cancel();
    final res = await _voiceNoteService.stopRecording();
    if (mounted) {
      setState(() {
        _isRecordingVoiceNote = false;
        _voiceRecordDurationSeconds = 0;
      });
    }
    if (res != null) {
      await _sendMedia(
        File(res.filePath),
        'audio',
        durationMs: res.durationMs,
      );
    }
  }

  Future<void> _sendMedia(File file, String mediaType,
      {int? durationMs}) async {
    if (!await file.exists()) return;
    setState(() => _isSending = true);
    try {
      final msg = await widget.routingService.sendMediaMessage(
        recipientOfflineMeshId: widget.friend.offlineMeshId,
        file: file,
        mediaType: mediaType,
        durationMs: durationMs,
      );
      if (mounted) {
        setState(() {
          _messages.removeWhere((m) => m.id == msg.id);
          _messages.add(msg);
          _messages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
        });
        _scrollToBottom();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send $mediaType: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  Future<void> _capturePhoto() async {
    try {
      final picker = ImagePicker();
      final photo =
          await picker.pickImage(source: ImageSource.camera, imageQuality: 85);
      if (photo != null) {
        await _sendMedia(File(photo.path), 'image');
      }
    } catch (e) {
      debugPrint('Error capturing photo: $e');
    }
  }

  Future<void> _pickGalleryImage() async {
    try {
      final picker = ImagePicker();
      final image =
          await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
      if (image != null) {
        await _sendMedia(File(image.path), 'image');
      }
    } catch (e) {
      debugPrint('Error picking image: $e');
    }
  }

  Future<void> _pickVideo() async {
    try {
      final picker = ImagePicker();
      final video = await picker.pickVideo(source: ImageSource.gallery);
      if (video != null) {
        await _sendMedia(File(video.path), 'video');
      }
    } catch (e) {
      debugPrint('Error picking video: $e');
    }
  }

  Future<void> _pickDocument() async {
    try {
      final result = await FilePicker.platform.pickFiles();
      if (result != null && result.files.single.path != null) {
        await _sendMedia(File(result.files.single.path!), 'file');
      }
    } catch (e) {
      debugPrint('Error picking file: $e');
    }
  }

  void _showAttachmentPicker() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => AttachmentPickerSheet(
        onCameraTap: _capturePhoto,
        onGalleryTap: _pickGalleryImage,
        onVideoTap: _pickVideo,
        onDocumentTap: _pickDocument,
      ),
    );
  }

  void _onReplyToMessage(Message msg) {
    setState(() {
      _replyingToMessage = msg;
    });
    _focusNode.requestFocus();
  }

  void _onToggleReaction(Message msg, String emoji) {
    widget.routingService.sendReaction(
      peerOfflineMeshId: widget.friend.offlineMeshId,
      messageId: msg.id,
      emoji: emoji,
    );
  }

  void _showForwardDialog(Message msg) {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        return FutureBuilder<List<UserProfile>>(
          future: widget.friendService != null
              ? widget.friendService!.getFriends()
              : FriendService(
                  baseUrl: widget.routingService.messageService.baseUrl,
                  jwtToken: widget.routingService.messageService.jwtToken,
                ).getFriends(),
          builder: (modalCtx, snapshot) {
            final friends = snapshot.data ?? [];
            return SafeArea(
              child: SizedBox(
                height: MediaQuery.sizeOf(modalCtx).height * 0.5,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      child: Text('Forward message to...',
                          style: Theme.of(modalCtx).textTheme.titleLarge),
                    ),
                    if (snapshot.connectionState == ConnectionState.waiting)
                      const Expanded(
                          child: Center(child: CircularProgressIndicator()))
                    else if (friends.isEmpty)
                      const Expanded(
                        child: Center(
                            child:
                                Text('No contacts available to forward to.')),
                      )
                    else
                      Expanded(
                        child: ListView.separated(
                          itemCount: friends.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (itemCtx, i) {
                            final f = friends[i];
                            return ListTile(
                              leading: MeshAvatar(name: f.username),
                              title: Text(f.username),
                              subtitle: Text(f.offlineMeshId),
                              trailing: const Icon(Icons.send_rounded,
                                  color: MeshColors.blue),
                              onTap: () async {
                                Navigator.pop(ctx);
                                await widget.routingService.sendMessage(
                                  f.offlineMeshId,
                                  msg.content,
                                  mediaType: msg.mediaType,
                                );
                                if (mounted) {
                                  scaffoldMessenger.showSnackBar(
                                    SnackBar(
                                        content:
                                            Text('Forwarded to ${f.username}')),
                                  );
                                }
                              },
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showEditDialog(Message msg) {
    final editController = TextEditingController(text: msg.content);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit message'),
        content: TextField(
          controller: editController,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Edit your message...',
            border: OutlineInputBorder(),
          ),
          maxLines: 4,
          minLines: 1,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final newText = editController.text.trim();
              if (newText.isNotEmpty && newText != msg.content) {
                Navigator.pop(ctx);
                await widget.routingService.editMessage(
                  peerOfflineMeshId: widget.friend.offlineMeshId,
                  messageId: msg.id,
                  newContent: newText,
                );
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteForEveryone(Message msg) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete for everyone?'),
        content: const Text(
          'This message will be deleted for everyone in this chat.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await widget.routingService.deleteMessageForEveryone(
                peerOfflineMeshId: widget.friend.offlineMeshId,
                messageId: msg.id,
              );
            },
            child: const Text(
              'Delete for everyone',
              style: TextStyle(
                  color: Colors.redAccent, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  void _showMessageOptions(Message msg) {
    final isMe = msg.senderOfflineMeshId != widget.friend.offlineMeshId;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Quick emoji reaction bar
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest
                          .withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: _quickEmojis.map((emoji) {
                        return InkWell(
                          borderRadius: BorderRadius.circular(20),
                          onTap: () {
                            Navigator.pop(ctx);
                            _onToggleReaction(msg, emoji);
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(6),
                            child: Text(emoji,
                                style: const TextStyle(fontSize: 26)),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
                ListTile(
                  leading:
                      const Icon(Icons.reply_rounded, color: MeshColors.blue),
                  title: const Text('Reply'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _onReplyToMessage(msg);
                  },
                ),
                ListTile(
                  leading:
                      const Icon(Icons.forward_rounded, color: MeshColors.blue),
                  title: const Text('Forward'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _showForwardDialog(msg);
                  },
                ),
                if (isMe && !msg.isDeleted)
                  ListTile(
                    leading:
                        const Icon(Icons.edit_outlined, color: MeshColors.blue),
                    title: const Text('Edit message'),
                    onTap: () {
                      Navigator.pop(ctx);
                      _showEditDialog(msg);
                    },
                  ),
                ListTile(
                  leading: const Icon(Icons.copy_rounded),
                  title: const Text('Copy text'),
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: msg.content));
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('Message copied to clipboard')),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.note_add_outlined),
                  title: const Text('Save to Notes'),
                  subtitle: const Text('Keep a personal copy on this device'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _saveMessageToNotes(msg);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.delete_outline_rounded,
                      color: Colors.redAccent),
                  title: const Text('Delete for me',
                      style: TextStyle(color: Colors.redAccent)),
                  onTap: () async {
                    Navigator.pop(ctx);
                    await widget.routingService.localStorageService
                        .removeMessage(widget.friend.offlineMeshId, msg.id);
                    setState(() {
                      _messages.removeWhere((m) => m.id == msg.id);
                    });
                  },
                ),
                if (isMe && !msg.isDeleted)
                  ListTile(
                    leading: const Icon(Icons.delete_forever_rounded,
                        color: Colors.redAccent),
                    title: const Text('Delete for everyone',
                        style: TextStyle(color: Colors.redAccent)),
                    onTap: () {
                      Navigator.pop(ctx);
                      _confirmDeleteForEveryone(msg);
                    },
                  ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _loadContactSecurity() async {
    final encService = widget.routingService.encryptionService;
    if (encService != null) {
      try {
        final secInfo = await encService
            .getContactSecurityInfo(widget.friend.offlineMeshId);
        if (mounted) {
          setState(() {
            _contactSecurity = secInfo;
          });
        }
      } catch (e) {
        debugPrint('Could not load security info for contact: $e');
      }
    }
  }

  void _showSecurityDialog() {
    final encService = widget.routingService.encryptionService;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          final isVerified = _contactSecurity?.verificationStatus ==
              VerificationStatus.VERIFIED;
          final isKeyChanged = _contactSecurity?.verificationStatus ==
              VerificationStatus.KEY_CHANGED;
          final fingerprint =
              _contactSecurity?.fingerprint ?? 'No public key registered yet';

          Color statusColor = MeshColors.orange;
          String statusText = 'UNVERIFIED';
          IconData statusIcon = Icons.lock_outline;

          if (isVerified) {
            statusColor = MeshColors.blue;
            statusText = 'VERIFIED';
            statusIcon = Icons.verified_user;
          } else if (isKeyChanged) {
            statusColor = MeshColors.orange;
            statusText = 'KEY CHANGED (WARNING)';
            statusIcon = Icons.warning_amber_rounded;
          }

          return AlertDialog(
            title: Row(
              children: [
                Icon(statusIcon, color: statusColor),
                const SizedBox(width: 8),
                const Text('E2EE Security',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Review the public-key fingerprint for ${widget.friend.username} before trusting this contact.',
                    style: const TextStyle(fontSize: 14),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: statusColor),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(statusIcon, size: 16, color: statusColor),
                        const SizedBox(width: 6),
                        Text(
                          statusText,
                          style: TextStyle(
                            color: statusColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (isKeyChanged) ...[
                    const SizedBox(height: 10),
                    const Text(
                      'Warning: The public key of this contact changed unexpectedly. Verify out-of-band before trusting this contact.',
                      style: TextStyle(
                          color: MeshColors.orange,
                          fontSize: 12,
                          fontWeight: FontWeight.w600),
                    ),
                  ],
                  const SizedBox(height: 16),
                  const Text(
                    'Safety Number / Fingerprint:',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                          color: Theme.of(context).colorScheme.outlineVariant),
                    ),
                    child: SelectableText(
                      fingerprint,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 13,
                        letterSpacing: 1.1,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Compare this fingerprint out-of-band (e.g. in person or via trusted audio call) to ensure your communication is not intercepted.',
                    style: TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
            actions: [
              if (encService != null && _contactSecurity != null)
                TextButton(
                  onPressed: () async {
                    final newStatus = isVerified
                        ? VerificationStatus.UNVERIFIED
                        : VerificationStatus.VERIFIED;
                    await encService.setContactVerification(
                        widget.friend.offlineMeshId, newStatus);
                    final updated = await encService
                        .getContactSecurityInfo(widget.friend.offlineMeshId);
                    setDialogState(() {
                      _contactSecurity = updated;
                    });
                    setState(() {
                      _contactSecurity = updated;
                    });
                  },
                  child: Text(
                    isVerified ? 'Mark as Unverified' : 'Mark as Verified',
                    style: TextStyle(
                        color: isVerified ? Colors.grey : MeshColors.blue),
                  ),
                ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Close'),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _typingDebounce?.cancel();
    widget.routingService.messageService.presenceService.sendTyping(false);
    _incomingSub?.cancel();
    _presenceSubscription?.cancel();
    _voiceNoteService.dispose();
    _voiceTimer?.cancel();
    _draftTimer?.cancel();
    _saveDraft();
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Widget _buildStatusTicks(String status, bool isMe, TransportType? transport) {
    if (!isMe) return const SizedBox.shrink();

    Widget tickIcon;
    switch (status.toLowerCase()) {
      case 'sending':
      case 'queued':
        tickIcon = const Icon(Icons.access_time_rounded,
            size: 12, color: Colors.white70);
        break;
      case 'sent':
        tickIcon =
            const Icon(Icons.check_rounded, size: 14, color: Colors.white70);
        break;
      case 'delivered':
        tickIcon =
            const Icon(Icons.done_all_rounded, size: 15, color: Colors.white70);
        break;
      case 'read':
      case 'seen':
        tickIcon = const Icon(Icons.done_all_rounded,
            size: 15, color: Color(0xFF34B7F1));
        break;
      default:
        tickIcon =
            const Icon(Icons.done_all_rounded, size: 15, color: Colors.white70);
    }

    String transportLabel = '';
    if (transport != null) {
      switch (transport) {
        case TransportType.WIFI_LAN:
          transportLabel = 'LAN';
          break;
        case TransportType.INTERNET:
          transportLabel = 'NET';
          break;
      }
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (transportLabel.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            margin: const EdgeInsets.only(right: 4),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              transportLabel,
              style: const TextStyle(
                  fontSize: 8,
                  fontWeight: FontWeight.bold,
                  color: Colors.white),
            ),
          ),
        ],
        tickIcon,
      ],
    );
  }

  Widget _buildQuotedBannerInsideBubble(Message msg, bool isMe, bool isDark) {
    if (msg.replyToContent == null) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: isMe
            ? Colors.black.withValues(alpha: 0.18)
            : (isDark
                ? Colors.black.withValues(alpha: 0.25)
                : Colors.grey.withValues(alpha: 0.12)),
        borderRadius: BorderRadius.circular(8),
        border: Border(
          left: BorderSide(
            color: isMe ? MeshColors.blue : MeshColors.blue,
            width: 3.5,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            msg.replyToSender ?? 'Message',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: isMe ? MeshColors.blue : MeshColors.blue,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            msg.replyToContent!,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              color: isMe
                  ? Colors.white70
                  : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReactionsBadge(Message msg, bool isMe) {
    if (msg.reactions == null || msg.reactions!.isEmpty) {
      return const SizedBox.shrink();
    }

    // Group reaction counts
    final counts = <String, int>{};
    for (var r in msg.reactions!.values) {
      counts[r] = (counts[r] ?? 0) + 1;
    }

    return GestureDetector(
      onTap: () => _showMessageOptions(msg),
      child: Container(
        margin: const EdgeInsets.only(top: 2),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: Theme.of(context)
                  .colorScheme
                  .outlineVariant
                  .withValues(alpha: 0.7)),
          boxShadow: [
            BoxBarShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: counts.entries.map((e) {
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Text(
                '${e.key}${e.value > 1 ? ' ${e.value}' : ''}',
                style: const TextStyle(fontSize: 11),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildDateHeader(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final msgDate = DateTime(date.year, date.month, date.day);

    String label;
    if (msgDate == today) {
      label = 'Today';
    } else if (msgDate == today.subtract(const Duration(days: 1))) {
      label = 'Yesterday';
    } else {
      label = '${date.day}/${date.month}/${date.year}';
    }

    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 12),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
        decoration: BoxDecoration(
          color: Theme.of(context)
              .colorScheme
              .surfaceContainerHighest
              .withValues(alpha: 0.75),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxBarShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  void _initPresence() {
    final ps = widget.routingService.messageService.presenceService;
    _peerPresence = ps.getPresence(widget.friend.offlineMeshId);
    _presenceSubscription = ps.presenceUpdates.listen((update) {
      if (update.offlineMeshId == widget.friend.offlineMeshId && mounted) {
        setState(() {
          _peerPresence = update;
        });
      }
    });
  }

  Future<void> _checkBlockedStatus() async {
    final isBlocked =
        await _friendService.isUserBlocked(widget.friend.offlineMeshId);
    if (mounted) {
      setState(() {
        _isBlocked = isBlocked;
      });
    }
  }

  Future<void> _toggleBlock() async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    if (_isBlocked) {
      await _friendService.unblockUser(widget.friend.offlineMeshId);
      if (mounted) {
        setState(() => _isBlocked = false);
        scaffoldMessenger.showSnackBar(
          SnackBar(content: Text('Unblocked ${widget.friend.username}')),
        );
      }
    } else {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Block ${widget.friend.username}?'),
          content: const Text(
            'Blocked contacts will no longer be able to send you messages or calls.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
              child: const Text('Block'),
            ),
          ],
        ),
      );
      if (confirm == true) {
        await _friendService.blockUser(widget.friend.offlineMeshId);
        if (mounted) {
          setState(() => _isBlocked = true);
          scaffoldMessenger.showSnackBar(
            SnackBar(content: Text('Blocked ${widget.friend.username}')),
          );
        }
      }
    }
  }

  Future<void> _clearConversation() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear conversation?'),
        content: const Text(
          'This will clear all messages in this conversation on this device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      for (final m in _messages) {
        await widget.routingService.localStorageService
            .removeMessage(widget.friend.offlineMeshId, m.id);
      }
      if (mounted) {
        setState(() {
          _messages.clear();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Conversation cleared')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final bool isNearby =
        widget.routingService.isPeerNearby(widget.friend.offlineMeshId);
    final bool isCloudOnline =
        widget.routingService.messageService.jwtToken.isNotEmpty;
    final isVerified =
        _contactSecurity?.verificationStatus == VerificationStatus.VERIFIED;
    final isKeyChanged =
        _contactSecurity?.verificationStatus == VerificationStatus.KEY_CHANGED;

    final visibleMessages = _messages
        .where(
            (m) => m.content.toLowerCase().contains(_searchQuery.toLowerCase()))
        .toList();

    // OfflineMesh conversation surfaces
    const outgoingColor = MeshColors.navy;
    final incomingColor = Theme.of(context).colorScheme.surface;

    return Scaffold(
      appBar: AppBar(
        flexibleSpace: const GlassSurface(
            blur: true, padding: EdgeInsets.zero, child: SizedBox.expand()),
        titleSpacing: 0,
        title: InkWell(
          onTap: _showSecurityDialog,
          child: Row(
            children: [
              Stack(
                children: [
                  MeshAvatar(name: widget.friend.username, size: 40),
                  if (isNearby || _peerPresence?.isOnline == true)
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: MeshColors.blue,
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: Theme.of(context).colorScheme.surface,
                              width: 2),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            widget.friend.username,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Icon(
                          isVerified
                              ? Icons.verified_user
                              : isKeyChanged
                                  ? Icons.warning_amber_rounded
                                  : Icons.lock_outline,
                          size: 15,
                          color: isVerified
                              ? MeshColors.blue
                              : isKeyChanged
                                  ? MeshColors.orange
                                  : Colors.grey.shade600,
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _isBlocked
                          ? 'Blocked'
                          : _peerPresence?.isRecording == true
                              ? 'recording audio...'
                              : _peerPresence?.isTyping == true
                                  ? 'typing...'
                                  : _peerPresence?.isOnline == true
                                      ? 'Online'
                                      : isNearby
                                          ? 'Online · Wi-Fi LAN direct'
                                          : isCloudOnline
                                              ? 'Presence unconfirmed'
                                              : 'Offline · Outbox Queued',
                      style: TextStyle(
                        fontSize: 11,
                        color: _isBlocked
                            ? Colors.redAccent
                            : (_peerPresence?.isTyping == true ||
                                    _peerPresence?.isRecording == true)
                                ? MeshColors.blue
                                : (_peerPresence?.isOnline == true || isNearby)
                                    ? MeshColors.blue
                                    : (isCloudOnline
                                        ? MeshColors.blue
                                        : Colors.grey),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          IconButton(
              tooltip: 'Search messages',
              icon: const Icon(Icons.search),
              onPressed: () => setState(() {
                    _searchOpen = !_searchOpen;
                    _searchQuery = '';
                  })),
          IconButton(
            tooltip: 'Video call',
            icon: const Icon(Icons.videocam_outlined),
            onPressed: () async {
              if (!widget.callService
                  .canStartCall(widget.friend.offlineMeshId)) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text('No real-time connection available.')),
                );
                return;
              }
              final micStatus = await Permission.microphone.request();
              final camStatus = await Permission.camera.request();
              if (!micStatus.isGranted || !camStatus.isGranted) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content:
                            Text('Microphone and Camera permissions required')),
                  );
                }
                return;
              }
              if (!context.mounted) return;
              widget.callService
                  .initiateCall(widget.friend.offlineMeshId, isVideoCall: true);
              Navigator.of(context).push(
                MaterialPageRoute(
                    builder: (_) =>
                        CallScreen(callService: widget.callService)),
              );
            },
          ),
          IconButton(
            tooltip: 'Voice call',
            icon: const Icon(Icons.call_outlined),
            onPressed: () async {
              if (!widget.callService
                  .canStartCall(widget.friend.offlineMeshId)) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text('No real-time connection available.')),
                );
                return;
              }
              final micStatus = await Permission.microphone.request();
              if (!micStatus.isGranted) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('Microphone permission required')),
                  );
                }
                return;
              }
              if (!context.mounted) return;
              widget.callService.initiateCall(widget.friend.offlineMeshId,
                  isVideoCall: false);
              Navigator.of(context).push(
                MaterialPageRoute(
                    builder: (_) =>
                        CallScreen(callService: widget.callService)),
              );
            },
          ),
          IconButton(
            tooltip: 'Refresh conversation',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loadMessages,
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded),
            onSelected: (val) {
              if (val == 'block') {
                _toggleBlock();
              } else if (val == 'security') {
                _showSecurityDialog();
              } else if (val == 'clear') {
                _clearConversation();
              }
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(
                value: 'security',
                child: Row(
                  children: [
                    Icon(Icons.lock_outline, size: 20),
                    SizedBox(width: 12),
                    Text('Encryption info'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'block',
                child: Row(
                  children: [
                    Icon(
                      _isBlocked
                          ? Icons.check_circle_outline
                          : Icons.block_flipped,
                      size: 20,
                      color: _isBlocked ? Colors.green : Colors.redAccent,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      _isBlocked ? 'Unblock contact' : 'Block contact',
                      style: TextStyle(
                        color: _isBlocked ? Colors.green : Colors.redAccent,
                      ),
                    ),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'clear',
                child: Row(
                  children: [
                    Icon(Icons.delete_sweep_outlined, size: 20),
                    SizedBox(width: 12),
                    Text('Clear messages'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Container(
        // WhatsApp subtle chat wallpaper background
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
        ),
        child: Column(
          children: [
            if (_searchOpen)
              Padding(
                  padding: const EdgeInsets.all(12),
                  child: TextField(
                      autofocus: true,
                      decoration: const InputDecoration(
                          hintText: 'Search this conversation',
                          prefixIcon: Icon(Icons.search)),
                      onChanged: (value) =>
                          setState(() => _searchQuery = value))),
            if (_searchOpen) Text('${visibleMessages.length} messages found'),
            // Messages List
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _errorMessage != null
                      ? EmptyStateView(
                          icon: Icons.cloud_off_outlined,
                          title: 'History unavailable',
                          message:
                              'No local history is available. Send a message to connect.',
                          onAction: _loadMessages,
                        )
                      : _messages.isEmpty
                          ? const EmptyStateView(
                              icon: Icons.waving_hand_outlined,
                              title: 'Say hello',
                              message:
                                  'Messages are end-to-end encrypted and targeted specifically to this friend.',
                            )
                          : ListView.builder(
                              controller: _scrollController,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 10),
                              itemCount: visibleMessages.length,
                              itemBuilder: (context, index) {
                                final msg = visibleMessages[index];
                                final isMe = msg.senderOfflineMeshId !=
                                    widget.friend.offlineMeshId;
                                final time = TimeOfDay.fromDateTime(
                                        msg.createdAt.toLocal())
                                    .format(context);

                                // Check if we should insert date header
                                bool showDateHeader = false;
                                if (index == 0) {
                                  showDateHeader = true;
                                } else {
                                  final prevDate = visibleMessages[index - 1]
                                      .createdAt
                                      .toLocal();
                                  final currDate = msg.createdAt.toLocal();
                                  if (prevDate.year != currDate.year ||
                                      prevDate.month != currDate.month ||
                                      prevDate.day != currDate.day) {
                                    showDateHeader = true;
                                  }
                                }

                                return Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (showDateHeader)
                                      _buildDateHeader(msg.createdAt.toLocal()),
                                    // Swipe right to reply (WhatsApp gesture)
                                    Dismissible(
                                      key: ValueKey('swipe_${msg.id}'),
                                      direction: DismissDirection.startToEnd,
                                      confirmDismiss: (_) async {
                                        _onReplyToMessage(msg);
                                        HapticFeedback.lightImpact();
                                        return false; // Don't actually dismiss the widget
                                      },
                                      background: Container(
                                        alignment: Alignment.centerLeft,
                                        padding:
                                            const EdgeInsets.only(left: 16),
                                        child: const Icon(Icons.reply_rounded,
                                            color: MeshColors.blue, size: 24),
                                      ),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 3),
                                        child: Align(
                                          alignment: isMe
                                              ? Alignment.centerRight
                                              : Alignment.centerLeft,
                                          child: ConstrainedBox(
                                            constraints: BoxConstraints(
                                              maxWidth:
                                                  MediaQuery.sizeOf(context)
                                                          .width *
                                                      0.78,
                                            ),
                                            child: InkWell(
                                              onLongPress: () =>
                                                  _showMessageOptions(msg),
                                              borderRadius:
                                                  BorderRadius.circular(16),
                                              child: Column(
                                                crossAxisAlignment: isMe
                                                    ? CrossAxisAlignment.end
                                                    : CrossAxisAlignment.start,
                                                children: [
                                                  Container(
                                                    padding: const EdgeInsets
                                                        .fromLTRB(12, 8, 12, 6),
                                                    decoration: BoxDecoration(
                                                      color: isMe
                                                          ? outgoingColor
                                                          : incomingColor,
                                                      borderRadius:
                                                          BorderRadius.only(
                                                        topLeft: const Radius
                                                            .circular(16),
                                                        topRight: const Radius
                                                            .circular(16),
                                                        bottomLeft:
                                                            Radius.circular(
                                                                isMe ? 16 : 4),
                                                        bottomRight:
                                                            Radius.circular(
                                                                isMe ? 4 : 16),
                                                      ),
                                                      boxShadow: [
                                                        BoxBarShadow(
                                                          color: Colors.black
                                                              .withValues(
                                                                  alpha: 0.05),
                                                          blurRadius: 3,
                                                          offset: const Offset(
                                                              0, 1),
                                                        ),
                                                      ],
                                                    ),
                                                    child: Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      mainAxisSize:
                                                          MainAxisSize.min,
                                                      children: [
                                                        // Quoted Reply preview inside bubble
                                                        _buildQuotedBannerInsideBubble(
                                                            msg, isMe, isDark),

                                                        // Message Content
                                                        if (msg.isDeleted) ...[
                                                          Row(
                                                            mainAxisSize:
                                                                MainAxisSize
                                                                    .min,
                                                            children: [
                                                              Icon(
                                                                  Icons
                                                                      .block_rounded,
                                                                  size: 14,
                                                                  color: isDark
                                                                      ? Colors
                                                                          .white54
                                                                      : Colors
                                                                          .grey
                                                                          .shade600),
                                                              const SizedBox(
                                                                  width: 6),
                                                              Text(
                                                                "This message was deleted",
                                                                style:
                                                                    TextStyle(
                                                                  fontSize: 14,
                                                                  fontStyle:
                                                                      FontStyle
                                                                          .italic,
                                                                  color: isDark
                                                                      ? Colors
                                                                          .white54
                                                                      : Colors
                                                                          .grey
                                                                          .shade600,
                                                                ),
                                                              ),
                                                            ],
                                                          ),
                                                        ] else if (msg
                                                                .mediaType ==
                                                            'audio') ...[
                                                          VoiceMessageBubble(
                                                            message: msg,
                                                            isMe: isMe,
                                                            voiceNoteService:
                                                                _voiceNoteService,
                                                          ),
                                                        ] else if (msg
                                                                .mediaType ==
                                                            'image') ...[
                                                          ImageMessageBubble(
                                                            message: msg,
                                                            isMe: isMe,
                                                          ),
                                                        ] else if (msg
                                                                .mediaType ==
                                                            'video') ...[
                                                          VideoMessageBubble(
                                                            message: msg,
                                                            isMe: isMe,
                                                          ),
                                                        ] else if (msg
                                                                .mediaType ==
                                                            'file') ...[
                                                          DocumentMessageBubble(
                                                            message: msg,
                                                            isMe: isMe,
                                                          ),
                                                        ] else ...[
                                                          SelectableText(
                                                            msg.content,
                                                            style: TextStyle(
                                                              fontSize: 15,
                                                              height: 1.4,
                                                              color: isMe
                                                                  ? (isDark
                                                                      ? Colors
                                                                          .white
                                                                      : Colors
                                                                          .white)
                                                                  : Theme.of(
                                                                          context)
                                                                      .colorScheme
                                                                      .onSurface,
                                                            ),
                                                          ),
                                                        ],
                                                        const SizedBox(
                                                            height: 4),

                                                        // Timestamp and WhatsApp Double Checkmarks
                                                        Row(
                                                          mainAxisSize:
                                                              MainAxisSize.min,
                                                          mainAxisAlignment:
                                                              MainAxisAlignment
                                                                  .end,
                                                          children: [
                                                            if (msg.isEdited)
                                                              Padding(
                                                                padding:
                                                                    const EdgeInsets
                                                                        .only(
                                                                        right:
                                                                            4),
                                                                child: Text(
                                                                  "edited",
                                                                  style:
                                                                      TextStyle(
                                                                    fontSize:
                                                                        10,
                                                                    fontStyle:
                                                                        FontStyle
                                                                            .italic,
                                                                    color: isMe
                                                                        ? (isDark
                                                                            ? Colors
                                                                                .white70
                                                                            : Colors
                                                                                .white70)
                                                                        : Theme.of(context)
                                                                            .colorScheme
                                                                            .onSurfaceVariant,
                                                                  ),
                                                                ),
                                                              ),
                                                            Text(
                                                              time,
                                                              style: TextStyle(
                                                                fontSize: 10,
                                                                color: isMe
                                                                    ? (isDark
                                                                        ? Colors
                                                                            .white70
                                                                        : Colors
                                                                            .white70)
                                                                    : Theme.of(
                                                                            context)
                                                                        .colorScheme
                                                                        .onSurfaceVariant,
                                                              ),
                                                            ),
                                                            const SizedBox(
                                                                width: 4),
                                                            _buildStatusTicks(
                                                                msg.status,
                                                                isMe,
                                                                msg.transport),
                                                          ],
                                                        ),
                                                      ],
                                                    ),
                                                  ),

                                                  // Reactions pill pinned to bubble corner
                                                  _buildReactionsBadge(
                                                      msg, isMe),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
            ),

            // Quoted Reply Banner above input bar
            if (_replyingToMessage != null)
              Container(
                padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
                color: Theme.of(context).colorScheme.surface,
                child: Row(
                  children: [
                    Container(
                      width: 4,
                      height: 38,
                      decoration: BoxDecoration(
                        color: MeshColors.blue,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _replyingToMessage!.senderOfflineMeshId ==
                                    widget.routingService.wifiMessagingService
                                        .currentUser.offlineMeshId
                                ? 'You'
                                : widget.friend.username,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: MeshColors.blue,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _replyingToMessage!.content,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 20),
                      onPressed: () =>
                          setState(() => _replyingToMessage = null),
                    ),
                  ],
                ),
              ),

            // WhatsApp Style Input Bar
            _isBlocked
                ? Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        vertical: 14, horizontal: 16),
                    color: Theme.of(context).colorScheme.surface,
                    child: Center(
                      child: InkWell(
                        onTap: _toggleBlock,
                        child: const Text(
                          'You blocked this contact. Tap to unblock.',
                          style: TextStyle(
                            color: Colors.redAccent,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                  )
                : SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
                      child: Row(
                        children: [
                          // Text Input Pill
                          Expanded(
                            child: Container(
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.surface,
                                borderRadius: BorderRadius.circular(28),
                                boxShadow: [
                                  BoxBarShadow(
                                    color: Colors.black.withValues(alpha: 0.06),
                                    blurRadius: 4,
                                    offset: const Offset(0, 1),
                                  ),
                                ],
                              ),
                              child: Row(
                                children: [
                                  IconButton(
                                    icon: const Icon(
                                        Icons.emoji_emotions_outlined,
                                        color: Colors.grey),
                                    onPressed: () {
                                      // Add quick emoji
                                      _controller.text += '😊';
                                    },
                                  ),
                                  Expanded(
                                    child: _isRecordingVoiceNote
                                        ? Row(
                                            children: [
                                              const Icon(
                                                  Icons.fiber_manual_record,
                                                  color: Colors.red,
                                                  size: 16),
                                              const SizedBox(width: 8),
                                              Text(
                                                'Recording ${_voiceRecordDurationSeconds}s...',
                                                style: const TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    color: Colors.red),
                                              ),
                                            ],
                                          )
                                        : TextField(
                                            controller: _controller,
                                            focusNode: _focusNode,
                                            maxLines: 4,
                                            minLines: 1,
                                            textCapitalization:
                                                TextCapitalization.sentences,
                                            decoration: const InputDecoration(
                                              hintText: 'Message',
                                              border: InputBorder.none,
                                              enabledBorder: InputBorder.none,
                                              focusedBorder: InputBorder.none,
                                              contentPadding:
                                                  EdgeInsets.symmetric(
                                                      horizontal: 4,
                                                      vertical: 12),
                                            ),
                                            onSubmitted: (_) {
                                              if (!_isSending) _sendMessage();
                                            },
                                          ),
                                  ),
                                  if (_isRecordingVoiceNote)
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline,
                                          color: Colors.grey),
                                      onPressed: _cancelVoiceNoteRecording,
                                    )
                                  else ...[
                                    IconButton(
                                      icon: const Icon(
                                          Icons.attach_file_rounded,
                                          color: Colors.grey),
                                      onPressed: _showAttachmentPicker,
                                    ),
                                    if (!_hasInputText)
                                      IconButton(
                                        icon: const Icon(
                                            Icons.camera_alt_rounded,
                                            color: Colors.grey),
                                        onPressed: _capturePhoto,
                                      ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),

                          // WhatsApp Action Button (Mic or Send Arrow)
                          _isSending
                              ? const SizedBox(
                                  width: 48,
                                  height: 48,
                                  child: Padding(
                                    padding: EdgeInsets.all(12),
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2.5),
                                  ),
                                )
                              : _isRecordingVoiceNote
                                  ? FloatingActionButton(
                                      mini: true,
                                      backgroundColor: MeshColors.orange,
                                      foregroundColor: MeshColors.midnight,
                                      elevation: 2,
                                      onPressed: _sendVoiceNote,
                                      child: const Icon(Icons.send_rounded,
                                          size: 20),
                                    )
                                  : _hasInputText
                                      ? FloatingActionButton(
                                          mini: true,
                                          backgroundColor: MeshColors.orange,
                                          foregroundColor: MeshColors.midnight,
                                          elevation: 2,
                                          onPressed: () => _sendMessage(),
                                          child: const Icon(Icons.send_rounded,
                                              size: 20),
                                        )
                                      : FloatingActionButton(
                                          mini: true,
                                          backgroundColor: MeshColors.orange,
                                          foregroundColor: MeshColors.midnight,
                                          elevation: 2,
                                          onPressed: _startVoiceNoteRecording,
                                          tooltip: 'Voice message',
                                          child: const Icon(Icons.mic_rounded,
                                              size: 22),
                                        ),
                        ],
                      ),
                    ),
                  ),
          ],
        ),
      ),
    );
  }
}

class BoxBarShadow extends BoxShadow {
  const BoxBarShadow({
    super.color = const Color(0x33000000),
    super.offset = Offset.zero,
    super.blurRadius = 0.0,
    super.spreadRadius = 0.0,
  });
}
