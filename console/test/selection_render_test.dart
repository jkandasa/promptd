import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_test/flutter_test.dart';

// Confirms the chat message widgets (selectable markdown + SelectableText)
// build and lay out without assertions when nested inside the app-wide
// SelectionArea. No gestures are simulated.
void main() {
  testWidgets(
    'selectable markdown + SelectableText render inside SelectionArea',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: SelectionArea(
            child: Scaffold(
              body: ListView(
                children: const [
                  MarkdownBody(
                    data:
                        'First paragraph.\n\nSecond paragraph with **bold** '
                        'and a [link](https://example.com).\n\n- item one\n- item two',
                    selectable: true,
                  ),
                  SelectableText('A plain user message\nspanning two lines.'),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(MarkdownBody), findsOneWidget);
      expect(find.byType(SelectableText), findsWidgets);
    },
  );
}
