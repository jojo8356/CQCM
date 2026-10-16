import 'package:cqcm/screens/text_revision_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/widget_helpers.dart';

/// Les autres tests utilisent une fenêtre large (1200 x 2400) : un débordement
/// de mise en page sur un vrai téléphone y échappe forcément. Ce fichier rejoue
/// les écrans sur des largeurs de téléphone réelles.
///
/// Un `RenderFlex overflowed` lève une exception de rendu : `flutter test` fait
/// échouer le test, et `takeException` sert à nommer l'écran fautif (c'est
/// ainsi qu'a été trouvé le débordement du menu d'accueil : titre « Recopier
/// texte » + pastille des phrases à réviser sur une ligne).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('écrans étroits (téléphone)', () {
    testWidgets('menu d\'accueil sans débordement sur 320 dp', (tester) async {
      _usePhoneSurface(tester, const Size(320, 640));

      await openMenu(tester);

      expect(find.text('Recopier texte'), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'menu d\'accueil');
    });

    for (final size in _journeySizes) {
      testWidgets('parcours complet sans débordement sur '
          '${size.width.toInt()} dp', (tester) async {
        _usePhoneSurface(tester, size);

        // 1. Menu d'accueil.
        await openMenu(tester);
        final menuEntry = find.text('Recopier texte');
        expect(tester.takeException(), isNull, reason: 'menu d\'accueil');

        // 2. Écran du programme GP : courbe, sélecteur de séance, cartes.
        await reveal(tester, menuEntry);
        await tester.tap(menuEntry);
        await pumpUntilFound(tester, find.text('GP:'));
        await settleNavigation(tester);
        expect(tester.takeException(), isNull, reason: 'programme GP');

        // 3. Séance : en-tête (projet + mention), champ, boutons.
        final start = withinScreen(
          TextRevisionScreen,
          find.textContaining('Réviser '),
        );
        await reveal(tester, start);
        await tester.tap(start);
        await pumpUntilFound(tester, find.text('Phrase 1/5'));
        expect(tester.takeException(), isNull, reason: 'séance');

        // 4. Correction puis bilan. Les copies sont volontairement fausses :
        //    c'est la mise en page qui est testée, pas le score.
        for (var index = 0; index < 5; index++) {
          await tester.enterText(find.byType(TextField), 'phrase incomplète');
          await tester.pump();

          // `reveal` avant chaque appui : sur un écran étroit, le bouton peut
          // se trouver sous la ligne de flottaison de la liste.
          final validate = find.text('Valider');
          await reveal(tester, validate);
          await tester.tap(validate);
          await pumpUntilFound(tester, find.textContaining('mots justes'));
          expect(
            tester.takeException(),
            isNull,
            reason: 'correction de la phrase ${index + 1}',
          );

          if (index < 4) {
            final next = find.text('Phrase suivante');
            await reveal(tester, next);
            await tester.tap(next);
            await pumpUntilFound(tester, find.text('Phrase ${index + 2}/5'));
          }
        }

        final finish = find.text('Terminer la séance');
        await reveal(tester, finish);
        await tester.tap(finish);
        await pumpUntilFound(tester, find.text('Bilan de la séance'));
        expect(tester.takeException(), isNull, reason: 'bilan de la séance');
      });
    }
  });
}

/// Largeurs du parcours complet. Le menu d'accueil est en plus testé seul à
/// 320 dp (largeur qui a révélé son débordement) : le parcours entier reste
/// sur deux largeurs de téléphone courantes pour garder le test court.
const _journeySizes = <Size>[
  Size(360, 740),
  Size(411, 891),
];

/// Fenêtre de test à la taille d'un téléphone (1 pixel logique = 1 pixel).
void _usePhoneSurface(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}
