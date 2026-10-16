import 'package:cqcm/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ecran Rappels', () {
    testWidgets('la cloche du menu ouvre la configuration JSON', (
      tester,
    ) async {
      await tester.pumpWidget(const CQCMApp());
      await _pumpUntilFound(tester, find.text('QCM'));

      await tester.tap(find.byTooltip('Rappels'));
      await _pumpUntilFound(tester, find.text('Configuration JSON'));

      expect(find.text('Rappels'), findsWidgets);
      expect(find.text('Rappels activés (09:00)'), findsOneWidget);
      expect(find.text('Synchroniser'), findsOneWidget);
      expect(find.text('Autorisation'), findsOneWidget);
      expect(find.text('Notification de test'), findsOneWidget);
      expect(find.text('Tout annuler'), findsOneWidget);
      expect(find.text('Réglages effectifs'), findsOneWidget);
    });

    testWidgets('la synchronisation ne casse pas l ecran', (tester) async {
      await tester.pumpWidget(const CQCMApp());
      await _pumpUntilFound(tester, find.text('QCM'));

      await tester.tap(find.byTooltip('Rappels'));
      await _pumpUntilFound(tester, find.text('Synchroniser'));

      await tester.tap(find.text('Synchroniser'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      // Le plugin n'est pas disponible dans les tests : l'ecran doit rester
      // utilisable et afficher un message plutot que de lever une exception.
      expect(tester.takeException(), isNull);
      expect(find.text('Configuration JSON'), findsOneWidget);
    });

    testWidgets('la liste des rappels calcules est affichee', (tester) async {
      await tester.pumpWidget(const CQCMApp());
      await _pumpUntilFound(tester, find.text('QCM'));

      await tester.tap(find.byTooltip('Rappels'));
      await _pumpUntilFound(tester, find.text('Rappels programmés'));

      expect(find.text('Rappels programmés'), findsOneWidget);
      // Les 12 phrases du programme GP sont a reviser : rapport avec la
      // premiere phrase du programme.
      expect(find.textContaining('Commence par :'), findsWidgets);
    });
  });
}

Future<void> _pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  int maxPumps = 40,
}) async {
  for (var i = 0; i < maxPumps; i++) {
    await tester.pump(const Duration(milliseconds: 100));
    if (finder.evaluate().isNotEmpty) {
      return;
    }
  }

  fail('Timed out waiting for $finder');
}
