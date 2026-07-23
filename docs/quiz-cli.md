# CQCM Quiz CLI

CQCM embarque toujours les quiz de `assets/data/`, mais peut aussi charger des quiz depuis un dossier runtime externe. Ce dossier est choisi au lancement avec la variable d'environnement `CQCM_DATA_DIR`.

L'application propose aussi un bouton d'import dans l'accueil. Il ouvre un sélecteur de fichier JSON, valide le package, l'écrit dans le dossier runtime applicatif, puis recharge la liste des quiz sans rebuild.

## Lancer la production avec un dossier modifiable

```bash
CQCM_DATA_DIR=/var/lib/cqcm/quizzes ./cqcm
```

La CLI ci-dessous écrit dans le même dossier. Les quiz ajoutés dans ce dossier sont lus au prochain lancement de l'application, sans rebuild Flutter.

## Commandes

Initialiser le dossier runtime :

```bash
dart run bin/cqcm_quiz.dart --dir /var/lib/cqcm/quizzes init
```

Lister les quiz runtime :

```bash
dart run bin/cqcm_quiz.dart --dir /var/lib/cqcm/quizzes list
```

Valider un dossier runtime :

```bash
dart run bin/cqcm_quiz.dart --dir /var/lib/cqcm/quizzes validate
```

Valider un package JSON avant import :

```bash
dart run bin/cqcm_quiz.dart validate --package test/fixtures/sample_quiz_package.json
```

Ajouter un quiz depuis un package JSON :

```bash
dart run bin/cqcm_quiz.dart --dir /var/lib/cqcm/quizzes add-quiz \
  --package test/fixtures/sample_quiz_package.json
```

Ajouter un quiz depuis un fichier de questions JSON et des champs CLI :

```bash
dart run bin/cqcm_quiz.dart --dir /var/lib/cqcm/quizzes add-quiz \
  --id qualite-cli \
  --title "Qualite CLI" \
  --description "Questions ajoutees sans rebuild" \
  --category "Qualite" \
  --difficulty intermediaire \
  --icon "Q" \
  --questions ./questions-qualite-cli.json
```

Remplacer un quiz runtime existant :

```bash
dart run bin/cqcm_quiz.dart --dir /var/lib/cqcm/quizzes add-quiz \
  --package ./quiz.json \
  --replace
```

Ajouter une question manuellement :

```bash
dart run bin/cqcm_quiz.dart --dir /var/lib/cqcm/quizzes add-question \
  --quiz-id qualite-cli \
  --question "Quel est l'objectif du dossier runtime ?" \
  --option "Ajouter des quiz sans rebuild" \
  --option "Modifier les assets deja compiles" \
  --correct-index 0 \
  --explanation "Les assets sont empaquetes au build, le runtime est externe."
```

Ajouter une question a choix multiples :

```bash
dart run bin/cqcm_quiz.dart --dir /var/lib/cqcm/quizzes add-question \
  --quiz-id qualite-cli \
  --question "Quels fichiers sont ecrits par la CLI ?" \
  --option "data.json" \
  --option "questions-<id>.json" \
  --option "pubspec.yaml" \
  --correct-indexes 0 \
  --correct-indexes 1
```

Ajouter une question depuis un JSON objet :

```bash
dart run bin/cqcm_quiz.dart --dir /var/lib/cqcm/quizzes add-question \
  --quiz-id qualite-cli \
  --json ./question.json
```

## Format package JSON

```json
{
  "quiz": {
    "id": "cli-sample",
    "title": "CLI Sample",
    "description": "Quiz ajoute par la CLI",
    "category": "CLI",
    "difficulty": "debutant",
    "questionCount": 1,
    "fileName": "questions-cli-sample.json",
    "icon": "C"
  },
  "questions": [
    {
      "id": 1,
      "question": "La CLI peut-elle ajouter un quiz sans rebuild ?",
      "options": ["Oui, via le dossier runtime", "Non, uniquement via assets"],
      "correctIndex": 0,
      "explanation": "L'application lit le dossier runtime en plus des assets embarques."
    }
  ]
}
```

## Limite importante

Cette approche est directe pour une production desktop ou serveur lancee depuis un shell. Sur Android/iOS, une application installee n'a pas un dossier arbitraire modifiable par une CLI locale classique ; il faudra soit une fonctionnalite d'import dans l'application, soit une synchronisation reseau, soit une commande d'administration specifique a l'environnement de deploiement.
