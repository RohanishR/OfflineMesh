import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../../core/ui/mesh_widgets.dart';
import 'package:uuid/uuid.dart';
import '../models/note_item.dart';
import '../services/notes_service.dart';

class NoteEditorScreen extends StatefulWidget {
  final NoteItem? initialNote;
  final bool startWithChecklist;
  final bool startWithPhoto;
  final bool startWithVideo;
  final bool startWithReminder;

  const NoteEditorScreen({
    super.key,
    this.initialNote,
    this.startWithChecklist = false,
    this.startWithPhoto = false,
    this.startWithVideo = false,
    this.startWithReminder = false,
  });

  @override
  State<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends State<NoteEditorScreen> {
  final NotesService _notesService = NotesService();

  late String _id;
  late TextEditingController _titleController;
  late TextEditingController _contentController;
  late List<ChecklistItem> _checklist;
  late List<TextEditingController> _checklistControllers;
  late List<String> _imagePaths;
  late List<String> _videoPaths;
  DateTime? _reminderDateTime;
  bool _isReminderDone = false;
  bool _isPinned = false;
  bool _isArchived = false;
  int _colorIndex = 0;
  bool _isChecklistMode = false;
  late DateTime _createdAt;
  late DateTime _updatedAt;
  bool _isDeleted = false;
  bool _closing = false;
  bool _canPop = false;

  Future<void> _saveAndClose() async {
    if (_closing) return;
    _closing = true;
    try {
      await _saveNote();
      if (!mounted) {
        return;
      }
      setState(() => _canPop = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          Navigator.pop(context);
        }
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Could not save. Your edits are still here. Please retry.')));
      }
    } finally {
      _closing = false;
    }
  }

  List<String> _labels = [];

  Future<void> _editLabels() async {
    final controller = TextEditingController(text: _labels.join(', '));
    final value = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
                title: const Text('Note labels'),
                content: TextField(
                    controller: controller,
                    autofocus: true,
                    decoration: const InputDecoration(
                        hintText: 'Work, Ideas, Personal',
                        helperText: 'Separate labels with commas')),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Cancel')),
                  FilledButton(
                      onPressed: () => Navigator.pop(ctx, controller.text),
                      child: const Text('Save'))
                ]));
    if (mounted && value != null) {
      setState(() => _labels = value
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toSet()
          .toList());
    }
  }

  @override
  void initState() {
    super.initState();
    final note = widget.initialNote;
    if (note != null) {
      _id = note.id;
      _labels = List.from(note.labels);
      _titleController = TextEditingController(text: note.title);
      _contentController = TextEditingController(text: note.content);
      _checklist = note.checklist.map((c) => c.copyWith()).toList();
      _imagePaths = List.from(note.imagePaths);
      _videoPaths = List.from(note.videoPaths);
      _reminderDateTime = note.reminderDateTime;
      _isReminderDone = note.isReminderDone;
      _isPinned = note.isPinned;
      _isArchived = note.isArchived;
      _colorIndex = note.colorIndex;
      _createdAt = note.createdAt;
      _updatedAt = note.updatedAt;
      _isChecklistMode = note.checklist.isNotEmpty;
    } else {
      _id = const Uuid().v4();
      _titleController = TextEditingController();
      _contentController = TextEditingController();
      _checklist = [];
      _imagePaths = [];
      _videoPaths = [];
      _reminderDateTime = null;
      _isReminderDone = false;
      _isPinned = false;
      _isArchived = false;
      _colorIndex = 0;
      _createdAt = DateTime.now();
      _updatedAt = DateTime.now();
      _isChecklistMode = widget.startWithChecklist;
    }

    _checklistControllers = _checklist
        .map((item) => TextEditingController(text: item.text))
        .toList();

    if (_isChecklistMode && _checklist.isEmpty) {
      _addChecklistItem();
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.startWithPhoto) {
        _pickMedia(isVideo: false);
      } else if (widget.startWithVideo) {
        _pickMedia(isVideo: true);
      } else if (widget.startWithReminder) {
        _showReminderDialog();
      }
    });
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    for (var controller in _checklistControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  void _addChecklistItem() {
    setState(() {
      final item = ChecklistItem(id: const Uuid().v4(), text: '');
      _checklist.add(item);
      _checklistControllers.add(TextEditingController());
    });
  }

  void _removeChecklistItem(int index) {
    setState(() {
      _checklist.removeAt(index);
      final controller = _checklistControllers.removeAt(index);
      controller.dispose();
    });
  }

  Future<void> _saveNote() async {
    if (_isDeleted) return;

    // Sync checklist text controllers
    for (int i = 0; i < _checklist.length; i++) {
      if (i < _checklistControllers.length) {
        _checklist[i].text = _checklistControllers[i].text.trim();
      }
    }
    // Filter out completely blank checklist items if there are valid items
    final validChecklist = _checklist
        .where((item) => item.text.isNotEmpty || item.isDone)
        .toList();

    final note = NoteItem(
      id: _id,
      title: _titleController.text.trim(),
      content: _contentController.text.trim(),
      checklist: _isChecklistMode ? validChecklist : [],
      imagePaths: _imagePaths,
      videoPaths: _videoPaths,
      reminderDateTime: _reminderDateTime,
      isReminderDone: _isReminderDone,
      isPinned: _isPinned,
      isArchived: _isArchived,
      colorIndex: _colorIndex,
      labels: List.from(_labels),
      createdAt: _createdAt,
      updatedAt: DateTime.now(),
    );

    if (note.isEmpty) {
      if (widget.initialNote != null) {
        await _notesService.deleteNote(_id);
      }
    } else {
      await _notesService.saveNote(note);
    }
  }

  Future<void> _pickMedia({required bool isVideo}) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: isVideo ? FileType.video : FileType.image,
        allowMultiple: true,
      );
      if (result != null && result.paths.isNotEmpty) {
        for (var path in result.paths) {
          if (path != null) {
            final storedPath =
                await _notesService.copyMediaFile(path, isVideo: isVideo);
            setState(() {
              if (isVideo) {
                if (!_videoPaths.contains(storedPath)) {
                  _videoPaths.add(storedPath);
                }
              } else {
                if (!_imagePaths.contains(storedPath)) {
                  _imagePaths.add(storedPath);
                }
              }
            });
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text('Failed to pick ${isVideo ? "video" : "photo"}: $e')),
        );
      }
    }
  }

  void _showColorPicker() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 8, bottom: 16),
                  child: Text(
                    'Color',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                ),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: List.generate(NoteItem.colorNames.length, (index) {
                    final color = NoteItem.getBackgroundColor(index, isDark);
                    final isSelected = _colorIndex == index;
                    return InkWell(
                      borderRadius: BorderRadius.circular(24),
                      onTap: () {
                        setState(() => _colorIndex = index);
                        Navigator.pop(ctx);
                      },
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: color,
                          border: Border.all(
                            color: isSelected
                                ? Theme.of(context).colorScheme.primary
                                : (isDark ? Colors.white24 : Colors.black12),
                            width: isSelected ? 2.5 : 1.0,
                          ),
                        ),
                        child: isSelected
                            ? Icon(
                                Icons.check_rounded,
                                size: 22,
                                color: isDark ? Colors.white : Colors.black87,
                              )
                            : (index == 0
                                ? Icon(
                                    Icons.format_color_reset_outlined,
                                    size: 18,
                                    color: isDark
                                        ? Colors.white54
                                        : Colors.black54,
                                  )
                                : null),
                      ),
                    );
                  }),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showReminderDialog() {
    final now = DateTime.now();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: Row(
                    children: [
                      const Icon(Icons.alarm_add_rounded, size: 22),
                      const SizedBox(width: 12),
                      Text(
                        'Set reminder',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.access_time_rounded),
                  title: const Text('Later today'),
                  trailing: const Text('6:00 PM',
                      style: TextStyle(color: Colors.grey)),
                  onTap: () {
                    final dt = DateTime(now.year, now.month, now.day, 18, 0);
                    _setReminderTime(dt.isAfter(now)
                        ? dt
                        : dt.add(const Duration(hours: 2)));
                    Navigator.pop(ctx);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.wb_sunny_outlined),
                  title: const Text('Tomorrow morning'),
                  trailing: const Text('8:00 AM',
                      style: TextStyle(color: Colors.grey)),
                  onTap: () {
                    final tomorrow = now.add(const Duration(days: 1));
                    _setReminderTime(DateTime(
                        tomorrow.year, tomorrow.month, tomorrow.day, 8, 0));
                    Navigator.pop(ctx);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.nights_stay_outlined),
                  title: const Text('Tomorrow evening'),
                  trailing: const Text('6:00 PM',
                      style: TextStyle(color: Colors.grey)),
                  onTap: () {
                    final tomorrow = now.add(const Duration(days: 1));
                    _setReminderTime(DateTime(
                        tomorrow.year, tomorrow.month, tomorrow.day, 18, 0));
                    Navigator.pop(ctx);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.edit_calendar_rounded),
                  title: const Text('Pick a date & time...'),
                  onTap: () async {
                    Navigator.pop(ctx);
                    final pickedDate = await showDatePicker(
                      context: context,
                      initialDate: _reminderDateTime ?? now,
                      firstDate: now,
                      lastDate: now.add(const Duration(days: 365)),
                    );
                    if (pickedDate != null && mounted) {
                      final pickedTime = await showTimePicker(
                        context: context,
                        initialTime:
                            TimeOfDay.fromDateTime(_reminderDateTime ?? now),
                      );
                      if (pickedTime != null && mounted) {
                        _setReminderTime(DateTime(
                          pickedDate.year,
                          pickedDate.month,
                          pickedDate.day,
                          pickedTime.hour,
                          pickedTime.minute,
                        ));
                      }
                    }
                  },
                ),
                if (_reminderDateTime != null) ...[
                  const Divider(),
                  ListTile(
                    leading: const Icon(Icons.delete_outline_rounded,
                        color: Colors.redAccent),
                    title: const Text('Delete reminder',
                        style: TextStyle(color: Colors.redAccent)),
                    onTap: () {
                      _setReminderTime(null);
                      Navigator.pop(ctx);
                    },
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  void _setReminderTime(DateTime? dt) {
    setState(() {
      _reminderDateTime = dt;
      _isReminderDone = false;
    });
  }

  void _deleteNote() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete note?'),
        content: const Text(
            'This will permanently delete this note and its attachments.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      _isDeleted = true;
      await _notesService.deleteNote(_id);
      if (mounted) {
        setState(() => _canPop = true);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) Navigator.pop(context);
        });
      }
    }
  }

  String _formatDateTime(DateTime dt) {
    final now = DateTime.now();
    final isToday =
        now.year == dt.year && now.month == dt.month && now.day == dt.day;
    final tomorrow = now.add(const Duration(days: 1));
    final isTomorrow = tomorrow.year == dt.year &&
        tomorrow.month == dt.month &&
        tomorrow.day == dt.day;

    final hour = dt.hour == 0 ? 12 : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    final minute = dt.minute.toString().padLeft(2, '0');
    final timeStr = '$hour:$minute $ampm';

    if (isToday) return 'Today, $timeStr';
    if (isTomorrow) return 'Tomorrow, $timeStr';

    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    return '${months[dt.month - 1]} ${dt.day}, $timeStr';
  }

  void _openImageLightbox(String path) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: Stack(
          children: [
            Center(
              child: InteractiveViewer(
                child: Image.file(
                  File(path),
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const Center(
                    child: Text('Image unavailable',
                        style: TextStyle(color: Colors.white)),
                  ),
                ),
              ),
            ),
            PositionBar(
              top: 40,
              left: 16,
              child: IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () => Navigator.pop(ctx),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openVideoPreview(String path) {
    final name = path.split(Platform.pathSeparator).last;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.video_library_rounded, color: MeshColors.blue),
            SizedBox(width: 10),
            Text('Video Attachment'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.black12,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                children: [
                  Icon(Icons.play_circle_fill,
                      size: 40, color: MeshColors.blue),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Video is saved locally in note storage.',
                      style: TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = _colorIndex == 0
        ? Theme.of(context).scaffoldBackgroundColor
        : NoteItem.getBackgroundColor(_colorIndex, isDark);
    final textColor = isDark ? Colors.white : Colors.black87;
    final hintColor = isDark ? Colors.white54 : Colors.black45;

    return PopScope(
      canPop: _canPop,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _saveAndClose();
      },
      child: Scaffold(
        backgroundColor: bgColor,
        appBar: AppBar(
          flexibleSpace: const GlassSurface(
              blur: true, padding: EdgeInsets.zero, child: SizedBox.expand()),
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: _saveAndClose,
          ),
          actions: [
            IconButton(
              icon: Icon(
                _isPinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
                color: _isPinned ? Theme.of(context).colorScheme.primary : null,
              ),
              tooltip: _isPinned ? 'Unpin' : 'Pin',
              onPressed: () => setState(() => _isPinned = !_isPinned),
            ),
            IconButton(
              icon: Icon(
                _reminderDateTime != null
                    ? Icons.notifications_active_rounded
                    : Icons.notification_add_outlined,
                color: _reminderDateTime != null ? Colors.amber[700] : null,
              ),
              tooltip: 'Reminder',
              onPressed: _showReminderDialog,
            ),
            IconButton(
              icon: Icon(
                _isArchived ? Icons.unarchive_outlined : Icons.archive_outlined,
              ),
              tooltip: _isArchived ? 'Unarchive' : 'Archive',
              onPressed: () {
                setState(() => _isArchived = !_isArchived);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content:
                        Text(_isArchived ? 'Note archived' : 'Note unarchived'),
                    duration: const Duration(seconds: 1),
                  ),
                );
              },
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert_rounded),
              onSelected: (val) {
                if (val == 'labels') _editLabels();
                if (val == 'delete') _deleteNote();
                if (val == 'color') _showColorPicker();
              },
              itemBuilder: (ctx) => [
                const PopupMenuItem(
                    value: 'labels', child: Text('Edit labels')),
                const PopupMenuItem(
                  value: 'color',
                  child: Row(
                    children: [
                      Icon(Icons.palette_outlined, size: 20),
                      SizedBox(width: 12),
                      Text('Change color'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(Icons.delete_outline_rounded,
                          color: Colors.redAccent, size: 20),
                      SizedBox(width: 12),
                      Text('Delete note',
                          style: TextStyle(color: Colors.redAccent)),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
        body: Column(
          children: [
            Expanded(
              child: ListView(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                children: [
                  if (_labels.isNotEmpty)
                    Wrap(
                        spacing: 6,
                        children: _labels
                            .map((label) => ActionChip(
                                label: Text(label), onPressed: _editLabels))
                            .toList()),
                  // Reminder banner chip if set
                  if (_reminderDateTime != null) ...[
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Chip(
                        avatar: Icon(
                          Icons.alarm_rounded,
                          size: 16,
                          color:
                              _isReminderDone ? Colors.grey : Colors.amber[800],
                        ),
                        label: Text(
                          _formatDateTime(_reminderDateTime!),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            decoration: _isReminderDone
                                ? TextDecoration.lineThrough
                                : null,
                          ),
                        ),
                        deleteIcon: const Icon(Icons.close_rounded, size: 16),
                        onDeleted: () => _setReminderTime(null),
                        backgroundColor: (isDark
                            ? Colors.white10
                            : Colors.black.withValues(alpha: 0.06)),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],

                  // Media gallery (Photos & Videos)
                  if (_imagePaths.isNotEmpty || _videoPaths.isNotEmpty) ...[
                    _buildMediaGallery(isDark),
                    const SizedBox(height: 16),
                  ],

                  // Title Field
                  TextField(
                    controller: _titleController,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: textColor,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Title',
                      hintStyle: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: hintColor,
                      ),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                    ),
                    maxLines: null,
                    textCapitalization: TextCapitalization.sentences,
                  ),
                  const SizedBox(height: 12),

                  // Content Area: Checklist or plain text
                  if (_isChecklistMode)
                    _buildChecklistEditor(isDark, textColor, hintColor)
                  else
                    TextField(
                      controller: _contentController,
                      style: TextStyle(
                          fontSize: 16, height: 1.5, color: textColor),
                      decoration: InputDecoration(
                        hintText: 'Note',
                        hintStyle: TextStyle(fontSize: 16, color: hintColor),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                      ),
                      maxLines: null,
                      keyboardType: TextInputType.multiline,
                    ),
                ],
              ),
            ),

            // Bottom Google Keep action toolbar
            _buildBottomToolbar(isDark),
          ],
        ),
      ),
    );
  }

  Widget _buildMediaGallery(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_imagePaths.isNotEmpty) ...[
          SizedBox(
            height: 140,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _imagePaths.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (ctx, idx) {
                final path = _imagePaths[idx];
                return Stack(
                  children: [
                    GestureDetector(
                      onTap: () => _openImageLightbox(path),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.file(
                          File(path),
                          height: 140,
                          width: 140,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            height: 140,
                            width: 140,
                            color: Colors.black12,
                            alignment: Alignment.center,
                            child: const Icon(Icons.broken_image_rounded,
                                size: 36),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 4,
                      right: 4,
                      child: InkWell(
                        onTap: () => setState(() => _imagePaths.removeAt(idx)),
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                            color: Colors.black54,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.close,
                              size: 16, color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 10),
        ],
        if (_videoPaths.isNotEmpty) ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: List.generate(_videoPaths.length, (idx) {
              final path = _videoPaths[idx];
              final fileName = path.split(Platform.pathSeparator).last;
              return Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white12
                      : Colors.black.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    InkWell(
                      onTap: () => _openVideoPreview(path),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.videocam_rounded,
                              color: MeshColors.blue, size: 20),
                          SizedBox(width: 8),
                        ],
                      ),
                    ),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 160),
                      child: Text(
                        fileName,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w500),
                      ),
                    ),
                    const SizedBox(width: 6),
                    InkWell(
                      onTap: () => setState(() => _videoPaths.removeAt(idx)),
                      child:
                          const Icon(Icons.close, size: 16, color: Colors.grey),
                    ),
                  ],
                ),
              );
            }),
          ),
        ],
      ],
    );
  }

  Widget _buildChecklistEditor(bool isDark, Color textColor, Color hintColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int i = 0; i < _checklist.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                Checkbox(
                  value: _checklist[i].isDone,
                  activeColor: Theme.of(context).colorScheme.primary,
                  onChanged: (val) {
                    setState(() {
                      _checklist[i].isDone = val ?? false;
                    });
                  },
                ),
                Expanded(
                  child: TextField(
                    controller: _checklistControllers[i],
                    style: TextStyle(
                      fontSize: 16,
                      color: _checklist[i].isDone ? hintColor : textColor,
                      decoration: _checklist[i].isDone
                          ? TextDecoration.lineThrough
                          : null,
                    ),
                    decoration: InputDecoration(
                      hintText: 'List item',
                      hintStyle: TextStyle(color: hintColor),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                    ),
                    textInputAction: TextInputAction.next,
                    onSubmitted: (_) => _addChecklistItem(),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 18),
                  color: hintColor,
                  onPressed: () => _removeChecklistItem(i),
                ),
              ],
            ),
          ),
        TextButton.icon(
          onPressed: _addChecklistItem,
          icon: const Icon(Icons.add_rounded),
          label: const Text('List item'),
        ),
      ],
    );
  }

  Widget _buildBottomToolbar(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: (isDark ? Colors.black26 : Colors.white24),
        border: Border(
          top: BorderSide(
            color: isDark ? Colors.white10 : Colors.black12,
            width: 0.5,
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.add_photo_alternate_outlined),
              tooltip: 'Add photo',
              onPressed: () => _pickMedia(isVideo: false),
            ),
            IconButton(
              icon: const Icon(Icons.video_library_outlined),
              tooltip: 'Add video',
              onPressed: () => _pickMedia(isVideo: true),
            ),
            IconButton(
              icon: Icon(
                _isChecklistMode
                    ? Icons.check_box_rounded
                    : Icons.check_box_outlined,
                color: _isChecklistMode
                    ? Theme.of(context).colorScheme.primary
                    : null,
              ),
              tooltip: 'Checklist mode',
              onPressed: () {
                setState(() {
                  _isChecklistMode = !_isChecklistMode;
                  if (_isChecklistMode && _checklist.isEmpty) {
                    if (_contentController.text.trim().isNotEmpty) {
                      final lines = _contentController.text.split('\n');
                      for (var line in lines) {
                        if (line.trim().isNotEmpty) {
                          _checklist.add(ChecklistItem(
                              id: const Uuid().v4(), text: line.trim()));
                          _checklistControllers
                              .add(TextEditingController(text: line.trim()));
                        }
                      }
                    }
                    if (_checklist.isEmpty) {
                      _addChecklistItem();
                    }
                  }
                });
              },
            ),
            IconButton(
              icon: const Icon(Icons.palette_outlined),
              tooltip: 'Background color',
              onPressed: _showColorPicker,
            ),
            IconButton(
              icon: const Icon(Icons.alarm_add_outlined),
              tooltip: 'Reminder',
              onPressed: _showReminderDialog,
            ),
            const Spacer(),
            Text(
              'Edited ${_formatEditedTime(_updatedAt)}',
              style: TextStyle(
                fontSize: 11,
                color: isDark ? Colors.white54 : Colors.black45,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatEditedTime(DateTime dt) {
    final now = DateTime.now();
    final hour = dt.hour == 0 ? 12 : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    final minute = dt.minute.toString().padLeft(2, '0');
    final timeStr = '$hour:$minute $ampm';

    if (now.year == dt.year && now.month == dt.month && now.day == dt.day) {
      return timeStr;
    }
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    return '${months[dt.month - 1]} ${dt.day}';
  }
}

class PositionBar extends StatelessWidget {
  final double? top;
  final double? left;
  final double? right;
  final double? bottom;
  final Widget child;

  const PositionBar({
    super.key,
    this.top,
    this.left,
    this.right,
    this.bottom,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: top,
      left: left,
      right: right,
      bottom: bottom,
      child: child,
    );
  }
}
