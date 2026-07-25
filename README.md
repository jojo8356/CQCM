# CQCM

CQCM est une application Flutter de quiz QCM. Elle embarque un catalogue de quiz dans `assets/data/` et permet aussi d'importer des quiz JSON à l'exécution, sans reconstruire l'application.

## Fonctionnalités

- Catalogue de quiz groupé par catégorie.
- Questions à choix unique et choix multiples.
- Explications après validation d'une réponse.
- Écran de résultats avec score et correction question par question.
- Rendu Markdown pour les questions et explications.
- Import de quiz JSON depuis l'écran d'accueil.
- CLI d'administration pour préparer, valider et ajouter des quiz runtime.

## Démarrage

Installer les dépendances :

```bash
flutter pub get
```

Lancer l'application :

```bash
flutter run
```

Lancer les tests :

```bash
flutter test
```

Analyser le code :

```bash
flutter analyze
```

Compiler une release Android :

```bash
flutter build apk --release
```

APK attendu :

```text
build/app/outputs/flutter-apk/app-release.apk
```

## Importer un quiz JSON

Depuis l'application :

1. Ouvrir l'écran d'accueil.
2. Cliquer sur le bouton d'import dans la barre du haut.
3. Sélectionner un fichier JSON au format package CQCM.
4. Vérifier que le quiz apparaît dans la liste.

Exemples prêts à tester :

- `exemple_import.json` : template court.
- `test_import_5_questions.json` : quiz de test avec 5 questions.

Valider un fichier avant import :

```bash
dart run bin/cqcm_quiz.dart validate --package test_import_5_questions.json
```

## Format JSON attendu

```json
{
  "quiz": {
    "id": "mon-quiz",
    "title": "Mon quiz",
    "description": "Description courte",
    "category": "Import",
    "difficulty": "debutant",
    "questionCount": 1,
    "fileName": "questions-mon-quiz.json",
    "icon": "Q"
  },
  "questions": [
    {
      "id": 1,
      "question": "Quelle est la bonne réponse ?",
      "options": ["A", "B", "C"],
      "correctIndex": 0,
      "explanation": "A est la bonne réponse."
    }
  ]
}
```

Pour une question à choix multiples, remplacer `correctIndex` par `correctIndices` :

```json
{
  "id": 2,
  "question": "Quelles réponses sont correctes ?",
  "options": ["A", "B", "C"],
  "correctIndices": [0, 2]
}
```

## CLI quiz

Initialiser un dossier runtime :

```bash
dart run bin/cqcm_quiz.dart --dir cqcm-runtime-data init
```

Ajouter un quiz depuis un package JSON :

```bash
dart run bin/cqcm_quiz.dart --dir cqcm-runtime-data add-quiz --package exemple_import.json
```

Lister les quiz runtime :

```bash
dart run bin/cqcm_quiz.dart --dir cqcm-runtime-data list
```

Documentation détaillée :

- `DOC.md`
- `docs/quiz-cli.md`

## Structure utile

```text
lib/
  models/       Modèles Quiz et Question
  screens/      Accueil, quiz, résultats
  services/     Chargement assets, runtime et import JSON
  widgets/      Cartes, options, progression, Markdown
assets/data/    Catalogue et questions embarqués
bin/            CLI cqcm_quiz.dart
docs/           Documentation spécialisée
test/           Tests unitaires, services, widgets et parcours
```

## Notes de production

Les fichiers dans `assets/data/` sont compilés dans l'application. Pour ajouter des quiz sans rebuild, utiliser le bouton d'import JSON ou un dossier runtime externe via `CQCM_DATA_DIR`.

Sur Android et iOS, l'import dans l'application est l'approche la plus directe. La CLI est surtout adaptée à un environnement desktop ou à une préparation de données avant distribution.
