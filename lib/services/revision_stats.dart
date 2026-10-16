/// Statistiques de révision : séries destinées au graphique d'avancement et
/// indicateurs de la courbe d'apprentissage.
library;

import '../models/revision_progress.dart';

class RevisionStats {
  /// Taux de validation de chaque tentative, dans l'ordre chronologique.
  final List<double> accuracySeries;

  /// Moyenne glissante (lissage) de [accuracySeries].
  final List<double> trendSeries;

  /// Dates des tentatives, alignées sur [accuracySeries].
  final List<DateTime> timestamps;

  final int attemptCount;
  final int reviewedItemCount;
  final int totalItemCount;
  final int masteredItemCount;
  final int dueItemCount;

  final double averageAccuracy;
  final double bestAccuracy;
  final double lastAccuracy;

  /// Vrai quand la fin de la courbe est meilleure que le début.
  final bool isImproving;

  final DateTime? lastReviewedAt;
  final DateTime? nextDueAt;

  /// Nombre de jours consécutifs (en terminant aujourd'hui ou hier) révisés.
  final int streakDays;

  const RevisionStats({
    required this.accuracySeries,
    required this.trendSeries,
    required this.timestamps,
    required this.attemptCount,
    required this.reviewedItemCount,
    required this.totalItemCount,
    required this.masteredItemCount,
    required this.dueItemCount,
    required this.averageAccuracy,
    required this.bestAccuracy,
    required this.lastAccuracy,
    required this.isImproving,
    required this.lastReviewedAt,
    required this.nextDueAt,
    required this.streakDays,
  });

  bool get hasHistory => accuracySeries.isNotEmpty;

  static RevisionStats from(
    Iterable<RevisionProgress> progresses, {
    DateTime? now,
    int window = 5,
  }) {
    final reference = now ?? DateTime.now();
    final progressList = progresses.toList();

    final attempts = <RevisionAttempt>[];
    for (final progress in progressList) {
      attempts.addAll(progress.attempts);
    }
    attempts.sort((a, b) => a.reviewedAt.compareTo(b.reviewedAt));

    final accuracySeries = attempts
        .map((attempt) => attempt.accuracy)
        .toList(growable: false);
    final trendSeries = _movingAverage(accuracySeries, window);

    final due = progressList.where((progress) => progress.isDue(reference));
    final mastered = progressList.where((progress) => progress.isMastered);
    final reviewed = progressList.where(
      (progress) => progress.attemptCount > 0,
    );

    DateTime? lastReviewedAt;
    DateTime? nextDueAt;
    for (final progress in progressList) {
      final last = progress.lastReviewedAt;
      if (last != null &&
          (lastReviewedAt == null || last.isAfter(lastReviewedAt))) {
        lastReviewedAt = last;
      }
      final dueAt = progress.dueAt;
      if (dueAt != null &&
          dueAt.isAfter(reference) &&
          (nextDueAt == null || dueAt.isBefore(nextDueAt))) {
        nextDueAt = dueAt;
      }
    }

    return RevisionStats(
      accuracySeries: accuracySeries,
      trendSeries: trendSeries,
      timestamps: attempts
          .map((attempt) => attempt.reviewedAt)
          .toList(growable: false),
      attemptCount: attempts.length,
      reviewedItemCount: reviewed.length,
      totalItemCount: progressList.length,
      masteredItemCount: mastered.length,
      dueItemCount: due.length,
      averageAccuracy: _average(accuracySeries),
      bestAccuracy: accuracySeries.isEmpty
          ? 0
          : accuracySeries.reduce((a, b) => a > b ? a : b),
      lastAccuracy: accuracySeries.isEmpty ? 0 : accuracySeries.last,
      isImproving: _isImproving(accuracySeries),
      lastReviewedAt: lastReviewedAt,
      nextDueAt: nextDueAt,
      streakDays: _streakDays(attempts, reference),
    );
  }

  static List<double> _movingAverage(List<double> values, int window) {
    if (values.isEmpty) return const [];
    final size = window < 1 ? 1 : window;
    final result = <double>[];
    for (var index = 0; index < values.length; index++) {
      final start = index - size + 1 < 0 ? 0 : index - size + 1;
      var sum = 0.0;
      for (var cursor = start; cursor <= index; cursor++) {
        sum += values[cursor];
      }
      result.add(sum / (index - start + 1));
    }
    return result;
  }

  static double _average(List<double> values) {
    if (values.isEmpty) return 0;
    var sum = 0.0;
    for (final value in values) {
      sum += value;
    }
    return sum / values.length;
  }

  static bool _isImproving(List<double> values) {
    if (values.length < 4) {
      return values.isNotEmpty && values.last >= 0.9;
    }
    final rawThird = (values.length / 3).floor();
    final third = rawThird < 1
        ? 1
        : (rawThird > values.length ? values.length : rawThird);
    final start = _average(values.sublist(0, third));
    final end = _average(values.sublist(values.length - third));
    return end >= start;
  }

  static int _streakDays(List<RevisionAttempt> attempts, DateTime now) {
    if (attempts.isEmpty) return 0;

    final days = <String>{
      for (final attempt in attempts) _dayKey(attempt.reviewedAt),
    };

    final today = DateTime(now.year, now.month, now.day);
    var cursor = today;
    if (!days.contains(_dayKey(cursor))) {
      cursor = today.subtract(const Duration(days: 1));
      if (!days.contains(_dayKey(cursor))) {
        return 0;
      }
    }

    var streak = 0;
    while (days.contains(_dayKey(cursor))) {
      streak++;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return streak;
  }

  static String _dayKey(DateTime date) =>
      '${date.year}-${date.month}-${date.day}';
}
