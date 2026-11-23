import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../../core/services/api_client.dart';
import '../../../../shared/models/study_model.dart';
import '../controllers/study_controller.dart';

double studyBottomPadding(BuildContext context, {bool inShell = false}) =>
    MediaQuery.paddingOf(context).bottom +
    (inShell && MediaQuery.sizeOf(context).width < 900 ? 116 : 24);

class StudyErrors extends StatelessWidget {
  const StudyErrors(
      {super.key, required this.controller, this.sections = const []});
  final StudyController controller;
  final List<String> sections;

  @override
  Widget build(BuildContext context) => Obx(() {
        final errors = controller.errors.entries
            .where((entry) =>
                sections.contains(entry.key) ||
                {'write', 'play'}.contains(entry.key))
            .toList();
        if (errors.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Material(
            color: Theme.of(context).colorScheme.errorContainer,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final entry in errors)
                      Text(entry.value,
                          style: TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onErrorContainer)),
                  ]),
            ),
          ),
        );
      });
}

class StudyEmpty extends StatelessWidget {
  const StudyEmpty(this.label,
      {super.key, this.icon = Icons.menu_book_outlined});
  final String label;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 28),
        child: Column(children: [
          Icon(icon,
              size: 32, color: Theme.of(context).colorScheme.onSurfaceVariant),
          const SizedBox(height: 8),
          Text(label, textAlign: TextAlign.center),
        ]),
      );
}

class StudyHeading extends StatelessWidget {
  const StudyHeading(this.title, {super.key, this.action});
  final String title;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 20, bottom: 8),
        child: Row(children: [
          Expanded(
              child: Text(title,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700))),
          if (action != null) action!,
        ]),
      );
}

class StudyThumbnail extends StatelessWidget {
  const StudyThumbnail(this.url, {super.key});
  final String url;
  @override
  Widget build(BuildContext context) {
    final fallback = ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: const Center(child: Icon(Icons.play_circle_outline)),
    );
    final api = ApiClient();
    final resolved = url.isEmpty ? '' : api.absoluteUrl(url);
    return SizedBox(
        width: 72,
        height: 46,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: resolved.isEmpty
              ? fallback
              : Image.network(resolved,
                  headers: api.isBackendUrl(resolved) && api.token != null
                      ? {'Authorization': 'Bearer ${api.token}'}
                      : null,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => fallback),
        ));
  }
}

class StudyItemRow extends StatelessWidget {
  const StudyItemRow(
      {super.key,
      required this.item,
      required this.onPlay,
      this.actions = const [],
      this.displayTitle,
      this.leading});
  final StudyItem item;
  final VoidCallback? onPlay;
  final List<Widget> actions;
  final Widget? leading;
  final String? displayTitle;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            if (leading != null) leading!,
            StudyThumbnail(item.thumbnailUrl),
            const SizedBox(width: 12),
            Expanded(
                child: InkWell(
                    onTap: onPlay,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(displayTitle ?? item.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleSmall),
                            const SizedBox(height: 4),
                            Text(
                                '${item.source == 'nas' ? 'NAS' : 'B站'} · ${item.status.label} · '
                                '${studyTime(item.positionSeconds)} / ${studyTime(item.durationSeconds)}',
                                style: Theme.of(context).textTheme.bodySmall),
                          ]),
                    ))),
            IconButton(
                tooltip: '播放',
                onPressed: onPlay,
                icon: const Icon(Icons.play_arrow)),
          ]),
          if (item.positionSeconds > 0)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child:
                  LinearProgressIndicator(value: item.progress, minHeight: 2),
            ),
          if (actions.isNotEmpty)
            Align(
                alignment: Alignment.centerRight,
                child: Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: actions)),
          const Divider(height: 1),
        ]),
      );
}

Future<bool> studyConfirm(
        BuildContext context, String title, String message) async =>
    await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
              title: Text(title),
              content: Text(message),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('取消')),
                FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('确认')),
              ],
            )) ??
    false;

Future<int?> studyPickList(
    BuildContext context, StudyController controller) async {
  if (controller.activeLists.isEmpty) {
    await showDialog<bool>(
        context: context,
        builder: (_) => StudyListEditor(controller: controller));
    if (!context.mounted) return null;
  }
  if (controller.activeLists.isEmpty) return null;
  return showDialog<int>(
      context: context,
      builder: (context) => SimpleDialog(
            title: const Text('添加到学习列表'),
            children: [
              for (final list in controller.activeLists)
                SimpleDialogOption(
                    onPressed: () => Navigator.pop(context, list.id),
                    child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(list.name))),
            ],
          ));
}

class StudyListEditor extends StatefulWidget {
  const StudyListEditor({super.key, required this.controller, this.list});
  final StudyController controller;
  final StudyList? list;
  @override
  State<StudyListEditor> createState() => _StudyListEditorState();
}

class _StudyListEditorState extends State<StudyListEditor> {
  late final TextEditingController _name;
  late final TextEditingController _description;
  late bool _archived;
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.list?.name);
    _description = TextEditingController(text: widget.list?.description);
    _archived = widget.list?.archived ?? false;
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Obx(() {
        final saving = widget.controller.writing;
        return PopScope(
            canPop: !saving,
            child: AlertDialog(
              title: Text(widget.list == null ? '新建学习列表' : '编辑学习列表'),
              content: SizedBox(
                  width: 420,
                  child: SingleChildScrollView(
                      child: Form(
                    key: _formKey,
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      TextFormField(
                          controller: _name,
                          autofocus: true,
                          enabled: !saving,
                          decoration: const InputDecoration(labelText: '名称'),
                          maxLength: 120,
                          validator: (value) =>
                              value == null || value.trim().isEmpty
                                  ? '请输入名称'
                                  : null),
                      TextFormField(
                          controller: _description,
                          enabled: !saving,
                          minLines: 2,
                          maxLines: 4,
                          decoration: const InputDecoration(labelText: '说明')),
                      if (widget.list != null)
                        SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('归档'),
                            value: _archived,
                            onChanged: saving
                                ? null
                                : (value) => setState(() => _archived = value)),
                      StudyErrors(controller: widget.controller),
                    ]),
                  ))),
              actions: [
                TextButton(
                    onPressed: saving ? null : () => Navigator.pop(context),
                    child: const Text('取消')),
                FilledButton(
                    onPressed: saving
                        ? null
                        : () async {
                            if (!_formKey.currentState!.validate()) return;
                            final saved = await widget.controller.saveList(
                                list: widget.list,
                                name: _name.text,
                                description: _description.text,
                                archived: _archived);
                            if (saved && context.mounted) {
                              Navigator.pop(context, true);
                            }
                          },
                    child: Text(saving ? '保存中' : '保存')),
              ],
            ));
      });
}
