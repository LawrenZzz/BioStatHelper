class VideoCategory {
  final int id;
  final String name;
  final String description;
  final String icon;
  final int? parentId;
  final String path;
  final int videoCount;
  final int childrenCount;

  VideoCategory({
    required this.id,
    required this.name,
    this.description = '',
    this.icon = '',
    this.parentId,
    String? path,
    this.videoCount = 0,
    this.childrenCount = 0,
  }) : path = path ?? name;

  factory VideoCategory.fromJson(Map<String, dynamic> json) {
    final name = json['name']?.toString() ?? '';
    return VideoCategory(
      id: json['id'] ?? 0,
      name: name,
      description: json['description']?.toString() ?? '',
      icon: json['icon']?.toString() ?? '',
      parentId: json['parent_id'],
      path: json['path']?.toString() ?? name,
      videoCount: json['video_count'] ?? 0,
      childrenCount: json['children_count'] ?? 0,
    );
  }

  int get depth {
    if (path.isEmpty) return 0;
    return path.split('/').length - 1;
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'icon': icon,
      'parent_id': parentId,
      'path': path,
      'video_count': videoCount,
      'children_count': childrenCount,
    };
  }
}

class ConceptCategory {
  final int id;
  final String name;
  final String description;
  final String icon;
  final int conceptCount;

  ConceptCategory({
    required this.id,
    required this.name,
    required this.description,
    required this.icon,
    this.conceptCount = 0,
  });

  factory ConceptCategory.fromJson(Map<String, dynamic> json) {
    return ConceptCategory(
      id: json['id'] ?? 0,
      name: json['name'] ?? '',
      description: json['description'] ?? '',
      icon: json['icon'] ?? '',
      conceptCount: json['concept_count'] ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'icon': icon,
      'concept_count': conceptCount,
    };
  }
}
