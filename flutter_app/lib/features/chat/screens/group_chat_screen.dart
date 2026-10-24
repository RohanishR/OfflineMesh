import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import '../../../core/models/message.dart';
import '../../../core/models/user.dart';
import '../../../core/services/routing_service.dart';
import '../../../core/services/voice_note_service.dart';
import '../../../core/services/friend_service.dart';
import '../../../core/ui/mesh_widgets.dart';
import '../models/group_chat_model.dart';
import '../services/group_service.dart';
import '../widgets/media_message_bubbles.dart';

class GroupChatScreen extends StatefulWidget {
  final GroupChat group;
  final RoutingService routingService;
  final GroupService groupService;
  final FriendService? friendService;

  const GroupChatScreen({
    super.key,
    required this.group,
    required this.routingService,
    required this.groupService,
    this.friendService,
  });

  @override
  State<GroupChatScreen> createState() => _GroupChatScreenState();
}

class _GroupChatScreenState extends State<GroupChatScreen> {
  late GroupChat _group;
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();
  final _voiceNoteService = VoiceNoteService();

  List<Message> _messages = [];
  bool _isLoading = true;
  bool _isSending = false;
  bool _hasInputText = false;
  bool _isRecordingVoiceNote = false;
  int _voiceRecordDurationSeconds = 0;
  Timer? _voiceTimer;
  StreamSubscription? _incomingSub;

  String get _myId =>
      widget.routingService.wifiMessagingService.currentUser.offlineMeshId;

  bool get _isAdmin {
    final me = _group.members.firstWhere(
      (m) => m.offlineMeshId == _myId,
      orElse: () => GroupMemberModel(
        offlineMeshId: '',
        username: '',
        role: 'MEMBER',
        joinedAt: DateTime.fromMillisecondsSinceEpoch(0),
      ),
    );
    return me.isAdmin;
  }

  @override
  void initState() {
    super.initState();
    _group = widget.group;
    _controller.addListener(_onTextChanged);
    _loadMessages();
    _refreshGroupDetails();

    _incomingSub = widget.routingService.incomingMessages.listen((msg) {
      if (mounted) {
        setState(() {
          _messages.removeWhere((m) => m.id == msg.id);
          _messages.add(msg);
          _messages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
        });
        _scrollToBottom();
      }
    });
  }

  @override
  void dispose() {
    _incomingSub?.cancel();
    _voiceTimer?.cancel();
    _voiceNoteService.dispose();
    _controller.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    final hasText = _controller.text.trim().isNotEmpty;
    if (hasText != _hasInputText) {
      setState(() => _hasInputText = hasText);
    }
  }

  Future<void> _refreshGroupDetails() async {
    try {
      final updated = await widget.groupService.getGroupDetails(_group.id);
      if (mounted) {
        setState(() => _group = updated);
      }
    } catch (_) {}
  }

  Future<void> _loadMessages() async {
    setState(() => _isLoading = true);
    try {
      final msgs = await widget.groupService.getGroupMessages(_group.id);
      if (mounted) {
        setState(() {
          _messages = msgs;
          _isLoading = false;
        });
        _scrollToBottom();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
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

  Future<void> _sendMessage({String? customContent, String mediaType = 'text'}) async {
    final text = customContent ?? _controller.text.trim();
    if (text.isEmpty || _isSending) return;

    final scaffoldMessenger = ScaffoldMessenger.of(context);
    setState(() => _isSending = true);
    try {
      final msg = await widget.groupService.sendGroupMessage(_group.id, text);
      if (customContent == null) _controller.clear();

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
        scaffoldMessenger.showSnackBar(
          SnackBar(content: Text('Failed to send group message: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  Future<void> _startVoiceNoteRecording() async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final started = await _voiceNoteService.startRecording();
    if (!started) {
      if (mounted) {
        scaffoldMessenger.showSnackBar(
          const SnackBar(content: Text('Microphone permission required for voice notes.')),
        );
      }
      return;
    }
    HapticFeedback.mediumImpact();
    setState(() {
      _isRecordingVoiceNote = true;
      _voiceRecordDurationSeconds = 0;
    });
    _voiceTimer?.cancel();
    _voiceTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() => _voiceRecordDurationSeconds++);
      }
    });
  }

  Future<void> _cancelVoiceNoteRecording() async {
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
    _voiceTimer?.cancel();
    final res = await _voiceNoteService.stopRecording();
    if (mounted) {
      setState(() {
        _isRecordingVoiceNote = false;
        _voiceRecordDurationSeconds = 0;
      });
    }
    if (res != null) {
      final mins = (res.durationMs ~/ 60000).toString().padLeft(2, '0');
      final secs = ((res.durationMs % 60000) ~/ 1000).toString().padLeft(2, '0');
      await _sendMessage(
        customContent: '🎤 Voice message ($mins:$secs)',
        mediaType: 'audio',
      );
    }
  }

  Future<void> _capturePhoto() async {
    try {
      final picker = ImagePicker();
      final photo = await picker.pickImage(source: ImageSource.camera, imageQuality: 85);
      if (photo != null) {
        await _sendMessage(customContent: '📷 Photo: ${photo.name}', mediaType: 'image');
      }
    } catch (_) {}
  }

  Future<void> _pickGalleryImage() async {
    try {
      final picker = ImagePicker();
      final image = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
      if (image != null) {
        await _sendMessage(customContent: '📷 Photo: ${image.name}', mediaType: 'image');
      }
    } catch (_) {}
  }

  Future<void> _pickVideo() async {
    try {
      final picker = ImagePicker();
      final video = await picker.pickVideo(source: ImageSource.gallery);
      if (video != null) {
        await _sendMessage(customContent: '🎥 Video: ${video.name}', mediaType: 'video');
      }
    } catch (_) {}
  }

  Future<void> _pickDocument() async {
    try {
      final result = await FilePicker.platform.pickFiles();
      if (result != null && result.files.single.name.isNotEmpty) {
        await _sendMessage(customContent: '📄 ${result.files.single.name}', mediaType: 'file');
      }
    } catch (_) {}
  }

  void _showAttachmentPicker() {
    showModalBottomSheet(
      context: context,
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

  void _showGroupDetails() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Column(
                    children: [
                      Container(
                        width: 72,
                        height: 72,
                        decoration: const BoxDecoration(
                          color: MeshColors.navy,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.groups_rounded, size: 42, color: Colors.white),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        _group.name,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      if (_group.description != null && _group.description!.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          _group.description!,
                          style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                        ),
                      ],
                      const SizedBox(height: 6),
                      Text(
                        '${_group.members.length} members',
                        style: const TextStyle(fontSize: 12, color: MeshColors.blue),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Members', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    if (_isAdmin)
                      TextButton.icon(
                        icon: const Icon(Icons.person_add_rounded, size: 18),
                        label: const Text('Add Member'),
                        onPressed: () {
                          Navigator.pop(ctx);
                          _showAddMemberDialog();
                        },
                      ),
                  ],
                ),
                const Divider(),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: _group.members.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final m = _group.members[i];
                      final isMe = m.offlineMeshId == _myId;
                      return ListTile(
                        leading: MeshAvatar(name: m.username),
                        title: Text(isMe ? '${m.username} (You)' : m.username),
                        subtitle: Text(m.offlineMeshId),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (m.isAdmin)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: MeshColors.orange.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Text(
                                  'ADMIN',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: MeshColors.orange,
                                  ),
                                ),
                              ),
                            if (_isAdmin && !isMe)
                              IconButton(
                                icon: const Icon(Icons.remove_circle_outline, color: Colors.red, size: 20),
                                onPressed: () => _removeMember(m.offlineMeshId),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red.shade50,
                      foregroundColor: Colors.red,
                      elevation: 0,
                    ),
                    icon: const Icon(Icons.exit_to_app_rounded),
                    label: const Text('Leave Group'),
                    onPressed: () {
                      Navigator.pop(ctx);
                      _leaveGroup();
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showAddMemberDialog() {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return FutureBuilder<List<UserProfile>>(
          future: widget.friendService != null
              ? widget.friendService!.getFriends()
              : FriendService(jwtToken: widget.groupService.jwtToken).getFriends(),
          builder: (_, snapshot) {
            final friends = (snapshot.data ?? [])
                .where((f) => !_group.members.any((m) => m.offlineMeshId == f.offlineMeshId))
                .toList();
            return SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('Add Friend to Group', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  ),
                  if (friends.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('All contacts are already members of this group.'),
                    )
                  else
                    Flexible(
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: friends.length,
                        itemBuilder: (_, i) {
                          final f = friends[i];
                          return ListTile(
                            leading: MeshAvatar(name: f.username),
                            title: Text(f.username),
                            subtitle: Text(f.offlineMeshId),
                            trailing: const Icon(Icons.add_rounded, color: MeshColors.blue),
                            onTap: () async {
                              Navigator.pop(ctx);
                              try {
                                final updated = await widget.groupService.addMember(_group.id, f.offlineMeshId);
                                if (mounted) {
                                  setState(() => _group = updated);
                                  scaffoldMessenger.showSnackBar(
                                    SnackBar(content: Text('Added ${f.username} to group')),
                                  );
                                }
                              } catch (e) {
                                if (mounted) {
                                  scaffoldMessenger.showSnackBar(
                                    SnackBar(content: Text('Failed to add member: $e')),
                                  );
                                }
                              }
                            },
                          );
                        },
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _removeMember(String memberMeshId) async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    try {
      final updated = await widget.groupService.removeMember(_group.id, memberMeshId);
      if (mounted) {
        setState(() => _group = updated);
        scaffoldMessenger.showSnackBar(
          const SnackBar(content: Text('Member removed from group')),
        );
      }
    } catch (e) {
      if (mounted) {
        scaffoldMessenger.showSnackBar(
          SnackBar(content: Text('Failed to remove member: $e')),
        );
      }
    }
  }

  Future<void> _leaveGroup() async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    try {
      await widget.groupService.removeMember(_group.id, _myId);
      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        scaffoldMessenger.showSnackBar(
          SnackBar(content: Text('Failed to leave group: $e')),
        );
      }
    }
  }

  String _getMembersSubtitle() {
    if (_group.members.isEmpty) return 'Group';
    final names = _group.members.map((m) => m.offlineMeshId == _myId ? 'You' : m.username).toList();
    return names.join(', ');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: InkWell(
          onTap: _showGroupDetails,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: const BoxDecoration(
                    color: MeshColors.navy,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.groups_rounded, size: 22, color: Colors.white),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _group.name,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        _getMembersSubtitle(),
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.white70 : Colors.black54,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline_rounded),
            onPressed: _showGroupDetails,
          ),
        ],
      ),
      body: Container(
        color: isDark ? const Color(0xFF0B141A) : const Color(0xFFEFEAE2),
        child: Column(
          children: [
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _messages.isEmpty
                      ? const Center(
                          child: Text(
                            'No messages in this group yet.\nSay hello!',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey),
                          ),
                        )
                      : ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          itemCount: _messages.length,
                          itemBuilder: (context, index) {
                            final msg = _messages[index];
                            final isMe = msg.senderOfflineMeshId == _myId;
                            final time = TimeOfDay.fromDateTime(msg.createdAt.toLocal()).format(context);

                            // Find sender username in group
                            final senderMember = _group.members.firstWhere(
                              (m) => m.offlineMeshId == msg.senderOfflineMeshId,
                              orElse: () => GroupMemberModel(
                                offlineMeshId: msg.senderOfflineMeshId,
                                username: msg.senderOfflineMeshId,
                                role: 'MEMBER',
                                joinedAt: DateTime.now(),
                              ),
                            );

                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 3),
                              child: Align(
                                alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                                child: ConstrainedBox(
                                  constraints: BoxConstraints(
                                    maxWidth: MediaQuery.sizeOf(context).width * 0.78,
                                  ),
                                  child: Container(
                                    padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
                                    decoration: BoxDecoration(
                                      color: isMe
                                          ? (isDark ? const Color(0xFF005C4B) : const Color(0xFFE7FFDB))
                                          : (isDark ? const Color(0xFF202C33) : Colors.white),
                                      borderRadius: BorderRadius.only(
                                        topLeft: const Radius.circular(16),
                                        topRight: const Radius.circular(16),
                                        bottomLeft: Radius.circular(isMe ? 16 : 4),
                                        bottomRight: Radius.circular(isMe ? 4 : 16),
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        // Sender Name in Group (WhatsApp convention)
                                        if (!isMe)
                                          Padding(
                                            padding: const EdgeInsets.only(bottom: 2),
                                            child: Text(
                                              senderMember.username,
                                              style: const TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.bold,
                                                color: MeshColors.orange,
                                              ),
                                            ),
                                          ),
                                        Text(
                                          msg.content,
                                          style: TextStyle(
                                            fontSize: 15,
                                            color: isDark ? Colors.white : Colors.black87,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          mainAxisAlignment: MainAxisAlignment.end,
                                          children: [
                                            Text(
                                              time,
                                              style: TextStyle(
                                                fontSize: 10,
                                                color: isDark ? Colors.white54 : Colors.black45,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
            ),

            // Bottom Input Pill
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surface,
                          borderRadius: BorderRadius.circular(28),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.06),
                              blurRadius: 4,
                              offset: const Offset(0, 1),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.emoji_emotions_outlined, color: Colors.grey),
                              onPressed: () => _controller.text += '😊',
                            ),
                            Expanded(
                              child: _isRecordingVoiceNote
                                  ? Row(
                                      children: [
                                        const Icon(Icons.fiber_manual_record, color: Colors.red, size: 16),
                                        const SizedBox(width: 8),
                                        Text(
                                          'Recording ${_voiceRecordDurationSeconds}s...',
                                          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red),
                                        ),
                                      ],
                                    )
                                  : TextField(
                                      controller: _controller,
                                      focusNode: _focusNode,
                                      maxLines: 4,
                                      minLines: 1,
                                      decoration: const InputDecoration(
                                        hintText: 'Group message',
                                        border: InputBorder.none,
                                        contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 12),
                                      ),
                                      onSubmitted: (_) {
                                        if (!_isSending) _sendMessage();
                                      },
                                    ),
                            ),
                            if (_isRecordingVoiceNote)
                              IconButton(
                                icon: const Icon(Icons.delete_outline, color: Colors.grey),
                                onPressed: _cancelVoiceNoteRecording,
                              )
                            else ...[
                              IconButton(
                                icon: const Icon(Icons.attach_file_rounded, color: Colors.grey),
                                onPressed: _showAttachmentPicker,
                              ),
                              if (!_hasInputText)
                                IconButton(
                                  icon: const Icon(Icons.camera_alt_rounded, color: Colors.grey),
                                  onPressed: _capturePhoto,
                                ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    _isSending
                        ? const SizedBox(
                            width: 48,
                            height: 48,
                            child: Padding(
                              padding: EdgeInsets.all(12),
                              child: CircularProgressIndicator(strokeWidth: 2.5),
                            ),
                          )
                        : _isRecordingVoiceNote
                            ? FloatingActionButton(
                                mini: true,
                                backgroundColor: const Color(0xFF25D366),
                                foregroundColor: Colors.white,
                                elevation: 2,
                                onPressed: _sendVoiceNote,
                                child: const Icon(Icons.send_rounded, size: 20),
                              )
                            : _hasInputText
                                ? FloatingActionButton(
                                    mini: true,
                                    backgroundColor: const Color(0xFF25D366),
                                    foregroundColor: Colors.white,
                                    elevation: 2,
                                    onPressed: () => _sendMessage(),
                                    child: const Icon(Icons.send_rounded, size: 20),
                                  )
                                : FloatingActionButton(
                                    mini: true,
                                    backgroundColor: const Color(0xFF25D366),
                                    foregroundColor: Colors.white,
                                    elevation: 2,
                                    onPressed: _startVoiceNoteRecording,
                                    child: const Icon(Icons.mic_rounded, size: 22),
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
