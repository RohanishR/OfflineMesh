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
      setState(() {
        _friends = friends;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chats'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadChats),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? Center(child: Text('Error: $_errorMessage'))
              : _friends.isEmpty
                  ? const Center(child: Text('No friends to chat with yet.'))
                  : ListView.builder(
                      itemCount: _friends.length,
                      itemBuilder: (context, index) {
                        final friend = _friends[index];
                        return ListTile(
                          leading: const CircleAvatar(child: Icon(Icons.person)),
                          title: Text(friend.username),
                          subtitle: const Text('Tap to open chat'),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ChatScreen(
                                  friend: friend,
                                  routingService: widget.routingService,
                                  callService: widget.callService,
                                ),
                              ),
                            );

                          },
                        );
                      },
                    ),
    );
  }
}
