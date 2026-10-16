import 'dart:convert';

import 'package:cqcm/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Mode recopier texte', () {
    testWidgets('note chaque phrase recopiée puis affiche le bilan', (
      tester,
    ) async {
      final deck = await _loadDeck();

      await _openGpScreen(tester);
      await _startSession(tester);
      await _pumpUntilFound(tester, find.text('Phrase 1/5'));

      for (var index = 0; index < 5; index++) {
        // L'ordre des phrases est tiré au hasard : on lit l'énoncé affiché.
        final item = _visibleItem(deck);

        await tester.enterText(find.byType(TextField), item.referenceAnswer);
        await tester.pump();
        await tester.tap(find.text('Valider'));
        await _pumpUntilFound(tester, find.text('100 %'));

        expect(find.text('Recopie exacte, bravo !'), findsOneWidget);

        if (index < 4) {
          await tester.tap(find.text('Phrase suivante'));
          await _pumpUntilFound(tester, find.text('Phrase ${index + 2}/5'));
        }
      }

      await tester.tap(find.text('Terminer la séance'));
      await _pumpUntilFound(tester, find.text('Bilan de la séance'));

      expect(find.text('100 %'), findsOneWidget);
      expect(find.textContaining('5/5 validées (seuil 95 %)'), findsOneWidget);
    });

    testWidgets('contrôle la contrainte et la structure de la user story', (
      tester,
    ) async {
      final deck = await _loadDeck();
      // us-boulangerie-2 : « ne pas utiliser le verbe payer ».
      final constrained = deck.items[1];

      await _openGpScreen(tester);
      await _openPhrase(tester, constrained, index: 1);
      await _pumpUntilFound(tester, find.text('Phrase 1/1'));

      expect(find.text('ne pas utiliser le verbe payer'), findsOneWidget);

      await tester.enterText(
        find.byType(TextField),
        constrained.referenceAnswer,
      );
      await tester.pump();
      await tester.tap(find.text('Valider'));
      await _pumpUntilFound(tester, find.text('100 %'));

      expect(find.text('Structure de la user story'), findsOneWidget);
      expect(find.text('Ta copie'), findsOneWidget);
      expect(find.text('Réponse attendue'), findsOneWidget);
      expect(find.textContaining('« payer » est toléré'), findsOneWidget);
    });

    testWidgets('détaille une copie incomplète et clôt la séance', (
      tester,
    ) async {
      final deck = await _loadDeck();
      final firstItem = deck.items.first;

      await _openGpScreen(tester);
      await _openPhrase(tester, firstItem, index: 0);
      await _pumpUntilFound(tester, find.text('Phrase 1/1'));

      // Copie partielle : seuls les premiers mots sont recopiés.
      await tester.enterText(find.byType(TextField), 'En tant que client');
      await tester.pump();
      await tester.tap(find.text('Valider'));
      await _pumpUntilFound(tester, find.textContaining('mots justes'));

      expect(find.text('contact'), findsOneWidget, reason: 'mot manquant');
      expect(find.text('client'), findsNWidgets(2));
      await _pumpUntilFound(
        tester,
        find.textContaining("À revoir aujourd'hui"),
      );

      await tester.tap(find.text('Terminer la séance'));
      await _pumpUntilFound(tester, find.text('Bilan de la séance'));

      expect(find.textContaining('seuil 95 %'), findsOneWidget);
      expect(find.textContaining('Refaire les 1 phrase ratée'), findsOneWidget);
      expect(
        find.textContaining("restent à revoir aujourd'hui"),
        findsOneWidget,
      );

      await tester.tap(find.text('Retour au programme'));
      await _pumpUntilFound(tester, find.text('GP:'));

      // La tentative est enregistrée : le rappel la compte comme « à revoir ».
      await _pumpUntilFound(tester, find.textContaining('1 à revoir'));
    });
  });
}

class _DeckFixture {
  final List<_ItemFixture> items;

  const _DeckFixture(this.items);
}

class _ItemFixture {
  final String prompt;
  final List<String> constraints;
  final String referenceAnswer;

  const _ItemFixture({
    required this.prompt,
    required this.constraints,
    required this.referenceAnswer,
  });
}

Future<_DeckFixture> _loadDeck() async {
  final raw = json.decode(
    await rootBundle.loadString('assets/data/revision-gp-us.json'),
  ) as Map<String, dynamic>;
  final items = (raw['items'] as List).cast<Map<String, dynamic>>();

  return _DeckFixture([
    for (final item in items)
      _ItemFixture(
        prompt: item['prompt'] as String,
        constraints: ((item['constraints'] as List?) ?? const [])
            .map((value) => value as String)
            .toList(),
        referenceAnswer: (item['answers'] as List).first as String,
      ),
  ]);
}

/// Ouvre le menu puis l'écran « Recopier texte ».
Future<void> _openGpScreen(WidgetTester tester) async {
  await tester.pumpWidget(const CQCMApp());
  await _pumpUntilFound(tester, find.text('Recopier texte'));

  await tester.tap(find.text('Recopier texte'));
  await _pumpUntilFound(tester, find.text('GP:'));
}

/// Lance la séance proposée par l'écran GP.
Future<void> _startSession(WidgetTester tester) async {
  final button = find.textContaining('Réviser ');
  await tester.scrollUntilVisible(
    button,
    300,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pump();
  await tester.tap(button);
}

/// Ouvre une séance d'une phrase en tapant sur sa fiche.
Future<void> _openPhrase(
  WidgetTester tester,
  _ItemFixture item, {
  required int index,
}) async {
  final finder = find.text(item.prompt).at(index);
  await tester.scrollUntilVisible(
    finder,
    300,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pump();
  await tester.tap(finder);
}

/// Phrase actuellement affichée dans la séance (l'ordre est aléatoire).
_ItemFixture _visibleItem(_DeckFixture deck) {
  final candidates = deck.items
      .where((item) => find.text(item.prompt).evaluate().isNotEmpty)
      .toList();

  if (candidates.isEmpty) {
    fail('Aucun énoncé visible dans la séance.');
  }
  if (candidates.length == 1) {
    return candidates.single;
  }

  // Deux énoncés identiques : la contrainte affichée permet de trancher.
  for (final candidate in candidates) {
    final hasChip = candidate.constraints.any(
      (constraint) => find.text(constraint).evaluate().isNotEmpty,
    );
    if (hasChip) return candidate;
  }
  return candidates.first;
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
