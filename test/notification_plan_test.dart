import 'dart:convert';

import 'package:cqcm/models/notification_settings.dart';
import 'package:cqcm/models/revision.dart';
import 'package:cqcm/models/revision_progress.dart';
import 'package:cqcm/services/notification_plan.dart';
import 'package:flutter_test/flutter_test.dart';

RevisionItem _item(String id, String prompt) {
  return RevisionItem(
    id: id,
    project: 'boulangerie',
    prompt: prompt,
    constraints: const [],
    answers: const ['En tant que client je veux payer en carte bancaire'],
  );
}

RevisionProgress _reviewed(String id, DateTime dueAt) {
  return RevisionProgress(
    itemId: id,
    attempts: [
      RevisionAttempt(
        reviewedAt: dueAt.subtract(const Duration(days: 3)),
        accuracy: 1,
        expectedWords: 10,
        matchedWords: 10,
        intervalDays: 3,
        repetitions: 2,
        easeFactor: 2.5,
      ),
    ],
    repetitions: 2,
    intervalDays: 3,
    lastReviewedAt: dueAt.subtract(const Duration(days: 3)),
    dueAt: dueAt,
  );
}

NotificationPlan _build({
  required List<RevisionItem> items,
  required Map<String, RevisionProgress> progress,
  required DateTime now,
  NotificationSettings settings = const NotificationSettings(),
  String deckTitle = 'User stories',
}) {
  return NotificationPlan.build(
    deckId: 'gp-us',
    deckTitle: deckTitle,
    items: items,
    progressFor: (itemId) =>
        progress[itemId] ?? RevisionProgress.initial(itemId),
    settings: settings,
    now: now,
  );
}

void main() {
  final morning = DateTime(2026, 4, 1, 8);

  group('regroupement par jour', () {
    test('les phrases dues partagent un seul rappel', () {
      final items = [
        _item('b1', 'Un client achete du pain'),
        _item('b2', 'Un client paie sans contact'),
        _item('b3', 'Un client paie en especes'),
      ];
      final progress = <String, RevisionProgress>{
        // Deja revue et echue : due aujourd hui.
        'b3': _reviewed('b3', DateTime(2026, 3, 30, 7)),
      };

      final plan = _build(
        items: items,
        progress: progress,
        now: morning,
        settings: const NotificationSettings(timezone: 'Europe/Paris'),
      );

      expect(plan.enabled, isTrue);
      expect(plan.notifications, hasLength(1));

      final reminder = plan.notifications.single;
      expect(reminder.id, 0);
      expect(reminder.fireAt, DateTime(2026, 4, 1, 9));
      expect(reminder.title, 'GP – 3 phrase(s) à réviser');
      expect(reminder.body, 'Commence par : Un client achete du pain');

      final payload = json.decode(reminder.payload) as Map<String, dynamic>;
      expect(payload['deck'], 'gp-us');
      expect(payload['count'], 3);
      expect(payload['date'], '2026-04-01');

      expect(plan.nextFireAt, DateTime(2026, 4, 1, 9));
      expect(plan.status, contains('1 rappel(s) planifié(s)'));
      expect(plan.status, contains('à 09:00'));
      expect(plan.status, contains('Europe/Paris'));
    });

    test('chaque echeance future a son rappel, a l heure configuree', () {
      final items = [
        _item('b1', 'Premiere'),
        _item('b2', 'Deuxieme'),
        _item('b3', 'Troisieme'),
      ];
      final progress = <String, RevisionProgress>{
        'b1': _reviewed('b1', DateTime(2026, 4, 1, 7)),
        'b2': _reviewed('b2', DateTime(2026, 4, 3, 7)),
        'b3': _reviewed('b3', DateTime(2026, 4, 3, 18)),
      };

      final plan = _build(items: items, progress: progress, now: morning);

      expect(plan.notifications, hasLength(2));
      expect(plan.notifications.first.fireAt, DateTime(2026, 4, 1, 9));
      expect(plan.notifications.last.fireAt, DateTime(2026, 4, 3, 9));
      expect(plan.notifications.first.title, 'GP – 1 phrase(s) à réviser');
      expect(plan.notifications.last.title, 'GP – 2 phrase(s) à réviser');
      expect(
        json.decode(plan.notifications.last.payload)['count'],
        2,
      );

      final dates = plan.notifications
          .map((reminder) => NotificationPlan.dayKey(reminder.fireAt))
          .toList();
      expect(dates, ['2026-04-01', '2026-04-03']);
    });

    test('une phrase jamais revue est rappelee des aujourd hui', () {
      final plan = _build(
        items: [_item('b1', 'Nouvelle phrase')],
        progress: const {},
        now: morning,
      );

      expect(plan.notifications.single.fireAt, DateTime(2026, 4, 1, 9));
    });

    test('apres l heure du jour, les phrases dues passent au lendemain', () {
      final plan = _build(
        items: [_item('b1', 'Nouvelle phrase')],
        progress: const {},
        now: DateTime(2026, 4, 1, 10, 30),
      );

      expect(plan.notifications.single.fireAt, DateTime(2026, 4, 2, 9));
    });
  });

  group('reglages', () {
    test('maxNotifications limite le nombre de rappels', () {
      final items = [
        _item('a', 'A'),
        _item('b', 'B'),
        _item('c', 'C'),
        _item('d', 'D'),
      ];
      final progress = <String, RevisionProgress>{
        'a': _reviewed('a', DateTime(2026, 4, 1, 7)),
        'b': _reviewed('b', DateTime(2026, 4, 2, 7)),
        'c': _reviewed('c', DateTime(2026, 4, 3, 7)),
        'd': _reviewed('d', DateTime(2026, 4, 4, 7)),
      };

      final plan = _build(
        items: items,
        progress: progress,
        now: morning,
        settings: const NotificationSettings(maxNotifications: 2),
      );

      expect(plan.notifications, hasLength(2));
      expect(plan.notifications.last.fireAt, DateTime(2026, 4, 2, 9));
    });

    test('rappel desactive : aucun plan, statut explicite', () {
      final plan = _build(
        items: [_item('b1', 'A')],
        progress: const {},
        now: morning,
        settings: const NotificationSettings(enabled: false),
      );

      expect(plan.enabled, isFalse);
      expect(plan.notifications, isEmpty);
      expect(plan.isEmpty, isTrue);
      expect(plan.nextFireAt, isNull);
      expect(plan.status, contains('désactivés'));
    });

    test('heure personnalisee utilisee pour le declenchement', () {
      final plan = _build(
        items: [_item('b1', 'A')],
        progress: const {},
        now: morning,
        settings: const NotificationSettings(hour: 19, minute: 45),
      );

      expect(plan.notifications.single.fireAt, DateTime(2026, 4, 1, 19, 45));
      expect(plan.status, contains('19:45'));
    });

    test('gabarits personnalises : {count}, {deck}, {prompt}, {date}', () {
      final plan = _build(
        items: [_item('b1', 'Phrase de test')],
        progress: const {},
        now: morning,
        deckTitle: 'User stories',
        settings: const NotificationSettings(
          titleTemplate: '{deck} : {count}',
          bodyTemplate: '{date} → {prompt}',
        ),
      );

      final reminder = plan.notifications.single;
      expect(reminder.title, 'User stories : 1');
      expect(reminder.body, '01/04/2026 à 09:00 → Phrase de test');
    });

    test('programme vide : rien a rappeler', () {
      final plan = _build(items: const [], progress: const {}, now: morning);

      expect(plan.notifications, isEmpty);
      expect(plan.status, contains('Aucune phrase au programme'));
      expect(plan.enabled, isTrue);
    });
  });

  group('outils', () {
    test('nextOccurrence choisit aujourd hui ou demain', () {
      expect(
        NotificationPlan.nextOccurrence(
          hour: 9,
          minute: 0,
          now: DateTime(2026, 4, 1, 8),
        ),
        DateTime(2026, 4, 1, 9),
      );
      expect(
        NotificationPlan.nextOccurrence(
          hour: 9,
          minute: 0,
          now: DateTime(2026, 4, 1, 9),
        ),
        DateTime(2026, 4, 2, 9),
      );
    });

    test('formatDate et dayKey', () {
      final date = DateTime(2026, 4, 9, 6, 5);

      expect(NotificationPlan.formatDate(date), '09/04/2026 à 06:05');
      expect(NotificationPlan.dayKey(date), '2026-04-09');
    });

    test('toPrettyJson decrit le plan complet', () {
      final plan = _build(
        items: [_item('b1', 'Phrase')],
        progress: const {},
        now: morning,
      );

      final decoded = json.decode(plan.toPrettyJson()) as Map<String, dynamic>;

      expect(decoded['enabled'], isTrue);
      expect(decoded['status'], isA<String>());
      expect(decoded['settings'], isA<Map<String, dynamic>>());
      expect(decoded['notifications'], hasLength(1));
      final first = (decoded['notifications'] as List).first;
      expect(first['title'], contains('à réviser'));
      expect(first['fireAt'], '2026-04-01T09:00:00.000');
    });
  });
}
