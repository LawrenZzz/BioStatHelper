import 'package:flutter/material.dart';

import 'liquid_glass_panel.dart';

class LibraryBrowseOption {
  const LibraryBrowseOption({
    required this.id,
    required this.title,
    this.subtitle = '',
    this.icon = '',
    this.count = 0,
  });

  final String id;
  final String title;
  final String subtitle;
  final String icon;
  final int count;
}

Future<void> showLibraryBrowseSheet({
  required BuildContext context,
  required String title,
  required String searchHint,
  required List<LibraryBrowseOption> options,
  required ValueChanged<LibraryBrowseOption> onSelected,
}) async {
  final selected = await showLiquidGlassBottomSheet<LibraryBrowseOption>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _LibraryBrowseSheet(
      title: title,
      searchHint: searchHint,
      options: options,
    ),
  );
  if (selected != null && context.mounted) {
    onSelected(selected);
  }
}

class _LibraryBrowseSheet extends StatefulWidget {
  const _LibraryBrowseSheet({
    required this.title,
    required this.searchHint,
    required this.options,
  });

  final String title;
  final String searchHint;
  final List<LibraryBrowseOption> options;

  @override
  State<_LibraryBrowseSheet> createState() => _LibraryBrowseSheetState();
}

class _LibraryBrowseSheetState extends State<_LibraryBrowseSheet> {
  var _query = '';
  var _sortBy = 'count';
  var _searchFieldRevision = 0;

  @override
  Widget build(BuildContext context) {
    final items = widget.options.where((item) {
      final needle = _query.trim().toLowerCase();
      return needle.isEmpty ||
          item.title.toLowerCase().contains(needle) ||
          item.subtitle.toLowerCase().contains(needle);
    }).toList()
      ..sort((a, b) {
        if (_sortBy == 'name') {
          return a.title.compareTo(b.title);
        }
        final countCompare = b.count.compareTo(a.count);
        return countCompare != 0 ? countCompare : a.title.compareTo(b.title);
      });

    final maxHeight = MediaQuery.sizeOf(context).height * 0.76;
    return SizedBox(
      height: maxHeight,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.title,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 14),
            TextFormField(
              key: ValueKey(_searchFieldRevision),
              initialValue: _query,
              autofocus: true,
              decoration: InputDecoration(
                hintText: widget.searchHint,
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        tooltip: '清空',
                        onPressed: () {
                          setState(() {
                            _query = '';
                            _searchFieldRevision++;
                          });
                        },
                        icon: const Icon(Icons.close),
                      ),
              ),
              onChanged: (value) => setState(() => _query = value),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('按数量'),
                  selected: _sortBy == 'count',
                  onSelected: (_) => setState(() => _sortBy = 'count'),
                ),
                ChoiceChip(
                  label: const Text('按名称'),
                  selected: _sortBy == 'name',
                  onSelected: (_) => setState(() => _sortBy = 'name'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Expanded(
              child: items.isEmpty
                  ? Center(
                      child: Text(
                        '没有匹配的内容',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    )
                  : ListView.separated(
                      itemCount: items.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final item = items[index];
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 3,
                          ),
                          leading: item.icon.isEmpty
                              ? const Icon(Icons.folder_outlined)
                              : Text(
                                  item.icon,
                                  style: const TextStyle(fontSize: 20),
                                ),
                          title: Text(
                            item.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: item.subtitle.isEmpty
                              ? null
                              : Text(
                                  item.subtitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                          trailing: item.count > 0
                              ? Text(
                                  '${item.count}',
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelLarge
                                      ?.copyWith(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primary,
                                        fontWeight: FontWeight.w700,
                                      ),
                                )
                              : null,
                          onTap: () => Navigator.of(context).pop(item),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
