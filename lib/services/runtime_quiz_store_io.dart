import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../models/question.dart';
import '../models/quiz.dart';

/// Dossier résolu, gardé en **valeur** (jamais un `Future`) : voir
/// `revision_store_io.dart`.
String? _resolvedDefaultDirectory;
bool _defaultDirectoryResolved = false;

String? defaultRuntimeDataDirectory() {
  final configured = Platform.environment['CQCM_DATA_DIR'];
  if (configured == null || configured.trim().isEmpty) {
    return null;
  }
  return configured;
}

Future<String?> resolveRuntimeDataDirectory(String? directoryPath) async {
  if (directoryPath != null && directoryPath.trim().isNotEmpty) {
    return directoryPath;
  }

  if (_defaultDirectoryResolved) {
    return _resolvedDefaultDirectory;
  }

  final resolved = await _resolveDefaultDirectory();
  if (resolved != null) {
    _resolvedDefaultDirectory = resolved;
    _defaultDirectoryResolved = true;
  }
  return resolved;
}

Future<String?> _resolveDefaultDirectory() async {
  // Sous `flutter test`, aucun plugin ne répond : inutile d'attendre (voir
  // `revision_store_io.dart`).
  if ((Platform.environment['FLUTTER_TEST'] ?? '').isNotEmpty) {
    _resolvedDefaultDirectory = null;
    _defaultDirectoryResolved = true;
    return null;
  }

  try {
    final supportDirectory = await getApplicationSupportDirectory().timeout(
      const Duration(milliseconds: 500),
    );
    return '${supportDirectory.path}/cqcm-runtime-data';
  } on MissingPluginException {
    _resolvedDefaultDirectory = null;
    _defaultDirectoryResolved = true;
    return null;
  } on TimeoutException {
    return null;
  } catch (_) {
    return null;
  }
}

Future<List<Quiz>> loadRuntimeQuizzes(String? directoryPath) async {
  final resolvedDirectory = await resolveRuntimeDataDirectory(directoryPath);
  if (resolvedDirectory == null || resolvedDirectory.trim().isEmpty) {
    return [];
  }

  final catalogueFile = File('$resolvedDirectory/data.json');
  if (!await catalogueFile.exists()) {
    return [];
  }

  final jsonString = await catalogueFile.readAsString();
  final data = json.decode(jsonString) as Map<String, dynamic>;
  final quizzes = (data['quizzes'] as List)
      .map((q) => Quiz.fromJson(q as Map<String, dynamic>))
      .toList();
  return quizzes;
}

Future<List<Question>?> loadRuntimeQuestions(
  String? directoryPath,
  String fileName,
) async {
  final resolvedDirectory = await resolveRuntimeDataDirectory(directoryPath);
  if (resolvedDirectory == null || resolvedDirectory.trim().isEmpty) {
    return null;
  }

  final questionFile = File('$resolvedDirectory/$fileName');
  if (!await questionFile.exists()) {
    return null;
  }

  final jsonString = await questionFile.readAsString();
  final data = json.decode(jsonString) as List;
  return data.map((q) => Question.fromJson(q as Map<String, dynamic>)).toList();
}

Future<Quiz> importQuizPackageJson(String jsonString) async {
  final package = _QuizPackage.fromJson(
    json.decode(jsonString) as Map<String, dynamic>,
  );
  _validatePackage(package);

  final directoryPath = await resolveRuntimeDataDirectory(
    defaultRuntimeDataDirectory(),
  );
  if (directoryPath == null) {
    throw StateError('Runtime quiz directory is unavailable.');
  }

  final directory = Directory(directoryPath);
  await directory.create(recursive: true);

  final catalogueFile = File('${directory.path}/data.json');
  final existingQuizzes = await catalogueFile.exists()
      ? (json.decode(await catalogueFile.readAsString())['quizzes'] as List)
            .map((q) => Quiz.fromJson(q as Map<String, dynamic>))
            .toList()
      : <Quiz>[];

  final mergedById = {
    for (final quiz in existingQuizzes) quiz.id: quiz,
    package.quiz.id: package.quiz,
  };

  await File('${directory.path}/${package.quiz.fileName}').writeAsString(
    _prettyJson(
      package.questions.map((question) => question.toJson()).toList(),
    ),
  );
  await catalogueFile.writeAsString(
    _prettyJson({
      'quizzes': mergedById.values.map((quiz) => quiz.toJson()).toList(),
    }),
  );

  return package.quiz;
}

class _QuizPackage {
  final Quiz quiz;
  final List<Question> questions;

  const _QuizPackage(this.quiz, this.questions);

  factory _QuizPackage.fromJson(Map<String, dynamic> json) {
    return _QuizPackage(
      Quiz.fromJson(json['quiz'] as Map<String, dynamic>),
      (json['questions'] as List)
          .map((q) => Question.fromJson(q as Map<String, dynamic>))
          .toList(),
    );
  }
}

void _validatePackage(_QuizPackage package) {
  if (package.quiz.id.trim().isEmpty) {
    throw StateError('Quiz id cannot be empty.');
  }
  if (package.quiz.title.trim().isEmpty) {
    throw StateError('Quiz title cannot be empty.');
  }
  if (package.questions.isEmpty) {
    throw StateError('Quiz "${package.quiz.id}" must contain questions.');
  }
  if (package.quiz.questionCount != package.questions.length) {
    throw StateError(
      'Quiz "${package.quiz.id}" declares ${package.quiz.questionCount} questions but contains ${package.questions.length}.',
    );
  }

  final ids = <int>{};
  for (final question in package.questions) {
    if (!ids.add(question.id)) {
      throw StateError('Duplicate question id ${question.id}.');
    }
    if (question.options.length < 2) {
      throw StateError(
        'Question ${question.id} must have at least two options.',
      );
    }
    if (question.allCorrectIndices.isEmpty) {
      throw StateError('Question ${question.id} must define a correct answer.');
    }
    for (final index in question.allCorrectIndices) {
      if (index < 0 || index >= question.options.length) {
        throw StateError(
          'Question ${question.id} correct index $index is outside option range.',
        );
      }
    }
  }
}

String _prettyJson(Object value) {
  return '${const JsonEncoder.withIndent('  ').convert(value)}\n';
}
