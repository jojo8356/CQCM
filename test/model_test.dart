import 'package:cqcm/models/question.dart';
import 'package:cqcm/models/quiz.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Quiz model', () {
    test('maps every JSON field to a Quiz', () {
      final quiz = Quiz.fromJson({
        'id': 'qualite-tests-junit',
        'title': 'Qualite dev - Tests et JUnit',
        'description': 'Tests logiciels et JUnit 5',
        'category': 'Qualite',
        'difficulty': 'intermediaire',
        'questionCount': 50,
        'fileName': 'questions-qualite-tests-junit.json',
        'icon': 'T',
      });

      expect(quiz.id, 'qualite-tests-junit');
      expect(quiz.title, 'Qualite dev - Tests et JUnit');
      expect(quiz.description, 'Tests logiciels et JUnit 5');
      expect(quiz.category, 'Qualite');
      expect(quiz.difficulty, 'intermediaire');
      expect(quiz.questionCount, 50);
      expect(quiz.fileName, 'questions-qualite-tests-junit.json');
      expect(quiz.icon, 'T');
    });
  });

  group('Question model', () {
    test('supports single-choice questions', () {
      final question = Question.fromJson({
        'id': 1,
        'question': 'Une question',
        'options': ['A', 'B', 'C'],
        'correctIndex': 1,
        'explanation': 'B est correcte.',
      });

      expect(question.isMultipleChoice, isFalse);
      expect(question.allCorrectIndices, [1]);
      expect(question.isCorrectAnswer({1}), isTrue);
      expect(question.isCorrectAnswer({0}), isFalse);
      expect(question.isCorrectAnswer({1, 2}), isFalse);
      expect(question.explanation, 'B est correcte.');
    });

    test('supports multiple-choice questions', () {
      final question = Question.fromJson({
        'id': 2,
        'question': 'Plusieurs reponses',
        'options': ['A', 'B', 'C'],
        'correctIndices': [0, 2],
      });

      expect(question.isMultipleChoice, isTrue);
      expect(question.allCorrectIndices, [0, 2]);
      expect(question.isCorrectAnswer({0, 2}), isTrue);
      expect(question.isCorrectAnswer({2, 0}), isTrue);
      expect(question.isCorrectAnswer({0}), isFalse);
      expect(question.isCorrectAnswer({0, 1, 2}), isFalse);
    });

    test('handles questions without declared correct answer defensively', () {
      const question = Question(
        id: 3,
        question: 'Sans reponse',
        options: ['A', 'B'],
      );

      expect(question.isMultipleChoice, isFalse);
      expect(question.allCorrectIndices, isEmpty);
      expect(question.isCorrectAnswer({}), isTrue);
      expect(question.isCorrectAnswer({0}), isFalse);
    });
  });
}
