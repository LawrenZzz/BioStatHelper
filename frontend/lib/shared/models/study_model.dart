import 'dart:math' as math;

int studyInt(dynamic value, [int fallback = 0]) =>
    value is num ? value.toInt() : int.tryParse('$value') ?? fallback;

bool studyBool(dynamic value) => value == true || value == 1 || value == 'true';

Map<String, dynamic> studyMap(dynamic value) =>
    value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

List<Map<String, dynamic>> studyRows(dynamic value) {
  final rows = value is Map ? value['data'] : value;
  if (rows is! List) throw const FormatException('Expected a data array');
  return rows.map((row) {
    if (row is! Map) throw const FormatException('Expected an object');
    return Map<String, dynamic>.from(row);
  }).toList();
}

String studyTime(int seconds) {
  final value = math.max(0, seconds);
  final minutes = (value ~/ 60 % 60).toString().padLeft(2, '0');
  final remainder = (value % 60).toString().padLeft(2, '0');
  return value >= 3600
      ? '${value ~/ 3600}:$minutes:$remainder'
      : '$minutes:$remainder';
}

enum StudyStatus {
  planned,
  learning,
  completed;

  String get label => switch (this) {
        planned => '待学习',
        learning => '学习中',
        completed => '已完成',
      };

  static StudyStatus parse(dynamic value) => StudyStatus.values.firstWhere(
        (status) => status.name == value,
        orElse: () => StudyStatus.planned,
      );
}

class StudyList {
  const StudyList(
      {required this.id,
      required this.name,
      this.description = '',
      this.sortOrder = 0,
      this.archived = false});

  final int id;
  final String name;
  final String description;
  final int sortOrder;
  final bool archived;

  factory StudyList.fromJson(Map<String, dynamic> json) => StudyList(
        id: studyInt(json['id']),
        name: '${json['name'] ?? ''}',
        description: '${json['description'] ?? ''}',
        sortOrder: studyInt(json['sort_order']),
        archived: studyBool(json['archived']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'sort_order': sortOrder,
        'archived': archived
      };
}

class StudyItem {
  const StudyItem(
      {required this.id,
      required this.listId,
      required this.title,
      this.videoId,
      this.source = 'nas',
      this.sourceData = const {},
      this.thumbnailUrl = '',
      this.durationSeconds = 0,
      this.status = StudyStatus.planned,
      this.positionSeconds = 0,
      this.favorite = false,
      this.sortOrder = 0,
      this.updatedAt,
      this.lastWatchedAt});

  final int id;
  final int listId;
  final int? videoId;
  final String source;
  final Map<String, dynamic> sourceData;
  final String title;
  final String thumbnailUrl;
  final int durationSeconds;
  final StudyStatus status;
  final int positionSeconds;
  final bool favorite;
  final int sortOrder;
  final DateTime? updatedAt;
  final DateTime? lastWatchedAt;

  double get progress => durationSeconds <= 0
      ? 0
      : (positionSeconds / durationSeconds).clamp(0.0, 1.0);

  String get courseTitle =>
      source == 'bilibili' ? '${sourceData['video_title'] ?? ''}'.trim() : '';

  String get partTitle => source == 'bilibili' && courseTitle.isNotEmpty
      ? 'P${studyInt(sourceData['page'], 1)} ${sourceData['title'] ?? title}'
      : title;

  factory StudyItem.fromJson(Map<String, dynamic> json) => StudyItem(
        id: studyInt(json['id']),
        listId: studyInt(json['list_id']),
        videoId: json['video_id'] == null ? null : studyInt(json['video_id']),
        source: '${json['source'] ?? 'nas'}',
        sourceData: Map.unmodifiable(studyMap(json['source_data'])),
        title: '${json['title'] ?? ''}',
        thumbnailUrl: '${json['thumbnail_url'] ?? ''}',
        durationSeconds: math.max(0, studyInt(json['duration_seconds'])),
        status: StudyStatus.parse(json['status']),
        positionSeconds: math.max(0, studyInt(json['position_seconds'])),
        favorite: studyBool(json['favorite']),
        sortOrder: studyInt(json['sort_order']),
        updatedAt: DateTime.tryParse('${json['updated_at'] ?? ''}'),
        lastWatchedAt: DateTime.tryParse('${json['last_watched_at'] ?? ''}'),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'list_id': listId,
        'video_id': videoId,
        'source': source,
        'source_data': sourceData,
        'title': title,
        'thumbnail_url': thumbnailUrl,
        'duration_seconds': durationSeconds,
        'status': status.name,
        'position_seconds': positionSeconds,
        'favorite': favorite,
        'sort_order': sortOrder,
      };
}

class StudyListGroup {
  StudyListGroup(this.items);
  final List<StudyItem> items;

  StudyItem get first => items.first;
  bool get isCourse =>
      first.source == 'bilibili' &&
      first.courseTitle.isNotEmpty &&
      (items.length > 1 ||
          studyInt(first.sourceData['part_count']) > 1 ||
          (first.sourceData['parts'] is List &&
              (first.sourceData['parts'] as List).length > 1));
  String get key => first.source == 'bilibili' && first.courseTitle.isNotEmpty
      ? 'course:${first.listId}:${first.sourceData['bvid']}'
      : 'item:${first.id}';
  String get title => isCourse ? first.courseTitle : first.title;
  int get completed =>
      items.where((item) => item.status == StudyStatus.completed).length;
  double get progress {
    final total =
        items.fold<int>(0, (value, item) => value + item.durationSeconds);
    if (total == 0) return completed / items.length;
    return items.fold<int>(
            0,
            (value, item) =>
                value +
                (item.status == StudyStatus.completed
                    ? item.durationSeconds
                    : item.positionSeconds.clamp(0, item.durationSeconds))) /
        total;
  }

  StudyItem get continueItem {
    final learning = items
        .where((item) => item.status == StudyStatus.learning)
        .toList()
      ..sort((a, b) => (b.lastWatchedAt ?? DateTime(1970))
          .compareTo(a.lastWatchedAt ?? DateTime(1970)));
    if (learning.isNotEmpty) return learning.first;
    return items.firstWhere((item) => item.status != StudyStatus.completed,
        orElse: () => first);
  }

  static List<StudyListGroup> collect(Iterable<StudyItem> items) {
    final groups = <String, StudyListGroup>{};
    for (final item in items) {
      final key = item.source == 'bilibili' &&
              item.courseTitle.isNotEmpty &&
              '${item.sourceData['bvid'] ?? ''}'.isNotEmpty
          ? 'course:${item.listId}:${item.sourceData['bvid']}'
          : 'item:${item.id}';
      (groups[key] ??= StudyListGroup([])).items.add(item);
    }
    for (final group in groups.values.where((group) => group.isCourse)) {
      group.items.sort((a, b) => studyInt(a.sourceData['page'], 1)
          .compareTo(studyInt(b.sourceData['page'], 1)));
    }
    return groups.values.toList();
  }
}

class StudyNote {
  const StudyNote(
      {required this.id,
      required this.itemId,
      required this.positionSeconds,
      required this.content,
      this.imageData});
  final int id;
  final int itemId;
  final int positionSeconds;
  final String content;
  final String? imageData;

  factory StudyNote.fromJson(Map<String, dynamic> json) => StudyNote(
        id: studyInt(json['id']),
        itemId: studyInt(json['item_id']),
        positionSeconds: studyInt(json['position_seconds']),
        content: '${json['content'] ?? ''}',
        imageData: (json['image_data'] ?? json['image_base64'])?.toString(),
      );
}

class StudyStats {
  const StudyStats(
      {this.todaySeconds = 0,
      this.totalSeconds = 0,
      this.sessions = 0,
      this.completedItems = 0,
      this.streakDays = 0,
      this.daily = const []});
  final int todaySeconds;
  final int totalSeconds;
  final int sessions;
  final int completedItems;
  final int streakDays;
  final List<({String date, int seconds})> daily;

  factory StudyStats.fromJson(Map<String, dynamic> json) => StudyStats(
        todaySeconds: studyInt(json['today_seconds']),
        totalSeconds: studyInt(json['total_seconds']),
        sessions: studyInt(json['sessions']),
        completedItems: studyInt(json['completed_items']),
        streakDays: studyInt(json['streak_days']),
        daily: (json['daily'] as List? ?? []).map((value) {
          final row = studyMap(value);
          return (
            date: '${row['date'] ?? ''}',
            seconds: studyInt(row['seconds'])
          );
        }).toList(),
      );
}

class StudySubscription {
  const StudySubscription(
      {required this.id,
      required this.name,
      this.source = 'nas',
      this.kind = 'category',
      this.nasCategoryId,
      this.sourceData = const {},
      this.enabled = true});
  final int id;
  final String name;
  final String source;
  final String kind;
  final int? nasCategoryId;
  final Map<String, dynamic> sourceData;
  final bool enabled;

  factory StudySubscription.fromJson(Map<String, dynamic> json) =>
      StudySubscription(
        id: studyInt(json['id']),
        name: '${json['name'] ?? json['title'] ?? ''}',
        source: '${json['source'] ?? 'nas'}',
        kind: '${json['kind'] ?? 'category'}',
        nasCategoryId: (json['nas_category_id'] ?? json['category_id']) == null
            ? null
            : studyInt(json['nas_category_id'] ?? json['category_id']),
        sourceData: {
          ...studyMap(json['source_data']),
          for (final key in ['mid', 'owner_mid', 'season_id'])
            if (json[key] != null) key: json[key]
        },
        enabled: json['enabled'] != false,
      );
}

class StudyUpdate {
  const StudyUpdate(
      {required this.id,
      required this.title,
      this.itemId,
      this.videoId,
      this.source = 'nas',
      this.sourceData = const {},
      this.thumbnailUrl = '',
      this.durationSeconds = 0,
      this.subscriptionId,
      this.discoveredAt,
      this.read = false});
  final int id;
  final int? itemId;
  final int? videoId;
  final String title;
  final String source;
  final Map<String, dynamic> sourceData;
  final String thumbnailUrl;
  final int durationSeconds;
  final bool read;
  final int? subscriptionId;
  final DateTime? discoveredAt;

  factory StudyUpdate.fromJson(Map<String, dynamic> json) => StudyUpdate(
        id: studyInt(json['id']),
        title: '${json['title'] ?? ''}',
        itemId: json['item_id'] == null ? null : studyInt(json['item_id']),
        videoId: json['video_id'] == null ? null : studyInt(json['video_id']),
        source: '${json['source'] ?? 'nas'}',
        sourceData: studyMap(json['source_data']),
        thumbnailUrl: '${json['thumbnail_url'] ?? ''}',
        durationSeconds: studyInt(json['duration_seconds']),
        read: studyBool(json['read'] ?? json['is_read']),
        subscriptionId: json['subscription_id'] == null
            ? null
            : studyInt(json['subscription_id']),
        discoveredAt: DateTime.tryParse(
                '${json['created_at'] ?? json['published_at'] ?? ''}')
            ?.toLocal(),
      );

  StudyItem toItem(int listId) => StudyItem(
      id: 0,
      listId: listId,
      videoId: videoId,
      title: title,
      source: source,
      sourceData: sourceData,
      thumbnailUrl: thumbnailUrl,
      durationSeconds: durationSeconds);
}
