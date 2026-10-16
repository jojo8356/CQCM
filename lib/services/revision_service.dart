import 'dart:convert';

import 'package:flutter/services.dart';

import '../models/revision.dart';
import '../models/revision_progress.dart';
import 'revision_scheduler.dart';
import 'revision_store.dart';
import 'text_scoring.dart';

/// Catalogue des paquets de révision et de leurs phrases.
class RevisionCatalog {
  final List<RevisionDeck> decks;
  final Map<String, List<RevisionItem>> itemsByDeck;

  const RevisionCatalog({required this.decks, required this.itemsByDeck});

  List<RevisionItem> itemsOf(String deckId) => itemsByDeck[deckId] ?? const [];

  List<RevisionItem> get allItems =>
      decks.expand((deck) => itemsOf(deck.id)).toList();

  RevisionDeck? deckById(String deckId) {
    for (final deck in decks) {
      if (deck.id == deckId) return deck;
    }
    return null;
  }
}

/// Lecture des paquets de révision embarqués et de la progression locale.
class RevisionService {
  /// Dossier de stockage de la progression (null : dossier par défaut).
  final String? dataDirectory;

  RevisionService({this.dataDirectory});

  static const String catalogueAsset = 'assets/data/revision-decks.json';

  Future<RevisionCatalog> loadCatalog() async {
    final catalogueJson = json.decode(
      await rootBundle.loadString(catalogueAsset),
    );
    final decks = ((catalogueJson as Map<String, dynamic>)['decks'] as List)
        .map((entry) => RevisionDeck.fromJson(entry as Map<String, dynamic>))
        .toList();

    final itemsByDeck = <String, List<RevisionItem>>{};
    for (final deck in decks) {
      itemsByDeck[deck.id] = await loadItems(deck);
    }

    return RevisionCatalog(decks: decks, itemsByDeck: itemsByDeck);
  }

  Future<List<RevisionItem>> loadItems(RevisionDeck deck) async {
    final deckJson = json.decode(
      await rootBundle.loadString('assets/data/${deck.fileName}'),
    );
    final items = ((deckJson as Map<String, dynamic>)['items'] as List)
        .map((entry) => RevisionItem.fromJson(entry as Map<String, dynamic>))
        .toList();
    return items;
  }

  Future<Map<String, RevisionProgress>> loadProgress() {
    return loadRevisionProgress(directoryPath: dataDirectory);
  }

  Future<void> saveProgress(Map<String, RevisionProgress> progress) {
    return saveRevisionProgress(progress, directoryPath: dataDirectory);
  }

  /// Enregistre une recopie : met à jour la progression et la prochaine
  /// échéance de la phrase.
  static RevisionProgress recordAttempt({
    required RevisionProgress progress,
    required TextScore score,
    required DateTime reviewedAt,
    int durationSeconds = 0,
  }) {
    return RevisionScheduler.apply(
      progress: progress,
      accuracy: score.accuracy,
      reviewedAt: reviewedAt,
      expectedWords: score.expectedWordCount,
      matchedWords: score.matchedWordCount,
      durationSeconds: durationSeconds,
    );
  }
}
