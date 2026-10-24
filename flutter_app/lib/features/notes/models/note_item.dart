import 'package:flutter/material.dart';

class ChecklistItem {
  final String id;
  String text;
  bool isDone;

  ChecklistItem({
    required this.id,
    required this.text,
    this.isDone = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'isDone': isDone,
      };

  factory ChecklistItem.fromJson(Map<String, dynamic> json) => ChecklistItem(
        id: json['id']?.toString() ?? '',
        text: json['text']?.toString() ?? '',
        isDone: json['isDone'] as bool? ?? false,
      );

  ChecklistItem copyWith({
    String? id,
    String? text,
    bool? isDone,
  }) {
    return ChecklistItem(
      id: id ?? this.id,
      text: text ?? this.text,
      isDone: isDone ?? this.isDone,
    );
  }
}

class NoteItem {
  final String id;
  String title;
  String content;
  List<ChecklistItem> checklist;
  List<String> imagePaths;
  List<String> videoPaths;
  DateTime? reminderDateTime;
  bool isReminderDone;
  bool isPinned;
  bool isArchived;
  int colorIndex;
  List<String> labels;
  DateTime createdAt;
  DateTime updatedAt;

  NoteItem({
    required this.id,
    this.title = '',
    this.content = '',
    List<ChecklistItem>? checklist,
    List<String>? imagePaths,
    List<String>? videoPaths,
    this.reminderDateTime,
    this.isReminderDone = false,
    this.isPinned = false,
    this.isArchived = false,
    this.colorIndex = 0,
    List<String>? labels,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : checklist = checklist ?? [],
        imagePaths = imagePaths ?? [],
        videoPaths = videoPaths ?? [],
        labels = labels ?? [],
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  bool get isEmpty =>
      title.trim().isEmpty &&
      content.trim().isEmpty &&
      checklist.isEmpty &&
      imagePaths.isEmpty &&
      videoPaths.isEmpty;

  bool get hasMedia => imagePaths.isNotEmpty || videoPaths.isNotEmpty;
  bool get hasReminder => reminderDateTime != null;
  bool get isReminderUpcoming =>
      reminderDateTime != null && reminderDateTime!.isAfter(DateTime.now());

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'content': content,
        'checklist': checklist.map((c) => c.toJson()).toList(),
        'imagePaths': imagePaths,
        'videoPaths': videoPaths,
        'reminderDateTime': reminderDateTime?.toIso8601String(),
        'isReminderDone': isReminderDone,
        'isPinned': isPinned,
        'isArchived': isArchived,
        'colorIndex': colorIndex,
        'labels': labels,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory NoteItem.fromJson(Map<String, dynamic> json) {
    return NoteItem(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      content: json['content']?.toString() ?? '',
      checklist: (json['checklist'] as List<dynamic>?)
              ?.map((item) =>
                  ChecklistItem.fromJson(item as Map<String, dynamic>))
              .toList() ??
          [],
      imagePaths: (json['imagePaths'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      videoPaths: (json['videoPaths'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      reminderDateTime: json['reminderDateTime'] != null
          ? DateTime.tryParse(json['reminderDateTime'].toString())
          : null,
      isReminderDone: json['isReminderDone'] as bool? ?? false,
      isPinned: json['isPinned'] as bool? ?? false,
      isArchived: json['isArchived'] as bool? ?? false,
      colorIndex: json['colorIndex'] as int? ?? 0,
      labels: (json['labels'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'].toString()) ?? DateTime.now()
          : DateTime.now(),
      updatedAt: json['updatedAt'] != null
          ? DateTime.tryParse(json['updatedAt'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  NoteItem copyWith({
    String? id,
    String? title,
    String? content,
    List<ChecklistItem>? checklist,
    List<String>? imagePaths,
    List<String>? videoPaths,
    DateTime? reminderDateTime,
    bool? isReminderDone,
    bool? isPinned,
    bool? isArchived,
    int? colorIndex,
    List<String>? labels,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return NoteItem(
      id: id ?? this.id,
      title: title ?? this.title,
      content: content ?? this.content,
      checklist: checklist ?? List.from(this.checklist),
      imagePaths: imagePaths ?? List.from(this.imagePaths),
      videoPaths: videoPaths ?? List.from(this.videoPaths),
      reminderDateTime: reminderDateTime ?? this.reminderDateTime,
      isReminderDone: isReminderDone ?? this.isReminderDone,
      isPinned: isPinned ?? this.isPinned,
      isArchived: isArchived ?? this.isArchived,
      colorIndex: colorIndex ?? this.colorIndex,
      labels: labels ?? List.from(this.labels),
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  // Google Keep Color Palette definition
  static const List<String> colorNames = [
    'Default',
    'Coral',
    'Peach',
    'Sand',
    'Mint',
    'Sage',
    'Fog',
    'Storm',
    'Dusk',
    'Blossom',
    'Clay',
    'Chalk',
  ];

  static Color getBackgroundColor(int index, bool isDark) {
    if (index <= 0 || index >= colorNames.length) {
      return isDark ? const Color(0xFF1E2124) : Colors.white;
    }
    if (isDark) {
      switch (index) {
        case 1:
          return const Color(0xFF77172E); // Coral
        case 2:
          return const Color(0xFF692B17); // Peach
        case 3:
          return const Color(0xFF7C4A03); // Sand
        case 4:
          return const Color(0xFF264D3B); // Mint
        case 5:
          return const Color(0xFF0C625D); // Sage
        case 6:
          return const Color(0xFF256377); // Fog
        case 7:
          return const Color(0xFF284255); // Storm
        case 8:
          return const Color(0xFF472E5B); // Dusk
        case 9:
          return const Color(0xFF6C394F); // Blossom
        case 10:
          return const Color(0xFF4B443A); // Clay
        case 11:
          return const Color(0xFF2C2F33); // Chalk
        default:
          return const Color(0xFF1E2124);
      }
    } else {
      switch (index) {
        case 1:
          return const Color(0xFFFAAFA8); // Coral
        case 2:
          return const Color(0xFFF39F76); // Peach
        case 3:
          return const Color(0xFFFFF8B8); // Sand
        case 4:
          return const Color(0xFFE2F6D3); // Mint
        case 5:
          return const Color(0xFFB4DDD3); // Sage
        case 6:
          return const Color(0xFFD4E4ED); // Fog
        case 7:
          return const Color(0xFFAECBFA); // Storm
        case 8:
          return const Color(0xFFD7AEFB); // Dusk
        case 9:
          return const Color(0xFFFDCFE8); // Blossom
        case 10:
          return const Color(0xFFE6C9A8); // Clay
        case 11:
          return const Color(0xFFE8EAED); // Chalk
        default:
          return Colors.white;
      }
    }
  }

  static Color getBorderColor(int index, bool isDark) {
    if (index == 0) {
      return isDark ? const Color(0xFF3C4043) : const Color(0xFFE0E0E0);
    }
    return getBackgroundColor(index, isDark).withValues(alpha: 0.85);
  }
}
