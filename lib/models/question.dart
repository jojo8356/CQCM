class Question {
  final int id;
  final String question;
  final List<String> options;
  final int? correctIndex;
  final List<int>? correctIndices;
  final String? explanation;

  const Question({
    required this.id,
    required this.question,
    required this.options,
    this.correctIndex,
    this.correctIndices,
    this.explanation,
  });

  bool get isMultipleChoice =>
      correctIndices != null && correctIndices!.length > 1;

  List<int> get allCorrectIndices {
    if (correctIndices != null) return correctIndices!;
    if (correctIndex != null) return [correctIndex!];
    return [];
  }

  bool isCorrectAnswer(Set<int> selectedIndices) {
    final correct = allCorrectIndices.toSet();
    return selectedIndices.length == correct.length &&
        selectedIndices.containsAll(correct);
  }

  factory Question.fromJson(Map<String, dynamic> json) {
    return Question(
      id: json['id'] as int,
      question: json['question'] as String,
      options: (json['options'] as List).cast<String>(),
      correctIndex: json['correctIndex'] as int?,
      correctIndices: json['correctIndices'] != null
          ? (json['correctIndices'] as List).cast<int>()
          : null,
      explanation: json['explanation'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'question': question,
      'options': options,
      if (correctIndex != null) 'correctIndex': correctIndex,
      if (correctIndices != null) 'correctIndices': correctIndices,
      if (explanation != null) 'explanation': explanation,
    };
  }
}
