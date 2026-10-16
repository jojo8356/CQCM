# Notifications et rappels de révision

Le mode « Recopier texte » (programme GP – user stories) suit une courbe
d'apprentissage : chaque phrase est reprogrammée à J+1, J+3, J+7, puis à
intervalle croissant. Pour que la révision ne dépende pas du hasard, l'application
programme des **notifications système** avec le plugin
[`flutter_local_notifications`](https://pub.dev/packages/flutter_local_notifications).

Tout est piloté par **JSON** : un fichier de configuration embarqué
(`assets/data/notifications.json`), une surcharge locale
(`notifications.json` dans le dossier de données), et une charge utile JSON
attachée à chaque notification.

## 1. Choix de la version du plugin

`pubspec.yaml` fixe :

```yaml
dependencies:
  flutter_local_notifications: ^19.5.0
  timezone: ^0.10.0        # dépendance directe de zonedSchedule
```

La série 19.x est la **dernière compatible avec Dart 3.9 / Flutter 3.22+** :

| Version | Contraintes du plugin |
| --- | --- |
| 19.5.0 | Dart `^3.4.0`, Flutter `>=3.22.0` |
| 20.x | Dart `>=3.8`, Flutter `>=3.32` |
| 21.x / 22.x | Dart `>=3.10`, Flutter `>=3.38.1` |

Ne pas monter en 20+ sans mettre à jour le SDK Flutter du projet. Le plugin 19.5
n'a pas d'implémentation web : `flutter run -d chrome` reste possible, mais les
rappels y sont simplement indisponibles (message dans l'écran Rappels).

## 2. Configuration JSON

`assets/data/notifications.json` (défauts embarqués) :

```json
{
  "enabled": true,
  "hour": 9,
  "minute": 0,
  "timezone": "Europe/Paris",
  "exact": false,
  "maxNotifications": 8,
  "requestPermissionOnStart": true,
  "channelId": "cqcm-revision",
  "channelName": "Révision CQCM",
  "channelDescription": "Rappels du programme de révision des user stories",
  "titleTemplate": "GP – {count} phrase(s) à réviser",
  "bodyTemplate": "Commence par : {prompt}"
}
```

| Clé | Effet |
| --- | --- |
| `enabled` | `false` annule tous les rappels programmés |
| `hour`, `minute` | heure locale du rappel (bornées à 0-23 / 0-59) |
| `timezone` | fuseau IANA appliqué par `timezone` ; vide = fuseau de l'appareil |
| `exact` | `true` → `exactAllowWhileIdle` (autorisation « alarmes exactes ») ; `false` → `inexactAllowWhileIdle` |
| `maxNotifications` | nombre maximum de rappels programmés d'un coup (1-32) |
| `requestPermissionOnStart` | demande l'autorisation au premier chargement |
| `channelId`/`channelName`/`channelDescription` | canal Android (créé une seule fois) |
| `titleTemplate` | `{count}`, `{date}`, `{prompt}`, `{deck}` sont remplacés |
| `bodyTemplate` | idem |

Surcharge locale : `NotificationSettingsStore.ensureOverrideFile()` crée un
`notifications.json` minimal au premier passage de l'écran Rappels ; seules les
clés présentes sont appliquées (fusion au-dessus des défauts). Le fichier vit à
côté de la progression :

- `CQCM_REVISION_DIR/notifications.json` si la variable d'environnement est
  définie (desktop, CLI, tests) ;
- sinon `<dossier de support de l'application>/cqcm-revision-data/notifications.json`.

`NotificationSettings` expose `settings.timeLabel`, `effectiveJson` et
`copyWith` ; `NotificationSettingsBundle` garde `defaultsJson`, `overrideJson`,
`overridePath` et `effectiveJson` (affichés dans l'écran Rappels).

## 3. Calcul du plan de rappels

`lib/services/notification_plan.dart` regroupe les phrases **dues** par jour
d'échéance et produit un rappel par jour à l'heure configurée :

```dart
final plan = NotificationPlan.build(
  deckId: 'gp-us',
  deckTitle: 'User stories',
  items: revisionPlan.itemsOf('gp-us'),
  progressFor: revisionPlan.progressFor,
  settings: bundle.settings,
  now: DateTime.now(),
);

plan.status;      // « 3 rappels programmés… » (phrase de statut)
plan.nextFireAt;  // prochaine échéance, ou null
plan.toPrettyJson();
```

Chaque `ReminderNotification` porte `id`, `fireAt`, `title`, `body` et une
`payload` JSON (`deck`, `date`, `itemIds`, `prompt`) : toucher la notification
expose cette charge utile dans `ReminderNotifications.lastPayload`.

## 4. Programmation et écran Rappels

`lib/services/notification_service.dart` :

```dart
final result = await ReminderNotifications.syncRevisionReminders(
  plan: revisionPlan,
  deck: deck,
);
result.summary; // affiché dans l'interface
```

- `initialize()` configure Android (drawable `cqcm_notification`), iOS/macOS
  (`DarwinInitializationSettings`), Linux (`LinuxInitializationSettings`) et
  Windows (`WindowsInitializationSettings('CQCM', 'com.cqcm.cqcm', <guid>)`).
- `applyPlan()` annule les rappels existants puis programme chaque échéance
  (`zonedSchedule`, `payload` JSON).
- `pendingSummary()` liste les rappels réellement enregistrés (`#id · titre · texte`).
- `showTestNotification()` affiche immédiatement la notification de test (id 99).
- `requestPermission()` demande `POST_NOTIFICATIONS` sur Android 13+ et les
  permissions Darwin sur iOS/macOS ; sur Android, `requestExactAlarmsPermission()`
  est demandée en plus quand `exact` vaut `true`.
- `cancelAll()` supprime tous les rappels.

La synchronisation est déclenchée :

- au démarrage du menu d'accueil (`MainMenuScreen`), après le calcul du plan ;
- après chaque séance de révision (`TextRevisionScreen`), car les échéances
  changent ;
- manuellement depuis l'écran **Rappels** (cloche de la barre de titre du menu
  et de l'écran GP).

L'écran `lib/screens/notifications_screen.dart` affiche l'état (activé, heure,
fuseau, mode exact/approximatif, prochaine échéance, plugin initialisé), les
boutons *Synchroniser*, *Autorisation*, *Notification de test*, *Tout annuler*,
la liste des rappels calculés, ceux enregistrés dans le système et les trois
blocs JSON (réglages effectifs, surcharge locale, défauts embarqués).

## 5. Configuration des plateformes

### Android (`android/app/build.gradle.kts`)

```kotlin
android {
    compileSdk = maxOf(35, flutter.compileSdkVersion) // 35 minimum pour la 19.x
    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    defaultConfig { multiDexEnabled = true }
}

kotlin {
    compilerOptions { jvmTarget = JvmTarget.JVM_17 }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    implementation("androidx.window:window:1.0.0")
    implementation("androidx.window:window-java:1.0.0")
}
```

Le desugaring est obligatoire même sans rappel programmé. Les deux dépendances
`androidx.window` sont le contournement documenté par le plugin contre un plantage
sur Android 12L+ lié au desugaring (bogue Flutter
[#110658](https://github.com/flutter/flutter/issues/110658)).

### Android : versions Gradle / AGP / Kotlin

Flutter refuse de démarrer le build si la chaîne Android est trop ancienne
(message « Your project's Gradle version (…) is lower than Flutter's minimum
supported version »). Les valeurs du projet et leurs bornes :

| Fichier | Réglage | Minimum imposé par Flutter | Valeur du projet |
| --- | --- | --- | --- |
| `android/gradle/wrapper/gradle-wrapper.properties` | `distributionUrl` | 8.14.0 | **8.14.3** |
| `android/settings.gradle.kts` | `com.android.application` | 8.11.1 | **8.11.1** |
| `android/settings.gradle.kts` | `org.jetbrains.kotlin.android` | 2.2.20 | **2.4.0** |
| `android/app/build.gradle.kts` | `compileOptions` / `jvmTarget` | Java 17 | **17** |

Ces versions restent dans les plages déclarées compatibles par Flutter
(AGP 8.11.1 ↔ Gradle 8.13–9.3, Kotlin 2.4.0 ↔ AGP 8.2.2–9.2) et correspondent à
la configuration testée par `flutter_local_notifications` 22.x.

Attendu au premier `flutter run` : deux avertissements de *version* (Gradle et
AGP en dessous des seuils « recommandé » de Flutter, qui poussent déjà vers
AGP 9). Ce ne sont pas des erreurs, le build continue. Pour les faire
disparaître il faudra la bascule AGP 9 / Gradle 9, qui implique aussi une
montée de `flutter_local_notifications` en 22.x (son `android/build.gradle`
passe alors de l'AGP 8.6.0 à 8.11.1) et de `timezone` en 0.11.

`android/gradle.properties` ne contient plus `android.enableJetifier` (inutile
ici, retirée par l'AGP 9) mais déclare `android.newDsl=false` et
`android.builtInKotlin=false`, les deux options que les migrations de
`flutter run` ajoutent d'elles-mêmes sur les projets AGP 9.

### Android (`android/app/src/main/AndroidManifest.xml`)

Permissions : `POST_NOTIFICATIONS`, `VIBRATE`, `RECEIVE_BOOT_COMPLETED`,
`SCHEDULE_EXACT_ALARM`. Récepteurs dans `<application>` :

```xml
<receiver android:exported="false"
    android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver" />
<receiver android:exported="false"
    android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver">
    <intent-filter>
        <action android:name="android.intent.action.BOOT_COMPLETED"/>
        <action android:name="android.intent.action.MY_PACKAGE_REPLACED"/>
        <action android:name="android.intent.action.QUICKBOOT_POWERON"/>
        <action android:name="com.htc.intent.action.QUICKBOOT_POWERON"/>
    </intent-filter>
</receiver>
```

`SCHEDULE_EXACT_ALARM` demande une autorisation à l'utilisateur (bouton
*Autorisation*) ; `USE_EXACT_ALARM` la supprime mais restreint la publication sur
les stores. Icône : `android/app/src/main/res/drawable/cqcm_notification.xml`
(silhouette blanche), référencée par `AndroidInitializationSettings`.

### iOS (`ios/Runner/AppDelegate.swift`)

```swift
if #available(iOS 10.0, *) {
  UNUserNotificationCenter.current().delegate = self as UNUserNotificationCenterDelegate
}
```

macOS n'a pas besoin de modification d'`AppDelegate` ; la permission Darwin est
demandée au premier lancement (`requestPermissionOnStart`).

### Linux / Windows / web

- **Linux** : affichage immédiat uniquement, aucune API de planification →
  `supportsScheduling` renvoie `false` et l'écran Rappels l'indique.
- **Windows** : planification supportée ; les notifications non répétées et
  l'absence d'identité de paquet limitent certaines fonctions (annulation).
- **Web** : plugin absent → tous les appels sont neutralisés, l'application
  continue de fonctionner avec les rappels in-app.

## 6. Limites connues

- Certains constructeurs (Xiaomi, Huawei…) tuent les applications en arrière-plan :
  voir <https://dontkillmyapp.com>. Aucun contournement possible côté code.
- Samsung limite à 500 alarmes planifiées via `AlarmManager`.
- iOS ne conserve que les 64 dernières notifications programmées.
- Une charge utile `null` est convertie en chaîne vide par le plugin.
- Les rappels sont **locaux** : aucun serveur, aucun réseau, aucune donnée ne
  quitte l'appareil.

## 7. Vérification rapide

1. `flutter pub get`
2. `flutter analyze`
3. `flutter test`
4. `flutter run`
5. Menu → cloche → *Notification de test* : la notification doit apparaître.
6. *Synchroniser* : la liste « Rappels programmés » et « Enregistrés dans le
   système » doivent afficher les mêmes échéances.
7. Passer `exact` à `true` dans `notifications.json` et appuyer sur
   *Autorisation* pour accorder les alarmes exactes.

Les tests unitaires (`test/notification_plan_test.dart`,
`test/notification_settings_test.dart`) ne touchent jamais au plugin : le calcul
du plan et la lecture du JSON sont testés en pur Dart.
