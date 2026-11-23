class QuickReference {
  final int id;
  final String title;
  final String category;
  final String content;
  final ReferenceType type;
  final List<String> tags;
  final bool isPinned;

  QuickReference({
    required this.id,
    required this.title,
    required this.category,
    required this.content,
    required this.type,
    this.tags = const [],
    this.isPinned = false,
  });

  factory QuickReference.fromJson(Map<String, dynamic> json) {
    return QuickReference(
      id: json['id'] ?? 0,
      title: json['title'] ?? '',
      category: _readCategory(json['category']),
      content: json['content'] ?? '',
      type: ReferenceType.values.firstWhere(
        (t) => t.name == (json['reference_type'] ?? json['type']),
        orElse: () => ReferenceType.table,
      ),
      tags: _readTags(json['tags']),
      isPinned: json['is_pinned'] ?? false,
    );
  }

  static String _readCategory(dynamic value) {
    if (value is Map<String, dynamic>) {
      return value['name'] ?? '';
    }
    return value?.toString() ?? '';
  }

  static List<String> _readTags(dynamic value) {
    if (value is! List) {
      return [];
    }
    return value
        .map((tag) {
          if (tag is Map<String, dynamic>) {
            return tag['name']?.toString() ?? '';
          }
          return tag.toString();
        })
        .where((tag) => tag.isNotEmpty)
        .toList();
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'category': category,
      'content': content,
      'reference_type': type.name,
      'tags': tags,
      'is_pinned': isPinned,
    };
  }
}

enum ReferenceType {
  table,
  formula,
  checklist,
  guideline,
  cheatSheet,
}

extension ReferenceTypeExtension on ReferenceType {
  String get displayName {
    switch (this) {
      case ReferenceType.table:
        return '数据表';
      case ReferenceType.formula:
        return '公式';
      case ReferenceType.checklist:
        return '检查清单';
      case ReferenceType.guideline:
        return '指南';
      case ReferenceType.cheatSheet:
        return '速查表';
    }
  }

  String get icon {
    switch (this) {
      case ReferenceType.table:
        return '📊';
      case ReferenceType.formula:
        return '📐';
      case ReferenceType.checklist:
        return '✅';
      case ReferenceType.guideline:
        return '📋';
      case ReferenceType.cheatSheet:
        return '📝';
    }
  }
}
