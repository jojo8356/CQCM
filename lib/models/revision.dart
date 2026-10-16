/// Modèles du mode « Recopier texte » (révision de phrases).
///
/// Un [RevisionDeck] est un paquet de révision (ex. GP – User stories).
/// Un [RevisionItem] est une phrase à recopier, avec une ou plusieurs
/// réponses de référence acceptées.
library;

class RevisionDeck {
  final String id;
  final String title;

  /// Libellé court affiché en titre de section (ex. « GP »).
  final String shortLabel;
  final String subtitle;
  final String description;
  final String icon;
  final int itemCount;
  final String fileName;

  const RevisionDeck({
    required this.id,
    required this.title,
    this.shortLabel = '',
    required this.subtitle,
    required this.description,
    required this.icon,
    required this.itemCount,
    required this.fileName,
  });

  factory RevisionDeck.fromJson(Map<String, dynamic> json) {
    return RevisionDeck(
      id: json['id'] as String,
      title: json['title'] as String,
      shortLabel: (json['shortLabel'] as String?) ?? '',
      subtitle: (json['subtitle'] as String?) ?? '',
      description: (json['description'] as String?) ?? '',
      icon: (json['icon'] as String?) ?? '📝',
      itemCount: (json['itemCount'] as int?) ?? 0,
      fileName: json['fileName'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'shortLabel': shortLabel,
      'subtitle': subtitle,
      'description': description,
      'icon': icon,
      'itemCount': itemCount,
      'fileName': fileName,
    };
  }
}

class RevisionItem {
  final String id;
  final String project;
  final String prompt;

  /// Contraintes de l'énoncé, par exemple « ne pas utiliser le verbe payer ».
  final List<String> constraints;

  /// Réponses de référence acceptées (certains cas admettent plusieurs
  /// formulations, ex. « OU » dans l'énoncé EDT).
  final List<String> answers;

  const RevisionItem({
    required this.id,
    required this.project,
    required this.prompt,
    required this.constraints,
    required this.answers,
  });

  /// Réponse de référence principale (la première).
  String get referenceAnswer => answers.isEmpty ? '' : answers.first;

  bool get hasMultipleAnswers => answers.length > 1;

  factory RevisionItem.fromJson(Map<String, dynamic> json) {
    return RevisionItem(
      id: json['id'] as String,
      project: (json['project'] as String?) ?? '',
      prompt: json['prompt'] as String,
      constraints: ((json['constraints'] as List?) ?? const [])
          .map((value) => value as String)
          .toList(),
      answers: ((json['answers'] as List?) ?? const [])
          .map((value) => value as String)
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'project': project,
      'prompt': prompt,
      'constraints': constraints,
      'answers': answers,
    };
  }
}
