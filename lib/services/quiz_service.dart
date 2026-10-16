import 'dart:convert';

import '../models/quiz.dart';
import '../models/question.dart';
import 'asset_text.dart';
import 'runtime_quiz_store.dart';

class QuizService {
  final String? runtimeDataDirectory;

  QuizService({String? runtimeDataDirectory})
    : runtimeDataDirectory =
          runtimeDataDirectory ?? defaultRuntimeDataDirectory();

  Future<List<Quiz>> loadQuizzes() async {
    final resolvedRuntimeDataDirectory = runtimeDataDirectory == null
        ? null
        : await resolveRuntimeDataDirectory(runtimeDataDirectory);
    final jsonString = await loadAssetText('assets/data/data.json');
    final data = json.decode(jsonString) as Map<String, dynamic>;
    final quizzes = (data['quizzes'] as List)
        .map((q) => Quiz.fromJson(q as Map<String, dynamic>))
        .toList();

    final runtimeQuizzes = await loadRuntimeQuizzes(
      resolvedRuntimeDataDirectory,
    );
    if (runtimeQuizzes.isEmpty) {
      return quizzes;
    }

    final mergedById = {
      for (final quiz in quizzes) quiz.id: quiz,
      for (final quiz in runtimeQuizzes) quiz.id: quiz,
    };
    return mergedById.values.toList();
  }

  Future<List<Question>> loadQuestions(String fileName) async {
    final resolvedRuntimeDataDirectory = runtimeDataDirectory == null
        ? null
        : await resolveRuntimeDataDirectory(runtimeDataDirectory);
    final runtimeQuestions = await loadRuntimeQuestions(
      resolvedRuntimeDataDirectory,
      fileName,
    );
    if (runtimeQuestions != null) {
      return runtimeQuestions;
    }

    final jsonString = await loadAssetText('assets/data/$fileName');
    final data = json.decode(jsonString) as List;
    return data
        .map((q) => Question.fromJson(q as Map<String, dynamic>))
        .toList();
  }
}
