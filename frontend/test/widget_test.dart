import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibe_manager/main.dart';

void main() {
  testWidgets('shows login form when not authenticated', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const VibeApp());
    await tester.pumpAndSettle();

    expect(find.text('Vibe Manager'), findsWidgets);
    expect(find.text('Sign in'), findsOneWidget);
  });
}
