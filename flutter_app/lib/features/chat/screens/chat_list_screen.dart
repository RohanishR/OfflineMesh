import '../../../core/ui/mesh_widgets.dart';
import 'package:flutter/material.dart';
import '../../../core/services/friend_service.dart';
import '../../../core/services/message_service.dart';
import '../../../core/services/routing_service.dart';
import '../../../core/models/user.dart';
import '../../../core/services/call_service.dart';
import 'chat_screen.dart';

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
  List<UserProfile> _friends = [];
  String _query = '';
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadChats();
  }

  Future<void> _loadChats() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      // In a real app, there would be a dedicated /conversations endpoint.
      // Here, we'll list friends as possible chats.
      final friends = await widget.friendService.getFriends();
      if (!mounted) return;
      setState(() {
        _friends = friends;
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
                )));
  }

  void _compose() {
    showModalBottomSheet(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (context) => SafeArea(
            child: SizedBox(
                height: MediaQuery.sizeOf(context).height * .55,
                child: Column(children: [
                  Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text('New message',
                          style: Theme.of(context).textTheme.titleLarge)),
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
                                        leading:
                                            MeshAvatar(name: friend.username),
                                        title: Text(friend.username),
                                        onTap: () {
                                          Navigator.pop(context);
                                          _openChat(friend);
                                        },
                                      ))
                                  .toList())),
                ]))));
  }

  @override
  Widget build(BuildContext context) {
    final visible = _friends
        .where((f) =>
            f.username.toLowerCase().contains(_query) ||
            f.offlineMeshId.toLowerCase().contains(_query))
        .toList();
    return MeshPage(
      title: 'Messages',
      subtitle: 'A little closer. Wherever you are.',
      actions: [
        IconButton(
            tooltip: 'Refresh messages',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loadChats)
      ],
      floatingActionButton: FloatingActionButton(
          tooltip: 'New message',
          onPressed: _compose,
          child: const Icon(Icons.edit_outlined)),
      child: Column(children: [
        MeshSearch(
            hint: 'Find a friend to message',
            onChanged: (v) => setState(() => _query = v.toLowerCase())),
        Expanded(
            child: _isLoading
                ? const LoadingStateView()
                : _errorMessage != null
                    ? EmptyStateView(
                        icon: Icons.cloud_off_outlined,
                        title: 'Couldn’t load your friends',
                        message: 'Check your connection and try again.',
                        onAction: _loadChats)
                    : visible.isEmpty
                        ? EmptyStateView(
                            icon: Icons.forum_outlined,
                            title: _query.isEmpty
                                ? 'Your next conversation starts here'
                                : 'No matches',
                            message: _query.isEmpty
                                ? 'Add a friend using their OfflineMesh ID, then send your first message.'
                                : 'Try another name or OfflineMesh ID.')
                        : RefreshIndicator(
                            onRefresh: _loadChats,
                            child: ListView.separated(
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: const EdgeInsets.fromLTRB(24, 4, 24, 90),
                              itemCount: visible.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 10),
                              itemBuilder: (_, i) {
                                final friend = visible[i];
                                return GlassSurface(
                                    padding: EdgeInsets.zero,
                                    child: ListTile(
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                              horizontal: 16, vertical: 10),
                                      leading:
                                          MeshAvatar(name: friend.username),
                                      title: Text(friend.username,
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleMedium),
                                      subtitle: const Text(
                                          'Start or continue your conversation'),
                                      trailing: const Icon(
                                          Icons.chevron_right_rounded),
                                      onTap: () => _openChat(friend),
                                    ));
                              },
                            ))),
      ]),
    );
  }
}
