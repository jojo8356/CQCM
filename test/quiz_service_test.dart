import 'package:cqcm/services/quiz_service.dart';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('QuizService', () {
    final service = QuizService();

    test('loads the quiz catalogue from bundled assets', () async {
      final quizzes = await service.loadQuizzes();

      expect(quizzes, isNotEmpty);
      expect(quizzes.map((quiz) => quiz.id), contains('qualite-tests-junit'));
      expect(
        quizzes.map((quiz) => quiz.category).toSet(),
        containsAll([
          'Bases de données',
          'Statistiques',
          'Réseaux',
          'IHM',
          'Outils',
          'Qualité',
        ]),
      );
    });

    test('loads questions for a selected quiz', () async {
      final questions = await service.loadQuestions(
        'questions-qualite-tests-junit.json',
      );

      expect(questions, hasLength(50));
      expect(
        questions.first.question,
        contains('V\u00e9rification et Validation'),
      );
      expect(questions.first.options, hasLength(4));
      expect(questions.first.correctIndex, 1);
      expect(questions.first.explanation, isNotNull);
    });

    test('keeps catalogue question counts aligned with question files', () async {
      final quizzes = await service.loadQuizzes();

      for (final quiz in quizzes) {
        final questions = await service.loadQuestions(quiz.fileName);

        expect(
          questions,
          hasLength(quiz.questionCount),
          reason: '${quiz.id} declares ${quiz.questionCount} questions',
        );
        expect(
          questions.map((question) => question.id).toSet(),
          hasLength(questions.length),
          reason: '${quiz.id} should not contain duplicate question ids',
        );
        for (final question in questions) {
          expect(
            question.options,
            isNotEmpty,
            reason: '${quiz.id} question ${question.id} needs answer options',
          );
          expect(
            question.allCorrectIndices,
            isNotEmpty,
            reason: '${quiz.id} question ${question.id} needs an oracle',
          );
          expect(
            question.allCorrectIndices,
            everyElement(inInclusiveRange(0, question.options.length - 1)),
            reason:
                '${quiz.id} question ${question.id} correct indices must point to options',
          );
        }
      }
    });

    test('throws when a question asset is missing', () {
      expect(
        service.loadQuestions('missing-questions.json'),
        throwsA(isA<FlutterError>()),
      );
    });

    test('merges runtime quizzes and loads runtime questions first', () async {
      final runtimeDir = await Directory.systemTemp.createTemp(
        'cqcm_quiz_test_',
      );
      addTearDown(() async {
        if (await runtimeDir.exists()) {
          await runtimeDir.delete(recursive: true);
        }
      });

      await File('${runtimeDir.path}/data.json').writeAsString(
        json.encode({
          'quizzes': [
            {
              'id': 'runtime-cli',
              'title': 'Runtime CLI',
              'description': 'Ajoute sans rebuild',
              'category': 'Runtime',
              'difficulty': 'debutant',
              'questionCount': 1,
              'fileName': 'questions-runtime-cli.json',
              'icon': 'R',
            },
          ],
        }),
      );
      await File('${runtimeDir.path}/questions-runtime-cli.json').writeAsString(
        json.encode([
          {
            'id': 1,
            'question': 'Pourquoi utiliser un dossier runtime ?',
            'options': ['Pour rebuild', 'Pour ajouter sans rebuild'],
            'correctIndex': 1,
          },
        ]),
      );

      final runtimeService = QuizService(runtimeDataDirectory: runtimeDir.path);

      final quizzes = await runtimeService.loadQuizzes();
      final runtimeQuiz = quizzes.singleWhere(
        (quiz) => quiz.id == 'runtime-cli',
      );
      final questions = await runtimeService.loadQuestions(
        runtimeQuiz.fileName,
      );

      expect(runtimeQuiz.title, 'Runtime CLI');
      expect(runtimeQuiz.questionCount, 1);
      expect(
        questions.single.question,
        'Pourquoi utiliser un dossier runtime ?',
      );
      expect(questions.single.isCorrectAnswer({1}), isTrue);
    });
  });
}
