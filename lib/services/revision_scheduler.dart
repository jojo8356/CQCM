/// Planification des révisions : calcule la prochaine échéance d'une phrase
/// à partir du taux de validation de la recopie.
///
/// Algorithme inspiré de SM-2 (répétition espacée) : plus la phrase est
/// recopiée juste, plus l'intervalle avant la prochaine révision grandit.
/// Une phrase ratée revient le jour même, ce qui dessine la courbe
/// d'apprentissage visible dans l'historique.
library;

import '../models/revision_progress.dart';

class RevisionScheduler {
  /// En dessous de ce taux, la phrase n'est pas considérée comme validée.
  /// Seuil serré : la recopie est exigée « au mot près ».
  static const double passThreshold = 0.95;

  /// Bornes de sécurité de l'algorithme.
  static const double minEaseFactor = 1.3;
  static const double initialEaseFactor = 2.5;
  static const int maxIntervalDays = 180;

  /// Premiers intervalles (en jours) après 1, 2 et 3 réussites.
  static const List<int> firstIntervals = [1, 3, 7];

  /// Note de qualité (0 → 5) déduite du taux de validation.
  static int qualityFor(double accuracy) {
    if (accuracy >= 1.0) return 5;
    if (accuracy >= 0.98) return 4;
    if (accuracy >= passThreshold) return 3;
    if (accuracy >= 0.85) return 2;
    if (accuracy >= 0.6) return 1;
    return 0;
  }

  /// Enregistre une tentative et calcule la prochaine échéance.
  static RevisionProgress apply({
    required RevisionProgress progress,
    required double accuracy,
    required DateTime reviewedAt,
    int expectedWords = 0,
    int matchedWords = 0,
    int durationSeconds = 0,
  }) {
    final quality = qualityFor(accuracy);
    final passed = accuracy >= passThreshold;

    // Facteur de facilité : monte quand la recopie est parfaite,
    // descend quand elle est approximative.
    final delta = 0.1 - (5 - quality) * (0.08 + (5 - quality) * 0.02);
    var easeFactor = progress.easeFactor + delta;
    if (easeFactor < minEaseFactor) {
      easeFactor = minEaseFactor;
    }

    final int repetitions;
    final int intervalDays;
    final DateTime dueAt;

    if (passed) {
      repetitions = progress.repetitions + 1;
      intervalDays = intervalFor(
        repetitions: repetitions,
        previousIntervalDays: progress.intervalDays,
        easeFactor: easeFactor,
      );
      dueAt = reviewedAt.add(Duration(days: intervalDays));
    } else {
      repetitions = 0;
      intervalDays = 0;
      dueAt = reviewedAt;
    }

    final attempt = RevisionAttempt(
      reviewedAt: reviewedAt,
      accuracy: accuracy,
      expectedWords: expectedWords,
      matchedWords: matchedWords,
      intervalDays: intervalDays,
      repetitions: repetitions,
      easeFactor: easeFactor,
      durationSeconds: durationSeconds,
    );

    return progress.copyWith(
      attempts: [...progress.attempts, attempt],
      repetitions: repetitions,
      easeFactor: easeFactor,
      intervalDays: intervalDays,
      lastReviewedAt: reviewedAt,
      dueAt: dueAt,
    );
  }

  /// Intervalle en jours avant la prochaine révision.
  static int intervalFor({
    required int repetitions,
    required int previousIntervalDays,
    required double easeFactor,
  }) {
    if (repetitions <= firstIntervals.length) {
      return firstIntervals[repetitions - 1 < 0 ? 0 : repetitions - 1];
    }
    final base = previousIntervalDays <= 0
        ? firstIntervals.last
        : previousIntervalDays;
    final next = (base * easeFactor).round();
    if (next < 1) return 1;
    if (next > maxIntervalDays) return maxIntervalDays;
    return next;
  }

  /// Prochaines échéances à afficher : d'abord ce qui est dû, puis le reste.
  static List<RevisionProgress> sortByDue(
    Iterable<RevisionProgress> progresses, {
    required DateTime now,
  }) {
    final list = progresses.toList()
      ..sort((a, b) {
        final dueA = a.dueAt;
        final dueB = b.dueAt;
        if (dueA == null && dueB == null) return a.itemId.compareTo(b.itemId);
        if (dueA == null) return -1;
        if (dueB == null) return 1;
        return dueA.compareTo(dueB);
      });
    return list;
  }

  static List<RevisionProgress> dueOnly(
    Iterable<RevisionProgress> progresses, {
    required DateTime now,
  }) {
    return progresses.where((progress) => progress.isDue(now)).toList();
  }

  /// Date de la prochaine révision (null si tout est encore dû maintenant).
  static DateTime? nextDueAt(
    Iterable<RevisionProgress> progresses, {
    required DateTime now,
  }) {
    DateTime? next;
    for (final progress in progresses) {
      final due = progress.dueAt;
      if (due == null) continue;
      if (due.isAfter(now) && (next == null || due.isBefore(next))) {
        next = due;
      }
    }
    return next;
  }
}
