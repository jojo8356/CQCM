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

FLUTTER_BIN=""
if [ -x "$SCRIPT_DIR/flutter-pinned.sh" ]; then
  FLUTTER_BIN="$("$SCRIPT_DIR/flutter-pinned.sh" --print 2>/dev/null || true)"
fi
[ -n "$FLUTTER_BIN" ] || FLUTTER_BIN="$(command -v flutter || true)"
[ -n "$FLUTTER_BIN" ] ||
  die "flutter introuvable : voir .flutter-version et tools/flutter-pinned.sh"

ADB_BIN="$(command -v adb || true)"
if [ -z "$ADB_BIN" ]; then
  for candidate in \
    "${ANDROID_HOME:-}/platform-tools/adb" \
    "${ANDROID_SDK_ROOT:-}/platform-tools/adb" \
    "$HOME/android-sdk/platform-tools/adb" \
    "$HOME/Android/Sdk/platform-tools/adb"; do
    [ -n "$candidate" ] && [ -x "$candidate" ] && ADB_BIN="$candidate" && break
  done
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

DEVICE_ABI=""
if [ "$ABI" = "auto" ]; then
  if [ -z "$ADB_BIN" ]; then
    warn "adb introuvable : impossible de détecter le téléphone"
  else
    ADB=("$ADB_BIN")
    [ -n "$DEVICE" ] && ADB+=("-s" "$DEVICE")
    DEVICE_ABI="$("${ADB[@]}" shell getprop ro.product.cpu.abi 2>/dev/null |
      tr -d '\r' | head -n 1 || true)"
    if [ -z "$DEVICE_ABI" ]; then
      warn "aucun téléphone détecté par adb (ou pas de réponse) : \
utilise --abi, ou branche-le et accepte le débogage USB"
    else
      log "téléphone détecté : architecture $DEVICE_ABI"
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

if [ "$CLEAN" = "1" ]; then
  log "flutter clean"
  "$FLUTTER_BIN" clean
fi

if [ "$SYMBOLS" = "1" ] || [ "$OBFUSCATE" = "1" ]; then
  EXTRA+=(--split-debug-info=build/symbols)
fi
if [ "$OBFUSCATE" = "1" ]; then
  EXTRA+=(--obfuscate)
fi

# ---------------------------------------------------------------------------
# Compilation
# ---------------------------------------------------------------------------

if [ "$BUNDLE" = "1" ]; then
  log "flutter build appbundle --release"
  "$FLUTTER_BIN" build appbundle --release "${EXTRA[@]}"
  ARTIFACT="build/app/outputs/bundle/release/app-release.aab"
  [ -f "$ARTIFACT" ] || die "App Bundle attendu introuvable : $ARTIFACT"
  ok "App Bundle : $ARTIFACT ($(du -h "$ARTIFACT" | cut -f1))"
  printf '    %s\n' "sha256 : $(sha256sum "$ARTIFACT" | cut -d' ' -f1)"
  exit 0
fi

BUILD_ARGS=(build apk --release --target-platform "$TARGET")
[ "$SPLIT" = "1" ] && BUILD_ARGS+=(--split-per-abi)
BUILD_ARGS+=("${EXTRA[@]}")

log "flutter ${BUILD_ARGS[*]}"
"$FLUTTER_BIN" "${BUILD_ARGS[@]}"

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
# Installation
# ---------------------------------------------------------------------------

if [ "$INSTALL" = "1" ]; then
  [ -n "$ADB_BIN" ] ||
    die "adb introuvable : installe les platform-tools du SDK Android"
  APK="${APKS[0]}"
  ADB=("$ADB_BIN")
  [ -n "$DEVICE" ] && ADB+=("-s" "$DEVICE")

  log "adb install -r $APK"
  if ! "${ADB[@]}" install -r "$APK"; then
    warn "installation refusée. Cause la plus fréquente : l'application est \
déjà installée avec une autre signature"
    warn "remède : ${ADB[*]} uninstall com.cqcm.cqcm puis relancer"
    exit 1
  fi
  ok "installé sur le téléphone"
  printf '    %s\n' "lancer : ${ADB[*]} shell monkey -p com.cqcm.cqcm 1"
fi
