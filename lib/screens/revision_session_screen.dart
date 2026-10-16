import 'package:flutter/material.dart';

import '../models/revision.dart';
import '../models/revision_progress.dart';
import '../services/revision_plan.dart';
import '../services/revision_scheduler.dart';
import '../services/text_scoring.dart';
import '../widgets/word_diff_view.dart';

/// Séance de recopie : une phrase après l'autre, score au mot près,
/// puis mise à jour de la courbe d'apprentissage.
class RevisionSessionScreen extends StatefulWidget {
  final RevisionPlan plan;
  final List<RevisionItem> items;

  const RevisionSessionScreen({
    super.key,
    required this.plan,
    required this.items,
  });

  @override
  State<RevisionSessionScreen> createState() => _RevisionSessionScreenState();
}

class _SessionResult {
  final RevisionItem item;
  final TextScore score;

  const _SessionResult({required this.item, required this.score});
}

class _RevisionSessionScreenState extends State<RevisionSessionScreen> {
  final TextEditingController _controller = TextEditingController();
  final List<_SessionResult> _results = [];

  int _index = 0;
  DateTime _startedAt = DateTime.now();

  TextScore? _score;
  ConstraintCheck? _constraints;
  UserStoryStructure? _structure;
  RevisionProgress? _updatedProgress;
  bool _revealed = false;
  bool _isFinished = false;

  RevisionItem get _item => widget.items[_index];

  bool get _isLastItem => _index == widget.items.length - 1;

  bool get _hasValidated => _score != null || _revealed;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Valide la recopie en cours.
  ///
  /// Le score, les contraintes et le diff s'affichent **immédiatement** :
  /// l'enregistrement de la progression se poursuit en arrière-plan, car un
  /// stockage lent ne doit ni bloquer la séance ni désactiver le bouton
  /// « Valider » de la phrase suivante.
  Future<void> _validate() async {
    final typed = _controller.text;
    if (typed.trim().isEmpty) return;

    final item = _item;
    final score = TextScorer.score(typed, item.answers);
    final constraints = ConstraintCheck.evaluate(
      constraints: item.constraints,
      typed: typed,
      references: item.answers,
    );
    final startedAt = _startedAt;

    setState(() {
      _score = score;
      _constraints = constraints;
      _structure = UserStoryStructure.of(typed);
    });
    _results.add(_SessionResult(item: item, score: score));

    try {
      final updated = await widget.plan.record(
        item: item,
        score: score,
        reviewedAt: DateTime.now(),
        durationSeconds: DateTime.now().difference(startedAt).inSeconds,
      );
      if (!mounted) return;
      // L'utilisateur a pu passer à la phrase suivante pendant l'écriture.
      if (identical(_item, item) && _score == score) {
        setState(() => _updatedProgress = updated);
      }
    } catch (_) {
      // Enregistrement impossible : la séance et le bilan restent justes.
    }
  }

  void _reveal() {
    setState(() {
      _revealed = true;
      _structure = null;
      _constraints = null;
    });
  }

  void _next() {
    if (_isLastItem) {
      setState(() => _isFinished = true);
      return;
    }

    setState(() {
      _index++;
      _controller.clear();
      _score = null;
      _constraints = null;
      _structure = null;
      _updatedProgress = null;
      _revealed = false;
      _startedAt = DateTime.now();
    });
  }

  void _retryFailed() {
    final failed = _results
        .where((result) => !result.score.isValidated)
        .map((result) => result.item)
        .toList();
    if (failed.isEmpty) return;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) =>
            RevisionSessionScreen(plan: widget.plan, items: failed),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _isFinished
              ? 'Séance terminée'
              : 'Phrase ${_index + 1}/${widget.items.length}',
        ),
      ),
      body: _isFinished ? _buildSummary() : _buildQuestion(),
    );
  }

  Widget _buildQuestion() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final progressValue = (_index + (_hasValidated ? 1 : 0)) /
        widget.items.length;

    return Column(
      children: [
        LinearProgressIndicator(value: progressValue, minHeight: 4),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Étroit : l'étiquette du projet cède la place (ellipse) et la
              // mention de droite passe à la ligne au lieu de déborder.
              Row(
                children: [
                  Flexible(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: colorScheme.secondaryContainer,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        _item.project,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: colorScheme.onSecondaryContainer,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'à recopier au mot près',
                      textAlign: TextAlign.end,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.outline,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                _item.prompt,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (_item.constraints.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final constraint in _item.constraints)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: colorScheme.errorContainer,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          constraint,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colorScheme.onErrorContainer,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 16),
              TextField(
                controller: _controller,
                enabled: !_hasValidated,
                autofocus: true,
                minLines: 4,
                maxLines: 8,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  labelText: 'Ta recopie',
                  hintText: 'En tant que …\nJe veux …\nAfin de …',
                  helperText:
                      'Ponctuation, retours à la ligne, majuscules et accents ne comptent pas.',
                  helperMaxLines: 3,
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              if (!_hasValidated)
                Row(
                  children: [
                    Expanded(
                      child: FilledButton(
                        onPressed: _controller.text.trim().isEmpty
                            ? null
                            : _validate,
                        child: const Text('Valider'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    TextButton(
                      onPressed: _reveal,
                      child: const Text('Voir la réponse'),
                    ),
                  ],
                )
              else
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _next,
                    child: Text(
                      _isLastItem ? 'Terminer la séance' : 'Phrase suivante',
                    ),
                  ),
                ),
              if (_hasValidated) ...[
                const SizedBox(height: 20),
                _buildResultPanel(),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildResultPanel() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final score = _score;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (score == null)
          Card(
            color: colorScheme.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                "Réponse révélée : cette phrase n'est pas notée et ne modifie pas ta progression.",
                style: theme.textTheme.bodyMedium,
              ),
            ),
          )
        else
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        '${score.accuracyPercent} %',
                        style: theme.textTheme.displaySmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: _scoreColor(score),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${score.matchedWordCount}/${score.expectedWordCount} mots justes',
                              style: theme.textTheme.titleSmall,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              score.isPerfect
                                  ? 'Recopie exacte, bravo !'
                                  : 'Similarité ${score.similarityPercent} %',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.outline,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (score.isValidated)
                        Icon(Icons.check_circle, color: _scoreColor(score))
                      else
                        Icon(Icons.error_outline, color: _scoreColor(score)),
                    ],
                  ),
                  if (_updatedProgress != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      _nextReviewLabel(_updatedProgress!),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        if (_structure != null || (_constraints?.hasConstraints ?? false)) ...[
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Structure de la user story',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (_structure != null)
                    Wrap(
                      spacing: 10,
                      runSpacing: 8,
                      children: [
                        _StructureChip(
                          label: 'En tant que…',
                          ok: _structure!.hasRole,
                        ),
                        _StructureChip(
                          label: 'Je veux…',
                          ok: _structure!.hasNeed,
                        ),
                        _StructureChip(
                          label: 'Afin de…',
                          ok: _structure!.hasGoal,
                        ),
                      ],
                    ),
                  if (_constraints != null && _constraints!.hasConstraints) ...[
                    const SizedBox(height: 10),
                    Text(
                      _constraintLabel(_constraints!),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: _constraints!.isSatisfied
                            ? Colors.green.shade800
                            : Colors.red.shade800,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
        if (score != null) ...[
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: WordDiffView(score: score),
            ),
          ),
        ],
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _item.hasMultipleAnswers
                      ? 'Réponses acceptées'
                      : 'Réponse attendue',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                for (final answer in _item.answers)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Text(
                      answer,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        height: 1.4,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _constraintLabel(ConstraintCheck check) {
    if (!check.isSatisfied) {
      return 'À corriger : « ${check.violatedWords.join(', ')} » est interdit par l\'énoncé.';
    }
    if (check.creditedWords.isNotEmpty) {
      return 'Contrainte respectée (« ${check.creditedWords.join(', ')} » est toléré : '
          'il figure dans la réponse officielle).';
    }
    return 'Contrainte respectée (« ${check.avoidedWords.join(', ')} » absent de ta copie).';
  }

  Color _scoreColor(TextScore score) {
    final percent = score.accuracyPercent;
    if (percent >= 95) return Colors.green.shade700;
    if (percent >= 80) return Colors.orange.shade800;
    return Colors.red.shade700;
  }

  String _nextReviewLabel(RevisionProgress progress) {
    final days = progress.intervalDays;
    if (days <= 0) {
      return 'À revoir aujourd\'hui (intervalle remis à zéro).';
    }
    return 'Prochaine révision dans $days jour${days > 1 ? 's' : ''}.';
  }

  Widget _buildSummary() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final scored = _results.length;
    final average = scored == 0
        ? 0
        : _results
                  .map((result) => result.score.accuracy)
                  .reduce((a, b) => a + b) /
              scored;
    final validated = _results
        .where((result) => result.score.isValidated)
        .length;
    final failed = _results.where((result) => !result.score.isValidated);

    final nextDueAt = RevisionScheduler.nextDueAt(
      widget.items.map((item) => widget.plan.progressFor(item.id)),
      now: DateTime.now(),
    );

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Bilan de la séance',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 12),
                if (scored == 0)
                  Text(
                    'Aucune phrase notée pendant cette séance.',
                    style: theme.textTheme.titleMedium,
                  )
                else
                  Row(
                    children: [
                      Text(
                        '${(average * 100).round()} %',
                        style: theme.textTheme.displaySmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: average >= 0.95
                              ? Colors.green.shade700
                              : average >= 0.8
                              ? Colors.orange.shade800
                              : Colors.red.shade700,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'recopie moyenne\n$validated/$scored validée'
                          '${validated > 1 ? 's' : ''} (seuil 95 %)',
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                const SizedBox(height: 12),
                Text(
                  nextDueAt == null
                      ? 'Toutes les phrases de la séance restent à revoir aujourd\'hui.'
                      : 'Prochaine révision planifiée : ${_formatDate(nextDueAt)}.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.outline,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        for (var index = 0; index < _results.length; index++)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: Icon(
                _results[index].score.isValidated
                    ? Icons.check_circle
                    : Icons.error_outline,
                color: _scoreColor(_results[index].score),
              ),
              title: Text(
                _results[index].item.prompt,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                '${_results[index].score.accuracyPercent} %'
                ' · ${_results[index].score.matchedWordCount}'
                '/${_results[index].score.expectedWordCount} mots',
              ),
              trailing: Text(
                'F${index + 1}',
                style: theme.textTheme.labelMedium,
              ),
            ),
          ),
        const SizedBox(height: 8),
        if (failed.isNotEmpty)
          FilledButton.icon(
            onPressed: _retryFailed,
            icon: const Icon(Icons.replay),
            label: Text(
              'Refaire les ${failed.length} phrase'
              '${failed.length > 1 ? 's' : ''} ratée'
              '${failed.length > 1 ? 's' : ''}',
            ),
          ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Retour au programme'),
        ),
        const SizedBox(height: 8),
        Text(
          'Historique enregistré : la courbe d\'apprentissage se met à jour.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.outline,
          ),
        ),
      ],
    );
  }

  static String _formatDate(DateTime date) {
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    return '$day/$month/${date.year} à $hour:$minute';
  }
}

class _StructureChip extends StatelessWidget {
  final String label;
  final bool ok;

  const _StructureChip({required this.label, required this.ok});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = ok ? Colors.green.shade700 : Colors.red.shade700;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(ok ? Icons.check : Icons.close, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}
