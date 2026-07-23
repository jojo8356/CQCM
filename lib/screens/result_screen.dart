import 'package:flutter/material.dart';
import '../models/quiz.dart';
import '../models/question.dart';
import '../widgets/markdown_text.dart';

class ResultScreen extends StatelessWidget {
  final Quiz quiz;
  final List<Question> questions;
  final List<Set<int>> userAnswers;
  final int score;

  const ResultScreen({
    super.key,
    required this.quiz,
    required this.questions,
    required this.userAnswers,
    required this.score,
  });

  double get percentage => questions.isEmpty ? 0 : score / questions.length * 100;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Résultats'),
        leading: IconButton(
          icon: const Icon(Icons.home),
          onPressed: () => Navigator.of(context).popUntil((route) => route.isFirst),
        ),
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(32),
            color: percentage >= 70
                ? Colors.green.withValues(alpha: 0.1)
                : percentage >= 50
                    ? Colors.orange.withValues(alpha: 0.1)
                    : Colors.red.withValues(alpha: 0.1),
            child: Column(
              children: [
                Text(
                  '${percentage.round()}%',
                  style: Theme.of(context).textTheme.displayMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: percentage >= 70
                            ? Colors.green
                            : percentage >= 50
                                ? Colors.orange
                                : Colors.red,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  '$score / ${questions.length} réponses correctes',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  quiz.title,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colorScheme.outline,
                      ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: questions.length,
              itemBuilder: (context, index) {
                final question = questions[index];
                final userAnswer = userAnswers[index];
                final isCorrect = question.isCorrectAnswer(userAnswer);

                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ExpansionTile(
                    leading: Icon(
                      isCorrect ? Icons.check_circle : Icons.cancel,
                      color: isCorrect ? Colors.green : Colors.red,
                    ),
                    title: Text(
                      'Q${index + 1}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: MarkdownText(data: question.question),
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ...List.generate(question.options.length, (optIndex) {
                              final isUserChoice = userAnswer.contains(optIndex);
                              final isCorrectOption =
                                  question.allCorrectIndices.contains(optIndex);

                              return Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(
                                      isCorrectOption
                                          ? Icons.check
                                          : isUserChoice
                                              ? Icons.close
                                              : Icons.remove,
                                      size: 18,
                                      color: isCorrectOption
                                          ? Colors.green
                                          : isUserChoice
                                              ? Colors.red
                                              : colorScheme.outline,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        question.options[optIndex],
                                        style: TextStyle(
                                          fontWeight: isCorrectOption || isUserChoice
                                              ? FontWeight.w600
                                              : FontWeight.normal,
                                          color: isCorrectOption
                                              ? Colors.green.shade700
                                              : isUserChoice
                                                  ? Colors.red.shade700
                                                  : null,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }),
                            if (question.explanation != null) ...[
                              const SizedBox(height: 8),
                              MarkdownText(
                                data: question.explanation!,
                                textStyle: TextStyle(
                                  fontStyle: FontStyle.italic,
                                  color: colorScheme.outline,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () =>
                      Navigator.of(context).popUntil((route) => route.isFirst),
                  child: const Text('Retour à l\'accueil'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
