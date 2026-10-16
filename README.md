# CQCM

CQCM est une application Flutter de révision. L'écran d'accueil est un menu à deux entrées :

- **QCM** : quiz à choix unique ou multiple, avec correction et score ;
- **Recopier texte** : récitation de phrases au mot près (programme **GP** – user stories),
  avec pourcentage de validation, courbe d'apprentissage, révisions espacées et rappels.

Le catalogue de quiz est embarqué dans `assets/data/` et peut aussi être importé en JSON à
l'exécution, sans reconstruire l'application.

## Fonctionnalités

- Menu d'accueil avec choix du mode (QCM ou recopier texte).
- Catalogue de quiz groupé par catégorie.
- Questions à choix unique et choix multiples.
- Explications après validation d'une réponse.
- Écran de résultats avec score et correction question par question.
- Rendu Markdown pour les questions et explications.
- Import de quiz JSON depuis le catalogue QCM.
- Mode « Recopier texte » : comparaison mot à mot, pourcentage de validation,
  structure de user story et contraintes d'énoncé vérifiées.
- Révisions espacées (intervalles 1, 3, 7 jours puis × facteur de facilité) et
  courbe d'apprentissage dans l'écran GP.
- Rappels in-app : pastille, bandeau et prochaine échéance par programme.
- Notifications système programmées par `flutter_local_notifications`, réglées en
  JSON (`assets/data/notifications.json`) et pilotables depuis l'écran « Rappels ».
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

Résumé lisible (une ligne par fichier : `OK`, `OK (warning)`, `OK (error)`, `KO`) :

```bash
dart run bin/test_summary.dart
```

### Version de Flutter épinglée

Les minimums de Gradle / AGP / Kotlin viennent du SDK Flutter **installé** : la
version utilisée pour ce dépôt est écrite dans `.flutter-version` et tous les
scripts passent par elle.

```bash
tools/flutter-pinned.sh --check                 # où est le SDK, quelle version
tools/flutter-pinned.sh run -d linux            # flutter run avec ce SDK
tools/flutter-pinned.sh test
tools/flutter-pinned.sh --dart run bin/test_summary.dart
```

Le SDK attendu est un clone du dépôt à cette version :

```bash
git clone -b 3.47.5 --depth 1 \
  https://github.com/flutter/flutter.git ~/flutter-3.47
```

L'état « HEAD détachée » affiché par git est normal sur un tag. Un SDK géré
autrement (FVM, dossier personnel) se pointe avec
`CQCM_FLUTTER_SDK=/chemin/du/sdk`. `tools/flutter-linux.sh` utilise
automatiquement ce SDK épinglé ; `CQCM_FLUTTER` impose un autre binaire.

Changer de version = modifier `.flutter-version`, puis relancer
`tools/android-stack-check.sh` et `flutter test` (voir `docs/android-gradle.md`).

Analyser le code :

```bash
flutter analyze
```

Compiler l'APK de production **pour son propre téléphone** (release, une seule
architecture, installation directe) :

```bash
tools/build-apk.sh --install
```

Le script lit `ro.product.cpu.abi` du téléphone connecté (ainsi que sa taille
et sa densité d'écran), compile en release avec `--target-platform`
correspondant, puis installe l'APK par `adb install -r`. Sans téléphone branché :
`tools/build-apk.sh --abi arm64`.

Ajouter `--symbols` (recommandé) sort les symboles de débogage du binaire et
allège l'APK ; `--obfuscate --symbols` va plus loin. Le rétrécissement R8 et le
retrait des ressources inutilisées sont déjà actifs en release ; les règles
nécessaires à `flutter_local_notifications` (sérialisation Gson relue par
réflexion) sont dans `android/app/proguard-rules.pro`.

À la main :

```bash
adb shell getprop ro.product.cpu.abi                    # ex. arm64-v8a
flutter build apk --release --target-platform android-arm64
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

APK attendu :

```text
build/app/outputs/flutter-apk/app-release.apk
```

Signature stable (keystore de production), App Bundle pour le Play Store,
options d'optimisation (`--split-debug-info`, `--obfuscate`) et dépannage
d'installation : `docs/android-release.md`.

La chaîne de compilation Android (Gradle 8.14.3, AGP 8.11.1, Kotlin 2.4.0,
Java 17) est décrite dans `docs/android-gradle.md`, y compris le masquage des
deux avertissements de version et la bascule future vers AGP 9. Avant un build,
le diagnostic complet tient en une commande :

```bash
tools/android-stack-check.sh
```

Il compare les versions du projet aux minimums du SDK Flutter installé (et dit
si la bascule AGP 9 est déjà possible). À relancer après chaque
`flutter upgrade`.

## Mode recopier texte (GP)

Depuis le menu d'accueil :

1. Cliquer sur **Recopier texte**.
2. L'écran **GP :** affiche les 12 cas de user stories, la courbe d'apprentissage et
   le rappel du jour.
3. Choisir la taille de la séance (3, 5, 10 ou tout) puis **Réviser** : les phrases
   à réviser sont tirées **au hasard** à chaque séance.
4. Recopier la user story, valider, et lire la correction mot à mot.

Seuil de validation : **95 % des mots attendus** (ponctuation, majuscules, accents et
élisions ne comptent pas). Chaque phrase est ensuite replanifiée : J+1 après une première
réussite, puis 3, 7 jours, puis intervalle × facteur de facilité. Une phrase ratée revient
le jour même.

Progression stockée dans `revision-progress.json` (dossier de support de l'application ou
`CQCM_REVISION_DIR`). Documentation détaillée : `docs/mode-recopier-texte.md`.

## Notifications

Les échéances calculées par la courbe d'apprentissage sont programmées comme
notifications système (heure, fuseau, mode exact/approximatif, textes : tout est
dans `assets/data/notifications.json`, surchargeable par un `notifications.json`
local). L'écran **Rappels** de l'application affiche les réglages et le plan,
permet l'autorisation, la synchronisation et un envoi de test.

Détails et configuration Android/iOS : `docs/notifications.md`.

## Linux desktop sans droits root

`flutter run -d linux` exige les en-têtes GTK 3 (`libgtk-3-dev`), normalement
installés avec `sudo`. Sur une machine sans droits d'administration, extraire le
nécessaire dans un dossier personnel suffit :

```bash
tools/linux-desktop-deps.sh          # télécharge les .deb et les extrait
tools/flutter-linux.sh run -d linux  # wrapper : source l'environnement puis flutter
```

Détails, options et dépannage : `docs/linux-sans-root.md`.

## Importer un quiz JSON

Depuis le catalogue QCM (bouton **QCM** du menu) :

1. Ouvrir l'écran QCM.
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
- `docs/mode-recopier-texte.md`
- `docs/notifications.md`
- `docs/android-gradle.md`
- `docs/android-release.md`
- `docs/linux-sans-root.md`

## Structure utile

```text
lib/
  models/       Quiz, Question, paquets de révision et progression
  screens/      Menu, catalogue QCM, quiz, résultats, programme GP, séance de recopie
  services/     Chargement assets, runtime, import JSON, scoring, planificateur
  widgets/      Cartes, options, progression, Markdown, courbe, diff mot à mot
assets/data/    Catalogue et questions embarqués + programmes de révision
bin/            CLI cqcm_quiz.dart, résumé des tests test_summary.dart
docs/           Documentation spécialisée
test/           Tests unitaires, services, widgets et parcours
```

Les scripts d'environnement (aucun privilège requis) :

```text
tools/android-stack-check.sh   diagnostic Gradle / AGP / Kotlin / Java
tools/android-udev-rule.sh     accès USB du téléphone (règle udev)
tools/android-sdk-doctor.sh    SDK Android utilisé, licences, NDK
tools/build-apk.sh             APK release pour l'architecture du téléphone
tools/flutter-pinned.sh        lance le SDK Flutter de .flutter-version
tools/dev-disk-report.sh       rapport d'occupation disque (n'efface rien)
tools/linux-desktop-deps.sh    sysroot GTK 3 personnel pour le bureau Linux
tools/flutter-linux.sh         wrapper « source l'environnement puis flutter »
```

Le rapport disque liste les postes qui pèsent sur une machine Flutter/Android
(`~/.gradle`, `~/android-sdk`, `~/.pub-cache`, `~/.cache`…) et imprime les
commandes de nettoyage prêtes à copier, avec leur coût réel — il ne supprime
jamais rien :

```bash
tools/dev-disk-report.sh              # rapport complet
tools/dev-disk-report.sh --commands   # seulement les commandes de nettoyage
```

## Notes de production

Les fichiers dans `assets/data/` sont compilés dans l'application. Pour ajouter des quiz sans rebuild, utiliser le bouton d'import JSON ou un dossier runtime externe via `CQCM_DATA_DIR`.

Sur Android et iOS, l'import dans l'application est l'approche la plus directe. La CLI est surtout adaptée à un environnement desktop ou à une préparation de données avant distribution.
