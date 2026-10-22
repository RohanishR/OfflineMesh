import '../../../core/ui/mesh_widgets.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import '../models/file_metadata.dart';
import '../services/file_service.dart';
import '../../../core/services/friend_service.dart';
import '../../../core/services/routing_service.dart';
import '../../../core/models/user.dart';
import 'file_details_screen.dart';

class FileListScreen extends StatefulWidget {
  final FileService fileService;
  final RoutingService routingService;
  final FriendService? friendService;
  final bool showSent;

  const FileListScreen(
      {super.key,
      required this.fileService,
      required this.routingService,
      this.friendService,
      this.showSent = false});

  @override
  State<FileListScreen> createState() => _FileListScreenState();
}

class _FileListScreenState extends State<FileListScreen> {
  late Future<List<FileMetadata>> futureFiles;
  bool _isUploading = false;
  late bool _showSent;
  String _query = '';
  String _filter = 'All';
  double _uploadProgress = 0.0;

  StreamSubscription? _incomingFilesSub;

  @override
  void initState() {
    super.initState();
    _showSent = widget.showSent;
    _loadFiles();

    // Auto-refresh when new files arrive via Wi-Fi LAN
    _incomingFilesSub = widget.routingService.incomingFiles.listen((_) {
      if (mounted) {
        _loadFiles();
      }
    });
  }

  @override
  void dispose() {
    _incomingFilesSub?.cancel();
    super.dispose();
  }

  void _loadFiles() {
    setState(() {
      futureFiles = _showSent
          ? widget.routingService.getCombinedSentFiles()
          : widget.routingService.getCombinedReceivedFiles();
    });
  }

  String _getMimeType(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    switch (ext) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      case 'pdf':
        return 'application/pdf';
      case 'txt':
        return 'text/plain';
      case 'mp4':
        return 'video/mp4';
      case 'mp3':
        return 'audio/mpeg';
      default:
        return 'application/octet-stream';
    }
  }

  Future<void> _pickAndUploadFile() async {
    if (widget.friendService == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Friend service not available')));
      return;
    }

    try {
      final friends = await widget.friendService!.getFriends();
      if (friends.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('You have no friends to send files to.')));
        return;
      }

      UserProfile? selectedFriend;
      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('Select Recipient'),
            content: SizedBox(
              width: double.maxFinite,
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: friends.length,
                itemBuilder: (context, index) {
                  final friend = friends[index];
                  // Highlight nearby friends
                  final isNearby =
                      widget.routingService.isPeerNearby(friend.offlineMeshId);

                  return ListTile(
                    title: Row(
                      children: [
                        Text(friend.username),
                        if (isNearby) ...[
                          const SizedBox(width: 8),
                          const Icon(Icons.wifi_tethering,
                              size: 14, color: MeshColors.blue),
                        ]
                      ],
                    ),
                    subtitle: Text(friend.offlineMeshId),
                    onTap: () {
                      selectedFriend = friend;
                      Navigator.pop(context);
                    },
                  );
                },
              ),
            ),
          );
        },
      );

      if (selectedFriend == null) return; // User cancelled selection

      FilePickerResult? result = await FilePicker.platform.pickFiles();

      if (result != null && result.files.isNotEmpty) {
        final picked = result.files.single;
        if (picked.path == null) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Cannot read file from device storage')),
          );
          return;
        }

        File file = File(picked.path!);
        if (!file.existsSync()) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Selected file does not exist')),
          );
          return;
        }

        String fileName = picked.name;
        int fileSize = file.lengthSync();
        String contentType = _getMimeType(fileName);

        setState(() {
          _isUploading = true;
          _uploadProgress = 0.0;
        });

        try {
          await widget.routingService.sendFile(selectedFriend!.offlineMeshId,
              fileName, contentType, fileSize, file, (progress) {
            if (mounted) {
              setState(() {
                _uploadProgress = progress;
              });
            }
          });

          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('File sent successfully!')),
          );
          _loadFiles();
        } catch (e) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Send failed: $e')),
          );
        } finally {
          if (mounted) setState(() {
            _isUploading = false;
          });
        }
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  String _size(int bytes) => bytes < 1024
      ? '$bytes B'
      : bytes < 1048576
          ? '${(bytes / 1024).toStringAsFixed(1)} KB'
          : '${(bytes / 1048576).toStringAsFixed(1)} MB';
  @override
  Widget build(BuildContext context) => MeshPage(
        title: 'Files',
        subtitle: 'Everything shared. In one place.',
        actions: [
          IconButton(
              tooltip: 'Refresh files',
              icon: const Icon(Icons.refresh_rounded),
              onPressed: _loadFiles)
        ],
        floatingActionButton: widget.friendService == null
            ? null
            : FloatingActionButton(
                tooltip: 'Send a file',
                onPressed: _isUploading ? null : _pickAndUploadFile,
                child: const Icon(Icons.upload_file_rounded)),
        child: Column(children: [
          MeshSearch(
              hint: 'Search files',
              onChanged: (v) => setState(() => _query = v.toLowerCase())),
          Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(children: [
                Expanded(
                    child: SegmentedButton<bool>(
                        segments: const [
                      ButtonSegment(value: false, label: Text('Received')),
                      ButtonSegment(value: true, label: Text('Sent'))
                    ],
                        selected: {
                      _showSent
                    },
                        onSelectionChanged: (v) {
                          _showSent = v.first;
                          _loadFiles();
                        })),
              ])),
          SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              child: Row(
                  children: ['All', 'Images', 'Documents']
                      .map((filter) => Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                              label: Text(filter),
                              selected: _filter == filter,
                              onSelected: (_) =>
                                  setState(() => _filter = filter))))
                      .toList())),
          if (_isUploading)
            Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
                child: GlassSurface(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text('Sending · ${(_uploadProgress * 100).round()}%'),
                      const SizedBox(height: 8),
                      LinearProgressIndicator(
                          value: _uploadProgress.clamp(0, 1))
                    ]))),
          Expanded(
              child: FutureBuilder<List<FileMetadata>>(
                  future: futureFiles,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting)
                      return const LoadingStateView();
                    if (snapshot.hasError)
                      return EmptyStateView(
                          icon: Icons.cloud_off_outlined,
                          title: 'Files unavailable',
                          message:
                              'Check your connection and refresh your files.',
                          onAction: _loadFiles);
                    final files = (snapshot.data ?? [])
                        .where((f) =>
                            f.originalFileName.toLowerCase().contains(_query) &&
                            (_filter == 'All' ||
                                (_filter == 'Images'
                                    ? f.contentType.startsWith('image/')
                                    : !f.contentType.startsWith('image/'))))
                        .toList();
                    if (files.isEmpty)
                      return EmptyStateView(
                          icon: Icons.folder_open_rounded,
                          title: _query.isEmpty && _filter == 'All'
                              ? 'Room for something worth sharing'
                              : 'No matching files',
                          message: _showSent
                              ? 'Files you send will appear here.'
                              : 'Received files will appear here when available.');
                    return RefreshIndicator(
                        onRefresh: () async {
                          _loadFiles();
                          await futureFiles;
                        },
                        child: ListView.separated(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(24, 0, 24, 90),
                            itemCount: files.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 12),
                            itemBuilder: (_, i) {
                              final file = files[i];
                              final date = file.createdAt.toLocal();
                              return GlassSurface(
                                  padding: EdgeInsets.zero,
                                  child: ListTile(
                                    contentPadding: const EdgeInsets.all(16),
                                    leading: (file.contentType.startsWith('image/') &&
                                            file.localFilePath != null &&
                                            File(file.localFilePath!).existsSync())
                                        ? ClipRRect(
                                            borderRadius: BorderRadius.circular(14),
                                            child: Image.file(
                                              File(file.localFilePath!),
                                              width: 48,
                                              height: 48,
                                              fit: BoxFit.cover,
                                              errorBuilder: (_, __, ___) => Container(
                                                padding: const EdgeInsets.all(12),
                                                decoration: BoxDecoration(
                                                    color: MeshColors.blue.withValues(alpha: .12),
                                                    borderRadius: BorderRadius.circular(16)),
                                                child: const Icon(Icons.image_outlined),
                                              ),
                                            ),
                                          )
                                        : Container(
                                            padding: const EdgeInsets.all(12),
                                            decoration: BoxDecoration(
                                                color: MeshColors.blue
                                                    .withValues(alpha: .12),
                                                borderRadius:
                                                    BorderRadius.circular(16)),
                                            child: Icon(file.contentType
                                                    .startsWith('image/')
                                                ? Icons.image_outlined
                                                : Icons.description_outlined)),
                                    title: Text(file.originalFileName,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium),
                                    subtitle: Text(
                                        '${_size(file.fileSize)} · ${date.day}/${date.month}/${date.year}\n${file.status}${file.transport == null ? '' : ' · ${file.transport}'}'),
                                    trailing:
                                        const Icon(Icons.chevron_right_rounded),
                                    onTap: () => Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                            builder: (_) => FileDetailsScreen(
                                                fileMetadata: file,
                                                fileService:
                                                    widget.fileService))),
                                  ));
                            }));
                  })),
        ]),
      );
}
