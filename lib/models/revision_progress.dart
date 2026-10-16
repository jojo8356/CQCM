/// Historique de révision et progression d'une phrase.
library;

class RevisionAttempt {
  final DateTime reviewedAt;

  /// Taux de validation de la tentative (0 → 1).
  final double accuracy;
  final int expectedWords;
  final int matchedWords;

  /// Intervalle (en jours) appliqué après cette tentative.
  final int intervalDays;

  /// Répétitions consécutives réussies après cette tentative.
  final int repetitions;
  final double easeFactor;

  /// Durée de saisie, en secondes (0 si inconnue).
  final int durationSeconds;

  const RevisionAttempt({
    required this.reviewedAt,
    required this.accuracy,
    required this.expectedWords,
    required this.matchedWords,
    required this.intervalDays,
    required this.repetitions,
    required this.easeFactor,
    this.durationSeconds = 0,
  });

  int get accuracyPercent => (accuracy * 100).round();

  bool get isValidated => accuracy >= 0.95;

  factory RevisionAttempt.fromJson(Map<String, dynamic> json) {
    return RevisionAttempt(
      reviewedAt: DateTime.parse(json['reviewedAt'] as String),
      accuracy: (json['accuracy'] as num).toDouble(),
      expectedWords: (json['expectedWords'] as int?) ?? 0,
      matchedWords: (json['matchedWords'] as int?) ?? 0,
      intervalDays: (json['intervalDays'] as int?) ?? 0,
      repetitions: (json['repetitions'] as int?) ?? 0,
      easeFactor: (json['easeFactor'] as num?)?.toDouble() ?? 2.5,
      durationSeconds: (json['durationSeconds'] as int?) ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'reviewedAt': reviewedAt.toIso8601String(),
      'accuracy': accuracy,
      'expectedWords': expectedWords,
      'matchedWords': matchedWords,
      'intervalDays': intervalDays,
      'repetitions': repetitions,
      'easeFactor': easeFactor,
      'durationSeconds': durationSeconds,
    };
  }
}

/// État de révision d'une phrase (une [RevisionItem]).
class RevisionProgress {
  final String itemId;
  final List<RevisionAttempt> attempts;

  /// Répétitions consécutives réussies (remises à zéro en cas d'échec).
  final int repetitions;

  /// Facteur de facilité, base de la courbe d'apprentissage.
  final double easeFactor;

  /// Dernier intervalle appliqué, en jours.
  final int intervalDays;

  final DateTime? lastReviewedAt;
  final DateTime? dueAt;

  const RevisionProgress({
    required this.itemId,
    this.attempts = const [],
    this.repetitions = 0,
    this.easeFactor = 2.5,
    this.intervalDays = 0,
    this.lastReviewedAt,
    this.dueAt,
  });

  factory RevisionProgress.initial(String itemId) =>
      RevisionProgress(itemId: itemId);

  int get attemptCount => attempts.length;

  bool get isNew => attempts.isEmpty;

  double get bestAccuracy => attempts.isEmpty
      ? 0
      : attempts.map((attempt) => attempt.accuracy).reduce((a, b) => a > b ? a : b);

  double get lastAccuracy => attempts.isEmpty ? 0 : attempts.last.accuracy;

  double get averageAccuracy => attempts.isEmpty
      ? 0
      : attempts
                .map((attempt) => attempt.accuracy)
                .reduce((a, b) => a + b) /
            attempts.length;

  /// Part de maîtrise (0 → 1) : 5 répétitions réussies = phrase acquise.
  double get mastery {
    final ratio = repetitions / 5;
    if (ratio < 0) return 0;
    if (ratio > 1) return 1;
    return ratio;
  }

  bool get isMastered => repetitions >= 5;

  /// À réviser : jamais révisé, ou échéance atteinte.
  bool isDue(DateTime now) {
    if (dueAt == null) return true;
    return !dueAt!.isAfter(now);
  }

  Duration timeUntilDue(DateTime now) {
    if (dueAt == null) return Duration.zero;
    return dueAt!.difference(now);
  }

  RevisionProgress copyWith({
    List<RevisionAttempt>? attempts,
    int? repetitions,
    double? easeFactor,
    int? intervalDays,
    DateTime? lastReviewedAt,
    DateTime? dueAt,
  }) {
    return RevisionProgress(
      itemId: itemId,
      attempts: attempts ?? this.attempts,
      repetitions: repetitions ?? this.repetitions,
      easeFactor: easeFactor ?? this.easeFactor,
      intervalDays: intervalDays ?? this.intervalDays,
      lastReviewedAt: lastReviewedAt ?? this.lastReviewedAt,
      dueAt: dueAt ?? this.dueAt,
    );
  }

  factory RevisionProgress.fromJson(Map<String, dynamic> json) {
    return RevisionProgress(
      itemId: json['itemId'] as String,
      attempts: ((json['attempts'] as List?) ?? const [])
          .map((value) => RevisionAttempt.fromJson(value as Map<String, dynamic>))
          .toList(),
      repetitions: (json['repetitions'] as int?) ?? 0,
      easeFactor: (json['easeFactor'] as num?)?.toDouble() ?? 2.5,
      intervalDays: (json['intervalDays'] as int?) ?? 0,
      lastReviewedAt: json['lastReviewedAt'] == null
          ? null
          : DateTime.parse(json['lastReviewedAt'] as String),
      dueAt: json['dueAt'] == null
          ? null
          : DateTime.parse(json['dueAt'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'itemId': itemId,
      'attempts': attempts.map((attempt) => attempt.toJson()).toList(),
      'repetitions': repetitions,
      'easeFactor': easeFactor,
      'intervalDays': intervalDays,
      'lastReviewedAt': lastReviewedAt?.toIso8601String(),
      'dueAt': dueAt?.toIso8601String(),
    };
  }
}
