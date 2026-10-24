import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import '../../../core/models/message.dart';
import '../../../core/services/voice_note_service.dart';
import '../../../core/services/file_viewer_service.dart';
import '../../../core/ui/mesh_widgets.dart';

/// Formats duration to mm:ss
String _formatDuration(Duration d) {
  final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}

/// Formats bytes to human-readable size
String _formatFileSize(int? bytes) {
  if (bytes == null || bytes <= 0) return '';
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

/// WhatsApp-style Voice Note Audio Bubble
class VoiceMessageBubble extends StatefulWidget {
  final Message message;
  final bool isMe;
  final VoiceNoteService voiceNoteService;

  const VoiceMessageBubble({
    super.key,
    required this.message,
    required this.isMe,
    required this.voiceNoteService,
  });

  @override
  State<VoiceMessageBubble> createState() => _VoiceMessageBubbleState();
}

class _VoiceMessageBubbleState extends State<VoiceMessageBubble> {
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _totalDuration = Duration.zero;
  double _playbackSpeed = 1.0;

  StreamSubscription? _posSub;
  StreamSubscription? _durSub;
  StreamSubscription? _stateSub;

  @override
  void initState() {
    super.initState();
    if (widget.message.durationMs != null && widget.message.durationMs! > 0) {
      _totalDuration = Duration(milliseconds: widget.message.durationMs!);
    }

    final player = widget.voiceNoteService.player;
    _posSub = player.onPositionChanged.listen((pos) {
      if (mounted && _isPlaying) {
        setState(() => _position = pos);
      }
    });

    _durSub = player.onDurationChanged.listen((dur) {
      if (mounted && dur > Duration.zero) {
        setState(() => _totalDuration = dur);
      }
    });

    _stateSub = player.onPlayerStateChanged.listen((state) {
      if (mounted) {
        setState(() {
          _isPlaying = state == PlayerState.playing;
          if (state == PlayerState.completed) {
            _position = Duration.zero;
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _durSub?.cancel();
    _stateSub?.cancel();
    super.dispose();
  }

  Future<void> _togglePlayPause() async {
    final path = widget.message.mediaPath;
    if (path == null || !File(path).existsSync()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Audio file not found on device.')),
      );
      return;
    }

    if (_isPlaying) {
      await widget.voiceNoteService.pause();
    } else {
      await widget.voiceNoteService.playVoiceNote(path, speed: _playbackSpeed);
    }
  }

  void _cyclePlaybackSpeed() {
    setState(() {
      if (_playbackSpeed == 1.0) {
        _playbackSpeed = 1.5;
      } else if (_playbackSpeed == 1.5) {
        _playbackSpeed = 2.0;
      } else {
        _playbackSpeed = 1.0;
      }
    });
    if (_isPlaying) {
      widget.voiceNoteService.setPlaybackRate(_playbackSpeed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accentColor = widget.isMe ? Colors.white : MeshColors.blue;
    final trackColor = widget.isMe ? Colors.white24 : Colors.grey.shade300;
    final maxMs = _totalDuration.inMilliseconds > 0
        ? _totalDuration.inMilliseconds.toDouble()
        : (widget.message.durationMs?.toDouble() ?? 1000.0);
    final currentMs = _position.inMilliseconds.toDouble().clamp(0.0, maxMs);

    return Container(
      width: 250,
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Play / Pause Circle Button
              GestureDetector(
                onTap: _togglePlayPause,
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: widget.isMe
                        ? Colors.white.withValues(alpha: 0.2)
                        : const Color(0xFF25D366).withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    color: widget.isMe ? Colors.white : const Color(0xFF25D366),
                    size: 28,
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // Audio Waveform Scrubber
              Expanded(
                child: Column(
                  children: [
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        thumbShape:
                            const RoundSliderThumbShape(enabledThumbRadius: 6),
                        trackHeight: 3.5,
                        activeTrackColor: accentColor,
                        inactiveTrackColor: trackColor,
                        thumbColor: accentColor,
                        overlayShape: SliderComponentShape.noOverlay,
                      ),
                      child: Slider(
                        value: currentMs,
                        min: 0.0,
                        max: maxMs,
                        onChanged: (val) {
                          widget.voiceNoteService
                              .seek(Duration(milliseconds: val.toInt()));
                        },
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _isPlaying
                              ? _formatDuration(_position)
                              : _formatDuration(_totalDuration),
                          style: TextStyle(
                            fontSize: 11,
                            color: widget.isMe
                                ? Colors.white70
                                : theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        // Playback Speed Pill
                        GestureDetector(
                          onTap: _cyclePlaybackSpeed,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: widget.isMe
                                  ? Colors.white.withValues(alpha: 0.2)
                                  : Colors.black.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '${_playbackSpeed}x',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: widget.isMe
                                    ? Colors.white
                                    : theme.colorScheme.onSurface,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 6),
              // Mic Icon Badge
              Icon(
                Icons.mic,
                size: 20,
                color: widget.isMe ? Colors.white70 : const Color(0xFF34B7F1),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// WhatsApp-style Inline Image Bubble with Full-Screen Preview
class ImageMessageBubble extends StatelessWidget {
  final Message message;
  final bool isMe;

  const ImageMessageBubble({
    super.key,
    required this.message,
    required this.isMe,
  });

  @override
  Widget build(BuildContext context) {
    final path = message.mediaPath;
    final hasLocalFile = path != null && File(path).existsSync();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: GestureDetector(
            onTap: () {
              if (hasLocalFile) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => FullScreenImageViewer(
                      imagePath: path,
                      title: message.fileName ?? 'Photo',
                    ),
                  ),
                );
              }
            },
            child: hasLocalFile
                ? Hero(
                    tag: 'img_${message.id}',
                    child: Image.file(
                      File(path),
                      width: 240,
                      height: 200,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                          _buildPlaceholder(context, 'Failed to load image'),
                    ),
                  )
                : _buildPlaceholder(
                    context, message.fileName ?? 'Photo attachment'),
          ),
        ),
        if (message.content.isNotEmpty &&
            message.content != message.fileName) ...[
          const SizedBox(height: 6),
          Text(
            message.content,
            style: TextStyle(
              fontSize: 14,
              color:
                  isMe ? Colors.white : Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildPlaceholder(BuildContext context, String label) {
    return Container(
      width: 240,
      height: 160,
      color: Colors.black12,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.image_outlined, size: 40, color: Colors.grey),
            const SizedBox(height: 8),
            Text(label,
                style: const TextStyle(fontSize: 12, color: Colors.grey)),
            if (message.fileSize != null)
              Text(_formatFileSize(message.fileSize),
                  style: const TextStyle(fontSize: 11, color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}

/// WhatsApp-style Video Message Bubble
class VideoMessageBubble extends StatelessWidget {
  final Message message;
  final bool isMe;

  const VideoMessageBubble({
    super.key,
    required this.message,
    required this.isMe,
  });

  @override
  Widget build(BuildContext context) {
    final path = message.mediaPath;
    final hasLocalFile = path != null && File(path).existsSync();

    return GestureDetector(
      onTap: () {
        if (hasLocalFile) {
          FileViewerService.openFile(path, mimeType: 'video/*');
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Video file not available on this device.')),
          );
        }
      },
      child: Container(
        width: 240,
        height: 150,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            const Icon(Icons.videocam_rounded, size: 54, color: Colors.white54),
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.5),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.play_arrow_rounded,
                  size: 36, color: Colors.white),
            ),
            Positioned(
              bottom: 8,
              left: 10,
              right: 10,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      message.fileName ?? 'Video',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 12,
                          color: Colors.white,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                  if (message.fileSize != null)
                    Text(
                      _formatFileSize(message.fileSize),
                      style:
                          const TextStyle(fontSize: 11, color: Colors.white70),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// WhatsApp-style Document Message Bubble
class DocumentMessageBubble extends StatelessWidget {
  final Message message;
  final bool isMe;

  const DocumentMessageBubble({
    super.key,
    required this.message,
    required this.isMe,
  });

  IconData _getFileIcon(String? name) {
    if (name == null) return Icons.insert_drive_file_rounded;
    final ext = name.split('.').last.toLowerCase();
    switch (ext) {
      case 'pdf':
        return Icons.picture_as_pdf_rounded;
      case 'doc':
      case 'docx':
        return Icons.description_rounded;
      case 'zip':
      case 'rar':
      case '7z':
        return Icons.folder_zip_rounded;
      case 'mp3':
      case 'wav':
      case 'm4a':
        return Icons.audiotrack_rounded;
      default:
        return Icons.insert_drive_file_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final path = message.mediaPath;
    final hasLocalFile = path != null && File(path).existsSync();
    final fileName = message.fileName ?? message.content;

    return GestureDetector(
      onTap: () {
        if (hasLocalFile) {
          FileViewerService.openFile(path);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('File not found on this device.')),
          );
        }
      },
      child: Container(
        width: 250,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isMe
              ? Colors.white.withValues(alpha: 0.15)
              : Colors.black.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: isMe
                    ? Colors.white.withValues(alpha: 0.25)
                    : MeshColors.blue.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                _getFileIcon(fileName),
                color: isMe ? Colors.white : MeshColors.blue,
                size: 26,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: isMe
                          ? Colors.white
                          : Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _formatFileSize(message.fileSize),
                    style: TextStyle(
                      fontSize: 11,
                      color: isMe
                          ? Colors.white70
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            Icon(
              hasLocalFile ? Icons.open_in_new_rounded : Icons.download_rounded,
              size: 20,
              color: isMe ? Colors.white70 : Colors.grey,
            ),
          ],
        ),
      ),
    );
  }
}

/// Full-Screen Image Viewer with Interactive Pinch-Zoom and Share
class FullScreenImageViewer extends StatelessWidget {
  final String imagePath;
  final String title;

  const FullScreenImageViewer({
    super.key,
    required this.imagePath,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black.withValues(alpha: 0.8),
        foregroundColor: Colors.white,
        title: Text(title, style: const TextStyle(fontSize: 16)),
        actions: [
          IconButton(
            icon: const Icon(Icons.share_rounded),
            onPressed: () =>
                FileViewerService.shareFile(imagePath, mimeType: 'image/*'),
          ),
        ],
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 0.8,
          maxScale: 4.0,
          child: Image.file(
            File(imagePath),
            fit: BoxFit.contain,
          ),
        ),
      ),
    );
  }
}

/// WhatsApp-style Attachment Picker Modal Sheet
class AttachmentPickerSheet extends StatelessWidget {
  final VoidCallback onCameraTap;
  final VoidCallback onGalleryTap;
  final VoidCallback onVideoTap;
  final VoidCallback onDocumentTap;
  final VoidCallback? onNoteTap;

  const AttachmentPickerSheet({
    super.key,
    required this.onCameraTap,
    required this.onGalleryTap,
    required this.onVideoTap,
    required this.onDocumentTap,
    this.onNoteTap,
  });

  Widget _buildItem(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GlassSurface(
      padding: EdgeInsets.zero,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(26),
          onTap: () {
            Navigator.pop(context);
            onTap();
          },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: MeshColors.orange.withValues(alpha: .14),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon,
                    color: Theme.of(context).brightness == Brightness.dark
                        ? MeshColors.orange
                        : MeshColors.navy,
                    size: 26),
              ),
              const SizedBox(height: 12),
              Text(label,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleSmall),
            ]),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final actions = [
      (Icons.camera_alt_outlined, 'Camera', onCameraTap),
      (Icons.photo_library_outlined, 'Gallery', onGalleryTap),
      (Icons.videocam_outlined, 'Video', onVideoTap),
      (Icons.insert_drive_file_outlined, 'Document', onDocumentTap),
      if (onNoteTap != null) (Icons.note_alt_outlined, 'Notes', onNoteTap!),
    ];
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(children: [
              Expanded(
                  child: Text('Add to conversation',
                      style: Theme.of(context).textTheme.titleLarge)),
              IconButton(
                  tooltip: 'Close attachments',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded)),
            ]),
            Text('Choose what you’d like to share.',
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 20),
            LayoutBuilder(builder: (context, constraints) {
              final columns =
                  MediaQuery.textScalerOf(context).scale(1) > 1.5 ? 1 : 2;
              final width =
                  (constraints.maxWidth - (columns - 1) * 12) / columns;
              return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: actions
                      .map((action) => SizedBox(
                          width: width,
                          child: _buildItem(context,
                              icon: action.$1,
                              label: action.$2,
                              onTap: action.$3)))
                      .toList());
            }),
          ],
        ),
      ),
    );
  }
}
