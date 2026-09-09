import 'package:flutter/material.dart';
import '../models/file_metadata.dart';
import '../services/file_service.dart';
import 'package:crypto/crypto.dart';
import 'dart:io';

class FileDetailsScreen extends StatefulWidget {
  final FileMetadata fileMetadata;
  final FileService fileService;

  const FileDetailsScreen({super.key, required this.fileMetadata, required this.fileService});

  @override
  State<FileDetailsScreen> createState() => _FileDetailsScreenState();
}

class _FileDetailsScreenState extends State<FileDetailsScreen> {
  bool _isDownloading = false;
  double _downloadProgress = 0.0;
  String? _downloadPath;

  Future<void> _downloadFile() async {
    setState(() {
      _isDownloading = true;
      _downloadProgress = 0.0;
      _downloadPath = null;
    });

    try {
      File downloadedFile = await widget.fileService.downloadFile(widget.fileMetadata, (progress) {
        setState(() {
          _downloadProgress = progress;
        });
      });

      // Verify Checksum if provided
      if (widget.fileMetadata.checksum != null) {
        var bytes = await downloadedFile.readAsBytes();
        var digest = sha256.convert(bytes);
        if (digest.toString() != widget.fileMetadata.checksum) {
          throw Exception('Checksum verification failed!');
        }
      }

      setState(() {
        _downloadPath = downloadedFile.path;
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Downloaded successfully to $_downloadPath')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Download failed: $e')),
      );
    } finally {
      setState(() {
        _isDownloading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('File Details'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('ID: ${widget.fileMetadata.id}', style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 8),
            Text('File Name: ${widget.fileMetadata.originalFileName}', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text('Sender: ${widget.fileMetadata.senderOfflineMeshId}'),
            const SizedBox(height: 8),
            Text('Recipient: ${widget.fileMetadata.recipientOfflineMeshId}'),
            const SizedBox(height: 8),
            Text('Content Type: ${widget.fileMetadata.contentType}'),
            const SizedBox(height: 8),
            Text('Size: ${widget.fileMetadata.fileSize} bytes'),
            const SizedBox(height: 8),
            Text('Status: ${widget.fileMetadata.status}', style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('Created At: ${widget.fileMetadata.createdAt}'),
            if (widget.fileMetadata.checksum != null) ...[
              const SizedBox(height: 8),
              Text('Checksum: ${widget.fileMetadata.checksum}'),
            ],
            const Spacer(),
            if (_isDownloading) ...[
              LinearProgressIndicator(value: _downloadProgress),
              const SizedBox(height: 8),
              Text('Downloading... ${(_downloadProgress * 100).toStringAsFixed(1)}%'),
            ],
            if (_downloadPath != null) ...[
              const SizedBox(height: 8),
              Text('Saved to: $_downloadPath', style: const TextStyle(color: Colors.green)),
            ],
            const SizedBox(height: 16),
            Center(
              child: ElevatedButton.icon(
                onPressed: _isDownloading || widget.fileMetadata.status != 'AVAILABLE' ? null : _downloadFile,
                icon: const Icon(Icons.download),
                label: const Text('Download / Verify'),
              ),
            )
          ],
        ),
      ),
    );
  }
}
