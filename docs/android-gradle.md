# Build Android : chaîne Gradle / AGP / Kotlin

Cette page explique les versions utilisées pour compiler l'application Android,
d'où elles viennent, ce que signifient les avertissements affichés par
`flutter run`, comment les masquer, et comment passer plus tard à l'AGP 9.

## 1. Versions du projet

| Fichier | Réglage | Valeur | Minimum exigé par Flutter |
| --- | --- | --- | --- |
| `android/gradle/wrapper/gradle-wrapper.properties` | `distributionUrl` | **8.14.3** | 8.14.0 |
| `android/settings.gradle.kts` | `com.android.application` | **8.11.1** | 8.11.1 |
| `android/settings.gradle.kts` | `org.jetbrains.kotlin.android` | **2.4.0** | 2.2.20 |
| `android/app/build.gradle.kts` | `compileOptions` / `jvmTarget` | **17** | Java 17 |
| `android/app/build.gradle.kts` | `compileSdk` | **36** (`flutter.compileSdkVersion`) | 35 (plugin notifications) |

Ces minimums sont ceux du plugin Gradle embarqué dans le SDK Flutter
(`DependencyVersionChecker`) : en dessous, la compilation s'arrête avec par
exemple « Your project's Gradle version (…) is lower than Flutter's minimum
supported version of 8.14.0 ». Ils montent au fil des versions de Flutter.

Les valeurs choisies sont exactement celles des gabarits `flutter create`
actuels côté Gradle/AGP/Kotlin, et la configuration testée par
`flutter_local_notifications` : AGP 8.11.1 ↔ Gradle 8.13–9.3 et Kotlin 2.4.0 ↔
AGP 8.2.2–9.2 sont des plages déclarées compatibles par Flutter.

Après toute modification de ces fichiers :

```bash
flutter clean          # purge build/ qui garde la configuration précédente
rm -rf android/.gradle # purge le cache de configuration Gradle
```

## 2. Les deux avertissements « will soon be dropped »

```text
Warning: Flutter support for your project's Gradle version (8.14.3) will soon be
dropped. Please upgrade your Gradle version to a version of at least 9.1.0 soon.
Warning: Flutter support for your project's Android Gradle Plugin version
(8.11.1) will soon be dropped. Please upgrade your Android Gradle Plugin version
to a version of at least 9.0.1 soon.
```

Ce sont les seuils « recommandés » de Flutter (`warnGradleVersion` 9.1.0,
`warnAGPVersion` 9.0.1) : au-dessus des minimums, donc **le build continue**.
Ils poussent simplement vers AGP 9 / Gradle 9.

## 3. Les masquer

`android/gradle.properties` contient :

```properties
skipDependencyChecks=true
```

`FlutterPlugin.kt` lit cette propriété de projet et, si elle vaut `true`, saute
`DependencyVersionChecker.checkDependencyVersions` — c'est exactement ce que fait
le drapeau de ligne de commande :

```bash
flutter run --android-skip-build-dependency-validation
```

Ce qui est sauté : la validation des versions de Java, Gradle, AGP, Kotlin et du
`minSdk`. Rien d'autre : compilation, desugaring, plugins et signature sont
inchangés. À connaître : si un jour le build Android échoue bizarrement après une
mise à jour de Flutter, **commenter cette ligne** ramène les messages de version,
beaucoup plus lisibles qu'une erreur Gradle obscure.

## 4. Passer à AGP 9 / Gradle 9 (plus tard, en une seule fois)

La migration est préparée mais volontairement reportée : elle ne supprime pas
d'avertissements, elle en échange (voir la liste ci-dessous), et elle impose des
montées de dépendances.

Modifications à faire ensemble :

```text
gradle-wrapper.properties   8.14.3  -> 9.3.1
settings.gradle.kts         AGP 8.11.1 -> 9.1.0 (Kotlin 2.4.0 inchangé)
app/build.gradle.kts        retirer id("kotlin-android") : Flutter applique
                            KGP lui-même quand builtInKotlin=false
gradle.properties           garder android.newDsl=false et
                            android.builtInKotlin=false (obligatoires),
                            ajouter android.sync.suppressAgpWarnings=DEPRECATED_DSL
pubspec.yaml                flutter_local_notifications ^19.5.0 -> ^22.3.2
                            timezone ^0.10.0 -> ^0.11.0
lib/services/notification_service.dart
                            initialize(settings: …), show(id: …),
                            zonedSchedule(id: …, scheduledDate: …,
                            notificationDetails: …) : l'API 20.x est passée en
                            paramètres nommés
```

Avertissements qui resteraient sur AGP 9 (aucun n'est corrigeable dans le
projet, ils viennent de Flutter ou de KGP) :

| Avertissement | Émetteur |
| --- | --- |
| `The option setting 'android.newDsl=false' is deprecated` | AGP |
| `The option setting 'android.builtInKotlin=false' is deprecated` | AGP |
| `API 'applicationVariants' is obsolete …` | plugin Gradle de Flutter |
| `Deprecated 'org.jetbrains.kotlin.android' plugin usage` | KGP |
| `Your app uses the following plugins that apply Kotlin Gradle Plugin` | plugin Gradle de Flutter |

Pourquoi les opt-outs sont obligatoires aujourd'hui :

- `android.newDsl=false` : le plugin Gradle de Flutter utilise encore l'API de
  variantes historique (`applicationVariants`), migrée progressivement
  ([flutter#166550](https://github.com/flutter/flutter/issues/166550)).
- `android.builtInKotlin=false` : plusieurs paquets Flutter appliquent encore
  `org.jetbrains.kotlin.android`, ce que le Kotlin intégré de l'AGP 9 refuse
  (« The 'org.jetbrains.kotlin.android' plugin is no longer required for Kotlin
  support since AGP 9.0. Solution: Remove … »).

Quand refaire cette bascule : quand le plugin de Flutter n'utilisera plus l'API
de variantes historique et que les paquets du projet n'appliqueront plus KGP —
à ce moment-là les opt-outs et leurs avertissements disparaissent tous seuls.

Rappel : `flutter clean`, `rm -rf android/.gradle` puis `flutter pub get` après
une telle migration.

## 5. Ne plus subir ces problèmes

Le fond du problème est un décalage de trois horloges : le SDK Flutter relève
ses minimums à chaque version, AGP/Gradle relèvent les leurs, et les paquets
tiers suivent avec du retard. Aucun réglage ne supprime ce décalage ; cinq
leviers le rendent gérable, du plus efficace au plus anecdotique.

1. **Figer la version du SDK Flutter.** C'est le levier principal : les
   minimums viennent du SDK, donc un SDK qui ne bouge pas ne fait pas bouger le
   plancher. C'est la version écrite dans `.flutter-version`, utilisée par
   `tools/flutter-pinned.sh` (voir § 7) : les montées de Flutter deviennent une
   décision, avec `tools/android-stack-check.sh` et `flutter test` comme
   garde-fous.
2. **Un diagnostic avant chaque build** (§ 6) : après un `flutter upgrade`, il
   dit en deux secondes si le plancher a monté, et quelles lignes corriger.
3. **Le masquage assumé** (`skipDependencyChecks=true`, § 3) : utile pour ne
   plus voir deux avertissements à chaque build, à condition de faire le
   diagnostic autrement — sinon une montée de minimum devient un échec Gradle
   obscur.
4. **Une surface Android minimale** : chaque greffon natif est une dépendance
   de plus sur AGP/Kotlin, et un candidat de plus pour l'échec du Kotlin
   intégré (`builtInKotlin=false`). Ici les quatre greffons utilisés
   (`file_selector`, `path_provider`, `flutter_local_notifications`,
   `url_launcher`) sont sobres : à garder en tête avant d'en ajouter un.
5. **Un seul JDK**, celui que Flutter recommande (Java 17 aujourd'hui), avec
   `flutter config --jdk-dir` si le `java` du `PATH` est plus ancien : un JDK 11
   est l'autre cause classique d'échec, et elle n'a rien à voir avec AGP.

Ce qui n'est **pas** une solution : monter AGP tout de suite (§ 4). On y gagne
deux avertissements et on en récupère quatre, dont trois émis par le SDK
Flutter lui-même.

## 6. Diagnostic automatique

```bash
tools/android-stack-check.sh            # rapport lisible
tools/android-stack-check.sh --json     # même rapport, exploitable par script
tools/android-stack-check.sh --project AUTRE/DEPOT --flutter-root ~/flutter
```

Le script lit les versions déclarées dans `android/` (wrapper, `settings`,
`app/build.gradle.kts`, `gradle.properties`, `java -version`) et les compare aux
seuils du SDK Flutter **installé**, lus directement dans
`packages/flutter_tools/gradle/src/main/kotlin/DependencyVersionChecker.kt` :

| État affiché | Signification |
| --- | --- |
| `ok` | au-dessus du minimum *et* du seuil recommandé |
| `[!]` | au-dessus du minimum, sous le seuil recommandé : avertissement |
| `KO` | sous un minimum : le build échouera, même avec le masquage |

Il indique aussi si la bascule AGP 9 est devenue possible, en cherchant l'API de
variantes historique (`applicationVariants`, `libraryVariants`…) dans le plugin
Gradle du SDK installé. Code de sortie : `0` tout va bien, `1` un minimum n'est
pas atteint, `2` SDK ou dépôt introuvable — utilisable tel quel dans un script
de build ou un hook git.

## 7. SDK Flutter épinglé

`.flutter-version` contient la version utilisée pour le dépôt (3.47.5) et
`tools/flutter-pinned.sh` lance ce SDK quel que soit le `flutter` du `PATH` :

```bash
tools/flutter-pinned.sh --check                       # version, racine, binaires
tools/flutter-pinned.sh run -d linux
tools/flutter-pinned.sh test
tools/flutter-pinned.sh --dart run bin/test_summary.dart
```

Le SDK attendu est un clone du dépôt à la version épinglée :

```bash
git clone -b 3.47.5 --depth 1 \
  https://github.com/flutter/flutter.git ~/flutter-3.47
```

L'« HEAD détachée » affichée par git est normale sur un tag : il n'y a rien à
réparer, et inutile de créer une branche, sauf pour modifier le SDK lui-même.
Emplacements essayés : `$CQCM_FLUTTER_SDK`, puis `~/flutter-<version>`,
`~/flutter-<majeure.mineure>` (donc `~/flutter-3.47` convient), puis
`~/.cqcm/flutter/<version>`, puis `/opt/flutter-<version>`. Un SDK FVM se pointe
avec `CQCM_FLUTTER_SDK=~/fvm/versions/3.47.5`.

Deux précautions après un changement d'un SDK à l'autre :

```bash
flutter clean            # purge build/ (compilé par l'autre SDK)
rm -rf .dart_tool android/.gradle
tools/flutter-pinned.sh pub get
```

`pubspec.lock` et `.dart_tool/package_config.json` mémorisent des chemins de SDK
et d'artefacts : `pub get` les régénère. `tools/flutter-linux.sh` (bureau Linux
sans root) utilise ce SDK épinglé par défaut, et `CQCM_FLUTTER` force un autre
binaire au besoin.
