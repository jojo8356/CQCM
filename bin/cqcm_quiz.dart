import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:cqcm/models/question.dart';
import 'package:cqcm/models/quiz.dart';

const _defaultDataDir = 'cqcm-runtime-data';

Future<void> main(List<String> args) async {
  final runner =
      CommandRunner<int>('cqcm-quiz', 'Manage CQCM runtime quiz JSON files.')
        ..argParser.addOption(
          'dir',
          abbr: 'd',
          help: 'Runtime data directory used by production.',
          defaultsTo: Platform.environment['CQCM_DATA_DIR'] ?? _defaultDataDir,
        )
        ..addCommand(InitCommand())
        ..addCommand(ListCommand())
        ..addCommand(ValidateCommand())
        ..addCommand(AddQuizCommand())
        ..addCommand(AddQuestionCommand());

  try {
    final exitCode = await runner.run(args) ?? 0;
    exitCode == 0 ? exit(0) : exit(exitCode);
  } on UsageException catch (error) {
    stderr.writeln(error);
    exit(64);
  } on FormatException catch (error) {
    stderr.writeln('Invalid JSON: ${error.message}');
    exit(65);
  } on FileSystemException catch (error) {
    stderr.writeln(error.message);
    exit(74);
  } on StateError catch (error) {
    stderr.writeln(error.message);
    exit(1);
  }
}

abstract class QuizCommand extends Command<int> {
  Directory get dataDir {
    final path = globalResults!['dir'] as String;
    return Directory(path);
  }

  File get catalogueFile => File('${dataDir.path}/data.json');

  Future<Catalogue> readCatalogue() async {
    if (!await catalogueFile.exists()) {
      return const Catalogue([]);
    }
    final data = json.decode(await catalogueFile.readAsString());
    return Catalogue.fromJson(data as Map<String, dynamic>);
  }

  Future<void> writeCatalogue(Catalogue catalogue) async {
    await dataDir.create(recursive: true);
    await catalogueFile.writeAsString(_prettyJson(catalogue.toJson()));
  }
}

class InitCommand extends QuizCommand {
  @override
  final name = 'init';

  @override
  final description = 'Create an empty runtime quiz directory.';

  @override
  Future<int> run() async {
    await writeCatalogue(await readCatalogue());
    stdout.writeln('Runtime quiz directory ready: ${dataDir.path}');
    return 0;
  }
}

class ListCommand extends QuizCommand {
  @override
  final name = 'list';

  @override
  final description = 'List runtime quizzes.';

  @override
  Future<int> run() async {
    final catalogue = await readCatalogue();
    if (catalogue.quizzes.isEmpty) {
      stdout.writeln('No runtime quizzes in ${dataDir.path}.');
      return 0;
    }

    for (final quiz in catalogue.quizzes) {
      stdout.writeln(
        '${quiz.id} | ${quiz.title} | ${quiz.questionCount} questions | ${quiz.fileName}',
      );
    }
    return 0;
  }
}

class ValidateCommand extends QuizCommand {
  @override
  final name = 'validate';

  @override
  final description = 'Validate a quiz package or the runtime directory.';

  ValidateCommand() {
    argParser.addOption(
      'package',
      abbr: 'p',
      help: 'JSON package containing {"quiz": {...}, "questions": [...]}.',
    );
  }

  @override
  Future<int> run() async {
    final packagePath = argResults!['package'] as String?;
    if (packagePath != null) {
      final package = await QuizPackage.fromFile(File(packagePath));
      validateQuizPackage(package);
      stdout.writeln('Valid package: $packagePath');
      return 0;
    }

    final catalogue = await readCatalogue();
    for (final quiz in catalogue.quizzes) {
      final questions = await readQuestions(
        File('${dataDir.path}/${quiz.fileName}'),
      );
      validateQuizPackage(QuizPackage(quiz, questions));
    }
    stdout.writeln('Valid runtime directory: ${dataDir.path}');
    return 0;
  }
}

class AddQuizCommand extends QuizCommand {
  @override
  final name = 'add-quiz';

  @override
  final description = 'Add or replace a quiz from JSON or CLI fields.';

  AddQuizCommand() {
    argParser
      ..addOption(
        'package',
        abbr: 'p',
        help: 'JSON package containing {"quiz": {...}, "questions": [...]}.',
      )
      ..addOption('id', help: 'Quiz id, for example qualite-tests-cli.')
      ..addOption('title', help: 'Quiz title.')
      ..addOption('description', defaultsTo: '', help: 'Quiz description.')
      ..addOption('category', defaultsTo: 'Import', help: 'Quiz category.')
      ..addOption(
        'difficulty',
        defaultsTo: 'intermediaire',
        help: 'Quiz difficulty label.',
      )
      ..addOption('icon', defaultsTo: '📚', help: 'Quiz icon.')
      ..addOption(
        'questions',
        abbr: 'q',
        help: 'Question JSON file containing a JSON array.',
      )
      ..addFlag(
        'replace',
        defaultsTo: false,
        negatable: false,
        help: 'Replace an existing quiz with the same id.',
      );
  }

  @override
  Future<int> run() async {
    final package = await _resolvePackage();
    validateQuizPackage(package);

    final catalogue = await readCatalogue();
    final existingIndex = catalogue.quizzes.indexWhere(
      (quiz) => quiz.id == package.quiz.id,
    );
    final replace = argResults!.flag('replace');
    if (existingIndex != -1 && !replace) {
      throw StateError(
        'Quiz "${package.quiz.id}" already exists. Re-run with --replace.',
      );
    }

    await dataDir.create(recursive: true);
    await File('${dataDir.path}/${package.quiz.fileName}').writeAsString(
      _prettyJson(package.questions.map((q) => q.toJson()).toList()),
    );

    final updatedQuizzes = [...catalogue.quizzes];
    if (existingIndex == -1) {
      updatedQuizzes.add(package.quiz);
    } else {
      updatedQuizzes[existingIndex] = package.quiz;
    }
    await writeCatalogue(Catalogue(updatedQuizzes));

    stdout.writeln(
      'Saved quiz ${package.quiz.id} with ${package.questions.length} questions in ${dataDir.path}.',
    );
    return 0;
  }

  Future<QuizPackage> _resolvePackage() async {
    final packagePath = argResults!['package'] as String?;
    if (packagePath != null) {
      return QuizPackage.fromFile(File(packagePath));
    }

    final id = _requiredOption('id');
    final title = _requiredOption('title');
    final questionsPath = _requiredOption('questions');
    final questions = await readQuestions(File(questionsPath));

    final quiz = Quiz(
      id: id,
      title: title,
      description: argResults!['description'] as String,
      category: argResults!['category'] as String,
      difficulty: argResults!['difficulty'] as String,
      questionCount: questions.length,
      fileName: 'questions-${_slug(id)}.json',
      icon: argResults!['icon'] as String,
    );
    return QuizPackage(quiz, questions);
  }

  String _requiredOption(String name) {
    final value = argResults![name] as String?;
    if (value == null || value.trim().isEmpty) {
      throw UsageException('Missing --$name.', usage);
    }
    return value;
  }
}

class AddQuestionCommand extends QuizCommand {
  @override
  final name = 'add-question';

  @override
  final description = 'Append one question to an existing runtime quiz.';

  AddQuestionCommand() {
    argParser
      ..addOption('quiz-id', help: 'Target runtime quiz id.')
      ..addOption('json', help: 'Question JSON object file.')
      ..addOption('question', help: 'Question text for manual entry.')
      ..addMultiOption(
        'option',
        abbr: 'o',
        help: 'Answer option. Repeat once per option.',
      )
      ..addOption(
        'correct-index',
        help: 'Single correct option index, zero-based.',
      )
      ..addMultiOption(
        'correct-indexes',
        help: 'Multiple correct option indices, zero-based.',
      )
      ..addOption('explanation', help: 'Optional explanation.');
  }

  @override
  Future<int> run() async {
    final quizId = _requiredOption('quiz-id');
    final catalogue = await readCatalogue();
    final quizIndex = catalogue.quizzes.indexWhere((quiz) => quiz.id == quizId);
    if (quizIndex == -1) {
      throw StateError('Unknown runtime quiz "$quizId".');
    }

    final quiz = catalogue.quizzes[quizIndex];
    final questionsFile = File('${dataDir.path}/${quiz.fileName}');
    final questions = await readQuestions(questionsFile);
    final nextId = questions.isEmpty
        ? 1
        : questions
                  .map((question) => question.id)
                  .reduce((a, b) => a > b ? a : b) +
              1;
    final question = await _resolveQuestion(nextId);
    validateQuestion(question);

    final updatedQuestions = [...questions, question];
    await questionsFile.writeAsString(
      _prettyJson(updatedQuestions.map((q) => q.toJson()).toList()),
    );

    final updatedQuiz = Quiz(
      id: quiz.id,
      title: quiz.title,
      description: quiz.description,
      category: quiz.category,
      difficulty: quiz.difficulty,
      questionCount: updatedQuestions.length,
      fileName: quiz.fileName,
      icon: quiz.icon,
    );
    final updatedQuizzes = [...catalogue.quizzes]..[quizIndex] = updatedQuiz;
    await writeCatalogue(Catalogue(updatedQuizzes));

    stdout.writeln('Added question ${question.id} to $quizId.');
    return 0;
  }

  Future<Question> _resolveQuestion(int nextId) async {
    final jsonPath = argResults!['json'] as String?;
    if (jsonPath != null) {
      final data = json.decode(await File(jsonPath).readAsString());
      return Question.fromJson(data as Map<String, dynamic>);
    }

    final text = _requiredOption('question');
    final options = argResults!.multiOption('option');
    if (options.length < 2) {
      throw UsageException('Use --option at least twice.', usage);
    }

    final correctIndexes = argResults!.multiOption('correct-indexes');
    final correctIndex = argResults!['correct-index'] as String?;
    if (correctIndex == null && correctIndexes.isEmpty) {
      throw UsageException('Use --correct-index or --correct-indexes.', usage);
    }

    return Question(
      id: nextId,
      question: text,
      options: options,
      correctIndex: correctIndex == null ? null : int.parse(correctIndex),
      correctIndices: correctIndexes.isEmpty
          ? null
          : correctIndexes.map(int.parse).toList(),
      explanation: argResults!['explanation'] as String?,
    );
  }

  String _requiredOption(String name) {
    final value = argResults![name] as String?;
    if (value == null || value.trim().isEmpty) {
      throw UsageException('Missing --$name.', usage);
    }
    return value;
  }
}

class Catalogue {
  final List<Quiz> quizzes;

  const Catalogue(this.quizzes);

  factory Catalogue.fromJson(Map<String, dynamic> json) {
    return Catalogue(
      (json['quizzes'] as List? ?? [])
          .map((q) => Quiz.fromJson(q as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {'quizzes': quizzes.map((quiz) => quiz.toJson()).toList()};
  }
}

class QuizPackage {
  final Quiz quiz;
  final List<Question> questions;

  const QuizPackage(this.quiz, this.questions);

  static Future<QuizPackage> fromFile(File file) async {
    final data = json.decode(await file.readAsString()) as Map<String, dynamic>;
    final quiz = Quiz.fromJson(data['quiz'] as Map<String, dynamic>);
    final questions = (data['questions'] as List)
        .map((q) => Question.fromJson(q as Map<String, dynamic>))
        .toList();
    return QuizPackage(quiz, questions);
  }
}

Future<List<Question>> readQuestions(File file) async {
  final data = json.decode(await file.readAsString()) as List;
  return data.map((q) => Question.fromJson(q as Map<String, dynamic>)).toList();
}

void validateQuizPackage(QuizPackage package) {
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
      'Quiz "${package.quiz.id}" declares ${package.quiz.questionCount} questions but has ${package.questions.length}.',
    );
  }

  final ids = <int>{};
  for (final question in package.questions) {
    validateQuestion(question);
    if (!ids.add(question.id)) {
      throw StateError(
        'Quiz "${package.quiz.id}" has duplicate question id ${question.id}.',
      );
    }
  }
}

void validateQuestion(Question question) {
  if (question.question.trim().isEmpty) {
    throw StateError('Question ${question.id} text cannot be empty.');
  }
  if (question.options.length < 2) {
    throw StateError('Question ${question.id} must have at least two options.');
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

String _prettyJson(Object value) {
  return '${const JsonEncoder.withIndent('  ').convert(value)}\n';
}

String _slug(String value) {
  final lower = value.toLowerCase();
  final normalized = lower.replaceAll(RegExp(r'[^a-z0-9]+'), '-');
  return normalized.replaceAll(RegExp(r'^-+|-+$'), '');
}
