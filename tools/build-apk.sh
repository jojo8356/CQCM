#!/usr/bin/env bash
#
# Construit l'APK de production (release) pour l'architecture du téléphone.
#
# Flutter compile par défaut les trois architectures (armeabi-v7a, arm64-v8a,
# x86_64) dans un seul APK : plus lourd et inutile quand on installe sur un
# appareil précis. Ce script lit `ro.product.cpu.abi` du téléphone connecté,
# choisit `--target-platform` en conséquence, compile en release et affiche le
# chemin, la taille et l'empreinte de l'APK produit.
#
# Usage :
#   tools/build-apk.sh                    # détecte le téléphone connecté
#   tools/build-apk.sh --install          # compile puis installe (adb install)
#   tools/build-apk.sh --abi arm64        # sans téléphone branché
#   tools/build-apk.sh --split            # un APK par architecture
#   tools/build-apk.sh --bundle           # App Bundle (.aab) pour le Play Store
#   tools/build-apk.sh --symbols          # --split-debug-info (APK plus léger)
#   tools/build-apk.sh --obfuscate --symbols
#   tools/build-apk.sh --build-number 42 --build-name 1.1.0
#   tools/build-apk.sh --device SERIAL    # plusieurs appareils branchés
#   tools/build-apk.sh --clean            # flutter clean avant compilation
#   tools/build-apk.sh --any-flutter      # accepter un SDK autre que l'épinglé
#   tools/build-apk.sh --reinstall        # désinstaller avant d'installer
#                                         # (signature différente)
#   tools/build-apk.sh --analyze-size     # rapport de poids du code Dart
#                                         # (JSON + DevTools)
#
# Options d'architecture (--abi) : auto (défaut), arm64, arm, x64.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_DIR"

log() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
ok() { printf '\033[1;32m ok\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*" >&2; }
die() {
  printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2
  exit 1
}

usage() {
  awk 'NR > 2 { if ($0 !~ /^#/) exit; sub(/^# ?/, ""); print }' \
    "${BASH_SOURCE[0]}"
}

# ---------------------------------------------------------------------------
# Options
# ---------------------------------------------------------------------------

ABI=auto
DEVICE=""
INSTALL=0
SPLIT=0
BUNDLE=0
SYMBOLS=0
OBFUSCATE=0
CLEAN=0
ANY_FLUTTER=0
REINSTALL=0
ANALYZE_SIZE=0
EXTRA=()

while [ $# -gt 0 ]; do
  case "$1" in
    --abi)
      shift
      [ $# -gt 0 ] || die "--abi attend arm64, arm, x64 ou auto"
      ABI="$1"
      ;;
    --device)
      shift
      [ $# -gt 0 ] || die "--device attend un numéro de série (adb devices)"
      DEVICE="$1"
      ;;
    --install) INSTALL=1 ;;
    --split) SPLIT=1 ;;
    --bundle) BUNDLE=1 ;;
    --symbols) SYMBOLS=1 ;;
    --obfuscate) OBFUSCATE=1 ;;
    --clean) CLEAN=1 ;;
    --any-flutter) ANY_FLUTTER=1 ;;
    --reinstall) REINSTALL=1 ;;
    --analyze-size) ANALYZE_SIZE=1 ;;
    --build-name | --build-number | --dart-define | --flavor)
      [ $# -ge 2 ] || die "$1 attend une valeur"
      EXTRA+=("$1" "$2")
      shift
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      warn "option inconnue : $1"
      usage >&2
      exit 2
      ;;
  esac
  shift
done

# ---------------------------------------------------------------------------
# Outils : flutter et adb
# ---------------------------------------------------------------------------

PINNED="$(awk '
  /^[[:space:]]*#/ { next }
  /^[[:space:]]*$/ { next }
  { print $1; exit }
' .flutter-version 2>/dev/null || true)"

FLUTTER_BIN=""
if [ -x "$SCRIPT_DIR/flutter-pinned.sh" ]; then
  FLUTTER_BIN="$("$SCRIPT_DIR/flutter-pinned.sh" --print 2>/dev/null || true)"
fi

if [ -z "$FLUTTER_BIN" ]; then
  # Le SDK épinglé manque : laisser parler flutter-pinned.sh (liste des
  # emplacements essayés + commande de clone), au lieu d'un message vague.
  warn "SDK Flutter épinglé ${PINNED:-?} introuvable .flutter-version"
  if [ -x "$SCRIPT_DIR/flutter-pinned.sh" ]; then
    "$SCRIPT_DIR/flutter-pinned.sh" --check >&2 || true
  fi
  FLUTTER_BIN="$(command -v flutter || true)"
  if [ -n "$FLUTTER_BIN" ]; then
    HAVE="$("$FLUTTER_BIN" --version 2>/dev/null | head -n 1 |
      awk '{print $2}' || true)"
    warn "repli sur le flutter du PATH : $FLUTTER_BIN (${HAVE:-version inconnue})"
    if [ -n "$PINNED" ] && [ "$HAVE" != "$PINNED" ]; then
      if [ "$ANY_FLUTTER" = "1" ]; then
        warn "version différente de l'épinglée ($PINNED) : --any-flutter demandé, \
on continue"
        warn "un SDK plus ancien échouera sur pubspec.yaml (Dart >= 3.9.2)"
      else
        die "SDK $HAVE alors que .flutter-version épingle $PINNED : \
installer le SDK épinglé (voir ci-dessus), pointer CQCM_FLUTTER_SDK vers un \
SDK $PINNED, ou forcer avec --any-flutter"
      fi
    fi
  fi
fi
[ -n "$FLUTTER_BIN" ] ||
  die "flutter introuvable : installer le SDK épinglé, puis relancer"

# Majeure de platform-tools d'un adb (« Version 36.0.2 » → 36), 0 si inconnue.
adb_major_version() {
  local bin="$1" version
  version="$("$bin" version 2>/dev/null |
    sed -n 's/.*Version \([0-9][0-9]*\)\..*/\1/p' | head -n 1 || true)"
  [ -n "$version" ] || version=0
  printf '%s\n' "$version"
}

# Parmi tous les adb disponibles, garder le plus récent : celui du système est
# souvent plus vieux (par exemple sans `adb pair`, ajouté en 30.0.0) que celui
# du SDK Android installé pour le projet.
ADB_BIN=""
ADB_MAJOR=-1
consider_adb() {
  local candidate="$1" version
  [ -n "$candidate" ] || return 0
  [ -x "$candidate" ] || return 0
  version="$(adb_major_version "$candidate")"
  if [ "$version" -gt "$ADB_MAJOR" ]; then
    ADB_MAJOR="$version"
    ADB_BIN="$candidate"
  fi
}
consider_adb "$(command -v adb 2>/dev/null || true)"
for candidate in \
  "$HOME/platform-tools/adb" \
  "$HOME/.cqcm/platform-tools/adb" \
  "${ANDROID_HOME:-}/platform-tools/adb" \
  "${ANDROID_SDK_ROOT:-}/platform-tools/adb" \
  "$HOME/android-sdk/platform-tools/adb" \
  "$HOME/Android/Sdk/platform-tools/adb"; do
  consider_adb "$candidate"
done
if [ -n "$ADB_BIN" ] && [ "$ADB_MAJOR" != "0" ]; then
  log "adb : $ADB_BIN (platform-tools $ADB_MAJOR)"
fi

# ---------------------------------------------------------------------------
# Architecture du téléphone
# ---------------------------------------------------------------------------

# abi -> cible Flutter. x86 (32 bits) n'est plus supporté par Flutter.
target_for_abi() {
  case "$1" in
    arm64 | arm64-v8a) printf 'android-arm64' ;;
    arm | armeabi-v7a | armeabi) printf 'android-arm' ;;
    x64 | x86_64) printf 'android-x64' ;;
    *) printf '' ;;
  esac
}

# Explique pourquoi adb ne peut pas parler au téléphone, au lieu de laisser
# croire qu'aucun appareil n'est branché.
adb_hint() {
  local out version
  out="$("${ADB[@]}" devices 2>&1 || true)"
  # La liste brute : elle donne le numéro de série et l'état exact.
  if [ -n "$out" ]; then
    printf '%s\n' "$out" | sed 's/^/    | /' >&2
  fi
  case "$out" in
    *"insufficient permissions"* | *"no permissions"*)
      warn "le téléphone est vu par adb mais Linux refuse l'accès (règles udev)"
      warn "  le câble fonctionne : il manque juste l'autorisation Linux"
      warn "  avec sudo : tools/android-udev-rule.sh --install"
      warn "  sans sudo : débogage SANS FIL sur le téléphone"
      warn "    Options pour les développeurs → Débogage sans fil → activer,"
      warn "    « Associer l'appareil avec un code » → puis sur le PC :"
      warn "    adb pair <ip>:<port_association>      (port d'ASSOCIATION)"
      warn "    adb connect <ip>:<port_connexion>     (port de CONNEXION)"
      version="$("$ADB_BIN" version 2>/dev/null |
        sed -n 's/.*Version \([0-9][0-9]*\)\..*/\1/p' | head -n 1 || true)"
      if [ -n "$version" ] && [ "$version" -lt 30 ]; then
        warn "ce platform-tools est en $version : la commande adb pair"
        warn "n'existe pas avant 30.0.0 — le mettre a jour :"
        warn "  ${ANDROID_HOME:-~/android-sdk}/cmdline-tools/latest/"
        warn "    bin/sdkmanager --install platform-tools"
        warn "  ou dl.google.com → platform-tools-latest-linux.zip, extrait"
        warn "    dans ~/platform-tools (le script le trouvera tout seul)"
      fi
      ;;
    *unauthorized*)
      warn "téléphone non autorisé : accepter « Autoriser le débogage USB » \
sur l'écran du téléphone, puis relancer"
      ;;
    *offline*)
      warn "téléphone hors ligne : débrancher/rebrancher le câble, ou \
« adb kill-server »"
      ;;
    *) ;;
  esac
}

# Interroge une propriété du téléphone (vide si absente ou pas d'appareil).
device_getprop() {
  "${ADB[@]}" shell getprop "$1" 2>/dev/null | tr -d '\r' | head -n 1 || true
}

# Affiche la taille et la densité logiques : c'est ce qui fixe la largeur en dp
# (un écran 720 px à 320 dpi = 360 dp de large, comme les tests écrans étroits).
report_screen() {
  local size density width_px density_dpi
  size="$("${ADB[@]}" shell wm size 2>/dev/null | tr -d '\r' | head -n 1 ||
    true)"
  density="$("${ADB[@]}" shell wm density 2>/dev/null | tr -d '\r' |
    head -n 1 || true)"
  width_px="$(printf '%s' "$size" | sed -n 's/.*: *\([0-9]\+\)x[0-9]\+.*/\1/p')"
  density_dpi="$(printf '%s' "$density" | sed -n 's/.*: *\([0-9]\+\).*/\1/p')"
  if [ -n "$width_px" ] && [ -n "$density_dpi" ] && [ "$density_dpi" != "0" ]
  then
    log "écran : ${size#*: }, densité ${density_dpi} dpi \
→ $((width_px * 160 / density_dpi)) dp de large"
  fi
}

DEVICE_ABI=""
if [ "$ABI" = "auto" ]; then
  if [ -z "$ADB_BIN" ]; then
    warn "adb introuvable : impossible de détecter le téléphone"
  else
    ADB=("$ADB_BIN")
    [ -n "$DEVICE" ] && ADB+=("-s" "$DEVICE")
    # `ro.product.cpu.abi` (ABI principale) puis, en secours, la première
    # entrée de `ro.product.cpu.abilist`.
    DEVICE_ABI="$(device_getprop ro.product.cpu.abi)"
    if [ -z "$DEVICE_ABI" ]; then
      DEVICE_ABI="$(device_getprop ro.product.cpu.abilist | cut -d, -f1)"
    fi
    if [ -z "$DEVICE_ABI" ]; then
      adb_hint
      warn "aucun téléphone exploitable par adb : utilise --abi, ou branche-le \
et accepte le débogage USB"
    else
      log "téléphone détecté : architecture $DEVICE_ABI"
      report_screen
    fi
  fi
fi

if [ -n "$DEVICE_ABI" ]; then
  ABI="$DEVICE_ABI"
fi
if [ "$ABI" = "auto" ]; then
  ABI="arm64"
  warn "architecture non détectée : compilation pour arm64 (arm64-v8a), \
le cas de la quasi-totalité des téléphones récents"
fi

TARGET="$(target_for_abi "$ABI")"
[ -n "$TARGET" ] || die "architecture non reconnue : $ABI"

# ---------------------------------------------------------------------------
# Préparation
# ---------------------------------------------------------------------------

# Le rétrécissement R8 (code) et le retrait des ressources inutilisées sont
# actifs par défaut en release ; `shrink=false` les désactiverait.
if grep -qE '^[[:space:]]*shrink[[:space:]]*=[[:space:]]*false' \
  android/gradle.properties 2>/dev/null; then
  warn "shrink=false dans android/gradle.properties : R8 et le retrait des \
ressources sont désactivés, l'APK sera plus lourd"
fi

# Pre-vol : un paquet du projet compile du code natif, et le NDK du SDK n'est
# qu'un marqueur ? Autant le dire avant deux minutes de compilation.
preflight_native_ndk() {
  local native_pkgs=() sdk_dir ndk_dir marker="" version
  for pkg in jni jni_flutter; do
    if grep -q "^  $pkg:" pubspec.lock 2>/dev/null; then
      native_pkgs+=("$pkg")
    fi
  done
  [ "${#native_pkgs[@]}" -gt 0 ] || return 0

  sdk_dir="$(sed -n 's/^sdk\.dir=//p' android/local.properties 2>/dev/null |
    head -n 1)"
  [ -n "$sdk_dir" ] || sdk_dir="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
  [ -n "$sdk_dir" ] || sdk_dir="$HOME/Android/Sdk"
  ndk_dir="$sdk_dir/ndk"
  [ -d "$ndk_dir" ] || return 0

  for version in $(find "$ndk_dir" -maxdepth 1 -mindepth 1 -type d \
    -printf '%f\n' 2>/dev/null || true); do
    [ -d "$ndk_dir/$version/toolchains" ] || marker="$marker $version"
  done
  [ -n "$marker" ] || return 0

  warn "${native_pkgs[*]} compile(nt) du code natif (CMake) mais le NDK de"
  warn "  $sdk_dir n'est qu'un marqueur :$marker"
  warn "  le build va echouer sur « Could not find toolchain file »"
  warn "  1. vrai NDK :"
  for version in $marker; do
    warn "       rm -rf $ndk_dir/$version"
  done
  warn "       tools/android-sdk-install.sh --sdk $sdk_dir"
  warn "  2. ou epingler path_provider_android 2.2.23 dans pubspec.yaml"
}

if [ "$CLEAN" = "1" ]; then
  log "flutter clean"
  "$FLUTTER_BIN" clean
fi

preflight_native_ndk

if [ "$SYMBOLS" = "1" ] || [ "$OBFUSCATE" = "1" ]; then
  EXTRA+=(--split-debug-info=build/symbols)
fi
if [ "$OBFUSCATE" = "1" ]; then
  EXTRA+=(--obfuscate)
fi

# ---------------------------------------------------------------------------
# Compilation
# ---------------------------------------------------------------------------

# Explique l'échec à partir du journal de compilation, au lieu de laisser
# l'utilisateur seul devant la sortie de Gradle.
report_build_failure() {
  local logfile="$1" sdk
  sdk="$(sed -n 's/.*Using Android SDK: *//p' "$logfile" | head -n 1)"

  if grep -qE "not been accepted|LicenceNotAcceptedException" "$logfile"; then
    warn "des composants du SDK Android ne peuvent pas être installés : \
licences non acceptées"
    [ -n "$sdk" ] && warn "  SDK concerné : $sdk"
    warn "  inventaire : tools/android-sdk-doctor.sh"
    warn "  réparation : tools/android-sdk-doctor.sh --fix${sdk:+ $sdk}"
  fi
  if grep -q "ndk;" "$logfile"; then
    warn "le plugin Gradle de Flutter impose un NDK pour tout projet \
d'application (il configure un CMake factice pour le forcer)"
    warn "  ce projet n'a aucun code natif : le NDK n'est là que pour Flutter"
    warn "  il doit être installé dans le SDK utilisé par Gradle — \
tools/android-sdk-doctor.sh --fix s'en charge"
  fi
  if grep -qE "Could not find toolchain file|configureCMake" "$logfile"; then
    warn "un paquet du projet compile du code natif (CMake) : le NDK COMPLET"
    warn "  est requis, pas seulement un marqueur"
    warn "  chaine habituelle : path_provider -> path_provider_android >= 2.3.0"
    warn "  -> jni, qui compile du C pour Android"
    warn "  deux sorties :"
    warn "    1. installer le vrai NDK (~1 Go, ~4 Go installes) :"
    warn "         rm -rf ~/Android/Sdk/ndk/<version>"
    warn "         tools/android-sdk-install.sh --sdk ~/Android/Sdk"
    warn "    2. garder le disque libre : epingler le paquet natif"
    warn "         dependency_overrides: path_provider_android: 2.2.23"
    warn "       (derniere version avant la migration JNI, puis flutter pub get)"
  fi
  if grep -qE "Gradle version .* is lower|requires Gradle" "$logfile"; then
    warn "version de Gradle trop ancienne : tools/android-stack-check.sh, \
puis docs/android-gradle.md"
  fi
  if grep -qE "Unsupported class file major version|requires Java" "$logfile"; then
    warn "problème de version de Java : tools/android-stack-check.sh"
  fi
}

# Lance la commande Flutter en gardant la sortie dans un journal (utile pour
# diagnostiquer, et affiché en direct).
run_flutter_build() {
  local logfile
  logfile="$(mktemp -t cqcm-build-XXXXXX.log)"
  log "flutter $*"
  if "$FLUTTER_BIN" "$@" 2>&1 | tee "$logfile"; then
    rm -f "$logfile"
    return 0
  fi
  printf '\n'
  report_build_failure "$logfile"
  warn "journal de compilation conservé : $logfile"
  exit 1
}

if [ "$BUNDLE" = "1" ]; then
  run_flutter_build build appbundle --release "${EXTRA[@]}"
  ARTIFACT="build/app/outputs/bundle/release/app-release.aab"
  [ -f "$ARTIFACT" ] || die "App Bundle attendu introuvable : $ARTIFACT"
  ok "App Bundle : $ARTIFACT ($(du -h "$ARTIFACT" | cut -f1))"
  printf '    %s\n' "sha256 : $(sha256sum "$ARTIFACT" | cut -d' ' -f1)"
  exit 0
fi

BUILD_ARGS=(build apk --release --target-platform "$TARGET")
if [ "$SPLIT" = "1" ]; then
  [ "$ANALYZE_SIZE" = "1" ] &&
    die "--analyze-size ne fonctionne pas avec --split-per-abi : Flutter veut
un seul APK à analyser (retirer l'un des deux)"
  BUILD_ARGS+=(--split-per-abi)
fi
if [ "$ANALYZE_SIZE" = "1" ]; then
  BUILD_ARGS+=(--analyze-size)
fi
BUILD_ARGS+=("${EXTRA[@]}")

run_flutter_build "${BUILD_ARGS[@]}"

APK_DIR="build/app/outputs/flutter-apk"
APKS=()
if [ "$SPLIT" = "1" ]; then
  while IFS= read -r file; do APKS+=("$file"); done < <(
    find "$APK_DIR" -maxdepth 1 -name '*-release.apk' | sort
  )
else
  [ -f "$APK_DIR/app-release.apk" ] && APKS=("$APK_DIR/app-release.apk")
fi
[ "${#APKS[@]}" -gt 0 ] ||
  die "aucun APK release trouvé dans $APK_DIR (le build a-t-il échoué ?)"

printf '\n'
ok "cible : $TARGET (architecture $ABI)"
for apk in "${APKS[@]}"; do
  printf '    %s  (%s)\n' "$apk" "$(du -h "$apk" | cut -f1)"
  printf '    %s\n' "sha256 : $(sha256sum "$apk" | cut -d' ' -f1)"
done

# ---------------------------------------------------------------------------
# Rapport de taille (--analyze-size)
# ---------------------------------------------------------------------------

if [ "$ANALYZE_SIZE" = "1" ]; then
  REPORT="$(find "$HOME/.flutter-devtools" -maxdepth 1     -name 'apk-code-size-analysis*.json' -printf '%T@ %p\n' 2>/dev/null |
    sort -rn | head -n 1 | cut -d' ' -f2- || true)"
  printf '\n'
  if [ -n "$REPORT" ]; then
    ok "rapport de poids : $REPORT"
    printf '    %s\n' "détail par paquet Dart et par asset"
    DART_BIN="$(dirname "$FLUTTER_BIN")/dart"
    if [ -x "$DART_BIN" ]; then
      printf '    %s\n' "visualiser : $DART_BIN devtools \
--appSizeBase=$REPORT"
    fi
  else
    warn "rapport introuvable dans ~/.flutter-devtools (build échoué ?)"
  fi
  printf '    %s\n' "détail de l'APK et du téléphone : tools/apk-size.sh"
fi

# ---------------------------------------------------------------------------
# Installation
# ---------------------------------------------------------------------------

if [ "$INSTALL" = "1" ]; then
  [ -n "$ADB_BIN" ] ||
    die "adb introuvable : installe les platform-tools du SDK Android"
  APK="${APKS[0]}"
  ADB=("$ADB_BIN")
  [ -n "$DEVICE" ] && ADB+=("-s" "$DEVICE")

  install_once() {
    local logfile="$1"
    "${ADB[@]}" install -r "$APK" >"$logfile" 2>&1
  }

  install_log="$(mktemp -t cqcm-install-XXXXXX.log)"
  log "adb install -r $APK"
  if ! install_once "$install_log"; then
    cat "$install_log" >&2
    case "$(cat "$install_log")" in
      *UPDATE_INCOMPATIBLE* | *"do not match newer version"*)
        if [ "$REINSTALL" = "1" ]; then
          warn "signature différente : désinstallation de l'application existante"
          warn "  la progression de révision enregistrée dans l'application est \
perdue"
          "${ADB[@]}" uninstall com.cqcm.cqcm || true
          if install_once "$install_log"; then
            rm -f "$install_log"
            ok "installé sur le téléphone (progression réinitialisée)"
            printf '    %s\n' \
              "lancer : ${ADB[*]} shell monkey -p com.cqcm.cqcm 1"
            exit 0
          fi
          cat "$install_log" >&2
          die "installation toujours refusée après désinstallation"
        fi
        warn "l'application installée sur le téléphone est signée autrement"
        warn "  (clé de débogage d'une autre machine, ou keystore de release)"
        warn "  remèdes :"
        warn "    ${ADB[*]} uninstall com.cqcm.cqcm && \
tools/build-apk.sh --install --symbols"
        warn "    ou relancer avec --reinstall (fait la désinstallation) :"
        warn "      tools/build-apk.sh --install --symbols --reinstall"
        warn "  la progression de révision vivant dans l'application, elle part"
        warn "  avec la désinstallation. Avant cela, si l'ancienne version est"
        warn "  débogable, sauvegarde possible :"
        warn "    ${ADB[*]} exec-out run-as com.cqcm.cqcm cat \\
files/cqcm-revision-data/progress.json > progress.json"
        warn "  pour que cela ne se reproduise plus : docs/android-release.md §5"
        warn "  (keystore de release stable)"
        ;;
      *VERSION_DOWNGRADE*)
        warn "version plus ancienne que celle installée : ajouter -d"
        warn "  ${ADB[*]} install -r -d $APK"
        ;;
      *)
        adb_hint
        warn "installation refusée (voir la sortie ci-dessus)"
        ;;
    esac
    rm -f "$install_log"
    exit 1
  fi
  rm -f "$install_log"
  ok "installé sur le téléphone"
  printf '    %s\n' "lancer : ${ADB[*]} shell monkey -p com.cqcm.cqcm 1"
fi
