import 'dart:io';
import 'dart:math';

import 'package:cqcm/services/revision_plan.dart';
import 'package:cqcm/services/revision_service.dart';
import 'package:cqcm/services/text_scoring.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final now = DateTime(2026, 4, 1, 18);

  group('RevisionCatalog', () {
    test('charge le programme GP depuis les assets', () async {
      final service = RevisionService();
      final catalog = await service.loadCatalog();

      expect(catalog.decks, hasLength(1));
      final deck = catalog.decks.single;
      expect(deck.id, 'gp-us');
      expect(deck.title, 'GP – User stories');
      expect(deck.shortLabel, 'GP');
      expect(deck.itemCount, 12);

      final items = catalog.itemsOf(deck.id);
      expect(items, hasLength(deck.itemCount));
      expect(items.map((item) => item.id).toSet(), hasLength(items.length));
      expect(
        items.map((item) => item.project).toSet(),
        containsAll([
          'Projet boulangerie',
          'Projet notes des étudiants',
          'Projet EDT',
        ]),
      );

      for (final item in items) {
        expect(item.prompt, isNotEmpty, reason: '${item.id} doit avoir un énoncé');
        expect(
          item.answers,
          isNotEmpty,
          reason: '${item.id} doit proposer une réponse de référence',
        );
        expect(
          UserStoryStructure.of(item.referenceAnswer).isComplete,
          isTrue,
          reason: '${item.id} doit être une user story complète',
        );
      }
    });

    test('les énoncés conservent leurs contraintes', () async {
      final catalog = await RevisionService().loadCatalog();
      final items = catalog.itemsOf('gp-us');

      final withoutPay = items.singleWhere(
        (item) => item.id == 'us-boulangerie-2',
      );
      final notes = items.singleWhere((item) => item.id == 'us-notes-1');
      final edt = items.singleWhere((item) => item.id == 'us-edt-2');

      expect(withoutPay.constraints, ['ne pas utiliser le verbe payer']);
      expect(TextScorer.forbiddenWordsOf(withoutPay.constraints.single), [
        'payer',
      ]);
      expect(
        TextScorer.forbiddenWordsOf(notes.constraints.single),
        ['gerer'],
      );
      expect(edt.constraints, isEmpty);
      expect(edt.hasMultipleAnswers, isTrue, reason: 'le cas EDT admet « OU »');
    });
  });

  group('RevisionPlan', () {
    late Directory directory;
    late RevisionService service;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('cqcm_revision_test_');
      service = RevisionService(dataDirectory: directory.path);
      addTearDown(() async {
        if (await directory.exists()) {
          await directory.delete(recursive: true);
        }
      });
    });

    test('un programme neuf a toutes ses phrases à réviser', () async {
      final plan = await RevisionPlan.load(service: service, now: now);

      final reminder = plan.reminderFor('gp-us');

      expect(reminder.totalCount, 12);
      expect(reminder.dueCount, 12);
      expect(reminder.newCount, 12);
      expect(reminder.shouldNotify, isTrue);
      expect(reminder.title, '12 phrases à réviser');
      expect(reminder.nextDueAt, isNull);
      expect(plan.statsOf('gp-us').hasHistory, isFalse);
    });

    test('la séance tire les phrases au hasard parmi celles à réviser', () async {
      final plan = await RevisionPlan.load(service: service, now: now);
      final allIds = plan.itemsOf('gp-us').map((item) => item.id).toSet();

      final session = plan.sessionItems('gp-us', size: 3, random: Random(7));
      final replay = plan.sessionItems('gp-us', size: 3, random: Random(7));

      expect(session, hasLength(3));
      expect(session.map((item) => item.id).toSet(), hasLength(3));
      expect(
        session.every((item) => allIds.contains(item.id)),
        isTrue,
      );
      expect(
        replay.map((item) => item.id).toList(),
        session.map((item) => item.id).toList(),
        reason: 'même graine : même tirage',
      );

      expect(plan.sessionItems('gp-us', size: 0), hasLength(12));
      expect(
        plan.sessionItems('gp-us', size: 12).map((item) => item.id).toSet(),
        allIds,
      );
    });

    test('une recopie validée est enregistrée sur disque', () async {
      final plan = await RevisionPlan.load(service: service, now: now);
      final item = plan.itemsOf('gp-us').first;
      final score = TextScorer.score(item.referenceAnswer, item.answers);

      final updated = await plan.record(
        item: item,
        score: score,
        reviewedAt: now,
      );

      expect(score.accuracyPercent, 100);
      expect(updated.repetitions, 1);
      expect(updated.dueAt, now.add(const Duration(days: 1)));

      final reloaded = await RevisionPlan.load(service: service, now: now);
      final stored = reloaded.progressFor(item.id);

      expect(stored.attemptCount, 1);
      expect(stored.attempts.single.accuracyPercent, 100);
      expect(stored.dueAt, now.add(const Duration(days: 1)));
      expect(reloaded.reminderFor('gp-us').dueCount, 11);
      expect(reloaded.reminderFor('gp-us').newCount, 11);
    });

    test('une phrase révisée sort de la file d\'attente', () async {
      final plan = await RevisionPlan.load(service: service, now: now);
      final items = plan.itemsOf('gp-us');
      final first = items.first;

      await plan.record(
        item: first,
        score: TextScorer.score(first.referenceAnswer, first.answers),
        reviewedAt: now,
      );

      final next = plan.sessionItems('gp-us', size: 2, random: Random(3));

      expect(next.map((item) => item.id), isNot(contains(first.id)));
      expect(next, hasLength(2));
    });

    test('une recopie ratée reste à revoir le jour même', () async {
      final plan = await RevisionPlan.load(service: service, now: now);
      final item = plan.itemsOf('gp-us').first;

      await plan.record(
        item: item,
        score: TextScorer.score('En tant que client', item.answers),
        reviewedAt: now,
      );

      final stored = plan.progressFor(item.id);

      expect(stored.intervalDays, 0);
      expect(stored.repetitions, 0);
      expect(stored.isDue(now), isTrue);
      expect(plan.dueItemsOf('gp-us'), hasLength(12));
    });

    test('la progression peut être réinitialisée', () async {
      final plan = await RevisionPlan.load(service: service, now: now);
      final item = plan.itemsOf('gp-us').first;

      await plan.record(
        item: item,
        score: TextScorer.score(item.referenceAnswer, item.answers),
        reviewedAt: now,
      );
      await plan.resetItem(item.id);
      expect(plan.progressFor(item.id).isNew, isTrue);

      await plan.record(
        item: item,
        score: TextScorer.score(item.referenceAnswer, item.answers),
        reviewedAt: now,
      );
      await plan.resetAll();

      final reloaded = await RevisionPlan.load(service: service, now: now);
      expect(reloaded.progressMap, isEmpty);
      expect(reloaded.reminderFor('gp-us').dueCount, 12);
    });
  });
}
