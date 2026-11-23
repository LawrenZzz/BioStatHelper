import 'package:bio_stat_helper/shared/widgets/library_browse_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('selecting an item does not reuse a disposed search controller',
      (tester) async {
    final selectedTitle = ValueNotifier<String>('none');
    addTearDown(selectedTitle.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: ValueListenableBuilder<String>(
                valueListenable: selectedTitle,
                builder: (context, selected, _) {
                  return Column(
                    children: [
                      Text('selected:$selected'),
                      FilledButton(
                        onPressed: () => showLibraryBrowseSheet(
                          context: context,
                          title: '全部课程',
                          searchHint: '搜索课程',
                          options: const [
                            LibraryBrowseOption(
                              id: 'course-a',
                              title: '课程 A',
                              count: 12,
                            ),
                          ],
                          onSelected: (option) {
                            selectedTitle.value = option.title;
                          },
                        ),
                        child: const Text('查看全部'),
                      ),
                    ],
                  );
                },
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('查看全部'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);

    await tester.enterText(find.byType(TextField), '课程');
    await tester.pump();
    await tester.tap(find.byTooltip('清空'));
    await tester.pump();

    await tester.tap(find.text('课程 A'));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('selected:课程 A'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
