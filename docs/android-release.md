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

## 2. Le cas de l'Oukitel WP32

Caractéristiques utiles pour le build (fiche technique du WP32) :

| Élément | Valeur | Conséquence |
| --- | --- | --- |
| SoC | Unisoc T606 / UMS9230, 8 cœurs 64 bits (Cortex-A75 + A55) | `arm64-v8a` → `--target-platform android-arm64` |
| Système | Android 13 (API 33) | `minSdk` 24 et `compileSdk` 36 du projet conviennent ; aucun réglage à changer |
| Mémoire | 4 Go de RAM | écart debug/release très net : la release (AOT) est la seule version fluide |
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
dans les règles installées par Android Studio. Trois issues, de la plus simple
à la plus lourde.

### a) Débogage sans fil (aucun root, recommandé)

Android 11+ le permet ; le WP32 est sous Android 13. Sur le téléphone :
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

### b) Règle udev (si tu as sudo)

```bash
lsusb | grep -iE 'unisoc|spreadtrum|oukitel'   # relever l'idVendor (1782 ?)
echo 'SUBSYSTEM=="usb", ATTR{idVendor}=="1782", MODE="0666", GROUP="plugdev"' \
  | sudo tee /etc/udev/rules.d/51-android.rules
sudo udevadm control --reload-rules && sudo udevadm trigger
adb kill-server && adb devices
```

Si l'ajout au groupe `plugdev` est récent, une reconnexion de session est
nécessaire (vérifier avec `groups | grep plugdev`).

### c) Se passer complètement d'adb

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

## 8. Dépannage

| Message | Cause | Remède |
| --- | --- | --- |
| `INSTALL_FAILED_NO_MATCHING_ABIS` | APK compilé pour une autre architecture | relancer `tools/build-apk.sh` (détection automatique) ou `--abi` |
| `INSTALL_FAILED_UPDATE_INCOMPATIBLE` | application déjà installée, autre signature | `adb uninstall com.cqcm.cqcm` puis réinstaller |
| `INSTALL_FAILED_INSUFFICIENT_STORAGE` | espace libre | libérer de la place sur le téléphone |
| `device unauthorized` | autorisation USB non accordée | accepter « Autoriser le débogage USB » sur le téléphone |
| `insufficient permissions for device` | règles udev (Linux) | §7 : débogage sans fil, règle udev, ou transfert manuel de l'APK |
| `adb: more than one device` | deux appareils branchés | `--device <serial>` (`adb devices` pour la liste) |
| `No target device found` (`flutter install`) | téléphone non vu | `adb devices`, câble, mode développeur + débogage USB |
| APK toujours lent | build debug/`flutter run` | compiler avec `tools/build-apk.sh` (release) |

Sur le téléphone : Paramètres → À propos → **Numéro de build** (7 appuis) pour
activer les options de développement, puis Paramètres → Système → Options pour
les développeurs → **Débogage USB**.
