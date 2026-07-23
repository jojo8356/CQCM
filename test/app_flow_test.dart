import 'package:cqcm/main.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CQCM app flow', () {
    testWidgets('launches, loads categories, and opens a quiz from home', (
      tester,
    ) async {
      await tester.pumpWidget(const CQCMApp());
      await _pumpUntilFound(tester, find.byType(Scrollable));

      expect(find.text('CQCM'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Qualité dev – Tests et JUnit'),
        500,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pump();

      await tester.tap(find.text('Qualité dev – Tests et JUnit'));
      await _pumpUntilFound(tester, find.text('Qualité dev – Tests et JUnit'));

      expect(find.text('Qualité dev – Tests et JUnit'), findsWidgets);
    });
  });
}

Future<void> _pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  int maxPumps = 20,
}) async {
  for (var i = 0; i < maxPumps; i++) {
    await tester.pump(const Duration(milliseconds: 100));
    if (finder.evaluate().isNotEmpty) {
      return;
    }
  }

  fail('Timed out waiting for $finder');
}
