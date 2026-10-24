import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/ui/mesh_widgets.dart';
import '../models/note_item.dart';
import '../services/notes_service.dart';
import 'note_editor_screen.dart';

enum NoteFilter {
  all,
  reminders,
  pinned,
  media,
  checklists,
  archive,
}

class NotesScreen extends StatefulWidget {
  const NotesScreen({super.key});

  @override
  State<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends State<NotesScreen> {
  final NotesService _notesService = NotesService();
  final TextEditingController _searchController = TextEditingController();

  bool _isGridView = true;
  NoteFilter _currentFilter = NoteFilter.all;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _notesService.initialize();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.trim().toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _openEditor({
    NoteItem? note,
    bool startWithChecklist = false,
    bool startWithPhoto = false,
    bool startWithVideo = false,
    bool startWithReminder = false,
  }) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => NoteEditorScreen(
          initialNote: note,
          startWithChecklist: startWithChecklist,
          startWithPhoto: startWithPhoto,
          startWithVideo: startWithVideo,
          startWithReminder: startWithReminder,
        ),
      ),
    );
  }

  List<NoteItem> _applyFilter(List<NoteItem> allNotes) {
    return allNotes.where((note) {
      // Archive filtering
      if (_currentFilter == NoteFilter.archive) {
        if (!note.isArchived) return false;
      } else {
        if (note.isArchived) return false;
      }

      // Tab filters
      switch (_currentFilter) {
        case NoteFilter.reminders:
          if (!note.hasReminder) return false;
          break;
        case NoteFilter.pinned:
          if (!note.isPinned) return false;
          break;
        case NoteFilter.media:
          if (!note.hasMedia) return false;
          break;
        case NoteFilter.checklists:
          if (note.checklist.isEmpty) return false;
          break;
        case NoteFilter.all:
        case NoteFilter.archive:
          break;
      }

      // Search query filtering
      if (_searchQuery.isNotEmpty) {
        final titleMatch = note.title.toLowerCase().contains(_searchQuery);
        final contentMatch = note.content.toLowerCase().contains(_searchQuery);
        final checklistMatch = note.checklist
            .any((c) => c.text.toLowerCase().contains(_searchQuery));
        if (!titleMatch &&
            !contentMatch &&
            !checklistMatch &&
            !note.labels
                .any((label) => label.toLowerCase().contains(_searchQuery))) {
          return false;
        }
      }

      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 4),
              child: Align(
                  alignment: Alignment.centerLeft,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Notes',
                          style: Theme.of(context).textTheme.headlineLarge),
                      const SizedBox(height: 6),
                      Text('Your ideas. A little more organized.',
                          style: Theme.of(context).textTheme.bodySmall),
                    ],
                  )),
            ),
            _buildSearchBar(isDark),

            // Horizontal Filter Chips
            _buildFilterChips(isDark),

            // Notes Stream & Grid/List view
            Expanded(
              child: StreamBuilder<List<NoteItem>>(
                stream: _notesService.notesStream,
                initialData: _notesService.currentNotes,
                builder: (context, snapshot) {
                  final allNotes = snapshot.data ?? [];
                  final filteredNotes = _applyFilter(allNotes);

                  if (filteredNotes.isEmpty) {
                    return _buildEmptyState(isDark);
                  }

                  final showSections = _currentFilter == NoteFilter.all &&
                      _searchQuery.isEmpty &&
                      filteredNotes.any((n) => n.isPinned) &&
                      filteredNotes.any((n) => !n.isPinned);

                  if (showSections) {
                    final pinnedNotes =
                        filteredNotes.where((n) => n.isPinned).toList();
                    final otherNotes =
                        filteredNotes.where((n) => !n.isPinned).toList();

                    return ListView(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                      children: [
                        _buildSectionHeader('PINNED'),
                        _buildNotesLayout(pinnedNotes, isDark),
                        const SizedBox(height: 16),
                        _buildSectionHeader('OTHERS'),
                        _buildNotesLayout(otherNotes, isDark),
                      ],
                    );
                  }

                  return ListView(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                    children: [
                      _buildNotesLayout(filteredNotes, isDark),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _buildNotesDock(isDark),
    );
  }

  Widget _buildSearchBar(bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      child: GlassSurface(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(children: [
          Expanded(
              child: TextField(
            controller: _searchController,
            decoration: const InputDecoration(
              hintText: 'Search notes',
              prefixIcon: Icon(Icons.search_rounded),
              filled: false,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
            ),
          )),
          if (_searchQuery.isNotEmpty)
            IconButton(
              tooltip: 'Clear search',
              icon: const Icon(Icons.close_rounded),
              onPressed: _searchController.clear,
            ),
          IconButton(
            tooltip: _isGridView ? 'List view' : 'Grid view',
            icon: Icon(_isGridView
                ? Icons.view_agenda_outlined
                : Icons.grid_view_rounded),
            onPressed: () {
              HapticFeedback.selectionClick();
              setState(() => _isGridView = !_isGridView);
            },
          ),
        ]),
      ),
    );
  }

  Widget _buildFilterChips(bool isDark) {
    final filters = [
      {'filter': NoteFilter.all, 'label': 'All', 'icon': Icons.notes_rounded},
      {
        'filter': NoteFilter.reminders,
        'label': 'Reminders',
        'icon': Icons.alarm_rounded
      },
      {
        'filter': NoteFilter.pinned,
        'label': 'Pinned',
        'icon': Icons.push_pin_rounded
      },
      {
        'filter': NoteFilter.media,
        'label': 'Media',
        'icon': Icons.photo_library_rounded
      },
      {
        'filter': NoteFilter.checklists,
        'label': 'Lists',
        'icon': Icons.check_box_rounded
      },
      {
        'filter': NoteFilter.archive,
        'label': 'Archive',
        'icon': Icons.archive_rounded
      },
    ];

    return SizedBox(
      height: 56 * MediaQuery.textScalerOf(context).scale(1).clamp(1, 2),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: filters.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, idx) {
          final item = filters[idx];
          final filter = item['filter'] as NoteFilter;
          final isSelected = _currentFilter == filter;

          return FilterChip(
            selected: isSelected,
            label: Text(
              item['label'] as String,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected
                    ? (isDark ? Colors.black87 : Colors.white)
                    : (isDark ? Colors.white70 : Colors.black87),
              ),
            ),
            avatar: Icon(
              item['icon'] as IconData,
              size: 15,
              color: isSelected
                  ? (isDark ? Colors.black87 : Colors.white)
                  : (isDark ? Colors.white70 : Colors.black87),
            ),
            selectedColor: Theme.of(context).colorScheme.primary,
            backgroundColor: Theme.of(context).colorScheme.surface,
            showCheckmark: false,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: BorderSide(
                color: isSelected
                    ? Theme.of(context).colorScheme.primary
                    : Colors.transparent,
              ),
            ),
            onSelected: (_) {
              HapticFeedback.selectionClick();
              setState(() => _currentFilter = filter);
            },
          );
        },
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 6, top: 12, bottom: 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.2,
          color: Colors.grey[600],
        ),
      ),
    );
  }

  Widget _buildNotesLayout(List<NoteItem> notes, bool isDark) {
    if (!_isGridView ||
        MediaQuery.sizeOf(context).width < 380 ||
        MediaQuery.textScalerOf(context).scale(1) > 1.3) {
      return Column(
        children: notes
            .map((note) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: NoteCard(
                    note: note,
                    isDark: isDark,
                    onTap: () => _openEditor(note: note),
                    onTogglePin: () => _notesService.togglePin(note.id),
                  ),
                ))
            .toList(),
      );
    }

    // 2-column staggered layout
    final leftColumn = <NoteItem>[];
    final rightColumn = <NoteItem>[];

    for (int i = 0; i < notes.length; i++) {
      if (i % 2 == 0) {
        leftColumn.add(notes[i]);
      } else {
        rightColumn.add(notes[i]);
      }
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            children: leftColumn
                .map((note) => Padding(
                      padding: const EdgeInsets.only(bottom: 10, right: 5),
                      child: NoteCard(
                        note: note,
                        isDark: isDark,
                        onTap: () => _openEditor(note: note),
                        onTogglePin: () => _notesService.togglePin(note.id),
                      ),
                    ))
                .toList(),
          ),
        ),
        Expanded(
          child: Column(
            children: rightColumn
                .map((note) => Padding(
                      padding: const EdgeInsets.only(bottom: 10, left: 5),
                      child: NoteCard(
                        note: note,
                        isDark: isDark,
                        onTap: () => _openEditor(note: note),
                        onTogglePin: () => _notesService.togglePin(note.id),
                      ),
                    ))
                .toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState(bool isDark) {
    IconData icon = Icons.lightbulb_outline_rounded;
    String message = 'Notes you add appear here';

    if (_searchQuery.isNotEmpty) {
      icon = Icons.search_off_rounded;
      message = 'No notes found matching "$_searchQuery"';
    } else {
      switch (_currentFilter) {
        case NoteFilter.reminders:
          icon = Icons.alarm_outlined;
          message = 'Notes with reminders appear here';
          break;
        case NoteFilter.pinned:
          icon = Icons.push_pin_outlined;
          message = 'Pinned notes appear here';
          break;
        case NoteFilter.media:
          icon = Icons.photo_library_outlined;
          message = 'Notes with photos or videos appear here';
          break;
        case NoteFilter.checklists:
          icon = Icons.check_box_outlined;
          message = 'Checklists appear here';
          break;
        case NoteFilter.archive:
          icon = Icons.archive_outlined;
          message = 'Archived notes appear here';
          break;
        default:
          break;
      }
    }

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 72, color: Colors.grey.withValues(alpha: 0.5)),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: Colors.grey[600],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotesDock(bool isDark) {
    return Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: GlassSurface(
          blur: true,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.check_box_outlined),
                tooltip: 'New list',
                onPressed: () => _openEditor(startWithChecklist: true),
              ),
              IconButton(
                icon: const Icon(Icons.photo_outlined),
                tooltip: 'New photo note',
                onPressed: () => _openEditor(startWithPhoto: true),
              ),
              IconButton(
                icon: const Icon(Icons.videocam_outlined),
                tooltip: 'New video note',
                onPressed: () => _openEditor(startWithVideo: true),
              ),
              IconButton(
                icon: const Icon(Icons.alarm_add_outlined),
                tooltip: 'New reminder note',
                onPressed: () => _openEditor(startWithReminder: true),
              ),
              const Spacer(),
              FloatingActionButton.small(
                heroTag: 'notes_create_fab',
                elevation: 2,
                backgroundColor: MeshColors.orange,
                foregroundColor: MeshColors.midnight,
                onPressed: () => _openEditor(),
                child: const Icon(Icons.add, size: 26),
              ),
            ],
          ),
        ));
  }
}

class NoteCard extends StatelessWidget {
  final NoteItem note;
  final bool isDark;
  final VoidCallback onTap;
  final VoidCallback onTogglePin;

  const NoteCard({
    super.key,
    required this.note,
    required this.isDark,
    required this.onTap,
    required this.onTogglePin,
  });

  String _formatReminder(DateTime dt) {
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

  @override
  Widget build(BuildContext context) {
    final bgColor = note.colorIndex == 0
        ? Theme.of(context).colorScheme.surface
        : NoteItem.getBackgroundColor(note.colorIndex, isDark);
    final borderColor = note.colorIndex == 0
        ? Theme.of(context).colorScheme.outlineVariant
        : NoteItem.getBorderColor(note.colorIndex, isDark);
    final textColor = Theme.of(context).colorScheme.onSurface;

    return Material(
      color: bgColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(26),
        side: BorderSide(color: borderColor, width: 1.0),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Media preview (Image)
            if (note.imagePaths.isNotEmpty)
              Image.file(
                File(note.imagePaths.first),
                width: double.infinity,
                height: 120,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),

            // Video preview banner if video exists and no image
            if (note.videoPaths.isNotEmpty && note.imagePaths.isEmpty)
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
                color: Colors.black12,
                child: const Row(
                  children: [
                    Icon(Icons.video_collection_rounded,
                        color: MeshColors.blue, size: 22),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Video attachment',
                        style: TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),

            Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title + Pin Button row
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (note.title.isNotEmpty)
                        Expanded(
                          child: Text(
                            note.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: textColor,
                            ),
                          ),
                        )
                      else
                        const Spacer(),
                      IconButton(
                        tooltip: note.isPinned ? 'Unpin note' : 'Pin note',
                        onPressed: () {
                          HapticFeedback.selectionClick();
                          onTogglePin();
                        },
                        icon: Icon(
                            note.isPinned
                                ? Icons.push_pin_rounded
                                : Icons.push_pin_outlined,
                            size: 18,
                            color: Theme.of(context).colorScheme.primary),
                      ),
                    ],
                  ),

                  // Note text content
                  if (note.content.isNotEmpty) ...[
                    if (note.title.isNotEmpty) const SizedBox(height: 6),
                    Text(
                      note.content,
                      maxLines: 6,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13.5,
                        color: textColor.withValues(alpha: 0.85),
                        height: 1.35,
                      ),
                    ),
                  ],

                  // Checklist preview
                  if (note.checklist.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Column(
                      children: note.checklist.take(4).map((item) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Row(
                            children: [
                              Icon(
                                item.isDone
                                    ? Icons.check_box_rounded
                                    : Icons.check_box_outline_blank_rounded,
                                size: 14,
                                color: item.isDone
                                    ? Colors.grey
                                    : Theme.of(context).colorScheme.primary,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  item.text,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    color:
                                        item.isDone ? Colors.grey : textColor,
                                    decoration: item.isDone
                                        ? TextDecoration.lineThrough
                                        : null,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                    if (note.checklist.length > 4)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          '+${note.checklist.length - 4} more items',
                          style:
                              TextStyle(fontSize: 11, color: Colors.grey[600]),
                        ),
                      ),
                  ],

                  // Bottom chips (Reminders / Media count)
                  if (note.hasReminder ||
                      (note.imagePaths.length + note.videoPaths.length >
                          1)) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        if (note.hasReminder)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? Colors.white10
                                  : Colors.black.withValues(alpha: 0.06),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.alarm_rounded,
                                  size: 12,
                                  color: Colors.amber[800],
                                ),
                                const SizedBox(width: 4),
                                Flexible(
                                    child: Text(
                                  _formatReminder(note.reminderDateTime!),
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w600,
                                    color: textColor,
                                  ),
                                )),
                              ],
                            ),
                          ),
                        if (note.imagePaths.length + note.videoPaths.length > 1)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 3),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? Colors.white10
                                  : Colors.black.withValues(alpha: 0.06),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.attach_file_rounded,
                                    size: 12, color: Colors.grey),
                                const SizedBox(width: 2),
                                Text(
                                  '${note.imagePaths.length + note.videoPaths.length}',
                                  style: const TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
