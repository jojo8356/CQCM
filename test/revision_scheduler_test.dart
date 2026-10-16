import 'package:cqcm/models/revision_progress.dart';
import 'package:cqcm/services/revision_scheduler.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final day1 = DateTime(2026, 3, 2, 9);

  RevisionProgress schedule(
    RevisionProgress progress,
    double accuracy,
    DateTime reviewedAt,
  ) {
    return RevisionScheduler.apply(
      progress: progress,
      accuracy: accuracy,
      reviewedAt: reviewedAt,
    );
  }

  group('RevisionScheduler.qualityFor', () {
    test('traduit le taux de validation en note de qualité', () {
      expect(RevisionScheduler.qualityFor(1.0), 5);
      expect(RevisionScheduler.qualityFor(0.99), 4);
      expect(RevisionScheduler.qualityFor(0.95), 3);
      expect(RevisionScheduler.qualityFor(0.9), 2);
      expect(RevisionScheduler.qualityFor(0.6), 1);
      expect(RevisionScheduler.qualityFor(0.2), 0);
    });
  });

  group('RevisionScheduler.apply', () {
    test('une recopie parfaite programme la révision à J+1', () {
      final progress = schedule(RevisionProgress.initial('us-1'), 1.0, day1);

      expect(progress.repetitions, 1);
      expect(progress.intervalDays, 1);
      expect(progress.dueAt, day1.add(const Duration(days: 1)));
      expect(progress.easeFactor, closeTo(2.6, 1e-9));
      expect(progress.attempts, hasLength(1));
      expect(progress.attempts.single.accuracyPercent, 100);
      expect(progress.isMastered, isFalse);
      expect(progress.isDue(day1.add(const Duration(days: 2))), isTrue);
      expect(progress.isDue(day1), isFalse);
    });

    test('les intervalles s\'allongent : 1, 3, 7 puis 20 jours', () {
      var progress = RevisionProgress.initial('us-1');
      final intervals = <int>[];

      for (var index = 0; index < 4; index++) {
        progress = schedule(
          progress,
          1.0,
          day1.add(Duration(days: index * 30)),
        );
        intervals.add(progress.intervalDays);
      }

      expect(intervals, [1, 3, 7, 20]);
      expect(progress.repetitions, 4);
      expect(progress.easeFactor, closeTo(2.9, 1e-9));
      expect(progress.attemptCount, 4);
    });

    test('un taux sous 95 % casse la série et ramène la phrase au jour même', () {
      var progress = RevisionProgress.initial('us-1');
      for (var index = 0; index < 3; index++) {
        progress = schedule(progress, 1.0, day1.add(Duration(days: index)));
      }
      final easeBefore = progress.easeFactor;

      final failed = schedule(progress, 0.88, day1.add(const Duration(days: 4)));

      expect(failed.repetitions, 0);
      expect(failed.intervalDays, 0);
      expect(failed.dueAt, day1.add(const Duration(days: 4)));
      expect(failed.easeFactor, lessThan(easeBefore));
      expect(failed.easeFactor, closeTo(easeBefore - 0.32, 1e-9));
      expect(failed.attempts, hasLength(4));
      expect(failed.isDue(day1.add(const Duration(days: 4))), isTrue);
    });

    test('le seuil de validation est strict : 94 % échoue, 95 % passe', () {
      final almost = schedule(RevisionProgress.initial('us-1'), 0.94, day1);
      final enough = schedule(RevisionProgress.initial('us-1'), 0.95, day1);

      expect(almost.repetitions, 0);
      expect(almost.dueAt, day1);
      expect(enough.repetitions, 1);
      expect(enough.intervalDays, 1);
    });

    test('le facteur de facilité ne descend pas sous 1.3', () {
      var progress = RevisionProgress.initial('us-1');
      for (var index = 0; index < 10; index++) {
        progress = schedule(progress, 0.1, day1.add(Duration(days: index)));
      }

      expect(progress.easeFactor, closeTo(RevisionScheduler.minEaseFactor, 1e-9));
    });

    test('les intervalles restent bornés', () {
      expect(
        RevisionScheduler.intervalFor(
          repetitions: 9,
          previousIntervalDays: 170,
          easeFactor: 3.0,
        ),
        RevisionScheduler.maxIntervalDays,
      );
    });

    test('la sérialisation JSON conserve la progression', () {
      final progress = schedule(RevisionProgress.initial('us-1'), 1.0, day1);
      final restored = RevisionProgress.fromJson(progress.toJson());

      expect(restored.itemId, 'us-1');
      expect(restored.repetitions, 1);
      expect(restored.intervalDays, 1);
      expect(restored.lastReviewedAt, progress.lastReviewedAt);
      expect(restored.dueAt, progress.dueAt);
      expect(restored.attempts.single.matchedWords, progress.attempts.single.matchedWords);
    });
  });

  group('RevisionScheduler.planning', () {
    test('dueOnly ne garde que les phrases à réviser', () {
      final due = schedule(RevisionProgress.initial('us-1'), 0.5, day1);
      final later = schedule(RevisionProgress.initial('us-2'), 1.0, day1);

      final dueNow = RevisionScheduler.dueOnly(
        [due, later],
        now: day1.add(const Duration(hours: 1)),
      );

      expect(dueNow.map((progress) => progress.itemId), ['us-1']);
      expect(dueNow.single.isNew, isFalse);
    });

    test('nextDueAt renvoie la prochaine échéance future', () {
      final soon = schedule(RevisionProgress.initial('us-1'), 0.95, day1);
      final later = schedule(RevisionProgress.initial('us-2'), 1.0, day1);

      expect(
        RevisionScheduler.nextDueAt([soon, later], now: day1),
        day1.add(const Duration(days: 1)),
      );
      expect(
        RevisionScheduler.nextDueAt(
          [soon, later],
          now: day1.add(const Duration(days: 30)),
        ),
        isNull,
      );
    });
  });
}
