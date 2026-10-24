import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/ui/mesh_widgets.dart';
import '../../../core/services/friend_service.dart';
import '../../../core/services/message_service.dart';
import '../../../core/services/routing_service.dart';
import '../../../core/models/user.dart';
import '../../../core/models/message.dart';
import '../../../core/services/call_service.dart';
import '../models/conversation_summary.dart';
import 'chat_screen.dart';
import '../models/group_chat_model.dart';
import '../services/group_service.dart';
import 'group_chat_screen.dart';

enum ChatFilter { all, unread, pinned, archived }

class ChatListScreen extends StatefulWidget {
  final FriendService friendService;
  final MessageService messageService;
  final RoutingService routingService;
  final CallService callService;

  const ChatListScreen({
    super.key,
    required this.friendService,
    required this.messageService,
    required this.routingService,
    required this.callService,
  });

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  List<ConversationSummary> _conversations = [];
  List<UserProfile> _friends = [];
  List<GroupChat> _groups = [];
  late final GroupService _groupService;
  String _query = '';
  ChatFilter _activeFilter = ChatFilter.all;
  bool _isLoading = true;
  String? _errorMessage;
  StreamSubscription? _incomingSub;

  @override
  void initState() {
    super.initState();
    _groupService = GroupService(
      baseUrl: widget.messageService.baseUrl,
      jwtToken: widget.messageService.jwtToken,
    );
    _loadAllData();

    // Listen to real-time incoming messages to update conversation previews & unread badges
    _incomingSub = widget.routingService.incomingMessages.listen((message) {
      _onIncomingMessageReceived(message);
    });
  }

  @override
  void dispose() {
    _incomingSub?.cancel();
    super.dispose();
  }

  void _onIncomingMessageReceived(Message message) {
    if (!mounted) return;
    final myId =
        widget.routingService.wifiMessagingService.currentUser.offlineMeshId;
    final peerId = message.senderOfflineMeshId == myId
        ? (message.recipientOfflineMeshId ?? '')
        : message.senderOfflineMeshId;

    if (peerId.isEmpty) return;

    setState(() {
      final index =
          _conversations.indexWhere((c) => c.peerOfflineMeshId == peerId);
      final isFromMe = message.senderOfflineMeshId == myId;

      if (index != -1) {
        final current = _conversations[index];
        final newUnread =
            isFromMe ? current.unreadCount : (current.unreadCount + 1);

        final updated = current.copyWith(
          lastMessage:
              message.isDeleted ? 'This message was deleted' : message.content,
          lastMessageSenderId: message.senderOfflineMeshId,
          lastMessageStatus: message.status,
          lastMessageTime: message.createdAt,
          unreadCount: newUnread,
          isFromMe: isFromMe,
          isEdited: message.isEdited,
          isDeleted: message.isDeleted,
          mediaType: message.mediaType,
        );

        _conversations.removeAt(index);
        _conversations.insert(0, updated);
      } else {
        // Find username from friends list
        final friendMatch = _friends.where((f) => f.offlineMeshId == peerId);
        final username =
            friendMatch.isNotEmpty ? friendMatch.first.username : peerId;

        final newConv = ConversationSummary(
          peerOfflineMeshId: peerId,
          peerUsername: username,
          lastMessage:
              message.isDeleted ? 'This message was deleted' : message.content,
          lastMessageSenderId: message.senderOfflineMeshId,
          lastMessageStatus: message.status,
          lastMessageTime: message.createdAt,
          unreadCount: isFromMe ? 0 : 1,
          isFromMe: isFromMe,
          isEdited: message.isEdited,
          isDeleted: message.isDeleted,
          mediaType: message.mediaType,
        );
        _conversations.insert(0, newConv);
      }
      _sortConversations();
    });
  }

  void _sortConversations() {
    _conversations.sort((a, b) {
      if (a.isPinned && !b.isPinned) return -1;
      if (!a.isPinned && b.isPinned) return 1;
      return b.lastMessageTime.compareTo(a.lastMessageTime);
    });
  }

  Future<void> _loadAllData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final myId =
          widget.routingService.wifiMessagingService.currentUser.offlineMeshId;
      final friends = await widget.friendService.getFriends();
      _friends = friends;

      final friendMap = {for (var f in friends) f.offlineMeshId: f};

      // 1. Gather all local conversation peer IDs
      final localPeerIds = await widget.routingService.localStorageService
          .getAllConversationPeerIds();
      final allPeerIds = <String>{...localPeerIds, ...friendMap.keys};

      final summaries = <ConversationSummary>[];

      for (final peerId in allPeerIds) {
        final messages = await widget.routingService.localStorageService
            .loadConversation(peerId);
        final flags = await widget.routingService.localStorageService
            .getConversationFlags(peerId);
        final username = friendMap[peerId]?.username ?? peerId;

        if (messages.isNotEmpty) {
          final last = messages.last;
          int unread = 0;
          for (final m in messages) {
            if (m.senderOfflineMeshId == peerId &&
                m.status.toLowerCase() != 'read') {
              unread++;
            }
          }

          summaries.add(ConversationSummary(
            peerOfflineMeshId: peerId,
            peerUsername: username,
            lastMessage:
                last.isDeleted ? 'This message was deleted' : last.content,
            lastMessageSenderId: last.senderOfflineMeshId,
            lastMessageStatus: last.status,
            lastMessageTime: last.createdAt,
            unreadCount: unread,
            isPinned: flags['pinned'] == true,
            isArchived: flags['archived'] == true,
            isMuted: flags['muted'] == true,
            isFromMe: last.senderOfflineMeshId == myId,
            isEdited: last.isEdited,
            isDeleted: last.isDeleted,
            mediaType: last.mediaType,
          ));
        } else if (friendMap.containsKey(peerId)) {
          // A friend with no messages yet
          summaries.add(ConversationSummary(
            peerOfflineMeshId: peerId,
            peerUsername: username,
            lastMessage: 'Tap to start chatting',
            lastMessageSenderId: '',
            lastMessageStatus: '',
            lastMessageTime: DateTime.fromMillisecondsSinceEpoch(0),
            unreadCount: 0,
            isPinned: flags['pinned'] == true,
            isArchived: flags['archived'] == true,
            isMuted: flags['muted'] == true,
          ));
        }
      }

      // 1.5 Load groups
      try {
        _groups = await _groupService.getUserGroups();
        for (final g in _groups) {
          summaries.add(ConversationSummary(
            peerOfflineMeshId: 'group:${g.id}',
            peerUsername: g.name,
            lastMessage: g.description?.isNotEmpty == true
                ? g.description!
                : 'Group · ${g.members.length} members',
            lastMessageSenderId: '',
            lastMessageStatus: 'sent',
            lastMessageTime: g.createdAt,
            unreadCount: 0,
            isGroup: true,
            groupId: g.id,
          ));
        }
      } catch (groupError) {
        debugPrint('Could not fetch groups: $groupError');
      }

      // 2. Fetch remote conversations if internet available
      try {
        final remote =
            await widget.routingService.messageService.getConversations();
        for (final r in remote) {
          final idx = summaries
              .indexWhere((s) => s.peerOfflineMeshId == r.peerOfflineMeshId);
          if (idx != -1) {
            final local = summaries[idx];
            if (r.lastMessageTime.isAfter(local.lastMessageTime)) {
              summaries[idx] = local.copyWith(
                lastMessage: r.lastMessage,
                lastMessageTime: r.lastMessageTime,
                lastMessageSenderId: r.lastMessageSenderId,
                lastMessageStatus: r.lastMessageStatus,
                isFromMe: r.isFromMe,
                unreadCount:
                    r.unreadCount > 0 ? r.unreadCount : local.unreadCount,
              );
            }
          } else {
            summaries.add(r);
          }
        }
      } catch (remoteError) {
        debugPrint('Could not fetch remote conversations: $remoteError');
      }

      if (!mounted) return;
      setState(() {
        _conversations = summaries;
        _sortConversations();
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  void _openChat(UserProfile friend) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          friend: friend,
          routingService: widget.routingService,
          callService: widget.callService,
          friendService: widget.friendService,
        ),
      ),
    ).then((_) {
      // Reload on return to refresh unread counts and latest messages
      _loadAllData();
    });
  }

  void _openGroupChat(GroupChat group) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GroupChatScreen(
          group: group,
          groupService: _groupService,
          routingService: widget.routingService,
          friendService: widget.friendService,
        ),
      ),
    ).then((_) {
      _loadAllData();
    });
  }

  void _showCreateGroupDialog() {
    final nameController = TextEditingController();
    final descController = TextEditingController();
    final selectedFriendIds = <String>{};

    showDialog(
      context: context,
      builder: (dlgCtx) => StatefulBuilder(
        builder: (context, setDlgState) => AlertDialog(
          title: const Text('New Group'),
          content: SingleChildScrollView(
            child: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'Group Name *',
                      hintText: 'e.g. Project OfflineMesh',
                      prefixIcon: Icon(Icons.group_outlined),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: descController,
                    decoration: const InputDecoration(
                      labelText: 'Description (optional)',
                      hintText: 'What is this group about?',
                      prefixIcon: Icon(Icons.description_outlined),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text('Select Members:',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 8),
                  if (_friends.isEmpty)
                    const Text('No friends available. Add friends first.',
                        style: TextStyle(color: Colors.grey, fontSize: 12))
                  else
                    ..._friends.map((f) {
                      final isSelected =
                          selectedFriendIds.contains(f.offlineMeshId);
                      return CheckboxListTile(
                        dense: true,
                        value: isSelected,
                        title: Text(f.username),
                        subtitle: Text(f.offlineMeshId,
                            style: const TextStyle(fontSize: 11)),
                        secondary: MeshAvatar(name: f.username, size: 32),
                        onChanged: (val) {
                          setDlgState(() {
                            if (val == true) {
                              selectedFriendIds.add(f.offlineMeshId);
                            } else {
                              selectedFriendIds.remove(f.offlineMeshId);
                            }
                          });
                        },
                      );
                    }),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dlgCtx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                final sm = ScaffoldMessenger.of(context);
                final name = nameController.text.trim();
                if (name.isEmpty) return;
                Navigator.pop(dlgCtx);
                try {
                  final group = await _groupService.createGroup(
                    name: name,
                    description: descController.text.trim().isEmpty
                        ? null
                        : descController.text.trim(),
                    memberOfflineMeshIds: selectedFriendIds.toList(),
                  );
                  if (mounted) {
                    _openGroupChat(group);
                  }
                } catch (e) {
                  if (mounted) {
                    sm.showSnackBar(
                      SnackBar(content: Text('Failed to create group: $e')),
                    );
                  }
                }
              },
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
  }

  void _compose() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .55,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text('New Conversation',
                    style: Theme.of(context).textTheme.titleLarge),
              ),
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: MeshColors.navy,
                  child: Icon(Icons.group_add_rounded, color: Colors.white),
                ),
                title: const Text('New group',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: const Text('Create a group chat with friends'),
                onTap: () {
                  Navigator.pop(context);
                  _showCreateGroupDialog();
                },
              ),
              const Divider(height: 1),
              Expanded(
                child: _friends.isEmpty
                    ? const EmptyStateView(
                        icon: Icons.people_outline,
                        title: 'Start with a friend',
                        message:
                            'Add an OfflineMesh ID from the Friends tab to begin a conversation.')
                    : ListView(
                        children: _friends
                            .map((friend) => ListTile(
                                  leading: MeshAvatar(name: friend.username),
                                  title: Text(friend.username,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold)),
                                  subtitle: Text(friend.offlineMeshId),
                                  onTap: () {
                                    Navigator.pop(context);
                                    _openChat(friend);
                                  },
                                ))
                            .toList(),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showConversationOptions(ConversationSummary conv) {
    HapticFeedback.mediumImpact();
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: MeshAvatar(name: conv.peerUsername),
              title: Text(conv.peerUsername,
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text(conv.peerOfflineMeshId),
            ),
            const Divider(),
            ListTile(
              leading: Icon(
                conv.isPinned
                    ? Icons.push_pin_outlined
                    : Icons.push_pin_rounded,
                color: MeshColors.blue,
              ),
              title: Text(conv.isPinned ? 'Unpin chat' : 'Pin chat'),
              onTap: () async {
                Navigator.pop(ctx);
                await widget.routingService.localStorageService
                    .setConversationFlag(
                  conv.peerOfflineMeshId,
                  'pinned',
                  !conv.isPinned,
                );
                setState(() {
                  final idx = _conversations.indexWhere(
                      (c) => c.peerOfflineMeshId == conv.peerOfflineMeshId);
                  if (idx != -1) {
                    _conversations[idx] =
                        conv.copyWith(isPinned: !conv.isPinned);
                    _sortConversations();
                  }
                });
              },
            ),
            ListTile(
              leading: Icon(
                conv.isMuted
                    ? Icons.notifications_active_outlined
                    : Icons.volume_off_rounded,
                color: MeshColors.orange,
              ),
              title: Text(
                  conv.isMuted ? 'Unmute notifications' : 'Mute notifications'),
              onTap: () async {
                Navigator.pop(ctx);
                await widget.routingService.localStorageService
                    .setConversationFlag(
                  conv.peerOfflineMeshId,
                  'muted',
                  !conv.isMuted,
                );
                setState(() {
                  final idx = _conversations.indexWhere(
                      (c) => c.peerOfflineMeshId == conv.peerOfflineMeshId);
                  if (idx != -1) {
                    _conversations[idx] = conv.copyWith(isMuted: !conv.isMuted);
                  }
                });
              },
            ),
            ListTile(
              leading: Icon(
                conv.isArchived
                    ? Icons.unarchive_outlined
                    : Icons.archive_outlined,
                color: Colors.teal,
              ),
              title: Text(conv.isArchived ? 'Unarchive chat' : 'Archive chat'),
              onTap: () async {
                Navigator.pop(ctx);
                await widget.routingService.localStorageService
                    .setConversationFlag(
                  conv.peerOfflineMeshId,
                  'archived',
                  !conv.isArchived,
                );
                setState(() {
                  final idx = _conversations.indexWhere(
                      (c) => c.peerOfflineMeshId == conv.peerOfflineMeshId);
                  if (idx != -1) {
                    _conversations[idx] =
                        conv.copyWith(isArchived: !conv.isArchived);
                  }
                });
              },
            ),
            ListTile(
              leading: const Icon(Icons.mark_chat_read_outlined,
                  color: Color(0xFF34B7F1)),
              title: const Text('Mark as read'),
              onTap: () async {
                Navigator.pop(ctx);
                await widget.routingService
                    .sendReadReceipt(conv.peerOfflineMeshId);
                setState(() {
                  final idx = _conversations.indexWhere(
                      (c) => c.peerOfflineMeshId == conv.peerOfflineMeshId);
                  if (idx != -1) {
                    _conversations[idx] = conv.copyWith(unreadCount: 0);
                  }
                });
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    if (dt.millisecondsSinceEpoch == 0) return '';
    final now = DateTime.now();
    final local = dt.toLocal();
    final today = DateTime(now.year, now.month, now.day);
    final msgDate = DateTime(local.year, local.month, local.day);

    if (msgDate == today) {
      final hour = local.hour > 12
          ? local.hour - 12
          : (local.hour == 0 ? 12 : local.hour);
      final minute = local.minute.toString().padLeft(2, '0');
      final ampm = local.hour >= 12 ? 'PM' : 'AM';
      return '$hour:$minute $ampm';
    } else if (msgDate == today.subtract(const Duration(days: 1))) {
      return 'Yesterday';
    } else if (now.difference(local).inDays < 7) {
      const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return days[local.weekday - 1];
    } else {
      return '${local.day}/${local.month}/${local.year.toString().substring(2)}';
    }
  }

  Widget _buildStatusTicks(String status) {
    switch (status.toLowerCase()) {
      case 'sending':
      case 'queued':
        return const Icon(Icons.access_time_rounded,
            size: 14, color: Colors.grey);
      case 'sent':
        return const Icon(Icons.check_rounded, size: 15, color: Colors.grey);
      case 'delivered':
        return const Icon(Icons.done_all_rounded, size: 16, color: Colors.grey);
      case 'read':
      case 'seen':
        return const Icon(Icons.done_all_rounded,
            size: 16, color: Color(0xFF34B7F1));
      default:
        return const Icon(Icons.check_rounded, size: 15, color: Colors.grey);
    }
  }

  List<ConversationSummary> _getFilteredConversations() {
    List<ConversationSummary> list = _conversations;

    // Filter by tab
    switch (_activeFilter) {
      case ChatFilter.all:
        list = list.where((c) => !c.isArchived).toList();
        break;
      case ChatFilter.unread:
        list = list.where((c) => !c.isArchived && c.unreadCount > 0).toList();
        break;
      case ChatFilter.pinned:
        list = list.where((c) => !c.isArchived && c.isPinned).toList();
        break;
      case ChatFilter.archived:
        list = list.where((c) => c.isArchived).toList();
        break;
    }

    // Filter by search query
    if (_query.trim().isNotEmpty) {
      final q = _query.toLowerCase();
      list = list
          .where((c) =>
              c.peerUsername.toLowerCase().contains(q) ||
              c.peerOfflineMeshId.toLowerCase().contains(q) ||
              c.lastMessage.toLowerCase().contains(q))
          .toList();
    }

    return list;
  }

  @override
  Widget build(BuildContext context) {
    final visible = _getFilteredConversations();
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return MeshPage(
      title: 'Chats',
      subtitle: 'Your conversations, connected.',
      actions: [
        IconButton(
          tooltip: 'Refresh conversations',
          icon: const Icon(Icons.refresh_rounded),
          onPressed: _loadAllData,
        ),
      ],
      floatingActionButton: FloatingActionButton(
        tooltip: 'New conversation',
        onPressed: _compose,
        backgroundColor: MeshColors.orange,
        child: const Icon(Icons.chat_rounded, color: MeshColors.midnight),
      ),
      child: Column(
        children: [
          // Search Bar
          MeshSearch(
            hint: 'Search names, IDs, or latest messages',
            onChanged: (v) => setState(() => _query = v),
          ),
          const SizedBox(height: 8),

          // WhatsApp Filter Chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                _buildFilterChip('All', ChatFilter.all),
                const SizedBox(width: 8),
                _buildFilterChip('Unread', ChatFilter.unread),
                const SizedBox(width: 8),
                _buildFilterChip('Pinned', ChatFilter.pinned),
                const SizedBox(width: 8),
                _buildFilterChip('Archived', ChatFilter.archived),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Main List View
          Expanded(
            child: _isLoading
                ? const LoadingStateView()
                : _errorMessage != null
                    ? EmptyStateView(
                        icon: Icons.cloud_off_outlined,
                        title: 'Couldn’t load conversations',
                        message: 'Check your connection or local storage.',
                        onAction: _loadAllData,
                      )
                    : visible.isEmpty
                        ? EmptyStateView(
                            icon: Icons.forum_outlined,
                            title: _query.isNotEmpty
                                ? 'No matching chats'
                                : _activeFilter == ChatFilter.unread
                                    ? 'No unread messages'
                                    : _activeFilter == ChatFilter.pinned
                                        ? 'No pinned chats'
                                        : _activeFilter == ChatFilter.archived
                                            ? 'No archived chats'
                                            : 'No conversations yet',
                            message: _query.isNotEmpty
                                ? 'Try searching for another contact or keyword.'
                                : 'Tap the chat button to start a conversation with a friend.',
                          )
                        : RefreshIndicator(
                            onRefresh: _loadAllData,
                            child: ListView.separated(
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: const EdgeInsets.fromLTRB(16, 4, 16, 90),
                              itemCount: visible.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 8),
                              itemBuilder: (context, i) {
                                final conv = visible[i];
                                final isNearby = widget.routingService
                                    .isPeerNearby(conv.peerOfflineMeshId);

                                return GlassSurface(
                                  padding: EdgeInsets.zero,
                                  child: ListTile(
                                    contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 14, vertical: 6),
                                    onTap: () {
                                      if (conv.isGroup) {
                                        final group = _groups.firstWhere(
                                          (g) => g.id == conv.groupId,
                                          orElse: () => GroupChat(
                                            id: conv.groupId ?? '',
                                            name: conv.peerUsername,
                                            createdByOfflineMeshId: '',
                                            createdAt: DateTime.now(),
                                            members: [],
                                          ),
                                        );
                                        _openGroupChat(group);
                                      } else {
                                        final friendMatch = _friends.where(
                                            (f) =>
                                                f.offlineMeshId ==
                                                conv.peerOfflineMeshId);
                                        final targetProfile =
                                            friendMatch.isNotEmpty
                                                ? friendMatch.first
                                                : UserProfile(
                                                    id: '',
                                                    username: conv.peerUsername,
                                                    offlineMeshId:
                                                        conv.peerOfflineMeshId,
                                                  );
                                        _openChat(targetProfile);
                                      }
                                    },
                                    onLongPress: () =>
                                        _showConversationOptions(conv),
                                    leading: conv.isGroup
                                        ? const CircleAvatar(
                                            radius: 24,
                                            backgroundColor: MeshColors.navy,
                                            child: Icon(Icons.groups_rounded,
                                                color: Colors.white, size: 26),
                                          )
                                        : Stack(
                                            children: [
                                              MeshAvatar(
                                                  name: conv.peerUsername,
                                                  size: 48),
                                              if (isNearby)
                                                Positioned(
                                                  bottom: 0,
                                                  right: 0,
                                                  child: Container(
                                                    width: 13,
                                                    height: 13,
                                                    decoration: BoxDecoration(
                                                      color: MeshColors.navy,
                                                      shape: BoxShape.circle,
                                                      border: Border.all(
                                                        color: Theme.of(context)
                                                            .colorScheme
                                                            .surface,
                                                        width: 2,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                            ],
                                          ),
                                    title: Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            conv.peerUsername,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontWeight: conv.unreadCount > 0
                                                  ? FontWeight.bold
                                                  : FontWeight.w600,
                                              fontSize: 16,
                                            ),
                                          ),
                                        ),
                                        if (conv.lastMessageTime
                                                .millisecondsSinceEpoch >
                                            0) ...[
                                          Text(
                                            _formatTime(conv.lastMessageTime),
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: conv.unreadCount > 0
                                                  ? MeshColors.navy
                                                  : (isDark
                                                      ? Colors.white60
                                                      : Colors.black45),
                                              fontWeight: conv.unreadCount > 0
                                                  ? FontWeight.bold
                                                  : FontWeight.normal,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                    subtitle: Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Row(
                                        children: [
                                          if (conv.isFromMe &&
                                              conv.lastMessageStatus
                                                  .isNotEmpty) ...[
                                            _buildStatusTicks(
                                                conv.lastMessageStatus),
                                            const SizedBox(width: 4),
                                          ],
                                          if (conv.mediaType == 'audio') ...[
                                            const Icon(Icons.mic_rounded,
                                                size: 16,
                                                color: MeshColors.blue),
                                            const SizedBox(width: 4),
                                          ] else if (conv.mediaType ==
                                              'image') ...[
                                            const Icon(Icons.image_rounded,
                                                size: 16,
                                                color: MeshColors.blue),
                                            const SizedBox(width: 4),
                                          ] else if (conv.mediaType ==
                                              'video') ...[
                                            const Icon(Icons.videocam_rounded,
                                                size: 16,
                                                color: MeshColors.blue),
                                            const SizedBox(width: 4),
                                          ] else if (conv.mediaType ==
                                              'file') ...[
                                            const Icon(
                                                Icons.insert_drive_file_rounded,
                                                size: 16,
                                                color: MeshColors.blue),
                                            const SizedBox(width: 4),
                                          ],
                                          Expanded(
                                            child: Text(
                                              conv.isDeleted
                                                  ? '🚫 This message was deleted'
                                                  : conv.lastMessage,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 14,
                                                fontStyle: conv.isDeleted
                                                    ? FontStyle.italic
                                                    : FontStyle.normal,
                                                color: conv.unreadCount > 0
                                                    ? (isDark
                                                        ? Colors.white
                                                        : Colors.black87)
                                                    : (isDark
                                                        ? Colors.white70
                                                        : Colors.black54),
                                                fontWeight: conv.unreadCount > 0
                                                    ? FontWeight.w600
                                                    : FontWeight.normal,
                                              ),
                                            ),
                                          ),
                                          if (conv.isMuted) ...[
                                            const SizedBox(width: 6),
                                            Icon(Icons.volume_off_rounded,
                                                size: 15,
                                                color: isDark
                                                    ? Colors.white38
                                                    : Colors.black38),
                                          ],
                                          if (conv.isPinned) ...[
                                            const SizedBox(width: 6),
                                            const Icon(Icons.push_pin_rounded,
                                                size: 15,
                                                color: MeshColors.blue),
                                          ],
                                          if (conv.unreadCount > 0) ...[
                                            const SizedBox(width: 6),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 7,
                                                      vertical: 2),
                                              decoration: const BoxDecoration(
                                                color: MeshColors.navy,
                                                shape: BoxShape.circle,
                                              ),
                                              child: Text(
                                                conv.unreadCount > 99
                                                    ? '99+'
                                                    : '${conv.unreadCount}',
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, ChatFilter filter) {
    final isSelected = _activeFilter == filter;
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () => setState(() => _activeFilter = filter),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? MeshColors.navy
              : Theme.of(context)
                  .colorScheme
                  .surfaceContainerHighest
                  .withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            color: isSelected
                ? Colors.white
                : Theme.of(context).colorScheme.onSurface,
          ),
        ),
      ),
    );
  }
}
