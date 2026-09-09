import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import '../models/file_metadata.dart';
import '../services/file_service.dart';
import 'file_details_screen.dart';

class FileListScreen extends StatefulWidget {
  final FileService fileService;
  final bool showSent;

  const FileListScreen({super.key, required this.fileService, this.showSent = false});

  @override
  State<FileListScreen> createState() => _FileListScreenState();
}

class _FileListScreenState extends State<FileListScreen> {
  late Future<List<FileMetadata>> futureFiles;
  bool _isUploading = false;
  double _uploadProgress = 0.0;

  @override
  void initState() {
    super.initState();
    _loadFiles();
  }

  void _loadFiles() {
    setState(() {
      futureFiles = widget.showSent
          ? widget.fileService.getSentFiles()
          : widget.fileService.getReceivedFiles();
    });
  }

  Future<void> _pickAndUploadFile() async {
    // Note: In a real app, recipient selection would happen before or during this step.
    // For testing, we'll prompt the user for a recipient OfflineMeshId or hardcode one.
    // Since we're demonstrating upload, we'll use a placeholder recipient for the test.
    String recipientOfflineMeshId = 'TEST_RECIPIENT_ID'; // Replace with actual selection logic

    FilePickerResult? result = await FilePicker.pickFiles();

    if (result != null && result.files.isNotEmpty) {
      File file = File(result.files.single.path!);
      String fileName = result.files.single.name;
      int fileSize = file.lengthSync();

      setState(() {
        _isUploading = true;
        _uploadProgress = 0.0;
      });

      try {
        // 1. Create Metadata
        FileMetadata metadata = await widget.fileService.createMetadata(
          recipientOfflineMeshId: recipientOfflineMeshId,
          originalFileName: fileName,
          contentType: 'application/octet-stream', // Hardcoded for simplicity
          fileSize: fileSize,
        );

        // 2. Upload File
        await widget.fileService.uploadFile(metadata, file, (progress) {
          setState(() {
            _uploadProgress = progress;
          });
        });

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('File uploaded successfully!')),
        );
        _loadFiles();
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Upload failed: $e')),
        );
      } finally {
        setState(() {
          _isUploading = false;
        });
      }
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
                      title: Text(file.originalFileName),
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
