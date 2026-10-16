/// Construction des rappels système à programmer.
///
/// Entièrement en Dart pur : le plan se déduit de la progression enregistrée
/// (JSON) et des réglages (JSON), ce qui le rend testable sans plugin et
/// visible depuis l'application sous forme de JSON.
library;

import 'dart:convert';

import '../models/notification_settings.dart';
import '../models/revision.dart';
import '../models/revision_progress.dart';

/// Un rappel prêt à être programmé dans le système.
class ReminderNotification {
  final int id;
  final DateTime fireAt;
  final String title;
  final String body;

  /// Charge utile JSON transmise quand l'utilisateur touche la notification.
  final String payload;

  const ReminderNotification({
    required this.id,
    required this.fireAt,
    required this.title,
    required this.body,
    required this.payload,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'fireAt': fireAt.toIso8601String(),
      'title': title,
      'body': body,
      'payload': payload,
    };
  }
}

class NotificationPlan {
  final bool enabled;
  final NotificationSettings settings;
  final List<ReminderNotification> notifications;

  /// Explication lisible : pourquoi autant (ou pas) de rappels.
  final String status;

  const NotificationPlan({
    required this.enabled,
    required this.settings,
    required this.notifications,
    required this.status,
  });

  bool get isEmpty => notifications.isEmpty;

  /// Prochain rappel, ou null si rien n'est planifié.
  DateTime? get nextFireAt {
    if (notifications.isEmpty) return null;
    return notifications.first.fireAt;
  }

  /// Construit le plan à partir du programme et de la progression.
  ///
  /// Une notification est prévue par **jour** où des phrases deviennent à
  /// réviser : le texte indique combien de phrases et laquelle commencer.
  static NotificationPlan build({
    required String deckId,
    required String deckTitle,
    required List<RevisionItem> items,
    required RevisionProgress Function(String itemId) progressFor,
    required NotificationSettings settings,
    required DateTime now,
  }) {
    if (!settings.enabled) {
      return NotificationPlan(
        enabled: false,
        settings: settings,
        notifications: const [],
        status: 'Rappels désactivés (notifications.json).',
      );
    }
    if (items.isEmpty) {
      return NotificationPlan(
        enabled: true,
        settings: settings,
        notifications: const [],
        status: 'Aucune phrase au programme : rien à rappeler.',
      );
    }

    final slots = <String, List<RevisionItem>>{};
    final fireAtByDay = <String, DateTime>{};

    for (final item in items) {
      final progress = progressFor(item.id);
      final dueMoment = _effectiveDueMoment(progress, now);

      var fireAt = DateTime(
        dueMoment.year,
        dueMoment.month,
        dueMoment.day,
        settings.hour,
        settings.minute,
      );
      if (!fireAt.isAfter(now)) {
        fireAt = nextOccurrence(
          hour: settings.hour,
          minute: settings.minute,
          now: now,
        );
      }

      final key = dayKey(fireAt);
      fireAtByDay[key] = fireAt;
      slots.putIfAbsent(key, () => <RevisionItem>[]).add(item);
    }

    final days = slots.keys.toList()
      ..sort((a, b) => fireAtByDay[a]!.compareTo(fireAtByDay[b]!));

    final notifications = <ReminderNotification>[];
    for (final key in days.take(settings.maxNotifications)) {
      final dayItems = slots[key]!;
      final fireAt = fireAtByDay[key]!;
      final count = dayItems.length;
      final firstPrompt = dayItems.first.prompt;

      notifications.add(
        ReminderNotification(
          id: notifications.length,
          fireAt: fireAt,
          title: render(
            settings.titleTemplate,
            count: count,
            deck: deckTitle,
            prompt: firstPrompt,
            date: fireAt,
          ),
          body: render(
            settings.bodyTemplate,
            count: count,
            deck: deckTitle,
            prompt: firstPrompt,
            date: fireAt,
          ),
          payload: json.encode({
            'deck': deckId,
            'count': count,
            'date': key,
          }),
        ),
      );
    }

    return NotificationPlan(
      enabled: true,
      settings: settings,
      notifications: notifications,
      status: notifications.isEmpty
          ? 'Aucun rappel planifié.'
          : '${notifications.length} rappel(s) planifié(s) '
                'à ${settings.timeLabel}${settings.timezone.isEmpty ? '' : ' (${settings.timezone})'}.',
    );
  }

  /// Prochain déclenchement de l'heure configurée (aujourd'hui ou demain).
  static DateTime nextOccurrence({
    required int hour,
    required int minute,
    required DateTime now,
  }) {
    final today = DateTime(now.year, now.month, now.day, hour, minute);
    if (today.isAfter(now)) return today;
    return today.add(const Duration(days: 1));
  }

  static String dayKey(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }

  static String formatDate(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    return '$day/$month/${date.year} à $hour:$minute';
  }

  /// Remplace `{count}`, `{prompt}`, `{deck}` et `{date}` dans un gabarit.
  static String render(
    String template, {
    required int count,
    required String deck,
    required String prompt,
    required DateTime date,
  }) {
    return template
        .replaceAll('{count}', '$count')
        .replaceAll('{prompt}', prompt)
        .replaceAll('{deck}', deck)
        .replaceAll('{date}', formatDate(date));
  }

  static DateTime _effectiveDueMoment(RevisionProgress progress, DateTime now) {
    if (progress.isNew) return now;
    final dueAt = progress.dueAt;
    if (dueAt == null || dueAt.isBefore(now)) return now;
    return dueAt;
  }

  /// Représentation JSON du plan (affichée dans l'écran Rappels).
  String toPrettyJson() {
    return '${const JsonEncoder.withIndent('  ').convert({
      'enabled': enabled,
      'status': status,
      'settings': settings.toJson(),
      'notifications': notifications
          .map((notification) => notification.toJson())
          .toList(),
    })}\n';
  }
}
