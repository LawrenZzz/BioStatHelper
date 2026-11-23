import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../../shared/models/study_model.dart';
import '../controllers/study_controller.dart';
import 'study_library_view.dart';
import 'study_lists_view.dart';
import 'study_offline_view.dart';
import 'study_search_view.dart';
import 'study_widgets.dart';
import 'study_settings_view.dart';

class StudyHomeView extends StatelessWidget {
  const StudyHomeView({super.key, required this.controller});
  final StudyController controller;

  void _open(BuildContext context, Widget page) =>
      Navigator.push(context, MaterialPageRoute<void>(builder: (_) => page));

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Scaffold(
        appBar: AppBar(title: const Text('学习库'), actions: [
          IconButton(
              tooltip: '学习与播放设置',
              icon: const Icon(Icons.tune),
              onPressed: () => _open(
                  context,
                  StudySettingsView(
                      controller: c.preferences, scheduler: c.scheduler))),
          IconButton(
              tooltip: '搜索',
              icon: const Icon(Icons.search),
              onPressed: () => _open(context, StudySearchView(controller: c))),
          Obx(() => IconButton(
              tooltip: '刷新',
              icon: const Icon(Icons.refresh),
              onPressed: c.busy.contains('lists') || c.busy.contains('items')
                  ? null
                  : c.refreshAll)),
        ]),
        body: Center(
            child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1120),
          child: RefreshIndicator(
              onRefresh: c.refreshAll,
              child: ListenableBuilder(
                  listenable: c.preferences,
                  builder: (context, _) => Obx(() {
                        final current = c.continueItem;
                        final lists = c.activeLists;
                        final unread =
                            c.updates.where((update) => !update.read).length;
                        final initialLoading = (c.busy.contains('lists') ||
                                c.busy.contains('items')) &&
                            c.lists.isEmpty;
                        return ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: EdgeInsets.fromLTRB(16, 8, 16,
                              studyBottomPadding(context, inShell: true)),
                          children: [
                            OutlinedButton.icon(
                                icon: const Icon(Icons.search),
                                label: const Text('搜索 NAS / B站'),
                                style: OutlinedButton.styleFrom(
                                    minimumSize: const Size.fromHeight(48),
                                    alignment: Alignment.centerLeft),
                                onPressed: () => _open(
                                    context, StudySearchView(controller: c))),
                            StudyErrors(controller: c, sections: const [
                              'lists',
                              'items',
                              'updates',
                              'stats',
                              'subscriptions'
                            ]),
                            if (initialLoading) const LinearProgressIndicator(),
                            for (final section
                                in c.preferences.savedValue.visibleCards) ...[
                              if (section == 'continue') ...[
                                StudyHeading('继续学习',
                                    action: IconButton(
                                        tooltip: '全部学习列表',
                                        icon: const Icon(Icons.arrow_forward),
                                        onPressed: () => _open(context,
                                            StudyListsView(controller: c)))),
                                if (current != null)
                                  StudyItemRow(
                                      item: current,
                                      onPlay: c.busy.contains('play')
                                          ? null
                                          : () => c.openItem(current))
                                else if (!initialLoading)
                                  const StudyEmpty('暂无待学习内容'),
                              ],
                              if (section == 'lists' || section == 'focus')
                                LayoutBuilder(builder: (context, constraints) {
                                  final listSection = Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        StudyHeading('学习列表',
                                            action: IconButton(
                                                tooltip: '新建列表',
                                                icon: const Icon(
                                                    Icons.playlist_add),
                                                onPressed: c.writing
                                                    ? null
                                                    : () => showDialog<bool>(
                                                        context: context,
                                                        builder: (_) =>
                                                            StudyListEditor(
                                                                controller:
                                                                    c)))),
                                        for (final list in lists.take(4))
                                          ListTile(
                                              contentPadding: EdgeInsets.zero,
                                              leading: const Icon(
                                                  Icons.playlist_play),
                                              title: Text(list.name,
                                                  maxLines: 2,
                                                  overflow:
                                                      TextOverflow.ellipsis),
                                              subtitle: Text(
                                                  '${c.itemsFor(list.id).where((item) => item.status == StudyStatus.completed).length}'
                                                  ' / ${c.itemsFor(list.id).length} 已完成'),
                                              trailing: const Icon(
                                                  Icons.chevron_right),
                                              onTap: () => _open(
                                                  context,
                                                  StudyListDetailView(
                                                      controller: c,
                                                      listId: list.id))),
                                        if (lists.isEmpty && !initialLoading)
                                          const StudyEmpty('尚未创建学习列表'),
                                        TextButton.icon(
                                            icon: const Icon(
                                                Icons.view_list_outlined),
                                            label: const Text('管理学习列表'),
                                            onPressed: () => _open(context,
                                                StudyListsView(controller: c))),
                                      ]);
                                  final focusSection = Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        StudyHeading('专注计时',
                                            action: IconButton(
                                                tooltip: '学习统计',
                                                icon: const Icon(
                                                    Icons.insights_outlined),
                                                onPressed: () => _open(
                                                    context,
                                                    StudyStatsView(
                                                        controller: c)))),
                                        StudyFocusPanel(controller: c),
                                      ]);
                                  return section == 'lists'
                                      ? listSection
                                      : focusSection;
                                }),
                              if (section == 'updates') ...[
                                StudyHeading('订阅更新',
                                    action: IconButton(
                                        tooltip: '订阅管理',
                                        icon: const Icon(Icons.tune),
                                        onPressed: () => _open(
                                            context,
                                            StudySubscriptionsView(
                                                controller: c)))),
                                ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    leading:
                                        const Icon(Icons.notifications_none),
                                    title: Text(unread == 0
                                        ? '暂无未读更新'
                                        : '$unread 条未读更新'),
                                    subtitle:
                                        Text('${c.subscriptions.length} 个订阅来源'),
                                    trailing: const Icon(Icons.chevron_right),
                                    onTap: () => _open(context,
                                        StudySubscriptionsView(controller: c))),
                              ],
                              if (section == 'shortcuts') ...[
                                const Divider(),
                                Wrap(spacing: 8, runSpacing: 8, children: [
                                  TextButton.icon(
                                      icon: const Icon(Icons.edit_note),
                                      label: const Text('时间点笔记'),
                                      onPressed: () => _open(context,
                                          StudyNotesView(controller: c))),
                                  TextButton.icon(
                                      icon: const Icon(Icons.history),
                                      label: const Text('历史'),
                                      onPressed: () => _open(context,
                                          StudyHistoryView(controller: c))),
                                  TextButton.icon(
                                      icon: const Icon(Icons.insights_outlined),
                                      label: const Text('统计'),
                                      onPressed: () => _open(context,
                                          StudyStatsView(controller: c))),
                                  TextButton.icon(
                                      icon: const Icon(
                                          Icons.download_done_outlined),
                                      label: const Text('离线缓存'),
                                      onPressed: () => _open(context,
                                          StudyOfflineView(controller: c))),
                                  TextButton.icon(
                                      icon: const Icon(Icons.import_export),
                                      label: const Text('资料导入导出'),
                                      onPressed: () => _open(context,
                                          StudyTransferView(controller: c))),
                                ]),
                              ],
                            ],
                          ],
                        );
                      }))),
        )));
  }
}

class StudyFocusPanel extends StatelessWidget {
  const StudyFocusPanel({super.key, required this.controller});
  final StudyController controller;
  @override
  Widget build(BuildContext context) => Obx(() {
        final c = controller;
        final running = c.focusRunning.value;
        final started = c.focusStarted.value != null;
        final seconds = c.focusSeconds.value;
        final target = c.focusTargetMinutes.value;
        return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(studyTime(seconds),
                  style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 4),
              Text(
                  '目标 $target 分钟 · 今日 ${studyTime(c.stats.value.todaySeconds)}'),
              Slider(
                  value: target.toDouble(),
                  min: 5,
                  max: 120,
                  divisions: 23,
                  label: '$target 分钟',
                  onChanged: started
                      ? null
                      : (value) => c.focusTargetMinutes.value = value.round()),
              Wrap(spacing: 8, runSpacing: 8, children: [
                FilledButton.icon(
                    icon: Icon(running ? Icons.pause : Icons.play_arrow),
                    label: Text(running
                        ? '暂停'
                        : started
                            ? '继续专注'
                            : '开始专注'),
                    onPressed: c.writing
                        ? null
                        : running
                            ? c.pauseFocus
                            : c.startFocus),
                IconButton(
                    tooltip: '完成并保存',
                    icon: const Icon(Icons.task_alt),
                    onPressed: !started || seconds == 0 || c.writing
                        ? null
                        : () => c.finishFocus()),
                IconButton(
                    tooltip: '结束并保存',
                    icon: const Icon(Icons.stop_circle_outlined),
                    onPressed: !started || seconds == 0 || c.writing
                        ? null
                        : () => c.finishFocus(completed: false)),
              ]),
            ]);
      });
}
