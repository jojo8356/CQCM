# APK de production pour son téléphone

Objectif : installer sur son propre téléphone une version **release**
(compilée AOT, bien plus rapide que le mode debug) **limitée à son
architecture** (APK plus léger) et **signée de façon stable** (les mises à
jour s'installent par-dessus).

## 1. La commande

Avec le script fourni, tout est automatique — il lit l'architecture du
téléphone connecté :

```bash
tools/build-apk.sh --install
```

Sans script, les deux étapes à la main :

```bash
# 1. architecture du téléphone (branche-le, débogage USB accepté)
adb shell getprop ro.product.cpu.abi        # ex. arm64-v8a

# 2. compilation pour cette seule architecture + installation
flutter build apk --release --target-platform android-arm64
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

`ro.product.cpu.abi` → `--target-platform` :

| Réponse du téléphone | `--target-platform` |
| --- | --- |
| `arm64-v8a` | `android-arm64` |
| `armeabi-v7a` | `android-arm` |
| `x86_64` (émulateur) | `android-x64` |

Sans `--target-platform`, Flutter compile **les trois** architectures dans un
même APK : inutile pour un appareil précis, et sensiblement plus lourd.

## 2. Le cas de l'Oukitel WP32 / WP32 Pro

Caractéristiques utiles pour le build (fiches techniques WP32 et WP32 Pro ;
le numéro de série relevé par `adb devices` — `WP32Pro…` — indique la variante
Pro) :

| Élément | Valeur | Conséquence |
| --- | --- | --- |
| SoC | Unisoc T606 / UMS9230, 8 cœurs **64 bits** (2×Cortex-A75 + 6×Cortex-A55) | `arm64-v8a` → `--target-platform android-arm64` |
| Système | Android 14 (WP32 Pro) / Android 13 (WP32) | `minSdk` 24 et `compileSdk` 36 du projet conviennent ; aucun réglage à changer |
| Mémoire | 6 Go (Pro) / 4 Go de RAM | écart debug/release très net : la release (AOT) est la seule version fluide |
| Écran | 5,93" 720×1440, densité 320 dpi | 720 ÷ 2 = **360 dp de large** — exactement la largeur des tests « écrans étroits » (`test/narrow_screens_test.dart`) |

Vérification des valeurs sur l'appareil (les mêmes commandes que le script) :

```bash
adb shell getprop ro.product.cpu.abi       # arm64-v8a
adb shell getprop ro.product.cpu.abilist   # arm64-v8a,armeabi-v7a,armeabi
adb shell wm size                          # Physical size: 720x1440
adb shell wm density                       # Physical density: 320  → 360 dp de large
```

Commande recommandée pour ce téléphone (une seule architecture, symboles de
débogage sortis du binaire, installation) :

```bash
tools/build-apk.sh --install --symbols
```

Équivalent à la main :

```bash
flutter build apk --release --target-platform android-arm64 \
  --split-debug-info=build/symbols
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

Android 13 exige l'autorisation `POST_NOTIFICATIONS` à l'exécution : au
premier lancement, passer par l'écran des rappels (bouton **Autorisation**)
puis **Notification de test** pour la valider — les rappels ne s'affichent
pas sans elle.

## 3. Options du script

| Commande | Effet |
| --- | --- |
| `tools/build-apk.sh` | release pour l'architecture du téléphone connecté |
| `tools/build-apk.sh --install` | idem + `adb install -r` |
| `tools/build-apk.sh --abi arm64` | sans téléphone branché (`arm64`, `arm`, `x64`) |
| `tools/build-apk.sh --split` | un APK par architecture (tous les `.apk`) |
| `tools/build-apk.sh --bundle` | App Bundle `.aab` (Play Store) |
| `tools/build-apk.sh --symbols` | symboles de débogage hors du binaire : APK plus léger |
| `tools/build-apk.sh --obfuscate --symbols` | + noms Dart illisibles |
| `tools/build-apk.sh --build-number 42` | numéro de version (sinon `pubspec.yaml`) |
| `tools/build-apk.sh --device SERIAL` | plusieurs appareils branchés |
| `tools/build-apk.sh --clean` | `flutter clean` avant de compiler |
| `tools/build-apk.sh --any-flutter` | accepter un SDK autre que l'épinglé |

À la fin, le script affiche le chemin, la taille et le `sha256` de chaque APK.

## 4. Pourquoi la release est plus rapide

En debug, Dart tourne dans une machine virtuelle (JIT) avec les assertions :
c'est ce qui permet le hot reload. En release, le code est compilé en natif
(AOT), les icônes non utilisées sont retirées (`tree-shake-icons`, actif par
défaut) et le `debug` de Flutter est désactivé. Gains typiques : ouverture
instantanée, pas de saccades dans les listes — visible sur un écran d'entrée
de gamme.

Réglages supplémentaires, à garder pour plus tard :

```bash
# APK plus léger : les symboles de débogage sortent du binaire
flutter build apk --release --target-platform android-arm64 \
  --split-debug-info=build/symbols

# + protection du code (les rapports de plantage exigent build/symbols/)
flutter build apk --release --target-platform android-arm64 \
  --split-debug-info=build/symbols --obfuscate

# d'où vient le poids de l'APK (nécessite une seule architecture)
flutter build apk --release --target-platform android-arm64 --analyze-size
```

`build/symbols` doit être conservé pour décoder un rapport de plantage : à
sauvegarder à côté de l'APK si l'application est distribuée.

### Ce qui réduit déjà le poids sans rien faire

- **R8** (rétrécissement, optimisation, renommage du bytecode) et le **retrait
  des ressources inutilisées** sont actifs par défaut dès qu'un build release
  est demandé : le plugin Gradle de Flutter positionne `minifyEnabled` et
  `shrinkResources` sur le type de build `release`. `shrink=false` dans
  `android/gradle.properties` les désactiverait (le script avertit dans ce cas).
- **Retrait des icônes non utilisées** (`tree-shake-icons`, actif par défaut).
- **Bibliothèques natives** : seule l'architecture visée est embarquée.
- Les données de l'application ne pèsent que **360 Ko** (`assets/data`,
  16 fichiers JSON) : l'essentiel du poids est le moteur Flutter lui-même.

### R8 et les notifications

`flutter_local_notifications` enregistre ses rappels programmés dans les
`SharedPreferences` en JSON, produit et relu **par réflexion** avec Gson. R8
renommant les champs par défaut, un rappel écrit par une version du binaire
peut devenir illisible après une mise à jour — le rappel disparaît alors sans
message. `android/app/proguard-rules.pro` (versionné) contient les règles qui
figent les noms nécessaires ; le rétrécissement et les optimisations restent
actifs. Ce fichier est lu automatiquement par le plugin Flutter, il n'y a rien
à déclarer côté Gradle.

En cas de doute après un build release, lancer **Notification de test** depuis
l'écran des rappels et vérifier `adb logcat | grep -i cqcm`.

## 5. Signature : la clé de débogage, puis la vraie

Par défaut (`android/app/build.gradle.kts`), la release est **signée avec la clé
de débogage** : l'APK s'installe très bien sur son propre téléphone, mais

- la clé de débogage diffère d'une machine à l'autre → un APK compilé ailleurs
  ne peut pas remplacer l'installation existante ;
- la supprimer (`rm ~/.android/debug.keystore`) change la signature ;
- le Play Store refuse une clé de débogage.

Pour une clé stable (2 minutes, une seule fois) :

```bash
keytool -genkey -v -keystore ~/cqcm-release.jks \
  -keyalg RSA -keysize 2048 -validity 10000 -alias cqcm
# mémorise le mot de passe du keystore et celui de l'alias

cat > android/key.properties <<'EOF'
storeFile=/home/pj509414/cqcm-release.jks
storePassword=MOT_DE_PASSE_KEYSTORE
keyAlias=cqcm
keyPassword=MOT_DE_PASSE_ALIAS
EOF
```

`android/key.properties` n'est pas versionné (`android/.gitignore`) — il ne doit
jamais l'être. `android/app/build.gradle.kts` détecte le fichier : présent, la
release est signée avec ce keystore ; absent, elle retombe sur la clé de
débogage (le développement reste inchangé). Sauvegardez `cqcm-release.jks` et
ses mots de passe ailleurs : sans eux, impossible de mettre à jour
l'application.

⚠️ Le passage clé de débogage → vraie clé change la signature : la première
installation échouera avec `INSTALL_FAILED_UPDATE_INCOMPATIBLE`. Il faut
désinstaller l'ancienne application (elle perd sa progression locale) :

```bash
adb uninstall com.cqcm.cqcm
tools/build-apk.sh --install
```

## 6. Autres façons d'installer

```bash
# build + install en une commande Flutter (release)
flutter install --release

# seulement lancer ce qui est déjà compilé
adb shell monkey -p com.cqcm.cqcm 1

# copier l'APK et l'installer à la main sur un appareil sans câble
adb push build/app/outputs/flutter-apk/app-release.apk /sdcard/Download/
# puis, sur le téléphone : ouvrir le fichier depuis « Fichiers »
```

Pour tester le comportement exact de la version de production **avec** les logs
et le hot reload, `flutter run --release` compile en release et le lance sur
l'appareil branché.

## 7. Téléphone invisible pour adb sous Linux

Symptôme, à chaque commande `adb` :

```text
error: insufficient permissions for device: user in plugdev group;
are your udev rules wrong?
```

Le téléphone **est** branché et vu par Linux : ce sont les règles udev qui
donnent l'accès USB à `root` seulement. Le fabricant du WP32 (Unisoc) n'est pas
dans les règles installées par Android Studio.

**En USB, aucune adresse IP n'est nécessaire** : seul le droit d'accès au
périphérique manque. Le débogage sans fil (§7b) n'est qu'un contournement pour
les machines sans `sudo`.

### a) Règle udev pour l'USB (recommandé, si sudo est disponible)

```bash
tools/android-udev-rule.sh            # détecte le fabricant et affiche la règle
tools/android-udev-rule.sh --install  # la pose (sudo demandé), recharge udev
```

Le script lit `lsusb`, reconnaît le téléphone (Unisoc/Spreadtrum, WP32 Pro),
écrit `/etc/udev/rules.d/51-android.rules`, recharge les règles et redémarre le
serveur adb. Ensuite : **débrancher/rebrancher le câble**, puis `adb devices`
doit afficher `device`. Aucun redémarrage de session nécessaire.

À la main, si tu préfères :

```bash
lsusb | grep -iE 'unisoc|spreadtrum'   # relever l'idVendor (1782 pour Unisoc)
echo 'SUBSYSTEM=="usb", ATTR{idVendor}=="1782", MODE="0666", GROUP="plugdev"' \
  | sudo tee /etc/udev/rules.d/51-android.rules
sudo udevadm control --reload-rules && sudo udevadm trigger
adb kill-server && adb devices
```

Si l'ajout au groupe `plugdev` est récent, une reconnexion de session peut être
nécessaire (vérifier avec `groups | grep plugdev`) — le script détecte ce cas et
utilise le groupe principal à la place.

### b) Débogage sans fil (uniquement sans sudo)

Android 11+ le permet ; le WP32 Pro est sous Android 14. Sur le téléphone :
**Paramètres → Système → Options pour les développeurs → Débogage sans fil**
→ activer. Deux ports différents entrent en jeu : celui de l'**association** et
celui de la **connexion** (affiché sur l'écran principal du débogage sans fil).

```bash
# 1. « Associer l'appareil avec un code d'association » sur le téléphone :
#    noter IP:PORT et le code à 6 chiffres
adb pair 192.168.1.42:39465         # port d'ASSOCIATION, le code est demandé

# 2. se connecter au port de CONNEXION (celui de l'écran principal)
adb connect 192.168.1.42:5555

# 3. vérifier
adb devices                         # 192.168.1.42:5555   device
tools/build-apk.sh --install --symbols
```

Le PC et le téléphone doivent être sur le même réseau Wi-Fi. Le port de
connexion change à chaque réactivation du débogage sans fil ou redémarrage :
refaire `adb connect`. L'appairage, lui, persiste.

Prérequis : `adb pair` n'existe qu'à partir de **platform-tools 30.0.0**
(`adb: unknown command pair` = outil trop ancien). Mise à jour, au choix :

```bash
# a) via le SDK Android déjà installé
~/android-sdk/cmdline-tools/latest/bin/sdkmanager --install platform-tools

# b) téléchargement direct (aucun SDK requis)
cd ~ && curl -O \
  https://dl.google.com/android/repository/platform-tools-latest-linux.zip
unzip -q -o platform-tools-latest-linux.zip     # crée ~/platform-tools/
~/platform-tools/adb version                    # 36.x
export PATH="$HOME/platform-tools:$PATH"        # ou laisser faire le script :
                                                # il cherche ~/platform-tools/adb
```

Attention à l'IP : celle des exemples (192.168.1.42) est fictive. Lire celle
affichée par l'écran **Débogage sans fil** du téléphone, et vérifier que le PC
est sur le même réseau (`ip -4 addr | grep 192.168`). `No route to host` =
mauvaise IP, débogage sans fil désactivé, ou réseaux différents (certains
Wi-Fi invités isolent les clients entre eux).

### c) Se passer complètement d'adb (aucun câble requis)

La compilation n'a pas besoin du téléphone : seule la détection de
l'architecture et l'installation l'utilisent.

```bash
tools/build-apk.sh --abi arm64 --symbols       # APK arm64 seul, sans adb
cd build/app/outputs/flutter-apk
python3 -m http.server 8000                    # servir le dossier des APK
# sur le téléphone (même Wi-Fi) : http://<ip-du-pc>:8000/app-release.apk
# télécharger, puis installer depuis « Fichiers » (sources inconnues)
```

Autre transfert possible : câble USB en mode MTP (copie de fichier), sans
règle udev ni débogage.

## 8. Le SDK Android que Gradle utilise

Avec plusieurs SDK sur la machine (celui du paquet de la distribution dans
`/usr/lib/android-sdk`, celui d'Android Studio, un SDK téléchargé à la main),
Gradle peut travailler dans le mauvais. Symptôme typique, avec un SDK sans
`cmdline-tools` ni licences acceptées :

```text
Warning: License for package NDK (Side by side) 28.2.13676358 not accepted.
com.android.builder.sdk.LicenceNotAcceptedException:
Failed to install the following Android SDK packages as some licences have not
been accepted.  ndk;28.2.13676358
  Using Android SDK: /usr/lib/android-sdk
```

Pourquoi le NDK est demandé : le plugin Gradle de Flutter **impose un NDK** à
tout projet d'application — il configure un CMake factice uniquement pour
qu'AGP le télécharge (voir `FlutterPluginUtils.forceNdkDownload`). Ce projet
n'ayant aucun code natif, le NDK ne sert à rien ici : il est une exigence de
l'outillage Flutter, pas du code. S'il est déjà installé dans le SDK utilisé, il
n'y a aucun téléchargement.

### Quel SDK est utilisé

Ordre de résolution (le premier trouvé gagne) :

1. `flutter config --android-sdk …` (réglage `android-sdk`) ;
2. `ANDROID_HOME`, puis `ANDROID_SDK_ROOT` ;
3. `~/Android/Sdk` (défaut de Flutter sous Linux).

Flutter écrit ce chemin dans `android/local.properties` (`sdk.dir`, non
versionné) à chaque build, et le transmet à Gradle.

### Diagnostic et réparation

```bash
tools/android-sdk-doctor.sh                  # inventorie les SDK, dit lequel sert
tools/android-sdk-doctor.sh --set ~/android-sdk   # imposer le bon SDK à Flutter
tools/android-sdk-doctor.sh --fix            # licences + composants manquants
```

`--fix` accepte les licences et installe `platform-tools`,
`platforms;android-36`, `build-tools;36.0.0` et `ndk;28.2.13676358` (versions
lues dans le SDK Flutter épinglé). Le NDK pèse environ 1 Go à télécharger :
si un autre NDK est déjà installé, le docteur le signale et indique la ligne
`ndkVersion = …` à mettre dans `android/app/build.gradle.kts` pour l'utiliser
tel quel et éviter le téléchargement.

### `sdkmanager` est déprécié : le nouveau CLI Android

Depuis les cmdline-tools récentes, `sdkmanager` affiche à chaque appel :

```text
WARNING: The SDK Manager CLI tool (sdkmanager) is deprecated.
Android CLI will be used instead.
```

**Cet avertissement est sans conséquence** : `sdkmanager` est toujours fourni
et fonctionnel, l'installation se poursuit normalement. Le remplaçant est le
nouveau CLI Android, présent dans le même dossier :

```bash
~/Android/Sdk/cmdline-tools/latest/bin/android sdk install "build-tools;36.0.0"
~/Android/Sdk/cmdline-tools/latest/bin/android sdk list --installed
```

`tools/android-sdk-install.sh` et `tools/android-sdk-doctor.sh --fix`
détectent ce binaire et l'utilisent en priorité (`--sdk <dossier>`, sortie sans
bruit), avec repli automatique sur `sdkmanager` s'il est absent ou échoue. Une
exception : les **licences** passent encore par `sdkmanager --licenses` (le
nouveau CLI n'a pas de sous-commande équivalente) — l'avertissement est alors
filtré, et l'étape est sautée si les licences sont déjà acceptées.

Android CLI sait aussi installer une application, piloter un appareil ou lire
l'arbre d'interface (`android run`, `android device`, `android layout`) : utile
pour automatiser, sans rapport avec le build Flutter lui-même.

L'installeur indique enfin le `PATH` à utiliser pour que `adb` soit celui du
SDK (plus récent que celui du système) — `tools/build-apk.sh` choisit de
lui-même, parmi les adb trouvés, celui dont la version est la plus élevée.

Après réparation : `tools/build-apk.sh --install --symbols`.

### Partir d'un SDK vide (aucun cmdline-tools sur la machine)

Cas d'une machine où le seul SDK est celui du paquet de la distribution
(`/usr/lib/android-sdk`) : sans `cmdline-tools` ni licences, Gradle ne peut
rien y installer, et le build échoue sur le NDK. Le remède est un **SDK
utilisateur complet**, sans root et sans toucher au SDK système :

```bash
tools/android-sdk-install.sh
```

Sans option, le script cherche un zip déjà téléchargé dans `~/Téléchargements`,
`~/Downloads` puis `~`, et sinon **retrouve le lien courant tout seul** : il
interroge l'index du dépôt Android
(`dl.google.com/android/repository/repository2-3.xml`) et prend le zip le plus
récent, avec repli sur la page `developer.android.com/studio`. Inutile donc de
recopier un lien — ceux des exemples et des vieux tutoriels finissent par
renvoyer un 404.

Variantes : `--url '<lien>'` ou `--zip <fichier>` pour forcer une version
précise, `--sdk <dossier>` pour un autre emplacement que `~/Android/Sdk`.

Ce que fait l'installeur : extraction des `cmdline-tools` dans
`<sdk>/cmdline-tools/latest`, acceptation des licences, puis installation de
`platform-tools`, `platforms;android-36`, `build-tools;36.0.0` et du NDK
attendu — versions lues dans le SDK Flutter épinglé. Dossier par défaut
`~/Android/Sdk`, celui que Flutter cherche seul sous Linux ; à la fin,
`flutter config --android-sdk` est réglé pour que Flutter et Gradle l'utilisent.
Prérequis : une JVM 17 ou plus récente (`--java-home` sinon).

### L'astuce du NDK si le disque est juste

Le NDK demandé pèse **~1 Go à télécharger** et **~4 Go une fois installé**.
Or, ce projet ne compile **aucun** code natif : Flutter exige le NDK pour tout
projet d'application (il configure un CMake factice pour le forcer), mais rien
n'est jamais compilé avec. Le contrôle de Flutter est la simple présence de
`ndk/<version>/source.properties` :

```bash
tools/android-sdk-install.sh --fake-ndk   # pose ce marqueur au lieu du NDK
```

Marche à suivre si l'espace manque, avec ses limites :

- le marqueur (quelques octets) suffit tant qu'aucun plugin ne compile de code
  natif — c'est le cas de tous les plugins de ce projet ;
- le jour où un plugin natif est ajouté, supprimer `<sdk>/ndk/<version>` puis
  relancer sans `--fake-ndk` : l'installeur téléchargera le vrai NDK ;
- `tools/android-sdk-doctor.sh` signale ces marqueurs (`(marqueur)`) pour
  qu'ils ne passent pas inaperçus.

**Le marqueur ne suffit pas toujours : `jni` compile vraiment du C.** Certains
paquets bâtissent du code natif à la compilation, et CMake exige alors le
fichier de chaîne d'outils du NDK
(`<ndk>/build/cmake/android.toolchain.cmake`) — un marqueur ne peut pas le
remplacer. C'est le cas de **`path_provider_android` à partir de 2.3.0**, passé
aux appels JNI directs, qui apporte `jni` et `jni_flutter` :

```bash
# le projet compile-t-il du code natif ?
grep -E '^  (jni|jni_flutter):' pubspec.lock
# qui l'apporte ?
tools/flutter-pinned.sh pub deps --style=compact | grep -i jni
```

Symptôme dans le build : `Execution failed for task ':jni:configureCMake…'`
puis `CMake Error … Could not find toolchain file`. Deux sorties, à choisir
selon la place sur le disque :

**(a) Installer le vrai NDK** (~1 Go à télécharger, ~4 Go installés) :

```bash
rm -rf ~/Android/Sdk/ndk/28.2.13676358
tools/android-sdk-install.sh --sdk ~/Android/Sdk     # NDK complet
tools/build-apk.sh --install --symbols
```

**(b) Garder les 4 Go : revenir à `path_provider_android` 2.2.23** — la
dernière version avant la migration JNI (mêmes fonctions, canaux de plateforme
classiques). Le marqueur de NDK suffit alors :

```yaml
# pubspec.yaml
dependency_overrides:
  path_provider_android: 2.2.23
```

```bash
tools/flutter-pinned.sh pub get
tools/build-apk.sh --install --symbols
```

L'application n'utilise `path_provider` que pour `getApplicationSupportDirectory`
(dossier de progression et de QCM importés) : 2.2.23 fait exactement le même
travail. Pour revenir en arrière plus tard, il suffira de supprimer le bloc
`dependency_overrides` et d'installer le vrai NDK.

**Autre cas : un plugin compile du code natif** pour une raison différente
(paquet ajouté plus tard). Deux sorties également :

```bash
# 1. le NDK après la ligne de Flutter (Flutter le connaît : il signale la
#    version manquante exactement)
sed -n '/^android {/,/^}/p' android/app/build.gradle.kts | head          # ndkVersion = flutter.ndkVersion
#    remplacer par la version du message d'erreur, ex. :
#    ndkVersion = "27.1.11552264"

# 2. le vrai NDK à la place du marqueur
rm -rf ~/Android/Sdk/ndk/28.2.13676358
tools/android-sdk-install.sh --sdk ~/Android/Sdk          # NDK complet (~1 Go)
```

Le chemin `1` est le plus rapide quand un NDK existe déjà ailleurs sur la
machine (celui d'un ancien Android Studio, par exemple) : aucune version de NDK
n'est « la bonne » ici, Flutter n'en veut qu'une présente.

`--no-ndk` est le troisième choix : installer tout le reste maintenant et
laisser le NDK pour plus tard (Gradle le réclamera au premier build).

Après réparation : `tools/build-apk.sh --install --symbols`.

## 9. Dépannage

| Message | Cause | Remède |
| --- | --- | --- |
| `INSTALL_FAILED_NO_MATCHING_ABIS` | APK compilé pour une autre architecture | relancer `tools/build-apk.sh` (détection automatique) ou `--abi` |
| `INSTALL_FAILED_UPDATE_INCOMPATIBLE` | application déjà installée, autre signature | `adb uninstall com.cqcm.cqcm` puis réinstaller |
| `INSTALL_FAILED_INSUFFICIENT_STORAGE` | espace libre | libérer de la place sur le téléphone |
| `device unauthorized` | autorisation USB non accordée | accepter « Autoriser le débogage USB » sur le téléphone |
| `insufficient permissions for device` | règles udev (Linux) | §7 : débogage sans fil, règle udev, ou transfert manuel de l'APK |
| `LicenceNotAcceptedException` / `not been accepted` | SDK sans `cmdline-tools` ou licences non acceptées | `tools/android-sdk-doctor.sh --fix` (§8) |
| `ndk;28.2.13676358` manquant | le plugin Flutter impose un NDK | idem — ou pointer `ndkVersion` sur un NDK déjà installé (§8) |
| `Using Android SDK: /usr/lib/android-sdk` alors que le SDK est ailleurs | SDK de la distribution prioritaire | `tools/android-sdk-doctor.sh --set <bon SDK>` (§8) |
| `adb: more than one device` | deux appareils branchés | `--device <serial>` (`adb devices` pour la liste) |
| `No target device found` (`flutter install`) | téléphone non vu | `adb devices`, câble, mode développeur + débogage USB |
| APK toujours lent | build debug/`flutter run` | compiler avec `tools/build-apk.sh` (release) |

Sur le téléphone : Paramètres → À propos → **Numéro de build** (7 appuis) pour
activer les options de développement, puis Paramètres → Système → Options pour
les développeurs → **Débogage USB**.
