import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:crypto/crypto.dart';
import '../models/file_metadata.dart';
import '../services/file_service.dart';
import '../../../core/services/file_viewer_service.dart';
import '../../../core/ui/mesh_widgets.dart';

class FileDetailsScreen extends StatefulWidget {
  final FileMetadata fileMetadata;
  final FileService fileService;

  const FileDetailsScreen({
    super.key,
    required this.fileMetadata,
    required this.fileService,
  });

  @override
  State<FileDetailsScreen> createState() => _FileDetailsScreenState();
}

class _FileDetailsScreenState extends State<FileDetailsScreen> {
  bool _isDownloading = false;
  double _downloadProgress = 0.0;
  String? _downloadPath;
  String? _textContent;

  @override
  void initState() {
    super.initState();
    _downloadPath = widget.fileMetadata.localFilePath;
    _checkAndLoadTextPreview();
  }

  bool _isImage(String name, String type) {
    if (type.startsWith('image/')) return true;
    final ext = name.split('.').last.toLowerCase();
    return ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'].contains(ext);
  }

  bool _isText(String name, String type) {
    if (type.startsWith('text/')) return true;
    final ext = name.split('.').last.toLowerCase();
    return ['txt', 'json', 'md', 'log', 'csv', 'xml', 'dart', 'py', 'java', 'html', 'css', 'js'].contains(ext);
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1048576) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1048576).toStringAsFixed(1)} MB';
  }

  Future<void> _checkAndLoadTextPreview() async {
    final path = _downloadPath;
    if (path == null) return;
    final file = File(path);
    if (!await file.exists()) return;

    if (_isText(widget.fileMetadata.originalFileName, widget.fileMetadata.contentType)) {
      try {
        final length = await file.length();
        if (length < 65536) {
          final content = await file.readAsString();
          if (mounted) setState(() => _textContent = content);
        } else {
          final bytes = await file.openRead(0, 65536).first;
          final content = String.fromCharCodes(bytes);
          if (mounted) setState(() => _textContent = '$content\n\n[... Truncated large file preview ...]');
        }
      } catch (_) {
        // Not plain UTF-8 text
      }
    }
  }

  Future<void> _downloadFile() async {
    setState(() {
      _isDownloading = true;
      _downloadProgress = 0.0;
    });

    try {
      final downloadedFile = await widget.fileService.downloadFile(
        widget.fileMetadata,
        (progress) {
          if (mounted) {
            setState(() {
              _downloadProgress = progress;
            });
          }
        },
      );

      // Verify Checksum if provided and not encrypted
      if (!widget.fileMetadata.isEncrypted && widget.fileMetadata.checksum != null) {
        final sha256Digest = await sha256.bind(downloadedFile.openRead()).last;
        if (sha256Digest.toString() != widget.fileMetadata.checksum) {
          throw Exception('Checksum verification failed!');
        }
      }

      setState(() {
        _downloadPath = downloadedFile.path;
        widget.fileMetadata.localFilePath = downloadedFile.path;
      });

      await _checkAndLoadTextPreview();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('File downloaded and ready to view!')),
      );
    } catch (e) {
      if (!mounted) return;
      final errorMsg = e.toString().replaceFirst('Exception: ', '');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Download failed: $errorMsg')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isDownloading = false;
        });
      }
    }
  }

  Future<void> _openFile() async {
    final path = _downloadPath;
    if (path == null) return;
    final success = await FileViewerService.openFile(
      path,
      mimeType: widget.fileMetadata.contentType,
    );
    if (!success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not find an app to open this file.')),
      );
    }
  }

  Future<void> _shareFile() async {
    final path = _downloadPath;
    if (path == null) return;
    await FileViewerService.shareFile(
      path,
      mimeType: widget.fileMetadata.contentType,
    );
  }

  @override
  Widget build(BuildContext context) {
    final localPath = _downloadPath;
    final hasLocalFile = localPath != null && File(localPath).existsSync();
    final isImage = _isImage(widget.fileMetadata.originalFileName, widget.fileMetadata.contentType);
    final isText = _isText(widget.fileMetadata.originalFileName, widget.fileMetadata.contentType);
    final isPending = widget.fileMetadata.status == 'PENDING';
    final isAvailable = widget.fileMetadata.status == 'AVAILABLE' ||
        widget.fileMetadata.status == 'COMPLETED';

    return Scaffold(
      appBar: AppBar(
        title: const Text('File Details'),
        actions: [
          if (hasLocalFile)
            IconButton(
              icon: const Icon(Icons.share_rounded),
              tooltip: 'Share file',
              onPressed: _shareFile,
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. IN-APP PREVIEW (When locally available)
            if (hasLocalFile && isImage) ...[
              GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => FullscreenImageViewer(
                        filePath: localPath,
                        fileName: widget.fileMetadata.originalFileName,
                      ),
                    ),
                  );
                },
                child: GlassSurface(
                  padding: const EdgeInsets.all(8),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: Stack(
                      alignment: Alignment.bottomRight,
                      children: [
                        Image.file(
                          File(localPath),
                          height: 280,
                          width: double.infinity,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            height: 200,
                            color: Colors.black26,
                            child: const Center(
                              child: Icon(Icons.broken_image_rounded, size: 48),
                            ),
                          ),
                        ),
                        Container(
                          margin: const EdgeInsets.all(12),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.7),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.zoom_in_rounded, color: Colors.white, size: 16),
                              SizedBox(width: 4),
                              Text('Tap to zoom', style: TextStyle(color: Colors.white, fontSize: 12)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ] else if (hasLocalFile && isText && _textContent != null) ...[
              GlassSurface(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Text Preview', style: TextStyle(fontWeight: FontWeight.bold)),
                        IconButton(
                          icon: const Icon(Icons.copy_rounded, size: 18),
                          tooltip: 'Copy text',
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: _textContent!));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Copied to clipboard')),
                            );
                          },
                        ),
                      ],
                    ),
                    const Divider(),
                    Container(
                      constraints: const BoxConstraints(maxHeight: 200),
                      width: double.infinity,
                      child: SingleChildScrollView(
                        child: Text(
                          _textContent!,
                          style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            // 2. FILE INFO CARD
            GlassSurface(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: MeshColors.blue.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Icon(
                          isImage
                              ? Icons.image_rounded
                              : Icons.insert_drive_file_rounded,
                          color: MeshColors.blue,
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.fileMetadata.originalFileName,
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${_formatSize(widget.fileMetadata.fileSize)} · ${widget.fileMetadata.contentType}',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Colors.grey,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Divider(),
                  ),
                  _buildDetailRow('Sender', widget.fileMetadata.senderOfflineMeshId),
                  const SizedBox(height: 8),
                  _buildDetailRow('Recipient', widget.fileMetadata.recipientOfflineMeshId),
                  const SizedBox(height: 8),
                  _buildDetailRow(
                    'Status',
                    widget.fileMetadata.status,
                    valueColor: widget.fileMetadata.status == 'COMPLETED' || widget.fileMetadata.status == 'AVAILABLE'
                        ? Colors.green
                        : Colors.amber,
                  ),
                  if (widget.fileMetadata.transport != null) ...[
                    const SizedBox(height: 8),
                    _buildDetailRow('Transport', widget.fileMetadata.transport!),
                  ],
                  if (widget.fileMetadata.isEncrypted) ...[
                    const SizedBox(height: 8),
                    _buildDetailRow('Security', 'End-to-End Encrypted', valueColor: MeshColors.blue),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 20),

            // 3. ACTION BUTTONS
            if (hasLocalFile) ...[
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                onPressed: _openFile,
                icon: const Icon(Icons.open_in_new_rounded),
                label: Text(isImage ? 'Open in Photo Viewer' : 'Open File'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                onPressed: _shareFile,
                icon: const Icon(Icons.share_rounded),
                label: const Text('Share File'),
              ),
            ] else ...[
              if (_isDownloading) ...[
                GlassSurface(
                  child: Column(
                    children: [
                      LinearProgressIndicator(value: _downloadProgress.clamp(0.0, 1.0)),
                      const SizedBox(height: 10),
                      Text(
                        'Downloading from Server: ${(_downloadProgress * 100).toStringAsFixed(1)}%',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ] else if (isPending) ...[
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.hourglass_top_rounded, color: Colors.amber, size: 24),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Sender is still uploading this file. It will be downloadable once upload completes.',
                          style: TextStyle(color: Colors.amber, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              ] else ...[
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  onPressed: isAvailable ? _downloadFile : null,
                  icon: const Icon(Icons.download_rounded),
                  label: const Text('Download to App'),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, {Color? valueColor}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 13)),
        Flexible(
          child: Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 13,
              color: valueColor,
            ),
            textAlign: TextAlign.end,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class FullscreenImageViewer extends StatelessWidget {
  final String filePath;
  final String fileName;

  const FullscreenImageViewer({
    super.key,
    required this.filePath,
    required this.fileName,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black.withValues(alpha: 0.8),
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(fileName, style: const TextStyle(color: Colors.white, fontSize: 16)),
        actions: [
          IconButton(
            icon: const Icon(Icons.share_rounded),
            tooltip: 'Share image',
            onPressed: () => FileViewerService.shareFile(filePath, mimeType: 'image/*'),
          ),
        ],
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 0.8,
          maxScale: 4.0,
          child: Image.file(File(filePath)),
        ),
      ),
    );
  }
}
