import 'package:flutter_test/flutter_test.dart';

import 'support/widget_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CQCM app flow', () {
    testWidgets('ouvre le catalogue QCM depuis le menu', (tester) async {
      useLargeSurface(tester);
      await openMenu(tester);

      expect(find.text('CQCM'), findsOneWidget);
      expect(find.text('Recopier texte'), findsOneWidget);
      expect(find.text('Que veux-tu réviser ?'), findsOneWidget);

      await tester.tap(find.text('QCM'));
      await pumpUntilFound(tester, find.text('Qualité dev – Tests et JUnit'));
      await settleNavigation(tester);

      await tester.tap(find.text('Qualité dev – Tests et JUnit'));
      await pumpUntilFound(tester, find.textContaining('Question 1/'));
      await settleNavigation(tester);

      expect(find.text('Qualité dev – Tests et JUnit'), findsWidgets);
    });

    testWidgets('revient au menu depuis le mode recopier texte', (
      tester,
    ) async {
      useLargeSurface(tester);
      await openMenu(tester);

      // Le plan est chargé : l'écran GP s'affiche au premier rendu.
      await tester.tap(find.text('Recopier texte'));
      await pumpUntilFound(tester, find.text('GP:'));
      await settleNavigation(tester);

      expect(
        find.text('GP – User stories · Programme de révision des US'),
        findsOneWidget,
      );
      expect(find.text('12 phrases au programme'), findsOneWidget);

      await tester.pageBack();
      await pumpUntilFound(tester, find.text('Que veux-tu réviser ?'));
      await settleNavigation(tester);

      expect(find.text('QCM'), findsOneWidget);
    });
  });
}
