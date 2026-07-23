import 'package:flutter/material.dart';
import '../models/quiz.dart';
import '../models/question.dart';
import '../services/quiz_service.dart';
import '../widgets/markdown_text.dart';
import '../widgets/option_tile.dart';
import '../widgets/progress_bar.dart';
import 'result_screen.dart';

class QuizScreen extends StatefulWidget {
  final Quiz quiz;

  const QuizScreen({super.key, required this.quiz});

  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> {
  final _quizService = QuizService();
  late Future<List<Question>> _questionsFuture;

  List<Question> _questions = [];
  int _currentIndex = 0;
  Set<int> _selectedIndices = {};
  bool _hasValidated = false;
  int _score = 0;
  final List<Set<int>> _userAnswers = [];

  @override
  void initState() {
    super.initState();
    _questionsFuture = _quizService.loadQuestions(widget.quiz.fileName);
    _questionsFuture.then((questions) {
      setState(() {
        _questions = questions;
      });
    });
  }

  Question get _currentQuestion => _questions[_currentIndex];
  bool get _isLastQuestion => _currentIndex == _questions.length - 1;

  void _onOptionTap(int index) {
    if (_hasValidated) return;

    setState(() {
      if (_currentQuestion.isMultipleChoice) {
        if (_selectedIndices.contains(index)) {
          _selectedIndices.remove(index);
        } else {
          _selectedIndices.add(index);
        }
      } else {
        _selectedIndices = {index};
      }
    });
  }

  void _validate() {
    if (_selectedIndices.isEmpty) return;

    setState(() {
      _hasValidated = true;
      if (_currentQuestion.isCorrectAnswer(_selectedIndices)) {
        _score++;
      }
      _userAnswers.add(Set.from(_selectedIndices));
    });
  }

  void _next() {
    if (_isLastQuestion) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => ResultScreen(
            quiz: widget.quiz,
            questions: _questions,
            userAnswers: _userAnswers,
            score: _score,
          ),
        ),
      );
      return;
    }

    setState(() {
      _currentIndex++;
      _selectedIndices = {};
      _hasValidated = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.quiz.title),
      ),
      body: FutureBuilder<List<Question>>(
        future: _questionsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Erreur : ${snapshot.error}'));
          }
          if (_questions.isEmpty) {
            return const Center(child: Text('Aucune question disponible.'));
          }

          final question = _currentQuestion;

          return Column(
            children: [
              QuizProgressBar(
                current: _currentIndex + 1,
                total: _questions.length,
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Question ${_currentIndex + 1}/${_questions.length}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.outline,
                            ),
                      ),
                      const SizedBox(height: 8),
                      MarkdownText(
                        data: question.question,
                        textStyle: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                      if (question.isMultipleChoice) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Theme.of(context)
                                .colorScheme
                                .tertiaryContainer,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'Plusieurs réponses possibles',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onTertiaryContainer,
                                ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),
                      ...List.generate(question.options.length, (index) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: OptionTile(
                            text: question.options[index],
                            index: index,
                            isSelected: _selectedIndices.contains(index),
                            isMultipleChoice: question.isMultipleChoice,
                            hasValidated: _hasValidated,
                            isCorrect:
                                question.allCorrectIndices.contains(index),
                            onTap: () => _onOptionTap(index),
                          ),
                        );
                      }),
                      if (_hasValidated && question.explanation != null) ...[
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Explication',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleSmall
                                    ?.copyWith(fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 8),
                              MarkdownText(data: question.explanation!),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _selectedIndices.isEmpty
                          ? null
                          : _hasValidated
                              ? _next
                              : _validate,
                      child: Text(
                        _hasValidated
                            ? (_isLastQuestion ? 'Voir les résultats' : 'Suivant')
                            : 'Valider',
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
