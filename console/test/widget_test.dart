import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:promptd_console/app.dart';
import 'package:promptd_console/models/promptd_models.dart';
import 'package:promptd_console/widgets/chat/message_bubble.dart';

void main() {
  testWidgets('renders login flow when no session is stored', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const PromptdConsoleApp());
    await tester.pumpAndSettle();

    expect(find.text('Sign in'), findsWidgets);
    expect(find.text('Server URL'), findsOneWidget);
    expect(find.text('User ID'), findsOneWidget);
  });

  testWidgets('user message edit button opens edit form', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MessageBubble(
            message: ChatMessage(
              id: 'msg-1',
              role: 'user',
              content: 'original message',
              sentAt: DateTime(2026),
            ),
            onDelete: (_) async {},
            onEdit: (_, _) async {},
            loadFileBytes: (_) async => Uint8List(0),
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('Edit message'));
    await tester.pump();

    expect(find.text('Edit message'), findsOneWidget);
    expect(find.text('original message'), findsOneWidget);
  });
}
