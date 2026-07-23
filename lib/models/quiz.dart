class Quiz {
  final String id;
  final String title;
  final String description;
  final String category;
  final String difficulty;
  final int questionCount;
  final String fileName;
  final String icon;

  const Quiz({
    required this.id,
    required this.title,
    required this.description,
    required this.category,
    required this.difficulty,
    required this.questionCount,
    required this.fileName,
    required this.icon,
  });

  factory Quiz.fromJson(Map<String, dynamic> json) {
    return Quiz(
      id: json['id'] as String,
      title: json['title'] as String,
      description: json['description'] as String,
      category: json['category'] as String,
      difficulty: json['difficulty'] as String,
      questionCount: json['questionCount'] as int,
      fileName: json['fileName'] as String,
      icon: json['icon'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'category': category,
      'difficulty': difficulty,
      'questionCount': questionCount,
      'fileName': fileName,
      'icon': icon,
    };
  }
}
