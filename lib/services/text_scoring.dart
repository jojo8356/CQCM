/// Comparaison « au mot près » entre une phrase attendue et la phrase saisie.
///
/// Le moteur est volontairement pur Dart (pas de dépendance Flutter) afin
/// d'être testable directement et réutilisable par la CLI.
library;

enum TokenStatus {
  /// Mot présent des deux côtés.
  matched,

  /// Mot attendu mais absent de la saisie.
  missing,

  /// Mot saisi en trop.
  extra,

  /// Mot saisi mais différent du mot attendu (faute de frappe).
  typo,
}

class ScoredToken {
  final String value;
  final TokenStatus status;

  const ScoredToken(this.value, this.status);

  bool get isCorrect => status == TokenStatus.matched;

  @override
  String toString() => '$value ($status)';

  @override
  bool operator ==(Object other) =>
      other is ScoredToken && other.value == value && other.status == status;

  @override
  int get hashCode => Object.hash(value, status);
}

/// Résultat d'une comparaison.
class TextScore {
  final String expected;
  final String typed;

  /// Mots de la réponse de référence, avec leur statut.
  final List<ScoredToken> expectedTokens;

  /// Mots saisis, avec leur statut.
  final List<ScoredToken> typedTokens;

  final int expectedWordCount;

  /// Nombre de mots attendus retrouvés dans la saisie.
  final int matchedWordCount;
  final int missingWordCount;
  final int extraWordCount;
  final int typoWordCount;

  const TextScore({
    required this.expected,
    required this.typed,
    required this.expectedTokens,
    required this.typedTokens,
    required this.expectedWordCount,
    required this.matchedWordCount,
    required this.missingWordCount,
    required this.extraWordCount,
    required this.typoWordCount,
  });

  /// Taux de validation : mots justes / mots attendus (0 → 1).
  double get accuracy =>
      expectedWordCount == 0 ? 0 : matchedWordCount / expectedWordCount;

  /// Précision : mots justes / mots saisis (0 → 1).
  double get precision {
    final typedCount = typedTokens.length;
    return typedCount == 0 ? 0 : matchedWordCount / typedCount;
  }

  /// Similarité globale (moyenne harmonique précision / rappel).
  double get similarity {
    final total = expectedWordCount + typedTokens.length;
    return total == 0 ? 0 : 2 * matchedWordCount / total;
  }

  int get accuracyPercent => (accuracy * 100).round();

  int get similarityPercent => (similarity * 100).round();

  bool get isValidated => accuracy >= TextScorer.passThreshold;

  bool get isEmpty => typedTokens.isEmpty;

  /// Tous les mots attendus sont présents, dans le bon ordre, sans extra.
  bool get isPerfect =>
      missingWordCount == 0 && extraWordCount == 0 && typoWordCount == 0;

  List<String> get missingWords => expectedTokens
      .where((token) => token.status == TokenStatus.missing)
      .map((token) => token.value)
      .toList();

  List<String> get misplacedWords => typedTokens
      .where((token) => token.status == TokenStatus.extra)
      .map((token) => token.value)
      .toList();

  List<String> get typoWords => typedTokens
      .where((token) => token.status == TokenStatus.typo)
      .map((token) => token.value)
      .toList();
}

/// Contraintes d'énoncé du type « ne pas utiliser le verbe payer ».
class ConstraintCheck {
  /// Mots interdits détectés dans l'énoncé.
  final List<String> forbiddenWords;

  /// Mots interdits présents dans la copie et absents de la réponse
  /// officielle : ce sont les vraies fautes.
  final List<String> violatedWords;

  /// Mots interdits présents dans la copie mais aussi dans la réponse
  /// officielle : tolérés (ex. « le montant à payer »).
  final List<String> creditedWords;

  /// Mots interdits absents de la copie.
  final List<String> avoidedWords;

  const ConstraintCheck({
    required this.forbiddenWords,
    required this.violatedWords,
    this.creditedWords = const [],
    this.avoidedWords = const [],
  });

  bool get hasConstraints => forbiddenWords.isNotEmpty;

  bool get isSatisfied => violatedWords.isEmpty;

  static ConstraintCheck evaluate({
    required List<String> constraints,
    required String typed,
    required List<String> references,
  }) {
    final forbidden = <String>{};
    for (final constraint in constraints) {
      forbidden.addAll(TextScorer.forbiddenWordsOf(constraint));
    }

    if (forbidden.isEmpty) {
      return const ConstraintCheck(forbiddenWords: [], violatedWords: []);
    }

    final typedWords = TextScorer.tokenize(typed).toSet();
    final referenceWords = <String>{};
    for (final reference in references) {
      referenceWords.addAll(TextScorer.tokenize(reference));
    }

    final violated = <String>[];
    final credited = <String>[];
    final avoided = <String>[];
    for (final word in forbidden) {
      if (!typedWords.contains(word)) {
        avoided.add(word);
      } else if (referenceWords.contains(word)) {
        credited.add(word);
      } else {
        violated.add(word);
      }
    }

    return ConstraintCheck(
      forbiddenWords: forbidden.toList(),
      violatedWords: violated,
      creditedWords: credited,
      avoidedWords: avoided,
    );
  }
}

/// Structure attendue d'une user story : rôle, besoin, but.
class UserStoryStructure {
  final bool hasRole;
  final bool hasNeed;
  final bool hasGoal;

  const UserStoryStructure({
    required this.hasRole,
    required this.hasNeed,
    required this.hasGoal,
  });

  bool get isComplete => hasRole && hasNeed && hasGoal;

  List<String> get missingParts => [
    if (!hasRole) 'En tant que…',
    if (!hasNeed) 'Je veux…',
    if (!hasGoal) 'Afin de…',
  ];

  static UserStoryStructure of(String text) {
    final words = TextScorer.tokenize(text);
    return UserStoryStructure(
      hasRole:
          _containsSequence(words, const ['en', 'tant', 'que']) ||
          _containsSequence(words, const ['en', 'tant', 'qu']),
      hasNeed: _containsSequence(words, const ['je', 'veux']),
      hasGoal: words.contains('afin'),
    );
  }

  static bool _containsSequence(List<String> words, List<String> sequence) {
    if (sequence.isEmpty || words.length < sequence.length) {
      return false;
    }
    for (var start = 0; start <= words.length - sequence.length; start++) {
      var found = true;
      for (var offset = 0; offset < sequence.length; offset++) {
        if (words[start + offset] != sequence[offset]) {
          found = false;
          break;
        }
      }
      if (found) {
        return true;
      }
    }
    return false;
  }
}

class TextScorer {
  /// Seuil de validation : 95 % des mots attendus (recopie « au mot près »).
  static const double passThreshold = 0.95;

  /// Découpe un texte en mots normalisés : minuscules, sans accents,
  /// sans ponctuation. « L'étudiant » → [le, etudiant].
  ///
  /// Un token est **un mot** : les chiffres et les lettres sont séparés
  /// (« 14h » → 14 puis h, « 2TD » → 2 puis td), et une élision est ramenée à
  /// son mot complet qu'elle soit écrite avec apostrophe (« afin d'acheter »)
  /// ou avec une espace (« afin d acheter »).
  static List<String> tokenize(String text) {
    final words = <String>[];
    final buffer = StringBuffer();

    void flush() {
      if (buffer.isEmpty) return;
      final word = buffer.toString();
      buffer.clear();
      // Élision sans apostrophe : « d acheter » se lit comme « d'acheter ».
      final expanded = _elisions[word] ?? word;
      for (final match in _wordRuns.allMatches(expanded)) {
        words.add(match.group(0)!);
      }
    }

    for (final rune in text.toLowerCase().runes) {
      final char = String.fromCharCode(rune);

      if (char == "'" || char == '\u2019') {
        // Élision : « qu'étudiant » ou « d'acheter ».
        flush();
        continue;
      }

      final normalized = _accentMap[char] ?? char;
      if (_wordChar.hasMatch(normalized)) {
        buffer.write(normalized);
      } else {
        flush();
      }
    }
    flush();
    return words;
  }

  static final RegExp _wordChar = RegExp(r'^[a-z0-9]+$');

  /// Suites de lettres ou de chiffres à l'intérieur d'un mot (cf. « 14h »).
  static final RegExp _wordRuns = RegExp(r'[a-z]+|[0-9]+');

  /// Formes élidées ramenées à leur mot complet.
  static const Map<String, String> _elisions = {
    'l': 'le',
    'd': 'de',
    'j': 'je',
    'n': 'ne',
    's': 'se',
    'c': 'ce',
    'm': 'me',
    't': 'te',
    'qu': 'que',
    'lorsqu': 'lorsque',
    'puisqu': 'puisque',
    'quoiqu': 'quoique',
    'jusqu': 'jusque',
  };

  /// Score la saisie contre la meilleure des réponses de référence.
  static TextScore score(String typed, List<String> references) {
    if (references.isEmpty) {
      return TextScore(
        expected: '',
        typed: typed,
        expectedTokens: const [],
        typedTokens: [
          for (final word in tokenize(typed)) ScoredToken(word, TokenStatus.extra),
        ],
        expectedWordCount: 0,
        matchedWordCount: 0,
        missingWordCount: 0,
        extraWordCount: tokenize(typed).length,
        typoWordCount: 0,
      );
    }

    var best = _scoreAgainst(typed, references.first);
    for (final reference in references.skip(1)) {
      final candidate = _scoreAgainst(typed, reference);
      if (candidate.accuracy > best.accuracy ||
          (candidate.accuracy == best.accuracy &&
              candidate.similarity > best.similarity)) {
        best = candidate;
      }
    }
    return best;
  }

  /// Mots interdits extraits d'une contrainte (« ne pas utiliser le verbe
  /// payer » → [payer]).
  static List<String> forbiddenWordsOf(String constraint) {
    final words = tokenize(constraint);
    final triggers = ['mot', 'verbe', 'verbes', 'terme', 'expression'];
    for (var index = 0; index < words.length; index++) {
      if (triggers.contains(words[index])) {
        return words.skip(index + 1).toList();
      }
    }
    return const [];
  }

  /// Édition : distance de Levenshtein (utilisée pour repérer les fautes).
  static int editDistance(String a, String b) {
    if (a == b) return 0;
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;

    var previous = List<int>.generate(b.length + 1, (index) => index);
    var current = List<int>.filled(b.length + 1, 0);

    for (var i = 0; i < a.length; i++) {
      current[0] = i + 1;
      for (var j = 0; j < b.length; j++) {
        final cost = a.codeUnitAt(i) == b.codeUnitAt(j) ? 0 : 1;
        final deletion = previous[j + 1] + 1;
        final insertion = current[j] + 1;
        final substitution = previous[j] + cost;
        var best = deletion < insertion ? deletion : insertion;
        if (substitution < best) {
          best = substitution;
        }
        current[j + 1] = best;
      }
      final swap = previous;
      previous = current;
      current = swap;
    }
    return previous[b.length];
  }

  static TextScore _scoreAgainst(String typed, String expected) {
    final expectedWords = tokenize(expected);
    final typedWords = tokenize(typed);

    final table = _lcsTable(expectedWords, typedWords);
    final expectedStatus = List<TokenStatus>.filled(
      expectedWords.length,
      TokenStatus.missing,
    );
    final typedStatus = List<TokenStatus>.filled(
      typedWords.length,
      TokenStatus.extra,
    );

    var i = 0;
    var j = 0;
    while (i < expectedWords.length && j < typedWords.length) {
      if (expectedWords[i] == typedWords[j]) {
        expectedStatus[i] = TokenStatus.matched;
        typedStatus[j] = TokenStatus.matched;
        i++;
        j++;
      } else if (table[i + 1][j] >= table[i][j + 1]) {
        i++;
      } else {
        j++;
      }
    }

    _markTypos(expectedWords, expectedStatus, typedWords, typedStatus);

    var matched = 0;
    var missing = 0;
    var typo = 0;
    for (final status in expectedStatus) {
      switch (status) {
        case TokenStatus.matched:
          matched++;
        case TokenStatus.missing:
          missing++;
        case TokenStatus.typo:
          typo++;
          missing++;
        case TokenStatus.extra:
          break;
      }
    }

    var extra = 0;
    var typedTypo = 0;
    for (final status in typedStatus) {
      switch (status) {
        case TokenStatus.extra:
          extra++;
        case TokenStatus.typo:
          typedTypo++;
        case TokenStatus.matched:
        case TokenStatus.missing:
          break;
      }
    }

    return TextScore(
      expected: expected,
      typed: typed,
      expectedTokens: [
        for (var index = 0; index < expectedWords.length; index++)
          ScoredToken(expectedWords[index], expectedStatus[index]),
      ],
      typedTokens: [
        for (var index = 0; index < typedWords.length; index++)
          ScoredToken(typedWords[index], typedStatus[index]),
      ],
      expectedWordCount: expectedWords.length,
      matchedWordCount: matched,
      missingWordCount: missing,
      extraWordCount: extra,
      typoWordCount: typo > 0 ? typo : typedTypo,
    );
  }

  /// Apparie les mots manquants et les mots en trop proches (faute de frappe).
  static void _markTypos(
    List<String> expectedWords,
    List<TokenStatus> expectedStatus,
    List<String> typedWords,
    List<TokenStatus> typedStatus,
  ) {
    final missing = <int>[
      for (var index = 0; index < expectedStatus.length; index++)
        if (expectedStatus[index] == TokenStatus.missing) index,
    ];
    final extra = <int>[
      for (var index = 0; index < typedStatus.length; index++)
        if (typedStatus[index] == TokenStatus.extra) index,
    ];

    final used = <int>{};
    for (final expectedIndex in missing) {
      final expectedWord = expectedWords[expectedIndex];
      for (final typedIndex in extra) {
        if (used.contains(typedIndex)) continue;
        if ((typedIndex - expectedIndex).abs() > 3) continue;
        final typedWord = typedWords[typedIndex];
        if (!_looksLikeTypo(expectedWord, typedWord)) continue;

        expectedStatus[expectedIndex] = TokenStatus.typo;
        typedStatus[typedIndex] = TokenStatus.typo;
        used.add(typedIndex);
        break;
      }
    }
  }

  static bool _looksLikeTypo(String expected, String typed) {
    if (expected == typed) return false;
    if (expected.length <= 2 || typed.length <= 2) return false;
    final distance = editDistance(expected, typed);
    if (distance <= 1) return true;
    final longest = expected.length > typed.length
        ? expected.length
        : typed.length;
    return distance <= 2 && longest >= 6;
  }

  static List<List<int>> _lcsTable(List<String> a, List<String> b) {
    final table = List<List<int>>.generate(
      a.length + 1,
      (_) => List<int>.filled(b.length + 1, 0),
    );
    for (var i = a.length - 1; i >= 0; i--) {
      for (var j = b.length - 1; j >= 0; j--) {
        table[i][j] = a[i] == b[j]
            ? table[i + 1][j + 1] + 1
            : (table[i + 1][j] >= table[i][j + 1]
                  ? table[i + 1][j]
                  : table[i][j + 1]);
      }
    }
    return table;
  }

  static const Map<String, String> _accentMap = {
    'à': 'a', 'á': 'a', 'â': 'a', 'ä': 'a', 'ã': 'a', 'å': 'a',
    'ç': 'c',
    'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e',
    'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i',
    'ò': 'o', 'ó': 'o', 'ô': 'o', 'ö': 'o', 'õ': 'o',
    'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u',
    'ñ': 'n', 'ý': 'y', 'ÿ': 'y',
    'æ': 'ae', 'œ': 'oe', 'ø': 'o', 'ß': 'ss',
  };
}
