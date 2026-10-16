import 'package:cqcm/services/revision_plan.dart';
import 'package:cqcm/services/text_scoring.dart';
import 'package:cqcm/widgets/revision_chart.dart';
import 'package:cqcm/widgets/revision_reminder_banner.dart';
import 'package:cqcm/widgets/word_diff_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(WidgetTester tester, Widget child) {
  return tester.pumpWidget(
    MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child))),
  );
}

void main() {
  group('RevisionChart', () {
    testWidgets('affiche un message quand il n\'y a pas d\'historique', (
      tester,
    ) async {
      await _pump(tester, const RevisionChart(values: []));

      expect(
        find.text('Aucune révision enregistrée pour le moment.'),
        findsOneWidget,
      );
    });

    testWidgets('trace la courbe dès la première tentative', (tester) async {
      await _pump(
        tester,
        const RevisionChart(values: [0.5, 0.8, 1.0], trendValues: [0.5, 0.65, 0.76]),
      );

      expect(find.byType(CustomPaint), findsWidgets);
      expect(
        find.text('Aucune révision enregistrée pour le moment.'),
        findsNothing,
      );
    });
  });

  group('WordDiffView', () {
    testWidgets('affiche la copie et la référence mot à mot', (tester) async {
      final score = TextScorer.score(
        'En tant que client je veux payer en carte bancaire',
        const [
          'En tant que client je veux payer en carte bancaire sans contact',
        ],
      );

      await _pump(tester, WordDiffView(score: score));

      expect(find.text('Ta copie'), findsOneWidget);
      expect(find.text('Réponse attendue'), findsOneWidget);
      expect(find.text('payer'), findsNWidgets(2));
      expect(find.text('contact'), findsOneWidget);
      expect(find.text('manquant'), findsOneWidget);
      expect(find.text('juste'), findsOneWidget);
    });
  });

  group('RevisionReminderBanner', () {
    RevisionReminder reminder({required int dueCount}) {
      return RevisionReminder(
        deckId: 'gp-us',
        deckTitle: 'GP – User stories',
        dueCount: dueCount,
        newCount: dueCount,
        totalCount: 12,
        nextDueAt: DateTime(2026, 4, 2, 8),
        now: DateTime(2026, 4, 1, 8),
      );
    }

    testWidgets('propose de réviser quand des phrases sont dues', (tester) async {
      var started = false;

      await _pump(
        tester,
        RevisionReminderBanner(
          reminder: reminder(dueCount: 3),
          onStart: () => started = true,
        ),
      );

      expect(
        find.text('GP – User stories · 3 phrases à réviser'),
        findsOneWidget,
      );
      expect(find.textContaining('Prochaine révision : demain'), findsOneWidget);

      await tester.tap(find.text('Réviser'));
      expect(started, isTrue);
    });

    testWidgets('annonce la prochaine échéance quand tout est à jour', (
      tester,
    ) async {
      await _pump(
        tester,
        RevisionReminderBanner(reminder: reminder(dueCount: 0)),
      );

      expect(find.text('GP – User stories · Tout est à jour'), findsOneWidget);
      expect(find.text('Réviser'), findsNothing);
    });
  });

  group('ReminderBadge', () {
    testWidgets('ne s\'affiche pas à zéro', (tester) async {
      await _pump(tester, const ReminderBadge(count: 0));

      expect(find.text('0'), findsNothing);
    });

    testWidgets('affiche le nombre de phrases dues', (tester) async {
      await _pump(tester, const ReminderBadge(count: 7));

      expect(find.text('7'), findsOneWidget);
    });
  });
}
