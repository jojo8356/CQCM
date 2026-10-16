import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import '../models/quiz.dart';
import '../services/quiz_service.dart';
import '../services/runtime_quiz_store.dart';
import '../widgets/quiz_card.dart';
import 'quiz_screen.dart';

/// Catalogue des QCM, regroupé par catégorie.
///
/// Accessible depuis le bouton « QCM » du menu d'accueil.
class QuizCatalogScreen extends StatefulWidget {
  const QuizCatalogScreen({super.key});

  @override
  State<QuizCatalogScreen> createState() => _QuizCatalogScreenState();
}

class _QuizCatalogScreenState extends State<QuizCatalogScreen> {
  QuizService _quizService = QuizService();
  late Future<List<Quiz>> _quizzesFuture;
  bool _isImporting = false;

  @override
  void initState() {
    super.initState();
    _quizzesFuture = _quizService.loadQuizzes();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('QCM'),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: 'Importer un quiz JSON',
            onPressed: _isImporting ? null : _importQuiz,
            icon: _isImporting
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.upload_file),
          ),
        ],
      ),
      body: FutureBuilder<List<Quiz>>(
        future: _quizzesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Erreur : ${snapshot.error}'));
          }

          final quizzes = snapshot.data!;
          final categories = <String, List<Quiz>>{};
          for (final quiz in quizzes) {
            categories.putIfAbsent(quiz.category, () => []).add(quiz);
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: categories.length,
            itemBuilder: (context, index) {
              final category = categories.keys.elementAt(index);
              final categoryQuizzes = categories[category]!;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (index > 0) const SizedBox(height: 24),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      category,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  ...categoryQuizzes.map(
                    (quiz) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: QuizCard(
                        quiz: quiz,
                        onTap: () => _startQuiz(quiz),
                      ),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  void _startQuiz(Quiz quiz) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => QuizScreen(quiz: quiz)));
  }

  Future<void> _importQuiz() async {
    setState(() {
      _isImporting = true;
    });

    try {
      const typeGroup = XTypeGroup(
        label: 'Quiz JSON',
        extensions: ['json'],
        mimeTypes: ['application/json'],
        uniformTypeIdentifiers: ['public.json'],
        webWildCards: ['application/json'],
      );
      final file = await openFile(acceptedTypeGroups: [typeGroup]);
      if (file == null) {
        return;
      }

      final quiz = await importQuizPackageJson(await file.readAsString());
      final runtimeDataDirectory = await resolveRuntimeDataDirectory(
        _quizService.runtimeDataDirectory,
      );
      if (!mounted) {
        return;
      }

      setState(() {
        _quizService = QuizService(runtimeDataDirectory: runtimeDataDirectory);
        _quizzesFuture = _quizService.loadQuizzes();
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Quiz importé : ${quiz.title}')));
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Import impossible : $error')));
    } finally {
      if (mounted) {
        setState(() {
          _isImporting = false;
        });
      }
    }
  }
}
