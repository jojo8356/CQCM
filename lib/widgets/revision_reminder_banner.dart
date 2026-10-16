import 'package:flutter/material.dart';

import '../services/revision_plan.dart';

/// Notification de révision : signale les phrases à réviser aujourd'hui et
/// propose de lancer la séance.
class RevisionReminderBanner extends StatelessWidget {
  final RevisionReminder reminder;
  final VoidCallback? onStart;
  final bool compact;

  const RevisionReminderBanner({
    super.key,
    required this.reminder,
    this.onStart,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDue = reminder.shouldNotify;

    final background = isDue
        ? colorScheme.tertiaryContainer
        : colorScheme.surfaceContainerHighest;
    final foreground = isDue
        ? colorScheme.onTertiaryContainer
        : colorScheme.onSurfaceVariant;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(compact ? 12 : 16),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isDue ? Icons.notifications_active : Icons.notifications_none,
            color: foreground,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${reminder.deckTitle} · ${reminder.title}',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: foreground,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  isDue
                      ? '${reminder.detail}\nProchaine révision : ${reminder.nextDueLabel}'
                      : 'Prochaine révision : ${reminder.nextDueLabel}',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: foreground),
                ),
              ],
            ),
          ),
          if (isDue && onStart != null) ...[
            const SizedBox(width: 8),
            FilledButton(
              onPressed: onStart,
              child: const Text('Réviser'),
            ),
          ],
        ],
      ),
    );
  }
}

/// Pastille numérique utilisée sur les boutons du menu.
class ReminderBadge extends StatelessWidget {
  final int count;

  const ReminderBadge({super.key, required this.count});

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();

    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: colorScheme.error,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        '$count',
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: colorScheme.onError,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
