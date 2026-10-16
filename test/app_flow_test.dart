import 'package:cqcm/main.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CQCM app flow', () {
    testWidgets('ouvre le catalogue QCM depuis le menu', (tester) async {
      await tester.pumpWidget(const CQCMApp());
      await _pumpUntilFound(tester, find.text('QCM'));

      expect(find.text('CQCM'), findsOneWidget);
      expect(find.text('Recopier texte'), findsOneWidget);
      expect(find.text('Que veux-tu réviser ?'), findsOneWidget);

      await tester.tap(find.text('QCM'));
      await _pumpUntilFound(tester, find.byType(Scrollable));

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

    testWidgets('revient au menu depuis le mode recopier texte', (tester) async {
      await tester.pumpWidget(const CQCMApp());
      await _pumpUntilFound(tester, find.text('Recopier texte'));

      await tester.tap(find.text('Recopier texte'));
      await _pumpUntilFound(tester, find.text('GP:'));

      expect(find.text('Recopier texte'), findsOneWidget);

      await tester.pageBack();
      await _pumpUntilFound(tester, find.text('Que veux-tu réviser ?'));

      expect(find.text('QCM'), findsOneWidget);
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
