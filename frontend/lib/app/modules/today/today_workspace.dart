import 'package:flutter/material.dart';

/// 今日工作台的工作区枚举，对应左栏导航项。
enum TodayWorkspace {
  focus('今日 · 专注', Icons.star),
  list('列表', Icons.view_list),
  calendar('日历', Icons.calendar_month),
  kanban('看板', Icons.dashboard),
  inbox('收件箱', Icons.inbox),
  next('下一步', Icons.arrow_forward),
  waiting('等待', Icons.hourglass_empty),
  someday('稍后', Icons.outbox),
  context('上下文', Icons.account_tree),
  review('每周回顾', Icons.reviews),
  ;

  const TodayWorkspace(this.label, this.icon);
  final String label;
  final IconData icon;
}
