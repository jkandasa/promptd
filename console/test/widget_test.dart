import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:console/app.dart';

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
}
