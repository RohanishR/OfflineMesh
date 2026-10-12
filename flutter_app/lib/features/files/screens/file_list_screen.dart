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

  const FileListScreen({
    super.key, 
    required this.fileService, 
    required this.routingService,
    this.friendService, 
    this.showSent = false
  });

  @override
  State<FileListScreen> createState() => _FileListScreenState();
}

class _FileListScreenState extends State<FileListScreen> {
  late Future<List<FileMetadata>> futureFiles;
  bool _isUploading = false;
  double _uploadProgress = 0.0;
  
  StreamSubscription? _incomingFilesSub;

  @override
  void initState() {
    super.initState();
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
      futureFiles = widget.showSent
          ? widget.routingService.getCombinedSentFiles()
          : widget.routingService.getCombinedReceivedFiles();
    });
  }

  String _getMimeType(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    switch (ext) {
      case 'jpg':
      case 'jpeg': return 'image/jpeg';
      case 'png': return 'image/png';
      case 'gif': return 'image/gif';
      case 'pdf': return 'application/pdf';
      case 'txt': return 'text/plain';
      case 'mp4': return 'video/mp4';
      case 'mp3': return 'audio/mpeg';
      default: return 'application/octet-stream';
    }
  }

  Future<void> _pickAndUploadFile() async {
    if (widget.friendService == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Friend service not available')));
      return;
    }

    try {
      final friends = await widget.friendService!.getFriends();
      if (friends.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('You have no friends to send files to.')));
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
                  final isNearby = widget.routingService.isPeerNearby(friend.offlineMeshId);
                  
                  return ListTile(
                    title: Row(
                      children: [
                        Text(friend.username),
                        if (isNearby) ...[
                          const SizedBox(width: 8),
                          const Icon(Icons.wifi_tethering, size: 14, color: Colors.green),
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
        File file = File(result.files.single.path!);
        String fileName = result.files.single.name;
        int fileSize = file.lengthSync();
        String contentType = _getMimeType(fileName);

        setState(() {
          _isUploading = true;
          _uploadProgress = 0.0;
        });

        try {
          await widget.routingService.sendFile(
            selectedFriend!.offlineMeshId,
            fileName,
            contentType,
            fileSize,
            file,
            (progress) {
              if (mounted) {
                setState(() {
                  _uploadProgress = progress;
                });
              }
            }
          );

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
          setState(() {
            _isUploading = false;
          });
        }
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.showSent ? 'Sent Files' : 'Received Files'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadFiles,
          )
        ],
      ),
      body: Column(
        children: [
          if (_isUploading)
            LinearProgressIndicator(value: _uploadProgress),
          Expanded(
            child: FutureBuilder<List<FileMetadata>>(
              future: futureFiles,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                } else if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return const Center(child: Text('No files found.'));
                }

                final files = snapshot.data!;
                return ListView.builder(
                  itemCount: files.length,
                  itemBuilder: (context, index) {
                    final file = files[index];
                    return ListTile(
                      leading: const Icon(Icons.insert_drive_file),
                      title: Row(
                        children: [
                          Expanded(child: Text(file.originalFileName)),
                          if (file.transport == 'WIFI_LAN')
                            const Icon(Icons.wifi_tethering, size: 14, color: Colors.green),
                          if (file.transport == 'BLUETOOTH')
                            const Icon(Icons.bluetooth, size: 14, color: Colors.blue),
                          if (file.transport == 'INTERNET')
                            const Icon(Icons.cloud, size: 14, color: Colors.grey),
                        ],
                      ),
                      subtitle: Text('Size: ${file.fileSize} bytes • Status: ${file.status}'),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => FileDetailsScreen(
                              fileMetadata: file,
                              fileService: widget.fileService,
                            ),
                          ),
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: widget.showSent
          ? FloatingActionButton(
              onPressed: _isUploading ? null : _pickAndUploadFile,
              tooltip: 'Upload File',
              child: const Icon(Icons.upload_file),
            )
          : null,
    );
  }
}

