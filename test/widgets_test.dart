import 'package:cqcm/models/quiz.dart';
import 'package:cqcm/widgets/markdown_text.dart';
import 'package:cqcm/widgets/option_tile.dart';
import 'package:cqcm/widgets/progress_bar.dart';
import 'package:cqcm/widgets/quiz_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('QuizCard', () {
    testWidgets('shows quiz metadata and triggers selection', (tester) async {
      var tapped = false;
      const quiz = Quiz(
        id: 'git',
        title: 'Git',
        description: 'Commandes Git et workflows',
        category: 'Outils',
        difficulty: 'intermediaire',
        questionCount: 20,
        fileName: 'questions-git.json',
        icon: 'G',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: QuizCard(quiz: quiz, onTap: () => tapped = true),
          ),
        ),
      );

      expect(find.text('G'), findsOneWidget);
      expect(find.text('Git'), findsOneWidget);
      expect(find.text('Commandes Git et workflows'), findsOneWidget);
      expect(find.text('20 questions'), findsOneWidget);
      expect(find.text('intermediaire'), findsOneWidget);

      await tester.tap(find.byType(QuizCard));

      expect(tapped, isTrue);
    });
  });

  group('OptionTile', () {
    testWidgets('uses radio controls for single-choice answers', (
      tester,
    ) async {
      var tapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OptionTile(
              text: 'Reponse A',
              index: 0,
              isSelected: false,
              isMultipleChoice: false,
              hasValidated: false,
              isCorrect: false,
              onTap: () => tapped = true,
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.radio_button_unchecked), findsOneWidget);

      await tester.tap(find.text('Reponse A'));

      expect(tapped, isTrue);
    });

    testWidgets('uses checkbox controls for multiple-choice answers', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OptionTile(
              text: 'Reponse multiple',
              index: 1,
              isSelected: true,
              isMultipleChoice: true,
              hasValidated: false,
              isCorrect: false,
              onTap: () {},
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.check_box), findsOneWidget);
      expect(find.text('Reponse multiple'), findsOneWidget);
    });

    testWidgets(
      'locks interaction and marks correct answers after validation',
      (tester) async {
        var taps = 0;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: OptionTile(
                text: 'Bonne reponse',
                index: 1,
                isSelected: false,
                isMultipleChoice: false,
                hasValidated: true,
                isCorrect: true,
                onTap: () => taps++,
              ),
            ),
          ),
        );

        expect(find.byIcon(Icons.check_circle), findsOneWidget);

        await tester.tap(find.text('Bonne reponse'));

        expect(taps, 0);
      },
    );

    testWidgets('marks selected wrong answers after validation', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OptionTile(
              text: 'Mauvaise reponse',
              index: 2,
              isSelected: true,
              isMultipleChoice: false,
              hasValidated: true,
              isCorrect: false,
              onTap: () {},
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.cancel), findsOneWidget);
    });
  });

  group('QuizProgressBar', () {
    testWidgets('represents current progress as current over total', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: QuizProgressBar(current: 2, total: 5)),
        ),
      );

      final progress = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );

      expect(progress.value, 0.4);
    });
  });

  group('MarkdownText', () {
    testWidgets('renders markdown content as visible text', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: MarkdownText(data: '**Important** et `code`')),
        ),
      );

      expect(find.textContaining('Important'), findsWidgets);
      expect(find.textContaining('code'), findsWidgets);
    });
  });
}
