/// Plan de révision : assemble le catalogue, la progression enregistrée et
/// les décisions de séance (quoi réviser aujourd'hui, quand relancer).
library;

import 'dart:math';

import '../models/revision.dart';
import '../models/revision_progress.dart';
import 'revision_scheduler.dart';
import 'revision_service.dart';
import 'revision_stats.dart';
import 'text_scoring.dart';

/// État de rappel d'un paquet : ce qu'il faut réviser, et quand revenir.
class RevisionReminder {
  final String deckId;
  final String deckTitle;
  final int dueCount;
  final int newCount;
  final int totalCount;
  final DateTime? nextDueAt;
  final DateTime now;

  const RevisionReminder({
    required this.deckId,
    required this.deckTitle,
    required this.dueCount,
    required this.newCount,
    required this.totalCount,
    required this.nextDueAt,
    required this.now,
  });

  bool get shouldNotify => dueCount > 0;

  bool get isComplete => totalCount > 0 && dueCount == 0;

  String get title {
    if (dueCount <= 0) return 'Tout est à jour';
    return dueCount == 1
        ? '1 phrase à réviser'
        : '$dueCount phrases à réviser';
  }

  String get detail {
    final parts = <String>[];
    if (newCount > 0) {
      parts.add(newCount == 1 ? '1 jamais vue' : '$newCount jamais vues');
    }
    final reviews = dueCount - newCount;
    if (reviews > 0) {
      parts.add(reviews == 1 ? '1 à revoir' : '$reviews à revoir');
    }
    if (parts.isEmpty && nextDueAt != null) {
      parts.add('prochaine échéance ${_formatDate(nextDueAt!)}');
    }
    return parts.join(' · ');
  }

  /// Délai avant la prochaine échéance (null si rien de planifié).
  Duration? get timeUntilNext {
    final due = nextDueAt;
    if (due == null || !due.isAfter(now)) return null;
    return due.difference(now);
  }

  String get nextDueLabel {
    final due = nextDueAt;
    if (due == null) return "aucune échéance planifiée";
    final days = _dayDelta(now, due);
    if (days <= 0) return "dans la journée";
    return days == 1 ? 'demain' : 'dans $days jours';
  }

  static int _dayDelta(DateTime from, DateTime to) {
    final start = DateTime(from.year, from.month, from.day);
    final end = DateTime(to.year, to.month, to.day);
    return end.difference(start).inDays;
  }

  static String _formatDate(DateTime date) {
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    return '$day/$month/${date.year}';
  }
}

class RevisionPlan {
  final RevisionService service;
  final RevisionCatalog catalog;
  final DateTime now;

  final Map<String, RevisionProgress> _progress;

  RevisionPlan({
    required this.service,
    required this.catalog,
    Map<String, RevisionProgress>? progress,
    DateTime? now,
  }) : _progress = progress ?? <String, RevisionProgress>{},
       now = now ?? DateTime.now();

  static Future<RevisionPlan> load({
    RevisionService? service,
    DateTime? now,
  }) async {
    final resolvedService = service ?? RevisionService();
    final catalog = await resolvedService.loadCatalog();
    final progress = await resolvedService.loadProgress();
    return RevisionPlan(
      service: resolvedService,
      catalog: catalog,
      progress: progress,
      now: now,
    );
  }

  Map<String, RevisionProgress> get progressMap =>
      Map<String, RevisionProgress>.unmodifiable(_progress);

  RevisionProgress progressFor(String itemId) =>
      _progress[itemId] ?? RevisionProgress.initial(itemId);

  List<RevisionItem> itemsOf(String deckId) => catalog.itemsOf(deckId);

  List<RevisionItem> dueItemsOf(String deckId) => itemsOf(
    deckId,
  ).where((item) => progressFor(item.id).isDue(now)).toList();

  RevisionStats statsOf(String deckId) => RevisionStats.from(
    itemsOf(deckId).map((item) => progressFor(item.id)),
    now: now,
  );

  RevisionReminder reminderFor(String deckId) {
    final items = itemsOf(deckId);
    final due = dueItemsOf(deckId);
    final newCount = due.where((item) => progressFor(item.id).isNew).length;
    final nextDueAt = RevisionScheduler.nextDueAt(
      items.map((item) => progressFor(item.id)),
      now: now,
    );
    return RevisionReminder(
      deckId: deckId,
      deckTitle: catalog.deckById(deckId)?.title ?? deckId,
      dueCount: due.length,
      newCount: newCount,
      totalCount: items.length,
      nextDueAt: nextDueAt,
      now: now,
    );
  }

  /// Séance du jour : les phrases à réviser sont tirées **au hasard**, puis
  /// complétées par les moins maîtrisées quand la séance est plus longue que
  /// le rappel du jour.
  ///
  /// [random] permet de fixer le tirage (tests, rejeu).
  List<RevisionItem> sessionItems(
    String deckId, {
    int size = 5,
    Random? random,
  }) {
    final rng = random ?? Random();
    final entries = itemsOf(deckId)
        .map((item) => MapEntry(item, progressFor(item.id)))
        .toList();

    final due = <MapEntry<RevisionItem, RevisionProgress>>[];
    final later = <MapEntry<RevisionItem, RevisionProgress>>[];
    for (final entry in entries) {
      if (entry.value.isDue(now)) {
        due.add(entry);
      } else {
        later.add(entry);
      }
    }
    due.shuffle(rng);

    // Les phrases non dues sont regroupées par palier de maîtrise, puis
    // tirées au hasard à l'intérieur de chaque palier.
    final buckets = <int, List<MapEntry<RevisionItem, RevisionProgress>>>{};
    for (final entry in later) {
      final level = (entry.value.mastery * 5).floor();
      buckets.putIfAbsent(level, () => <MapEntry<RevisionItem, RevisionProgress>>[]).add(entry);
    }
    final levels = buckets.keys.toList()..sort();

    final ordered = <RevisionItem>[
      for (final entry in due) entry.key,
    ];
    for (final level in levels) {
      final group = buckets[level]!..shuffle(rng);
      ordered.addAll(group.map((entry) => entry.key));
    }

    if (size <= 0 || size >= ordered.length) return ordered;
    return ordered.take(size).toList();
  }

  /// Enregistre une recopie et renvoie la progression mise à jour.
  Future<RevisionProgress> record({
    required RevisionItem item,
    required TextScore score,
    DateTime? reviewedAt,
    int durationSeconds = 0,
  }) async {
    final updated = RevisionService.recordAttempt(
      progress: progressFor(item.id),
      score: score,
      reviewedAt: reviewedAt ?? now,
      durationSeconds: durationSeconds,
    );
    _progress[item.id] = updated;
    await service.saveProgress(_progress);
    return updated;
  }

  Future<void> resetItem(String itemId) async {
    _progress.remove(itemId);
    await service.saveProgress(_progress);
  }

  Future<void> resetAll() async {
    _progress.clear();
    await service.saveProgress(_progress);
  }
}
