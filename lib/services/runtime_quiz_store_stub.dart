import '../models/question.dart';
import '../models/quiz.dart';

String? defaultRuntimeDataDirectory() => null;

Future<String?> resolveRuntimeDataDirectory(String? directoryPath) async {
  return directoryPath;
}

Future<List<Quiz>> loadRuntimeQuizzes(String? directoryPath) async => [];

Future<List<Question>?> loadRuntimeQuestions(
  String? directoryPath,
  String fileName,
) async {
  return null;
}

Future<Quiz> importQuizPackageJson(String jsonString) async {
  throw UnsupportedError('Quiz import is not supported on this platform.');
}
