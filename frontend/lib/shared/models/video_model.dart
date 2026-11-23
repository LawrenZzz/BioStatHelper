class VideoSidecar {
  final int id;
  final String fileName;
  final String extension;
  final String kind;
  final String title;
  final String url;

  const VideoSidecar({
    required this.id,
    required this.fileName,
    required this.extension,
    required this.kind,
    required this.title,
    required this.url,
  });

  factory VideoSidecar.fromJson(Map<String, dynamic> json) {
    return VideoSidecar(
      id: json['id'] ?? 0,
      fileName: json['file_name']?.toString() ?? '',
      extension: json['extension']?.toString() ?? '',
      kind: json['kind']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      url: json['url']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'file_name': fileName,
      'extension': extension,
      'kind': kind,
      'title': title,
      'url': url,
    };
  }
}

class Video {
  final int id;
  final String title;
  final String description;
  final String category;
  final String thumbnailUrl;
  final String videoUrl;
  final Duration duration;
  final DateTime createdAt;
  final List<String> tags;
  final bool isFavorite;
  final int? nasCategoryId;
  final String nasCategoryPath;
  final int? episodeNumber;
  final int sortOrder;
  final double progressPercent;
  final bool completed;
  final List<VideoSidecar> sidecars;
  final int? studyItemId;
  final String source;
  final Map<String, dynamic> sourceData;

  Video({
    required this.id,
    required this.title,
    required this.description,
    required this.category,
    required this.thumbnailUrl,
    required this.videoUrl,
    required this.duration,
    required this.createdAt,
    this.tags = const [],
    this.isFavorite = false,
    this.nasCategoryId,
    this.nasCategoryPath = '',
    this.episodeNumber,
    this.sortOrder = 0,
    this.progressPercent = 0,
    this.completed = false,
    this.sidecars = const [],
    this.studyItemId,
    this.source = 'nas',
    this.sourceData = const {},
  });

  factory Video.fromJson(Map<String, dynamic> json) {
    return Video(
      id: json['id'] ?? 0,
      title: json['title'] ?? '',
      description: json['description'] ?? '',
      category: _readCategory(json['category']),
      thumbnailUrl: json['thumbnail_url'] ?? '',
      videoUrl: json['video_url'] ?? '',
      duration: Duration(seconds: json['duration_seconds'] ?? 0),
      createdAt: DateTime.tryParse(json['created_at'] ?? '') ?? DateTime.now(),
      tags: _readTags(json['tags']),
      isFavorite: json['is_favorite'] ?? false,
      nasCategoryId: json['nas_category_id'],
      nasCategoryPath: json['nas_category_path']?.toString() ?? '',
      episodeNumber: json['episode_number'],
      sortOrder: json['sort_order'] ?? 0,
      progressPercent: (json['progress_percent'] ?? 0).toDouble(),
      completed: json['completed'] ?? false,
      sidecars: _readSidecars(json['sidecars']),
      studyItemId: json['study_item_id'],
      source: json['source']?.toString() ?? 'nas',
      sourceData: json['source_data'] is Map
          ? Map<String, dynamic>.from(json['source_data'])
          : const {},
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

  static List<VideoSidecar> _readSidecars(dynamic value) {
    if (value is! List) {
      return [];
    }
    return value
        .whereType<Map<String, dynamic>>()
        .map(VideoSidecar.fromJson)
        .where((item) => item.url.isNotEmpty)
        .toList();
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'category': category,
      'thumbnail_url': thumbnailUrl,
      'video_url': videoUrl,
      'duration_seconds': duration.inSeconds,
      'created_at': createdAt.toIso8601String(),
      'tags': tags,
      'is_favorite': isFavorite,
      'nas_category_id': nasCategoryId,
      'nas_category_path': nasCategoryPath,
      'episode_number': episodeNumber,
      'sort_order': sortOrder,
      'progress_percent': progressPercent,
      'completed': completed,
      'sidecars': sidecars.map((item) => item.toJson()).toList(),
      'study_item_id': studyItemId,
      'source': source,
      'source_data': sourceData,
    };
  }

  Video copyWith({
    int? id,
    String? title,
    String? description,
    String? category,
    String? thumbnailUrl,
    String? videoUrl,
    Duration? duration,
    DateTime? createdAt,
    List<String>? tags,
    bool? isFavorite,
    int? nasCategoryId,
    String? nasCategoryPath,
    int? episodeNumber,
    int? sortOrder,
    double? progressPercent,
    bool? completed,
    List<VideoSidecar>? sidecars,
    int? studyItemId,
    String? source,
    Map<String, dynamic>? sourceData,
  }) {
    return Video(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      category: category ?? this.category,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      videoUrl: videoUrl ?? this.videoUrl,
      duration: duration ?? this.duration,
      createdAt: createdAt ?? this.createdAt,
      tags: tags ?? this.tags,
      isFavorite: isFavorite ?? this.isFavorite,
      nasCategoryId: nasCategoryId ?? this.nasCategoryId,
      nasCategoryPath: nasCategoryPath ?? this.nasCategoryPath,
      episodeNumber: episodeNumber ?? this.episodeNumber,
      sortOrder: sortOrder ?? this.sortOrder,
      progressPercent: progressPercent ?? this.progressPercent,
      completed: completed ?? this.completed,
      sidecars: sidecars ?? this.sidecars,
      studyItemId: studyItemId ?? this.studyItemId,
      source: source ?? this.source,
      sourceData: sourceData ?? this.sourceData,
    );
  }

  bool get isWatched => completed || progressPercent >= 95;

  bool get isWatching => !isWatched && progressPercent > 0;

  List<VideoSidecar> get subtitleSidecars =>
      sidecars.where((item) => item.kind == 'subtitle').toList();

  List<VideoSidecar> get danmakuSidecars =>
      sidecars.where((item) => item.kind == 'danmaku').toList();

  String get formattedDuration {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}
