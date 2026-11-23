import 'package:bio_stat_helper/shared/models/project_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('简短项目摘要隐藏机器标记但保留CDISC待确认状态', () {
    final project = BiostatProject.fromJson({
      'description': 'SAP/TFL本轮审阅中。\n[snapshot:cdisc-unconfirmed]',
      'is_cdisc': false,
    });
    expect(project.displayDescription, 'SAP/TFL本轮审阅中。');
    expect(project.isCdiscUnconfirmed, isTrue);
    expect(project.cdiscLabel, 'CDISC 待确认');
  });

  test('项目状态统计及快照原文可独立读取', () {
    final project = BiostatProject.fromJson({
      'id': 1,
      'todo_count': 10,
      'done_todo_count': 3,
      'in_progress_todo_count': 2,
      'description': '快照\r\n当前阶段（原文）：SAP已签署；SAR反馈修订中。\r\n来源：总览',
    });
    expect(project.notStartedTodoCount, 5);
    expect(project.snapshotCurrentState, 'SAP已签署；SAR反馈修订中。');
    expect(BiostatProject.fromJson({}).snapshotCurrentState, isEmpty);
    expect(
        BiostatProject.fromJson({
          'todo_count': 1,
          'done_todo_count': 2,
        }).notStartedTodoCount,
        0);
  });

  group('ProjectTodo.fromJson GTD 字段', () {
    test('解析 GTD 轻量 DTO（todo_id 主键 + 完整字段）', () {
      final json = {
        'todo_id': 42,
        'title': '写 SAP 统计方法章节',
        'description': '沿用上一版模板',
        'project_id': 7,
        'project_name': '某 III 期试验',
        'status': 'waiting',
        'priority': 'high',
        'phase': 'SAP与TFL',
        'start_at': '2026-09-20T09:00:00',
        'due_at': '2026-09-25T18:00:00',
        'is_focused_today': true,
        'contexts': '["@DM","@work"]',
        'tags': '["SAP"]',
        'area': '工作',
        'energy_level': 'medium',
        'time_estimate': 90,
        'completed_at': null,
      };

      final todo = ProjectTodo.fromJson(json);

      expect(todo.id, 42);
      expect(todo.projectId, 7);
      expect(todo.projectName, '某 III 期试验');
      expect(todo.status, 'waiting');
      expect(todo.isWaiting, isTrue);
      expect(todo.priority, 'high');
      expect(todo.phase, 'SAP与TFL');
      expect(todo.isFocusedToday, isTrue);
      expect(todo.contexts, ['@DM', '@work']);
      expect(todo.tags, ['SAP']);
      expect(todo.area, '工作');
      expect(todo.energyLevel, 'medium');
      expect(todo.timeEstimate, 90);
      expect(todo.dueAt, isNotNull);
      expect(todo.isActive, isTrue);
    });

    test('contexts 已为 List 时直接解析', () {
      final json = {
        'todo_id': 1,
        'title': 't',
        'contexts': ['@home'],
      };
      final todo = ProjectTodo.fromJson(json);
      expect(todo.contexts, ['@home']);
    });

    test('默认状态为 next（非 open）', () {
      final todo = ProjectTodo.fromJson({'todo_id': 1, 'title': 't'});
      expect(todo.status, 'next');
      expect(todo.isNext, isTrue);
    });

    test('收件箱/归档/稍后谓词', () {
      expect(ProjectTodo.fromJson({'todo_id': 1, 'status': 'inbox'}).isInbox,
          isTrue);
      expect(
          ProjectTodo.fromJson({'todo_id': 2, 'status': 'archived'}).isArchived,
          isTrue);
      expect(
          ProjectTodo.fromJson({'todo_id': 3, 'status': 'someday'}).isSomeday,
          isTrue);
      expect(ProjectTodo.fromJson({'todo_id': 4, 'status': 'done'}).isDone,
          isTrue);
    });

    test('解析循环与日历展开字段', () {
      final todo = ProjectTodo.fromJson({
        'todo_id': 9,
        'title': '每日报告',
        'recurrence': 'daily',
        'occurrence_due_at': '2026-09-22T09:00:00',
      });
      expect(todo.recurrence, 'daily');
      expect(todo.occurrenceDueAt, isNotNull);
      expect(todo.occurrenceDueAt!.year, 2026);
      expect(todo.occurrenceDueAt!.day, 22);
    });

    test('BiostatProject 解析 is_inbox / review_at', () {
      final json = {
        'id': 3,
        'name': '收件箱',
        'is_inbox': true,
        'review_at': '2026-09-19T10:00:00',
        'created_at': '2026-09-01T00:00:00',
        'updated_at': '2026-09-01T00:00:00',
      };
      final project = BiostatProject.fromJson(json);
      expect(project.isInbox, isTrue);
      expect(project.reviewAt, isNotNull);
    });
  });
}
