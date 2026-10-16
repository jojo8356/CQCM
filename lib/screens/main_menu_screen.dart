import 'package:flutter/material.dart';

import '../services/revision_plan.dart';
import '../widgets/revision_reminder_banner.dart';
import 'quiz_catalog_screen.dart';
import 'text_revision_screen.dart';

/// Écran d'accueil : un menu à deux entrées, QCM et Recopier texte.
class MainMenuScreen extends StatefulWidget {
  const MainMenuScreen({super.key});

  @override
  State<MainMenuScreen> createState() => _MainMenuScreenState();
}

class _MainMenuScreenState extends State<MainMenuScreen> {
  RevisionPlan? _plan;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadReminder();
  }

  Future<void> _loadReminder() async {
    try {
      final plan = await RevisionPlan.load();
      if (!mounted) return;
      setState(() {
        _plan = plan;
        _isLoading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _plan = null;
        _isLoading = false;
        _error = 'Rappels indisponibles : $error';
      });
    }
  }

  RevisionReminder? get _reminder {
    final plan = _plan;
    if (plan == null || plan.catalog.decks.isEmpty) return null;
    return plan.reminderFor(plan.catalog.decks.first.id);
  }

  Future<void> _openQuizCatalog() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const QuizCatalogScreen()),
    );
  }

  Future<void> _openTextRevision() async {
    final plan = _plan;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TextRevisionScreen(plan: plan),
      ),
    );
    await _loadReminder();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final reminder = _reminder;

    return Scaffold(
      appBar: AppBar(title: const Text('CQCM'), centerTitle: true),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
        children: [
          Text(
            'Que veux-tu réviser ?',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Choisis un mode dans le menu.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
          const SizedBox(height: 24),
          _MenuCard(
            icon: Icons.checklist_rtl,
            title: 'QCM',
            subtitle:
                'Questions à choix unique ou multiple, correction et score détaillé.',
            onTap: _openQuizCatalog,
          ),
          const SizedBox(height: 14),
          _MenuCard(
            icon: Icons.edit_note,
            title: 'Recopier texte',
            subtitle:
                'GP : recopie les user stories au mot près, score par mot, révisions espacées.',
            badge: reminder?.shouldNotify == true ? reminder!.dueCount : 0,
            onTap: _openTextRevision,
          ),
          const SizedBox(height: 24),
          if (_isLoading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(8),
                child: CircularProgressIndicator(),
              ),
            )
          else if (reminder != null)
            RevisionReminderBanner(
              reminder: reminder,
              compact: true,
              onStart: _openTextRevision,
            ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MenuCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final int badge;
  final VoidCallback onTap;

  const _MenuCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.badge = 0,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 1,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: colorScheme.onPrimaryContainer),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          title,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (badge > 0) ...[
                          const SizedBox(width: 8),
                          ReminderBadge(count: badge),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.outline,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right, color: colorScheme.outline),
            ],
          ),
        ),
      ),
    );
  }
}
