import 'package:cqcm/models/revision_progress.dart';
import 'package:cqcm/services/revision_scheduler.dart';
import 'package:cqcm/services/revision_stats.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final day1 = DateTime(2026, 5, 4, 8);

  RevisionProgress attempt(
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

  test('sans historique, la courbe est vide', () {
    final stats = RevisionStats.from(
      [RevisionProgress.initial('us-1'), RevisionProgress.initial('us-2')],
      now: day1,
    );

    expect(stats.hasHistory, isFalse);
    expect(stats.accuracySeries, isEmpty);
    expect(stats.trendSeries, isEmpty);
    expect(stats.averageAccuracy, 0);
    expect(stats.dueItemCount, 2);
    expect(stats.reviewedItemCount, 0);
    expect(stats.nextDueAt, isNull);
    expect(stats.streakDays, 0);
  });

  test('la courbe suit les tentatives dans l\'ordre chronologique', () {
    var late = RevisionProgress.initial('us-late');
    late = attempt(late, 1.0, day1.add(const Duration(days: 3)));

    var early = RevisionProgress.initial('us-early');
    early = attempt(early, 0.5, day1);
    early = attempt(early, 0.6, day1.add(const Duration(days: 1)));

    final stats = RevisionStats.from([late, early], now: day1, window: 2);

    expect(stats.accuracySeries, [0.5, 0.6, 1.0]);
    expect(stats.trendSeries, [0.5, 0.55, 0.8]);
    expect(stats.attemptCount, 3);
    expect(stats.reviewedItemCount, 2);
    expect(stats.bestAccuracy, 1.0);
    expect(stats.lastAccuracy, 1.0);
    expect(stats.averageAccuracy, closeTo(0.7, 1e-9));
    expect(stats.isImproving, isTrue);
    expect(stats.lastReviewedAt, day1.add(const Duration(days: 3)));
  });

  test('la série de jours compte les jours consécutifs révisés', () {
    var progress = RevisionProgress.initial('us-1');
    progress = attempt(progress, 0.9, day1);
    progress = attempt(progress, 1.0, day1.add(const Duration(days: 1)));

    expect(RevisionStats.from([progress], now: day1).streakDays, 2);
    expect(
      RevisionStats.from(
        [progress],
        now: day1.add(const Duration(days: 1, hours: 20)),
      ).streakDays,
      2,
    );
    expect(
      RevisionStats.from(
        [progress],
        now: day1.add(const Duration(days: 5)),
      ).streakDays,
      0,
    );
  });

  test('les phrases acquises et les échéances sont comptées', () {
    var mastered = RevisionProgress.initial('us-1');
    for (var index = 0; index < 5; index++) {
      mastered = attempt(
        mastered,
        1.0,
        day1.add(Duration(days: index * 10)),
      );
    }
    final due = RevisionProgress.initial('us-2');

    final now = day1.add(const Duration(days: 41));
    final stats = RevisionStats.from([mastered, due], now: now);

    expect(mastered.isMastered, isTrue);
    expect(mastered.mastery, 1.0);
    expect(stats.masteredItemCount, 1);
    expect(stats.dueItemCount, 1);
    expect(stats.nextDueAt, isNotNull);
    expect(stats.nextDueAt!.isAfter(now), isTrue);
  });

  test('le graphique peut tracer un point unique', () {
    var progress = RevisionProgress.initial('us-1');
    progress = attempt(progress, 1.0, day1);

    final stats = RevisionStats.from([progress], now: day1, window: 5);

    expect(stats.accuracySeries, hasLength(1));
    expect(stats.trendSeries, [1.0]);
    expect(stats.isImproving, isTrue);
  });
}
