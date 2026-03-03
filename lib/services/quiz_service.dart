import 'dart:convert';
import 'package:flutter/services.dart';
import '../models/quiz.dart';
import '../models/question.dart';

class QuizService {
  Future<List<Quiz>> loadQuizzes() async {
    final jsonString = await rootBundle.loadString('assets/data/data.json');
    final data = json.decode(jsonString) as Map<String, dynamic>;
    final quizzes = (data['quizzes'] as List)
        .map((q) => Quiz.fromJson(q as Map<String, dynamic>))
        .toList();
    return quizzes;
  }

  Future<List<Question>> loadQuestions(String fileName) async {
    final jsonString = await rootBundle.loadString('assets/data/$fileName');
    final data = json.decode(jsonString) as List;
    return data
        .map((q) => Question.fromJson(q as Map<String, dynamic>))
        .toList();
  }
}
