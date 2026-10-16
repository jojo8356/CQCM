import 'package:flutter/material.dart';

import '../models/notification_settings.dart';
import '../services/notification_plan.dart';
import '../services/notification_service.dart';
import '../services/notification_settings_store.dart';
import '../services/revision_plan.dart';

/// Écran « Rappels » : tout ce qui concerne les notifications système,
/// piloté par le fichier JSON de configuration.
class NotificationsScreen extends StatefulWidget {
  /// Plan déjà chargé (menu ou écran GP) ; rechargé sinon.
  final RevisionPlan? plan;

  const NotificationsScreen({super.key, this.plan});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  RevisionPlan? _plan;
  NotificationSettingsBundle? _bundle;
  NotificationPlan? _notificationPlan;
  NotificationSyncResult? _syncResult;
  List<String> _pending = const [];
  bool _isLoading = true;
  bool _isBusy = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Appelé une seule fois, depuis [initState] : pas de setState avant le
  /// premier `await` (les champs ont déjà leurs valeurs initiales).
  Future<void> _load() async {
    final plan = widget.plan ?? await RevisionPlan.load();
    final bundle = await NotificationSettingsStore.load();
    final overridePath = await NotificationSettingsStore.ensureOverrideFile();
    final deck = plan.catalog.decks.isEmpty ? null : plan.catalog.decks.first;

    final notificationPlan = deck == null
        ? null
        : NotificationPlan.build(
            deckId: deck.id,
            deckTitle: deck.title,
            items: plan.itemsOf(deck.id),
            progressFor: plan.progressFor,
            settings: bundle.settings,
            now: plan.now,
          );

    if (!mounted) return;
    setState(() {
      _plan = plan;
      _bundle = bundle;
      _notificationPlan = notificationPlan;
      _isLoading = false;
      _message = overridePath == null
          ? null
          : 'Fichier de configuration : $overridePath';
    });

    await _refreshPending();
  }

  Future<void> _refreshPending() async {
    final pending = await ReminderNotifications.pendingSummary();
    if (!mounted) return;
    setState(() => _pending = pending);
  }

  Future<void> _run(
    Future<String?> Function() action, {
    String successMessage = 'Rappels synchronisés.',
  }) async {
    setState(() => _isBusy = true);

    // Une erreur du plugin (plateforme absente, permission refusée, test
    // automatique) est affichée comme un message : jamais propagée.
    String? error;
    try {
      error = await action();
    } catch (failure) {
      error = '$failure';
    }

    if (!mounted) return;
    setState(() {
      _isBusy = false;
      _message = error ?? successMessage;
    });
    await _refreshPending();
  }

  Future<void> _syncNow() async {
    final plan = _plan;
    if (plan == null || plan.catalog.decks.isEmpty) return;

    final deck = plan.catalog.decks.first;

    await _run(() async {
      final result = await ReminderNotifications.syncRevisionReminders(
        plan: plan,
        deck: deck,
      );
      if (!mounted) return null;
      setState(() => _syncResult = result);
      return result.error;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Rappels')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_bundle != null) _buildStatusCard(theme, _bundle!.settings),
                const SizedBox(height: 16),
                _buildActions(),
                const SizedBox(height: 16),
                _buildPlannedCard(theme),
                if (_pending.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _buildPendingCard(theme),
                ],
                const SizedBox(height: 16),
                _buildJsonCard(theme),
                const SizedBox(height: 16),
                Text(
                  'Toute la configuration vient du fichier JSON '
                  '(notifications.json) : active les rappels, change l\'heure, '
                  'le fuseau ou les textes, puis relance l\'application. '
                  'Les rappels sont reprogrammés après chaque séance.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
                if (_message != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _message!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ],
              ],
            ),
    );
  }

  Widget _buildStatusCard(ThemeData theme, NotificationSettings settings) {
    final colorScheme = theme.colorScheme;
    final nextFireAt = _notificationPlan?.nextFireAt;
    final initialized = ReminderNotifications.isInitialized;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  settings.enabled && nextFireAt != null
                      ? Icons.notifications_active
                      : Icons.notifications_off,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    settings.enabled
                        ? 'Rappels activés (${settings.timeLabel})'
                        : 'Rappels désactivés',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _InfoLine(label: 'Fuseau', value: settings.timezone.isEmpty
                ? 'celui de l\'appareil'
                : settings.timezone),
            _InfoLine(
              label: 'Mode',
              value: settings.exact
                  ? 'alarme exacte (autorisation spéciale)'
                  : 'approximatif (économe)',
            ),
            _InfoLine(
              label: 'Rappels max',
              value: '${settings.maxNotifications}',
            ),
            _InfoLine(
              label: 'Prochain rappel',
              value: nextFireAt == null
                  ? '—'
                  : NotificationPlan.formatDate(nextFireAt),
            ),
            _InfoLine(
              label: 'Plugin',
              value: initialized
                  ? 'initialisé'
                  : ReminderNotifications.isSupportedPlatform
                  ? 'non initialisé'
                  : 'plateforme non gérée',
            ),
            if (ReminderNotifications.lastError != null)
              _InfoLine(
                label: 'Dernière erreur',
                value: ReminderNotifications.lastError!,
              ),
            if (_syncResult != null) ...[
              const SizedBox(height: 8),
              Text(
                _syncResult!.summary,
                style: theme.textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildActions() {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        FilledButton.icon(
          onPressed: _isBusy ? null : _syncNow,
          icon: const Icon(Icons.sync),
          label: const Text('Synchroniser'),
        ),
        OutlinedButton.icon(
          onPressed: _isBusy
              ? null
              : () => _run(() async {
                  final settings = _bundle?.settings;
                  if (settings == null) return 'Configuration indisponible.';
                  final granted = await ReminderNotifications.requestPermission(
                    settings: settings,
                  );
                  if (granted == null) {
                    return 'Demande d\'autorisation traitée (voir le statut).';
                  }
                  return granted
                      ? 'Autorisation accordée.'
                      : 'Autorisation refusée.';
                }),
          icon: const Icon(Icons.privacy_tip_outlined),
          label: const Text('Autorisation'),
        ),
        OutlinedButton.icon(
          onPressed: _isBusy
              ? null
              : () => _run(
                  () async {
                    final settings = _bundle?.settings;
                    if (settings == null) return 'Configuration indisponible.';
                    return ReminderNotifications.showTestNotification(settings);
                  },
                  successMessage: 'Notification de test envoyée.',
                ),
          icon: const Icon(Icons.science_outlined),
          label: const Text('Notification de test'),
        ),
        OutlinedButton.icon(
          onPressed: _isBusy
              ? null
              : () => _run(
                  () async {
                    await ReminderNotifications.cancelAll();
                    return null;
                  },
                  successMessage: 'Rappels annulés.',
                ),
          icon: const Icon(Icons.cancel_outlined),
          label: const Text('Tout annuler'),
        ),
      ],
    );
  }

  Widget _buildPlannedCard(ThemeData theme) {
    final plan = _notificationPlan;
    if (plan == null) {
      return const SizedBox.shrink();
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Rappels programmés',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(plan.status, style: theme.textTheme.bodySmall),
            const SizedBox(height: 10),
            if (plan.notifications.isEmpty)
              Text(
                'Aucun rappel à programmer.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              )
            else
              for (final reminder in plan.notifications)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        NotificationPlan.formatDate(reminder.fireAt),
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(reminder.title, style: theme.textTheme.bodyMedium),
                      Text(
                        reminder.body,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                      ),
                    ],
                  ),
                ),
          ],
        ),
      ),
    );
  }

  Widget _buildPendingCard(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Enregistrés dans le système',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            for (final line in _pending)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(line, style: theme.textTheme.bodySmall),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildJsonCard(ThemeData theme) {
    final bundle = _bundle;
    if (bundle == null) return const SizedBox.shrink();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Configuration JSON',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            _JsonBlock(title: 'Réglages effectifs', data: bundle.effectiveJson),
            const SizedBox(height: 8),
            _JsonBlock(
              title: 'Surcharge locale (${bundle.hasOverride ? 'présente' : 'absente'})',
              data: bundle.overrideJson ?? '// aucun fichier de surcharge',
            ),
            const SizedBox(height: 8),
            _JsonBlock(
              title: 'Défauts embarqués (assets/data/notifications.json)',
              data: bundle.defaultsJson,
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  final String label;
  final String value;

  const _InfoLine({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ),
          Expanded(
            child: Text(value, style: theme.textTheme.bodySmall),
          ),
        ],
      ),
    );
  }
}

class _JsonBlock extends StatelessWidget {
  final String title;
  final String data;

  const _JsonBlock({required this.title, required this.data});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: 8),
      title: Text(title, style: theme.textTheme.labelLarge),
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: SelectableText(
            data,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
          ),
        ),
      ],
    );
  }
}
