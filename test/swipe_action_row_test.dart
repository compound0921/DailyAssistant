import 'package:daily_assistant/ui/swipe_action_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('reveals an action after swiping left', (tester) async {
    var edits = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 320,
              child: SwipeActionRow(
                backgroundColor: Colors.white,
                actions: [
                  SwipeAction(
                    label: '编辑',
                    icon: Icons.edit_outlined,
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    onPressed: () => edits++,
                  ),
                ],
                child: Container(
                  height: 64,
                  color: Colors.white,
                  alignment: Alignment.center,
                  child: const Text('考试'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.drag(find.text('考试'), const Offset(-120, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('编辑'));
    await tester.pumpAndSettle();

    expect(edits, 1);
  });

  testWidgets('triggers full swipe only after passing the actions', (
    tester,
  ) async {
    var toggles = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 320,
              child: SwipeActionRow(
                backgroundColor: Colors.white,
                onFullSwipe: () => toggles++,
                actions: [
                  SwipeAction(
                    label: '编辑',
                    icon: Icons.edit_outlined,
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    onPressed: () {},
                  ),
                ],
                child: Container(
                  height: 64,
                  color: Colors.white,
                  alignment: Alignment.center,
                  child: const Text('日程'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.drag(find.text('日程'), const Offset(-120, 0));
    await tester.pumpAndSettle();
    expect(toggles, 0);

    await tester.drag(find.text('日程'), const Offset(-220, 0));
    await tester.pumpAndSettle();
    expect(toggles, 1);
  });
}
