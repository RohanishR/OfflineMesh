import '../../../core/ui/mesh_widgets.dart';
import 'package:flutter/material.dart';
import '../../../core/services/friend_service.dart';
import '../../../core/models/user.dart';

class FriendsListScreen extends StatefulWidget {
  final FriendService friendService;

  const FriendsListScreen({super.key, required this.friendService});

  @override
  State<FriendsListScreen> createState() => _FriendsListScreenState();
}

class _FriendsListScreenState extends State<FriendsListScreen> {
  List<UserProfile> _friends = [];
  String _query = '';
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadFriends();
  }

  Future<void> _loadFriends() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
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

  Future<void> _addFriendDialog() async {
    final controller = TextEditingController();
    return showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Add Friend'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(hintText: "Enter OfflineMesh ID"),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                final id = controller.text.trim();
                if (id.isNotEmpty) {
                  Navigator.pop(dialogContext);
                  try {
                    await widget.friendService.connect(id);
                    if (mounted) _loadFriends();
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Failed to add friend: $e')),
                      );
                    }
                  }
                }
              },
              child: const Text('Add'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _remove(UserProfile friend) async {
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
              title: const Text('Remove friend?'),
              content: Text('Remove ${friend.username} from your friends?'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Keep friend')),
                FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Remove'))
              ],
            ));
    if (confirmed != true) {
      return;
    }
    try {
      await widget.friendService.removeFriend(friend.offlineMeshId);
      if (mounted) {
        await _loadFriends();
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Couldn’t remove friend. Try again.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final visible = _friends
        .where((f) =>
            f.username.toLowerCase().contains(_query) ||
            f.offlineMeshId.toLowerCase().contains(_query))
        .toList();
    return MeshPage(
      title: 'Friends',
      subtitle: 'Your people. One simple ID.',
      actions: [
        IconButton(
            tooltip: 'Refresh friends',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loadFriends)
      ],
      floatingActionButton: FloatingActionButton(
          tooltip: 'Add friend',
          onPressed: _addFriendDialog,
          child: const Icon(Icons.person_add_alt_1_rounded)),
      child: Column(children: [
        MeshSearch(
            hint: 'Search name or OfflineMesh ID',
            onChanged: (v) => setState(() => _query = v.toLowerCase())),
        Expanded(
            child: _isLoading
                ? const LoadingStateView()
                : _errorMessage != null
                    ? EmptyStateView(
                        icon: Icons.cloud_off_outlined,
                        title: 'Friends unavailable',
                        message: 'Check your connection and try again.',
                        onAction: _loadFriends)
                    : visible.isEmpty
                        ? EmptyStateView(
                            icon: Icons.people_outline,
                            title: _query.isEmpty
                                ? 'Make your first connection'
                                : 'No matches',
                            message: 'Find each other with an OfflineMesh ID.',
                            actionLabel: 'Add friend',
                            onAction: _addFriendDialog)
                        : RefreshIndicator(
                            onRefresh: _loadFriends,
                            child: ListView.separated(
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: const EdgeInsets.fromLTRB(24, 4, 24, 90),
                              itemCount: visible.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 12),
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
                                      subtitle: Text(friend.offlineMeshId,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis),
                                      trailing: IconButton(
                                          tooltip: 'Remove ${friend.username}',
                                          onPressed: () => _remove(friend),
                                          icon: const Icon(
                                              Icons.person_remove_outlined)),
                                    ));
                              },
                            ))),
      ]),
    );
  }
}
