import 'package:flutter/material.dart';

import '../models/revision.dart';
import '../models/revision_progress.dart';
import '../services/revision_plan.dart';
import '../services/revision_stats.dart';
import '../widgets/revision_chart.dart';
import '../widgets/revision_reminder_banner.dart';
import 'revision_session_screen.dart';

/// Écran « Recopier texte » : programme GP, progression et courbe
/// d'apprentissage.
class TextRevisionScreen extends StatefulWidget {
  /// Plan déjà chargé par le menu (évite un second chargement).
  final RevisionPlan? plan;

  const TextRevisionScreen({super.key, this.plan});

  @override
  State<TextRevisionScreen> createState() => _TextRevisionScreenState();
}

class _TextRevisionScreenState extends State<TextRevisionScreen> {
  RevisionPlan? _plan;
  bool _isLoading = true;
  String? _error;
  int _sessionSize = 5;

  @override
  void initState() {
    super.initState();
    if (widget.plan != null) {
      _plan = widget.plan;
      _isLoading = false;
    } else {
      _load();
    }
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final plan = await RevisionPlan.load();
      if (!mounted) return;
      setState(() {
        _plan = plan;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = 'Chargement impossible : $error';
      });
    }
  }

  Future<void> _startSession(List<RevisionItem> items) async {
    final plan = _plan;
    if (plan == null || items.isEmpty) return;

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RevisionSessionScreen(plan: plan, items: items),
      ),
    );
    await _load();
  }

  Future<void> _confirmReset(RevisionPlan plan, RevisionDeck deck) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Réinitialiser la progression ?'),
        content: Text(
          'L\'historique de révision de « ${deck.title} » sera effacé. '
          'Les phrases seront considérées comme jamais révisées.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Réinitialiser'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    await plan.resetAll();
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Recopier texte'),
        actions: [
          IconButton(
            tooltip: 'Recharger',
            onPressed: _plan == null ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_error!, textAlign: TextAlign.center),
        ),
      );
    }

    final plan = _plan!;
    if (plan.catalog.decks.isEmpty) {
      return const Center(child: Text('Aucun programme de révision.'));
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        for (final deck in plan.catalog.decks) ..._deckSection(plan, deck),
      ],
    );
  }

  List<Widget> _deckSection(RevisionPlan plan, RevisionDeck deck) {
    final items = plan.itemsOf(deck.id);
    final reminder = plan.reminderFor(deck.id);
    final stats = plan.statsOf(deck.id);

    final dueItems = plan.dueItemsOf(deck.id);
    final sessionItems = plan.sessionItems(deck.id, size: _sessionSize);

    final projects = <String, List<RevisionItem>>{};
    for (final item in items) {
      projects.putIfAbsent(item.project, () => []).add(item);
    }

    return [
      Text(
        deck.shortLabel.isEmpty ? '${deck.title}:' : '${deck.shortLabel}:',
        style: Theme.of(
          context,
        ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 4),
      Text(
        '${deck.title} · ${deck.subtitle}',
        style: Theme.of(
          context,
        ).textTheme.titleSmall?.copyWith(color: Theme.of(context).colorScheme.outline),
      ),
      const SizedBox(height: 12),
      Text(deck.description, style: Theme.of(context).textTheme.bodyMedium),
      const SizedBox(height: 16),
      RevisionReminderBanner(
        reminder: reminder,
        onStart: () => _startSession(
          dueItems.isEmpty ? sessionItems : dueItems,
        ),
      ),
      const SizedBox(height: 20),
      _StatsCard(stats: stats, subtitle: '${items.length} phrases au programme'),
      const SizedBox(height: 16),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Lancer une séance',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                'Les phrases à réviser passent en premier, puis les moins maîtrisées.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                ),
              ),
              const SizedBox(height: 12),
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 3, label: Text('3')),
                  ButtonSegment(value: 5, label: Text('5')),
                  ButtonSegment(value: 10, label: Text('10')),
                  ButtonSegment(value: 0, label: Text('Tout')),
                ],
                selected: {_sessionSize},
                onSelectionChanged: (selection) {
                  setState(() => _sessionSize = selection.first);
                },
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: sessionItems.isEmpty
                      ? null
                      : () => _startSession(sessionItems),
                  icon: const Icon(Icons.play_arrow),
                  label: Text(
                    'Réviser ${sessionItems.length} phrase'
                    '${sessionItems.length > 1 ? 's' : ''}',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 20),
      for (final entry in projects.entries) ...[
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            entry.key,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        for (final item in entry.value)
          _ItemTile(
            item: item,
            progress: plan.progressFor(item.id),
            now: plan.now,
            onTap: () => _startSession([item]),
          ),
        const SizedBox(height: 16),
      ],
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: () => _confirmReset(plan, deck),
          icon: const Icon(Icons.restart_alt),
          label: const Text('Réinitialiser la progression'),
        ),
      ),
    ];
  }
}

class _StatsCard extends StatelessWidget {
  final RevisionStats stats;
  final String subtitle;

  const _StatsCard({required this.stats, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Courbe d\'apprentissage',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (stats.hasHistory)
                  Icon(
                    stats.isImproving ? Icons.trending_up : Icons.trending_flat,
                    color: stats.isImproving
                        ? Colors.green
                        : theme.colorScheme.outline,
                  ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
            const SizedBox(height: 8),
            RevisionChart(
              values: stats.accuracySeries,
              trendValues: stats.trendSeries,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 20,
              runSpacing: 10,
              children: [
                _Stat(
                  label: 'Taux moyen',
                  value: stats.hasHistory
                      ? '${(stats.averageAccuracy * 100).round()} %'
                      : '—',
                ),
                _Stat(
                  label: 'Dernière',
                  value: stats.hasHistory
                      ? '${(stats.lastAccuracy * 100).round()} %'
                      : '—',
                ),
                _Stat(
                  label: 'Meilleure',
                  value: stats.hasHistory
                      ? '${(stats.bestAccuracy * 100).round()} %'
                      : '—',
                ),
                _Stat(
                  label: 'Révisions',
                  value: '${stats.attemptCount}',
                ),
                _Stat(
                  label: 'Acquises',
                  value: '${stats.masteredItemCount}/${stats.totalItemCount}',
                ),
                _Stat(
                  label: 'Jours d\'affilée',
                  value: '${stats.streakDays}',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;

  const _Stat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.outline,
          ),
        ),
      ],
    );
  }
}

class _ItemTile extends StatelessWidget {
  final RevisionItem item;
  final RevisionProgress progress;
  final DateTime now;
  final VoidCallback onTap;

  const _ItemTile({
    required this.item,
    required this.progress,
    required this.now,
    required this.onTap,
  });

  String get _scheduleLabel {
    if (progress.isNew) return 'Jamais révisée';
    if (progress.isDue(now)) return 'À réviser';
    final days = _dayDelta(now, progress.dueAt!);
    if (days <= 0) return 'À réviser aujourd\'hui';
    return days == 1 ? 'Révision demain' : 'Révision dans $days jours';
  }

  static int _dayDelta(DateTime from, DateTime to) {
    final start = DateTime(from.year, from.month, from.day);
    final end = DateTime(to.year, to.month, to.day);
    return end.difference(start).inDays;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDue = progress.isDue(now);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      item.prompt,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (isDue)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: colorScheme.tertiaryContainer,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        'à réviser',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colorScheme.onTertiaryContainer,
                        ),
                      ),
                    ),
                ],
              ),
              if (item.constraints.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  item.constraints.map((value) => '• $value').join('\n'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.outline,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: progress.mastery,
                        minHeight: 6,
                        backgroundColor: colorScheme.surfaceContainerHighest,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '${(progress.mastery * 100).round()} %',
                    style: theme.textTheme.labelMedium,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                progress.isNew
                    ? _scheduleLabel
                    : '$_scheduleLabel · dernière : ${(progress.lastAccuracy * 100).round()} %'
                          ' · ${progress.attemptCount} révision'
                          '${progress.attemptCount > 1 ? 's' : ''}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.outline,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
