#!/usr/bin/env bash
#
# Inventorie les SDK Android présents et dit lequel Flutter / Gradle utilisent.
#
# Pourquoi : quand plusieurs SDK cohabitent (celui de la distribution dans
# /usr/lib/android-sdk, celui du SDK téléchargé à la main, celui d'Android
# Studio), Gradle peut travailler dans le mauvais — un SDK sans
# `cmdline-tools` ni licences acceptées, incapable d'installer le NDK ou un
# composant manquant, d'où des échecs du genre :
#   com.android.builder.sdk.LicenceNotAcceptedException:
#   Failed to install the following Android SDK packages as some licences
#   have not been accepted. ndk;28.2.13676358
#
# Usage :
#   tools/android-sdk-doctor.sh                  # inventaire + diagnostic
#   tools/android-sdk-doctor.sh --fix [DOSSIER]  # licences + composants requis
#   tools/android-sdk-doctor.sh --set DOSSIER    # Flutter utilise ce SDK
#   tools/android-sdk-doctor.sh --flutter-root DIR
#
# Sans argument, rien n'est modifié : le script se contente de lire (et
# d'appeler `sdkmanager --list_installed` s'il existe).
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

MODE=report
TARGET_SDK=""
FLUTTER_ROOT=""

while [ $# -gt 0 ]; do
  case "$1" in
    --fix) MODE=fix ;;
    --set)
      shift
      [ $# -gt 0 ] || die "--set attend un dossier de SDK"
      MODE=set
      TARGET_SDK="$1"
      ;;
    --flutter-root)
      shift
      [ $# -gt 0 ] || die "--flutter-root attend un dossier"
      FLUTTER_ROOT="$1"
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      # Un chemin seul = la cible de --fix
      if [ "${1#-}" = "$1" ] && [ "$MODE" = "fix" ]; then
        TARGET_SDK="$1"
      else
        warn "option inconnue : $1"
        usage >&2
        exit 2
      fi
      ;;
  esac
  shift
done

# ---------------------------------------------------------------------------
# Flutter épinglé (pour connaître compileSdk / ndkVersion attendus)
# ---------------------------------------------------------------------------

FLUTTER_BIN=""
if [ -x "$SCRIPT_DIR/flutter-pinned.sh" ]; then
  FLUTTER_BIN="$("$SCRIPT_DIR/flutter-pinned.sh" --print 2>/dev/null || true)"
fi
[ -n "$FLUTTER_BIN" ] || FLUTTER_BIN="$(command -v flutter || true)"

if [ -z "$FLUTTER_ROOT" ] && [ -n "$FLUTTER_BIN" ]; then
  FLUTTER_ROOT="$(cd "$(dirname "$FLUTTER_BIN")/.." && pwd)"
fi

sdk_defaults() {
  # Valeurs attendues par le SDK épinglé, avec repli sur les constantes du
  # modèle Flutter 3.47.
  local ext="$FLUTTER_ROOT/packages/flutter_tools/gradle/src/main/kotlin/FlutterExtension.kt"
  COMPILE_SDK=36
  NDK_EXPECTED=28.2.13676358
  if [ -f "$ext" ]; then
    local value
    value="$(sed -n 's/.*compileSdkVersion: Int = \([0-9][0-9]*\).*/\1/p' "$ext" |
      head -n 1)"
    [ -n "$value" ] && COMPILE_SDK="$value"
    value="$(sed -n 's/.*ndkVersion: String = "\([^"]*\)".*/\1/p' "$ext" |
      head -n 1)"
    [ -n "$value" ] && NDK_EXPECTED="$value"
  fi
}

sdk_defaults

# ---------------------------------------------------------------------------
# Inventaire
# ---------------------------------------------------------------------------

# Nouveau CLI Android (« android sdk install ») : remplace sdkmanager, qui
# reste fourni et fonctionnel mais affiche un avertissement de dépréciation.
android_cli_in() {
  local dir="$1" candidate
  for candidate in \
    "$dir/cmdline-tools/latest/bin/android" \
    "$dir"/cmdline-tools/*/bin/android; do
    [ -x "$candidate" ] && printf '%s\n' "$candidate" && return 0
  done
  command -v android 2>/dev/null || return 1
}

# Installe des paquets : Android CLI d'abord, sdkmanager en repli.
# Les chemins de paquets acceptent les deux écritures (« platforms;android-36 »
# et « platforms/android-36 »).
install_packages_in() {
  local dir="$1" android_cli="$2" sdkmanager="$3"
  shift 3
  if [ -n "$android_cli" ]; then
    if ANDROID_HOME="$dir" "$android_cli" --sdk "$dir" sdk install "$@" \
      --no-metrics; then
      return 0
    fi
    warn "Android CLI en échec : repli sur sdkmanager (déprécié mais fonctionnel)"
  fi
  [ -n "$sdkmanager" ] || return 1
  "$sdkmanager" --sdk_root="$dir" --install "$@"
}

sdkmanager_for() {
  local dir="$1" candidate
  for candidate in \
    "$dir/cmdline-tools/latest/bin/sdkmanager" \
    "$dir"/cmdline-tools/*/bin/sdkmanager \
    "$dir/tools/bin/sdkmanager"; do
    [ -x "$candidate" ] && printf '%s\n' "$candidate" && return 0
  done
  return 1
}

sdk_report() {
  local dir="$1" label="$2"
  local cmdline="non" licenses="non" ndk="aucun"
  local platforms buildtools platformtools

  local listing

  if [ -n "$(sdkmanager_for "$dir" 2>/dev/null || true)" ]; then
    cmdline="oui"
  fi
  if [ -d "$dir/licenses" ]; then
    listing="$(find "$dir/licenses" -maxdepth 1 -type f 2>/dev/null | wc -l)"
    licenses="oui ($listing fichier(s))"
  fi
  if [ -d "$dir/ndk" ]; then
    ndk=""
    local version
    for version in $(find "$dir/ndk" -maxdepth 1 -mindepth 1 -type d \
      -printf '%f ' 2>/dev/null || true); do
      if [ -d "$dir/ndk/$version/toolchains" ]; then
        ndk="$ndk $version"
      else
        ndk="$ndk $version (marqueur)"
      fi
    done
    ndk="$(printf '%s\n' $ndk | tr -s '\n' ' ' | sed 's/^ *//')"
    [ -n "$ndk" ] || ndk="aucun"
  fi
  platforms="$(find "$dir/platforms" -maxdepth 1 -mindepth 1 -type d \
    -printf '%f ' 2>/dev/null | sed 's/ $//' || true)"
  buildtools="$(find "$dir/build-tools" -maxdepth 1 -mindepth 1 -type d \
    -printf '%f ' 2>/dev/null | sed 's/ $//' || true)"
  if [ -x "$dir/platform-tools/adb" ]; then
    platformtools="oui"
  else
    platformtools="non"
  fi

  printf '  %s\n' "$label"
  printf '    dossier        : %s\n' "$dir"
  printf '    cmdline-tools  : %s\n' "$cmdline"
  printf '    licences       : %s\n' "$licenses"
  printf '    NDK installé   : %s\n' "$ndk"
  printf '    platforms      : %s\n' "${platforms:-aucune}"
  printf '    build-tools    : %s\n' "${buildtools:-aucun}"
  printf '    platform-tools : %s\n' "$platformtools"
}

FLUTTER_CONFIG_SDK=""
SETTINGS="${XDG_CONFIG_HOME:-$HOME/.config}/flutter/settings"
if [ -f "$SETTINGS" ] && command -v python3 >/dev/null 2>&1; then
  FLUTTER_CONFIG_SDK="$(python3 -c "
import json, sys
try:
    print(json.load(open('$SETTINGS')).get('android-sdk') or '')
except Exception:
    print('')
" 2>/dev/null || true)"
fi

LOCAL_PROPERTIES_SDK=""
if [ -f android/local.properties ]; then
  LOCAL_PROPERTIES_SDK="$(sed -n 's/^sdk\.dir=//p' android/local.properties |
    head -n 1)"
fi

CANDIDATES=()
add_candidate() {
  local dir="$1" existing
  [ -n "$dir" ] || return 0
  [ -d "$dir" ] || return 0
  for existing in "${CANDIDATES[@]:-}"; do
    [ "$existing" = "$dir" ] && return 0
  done
  CANDIDATES+=("$dir")
}
# Ordre = ordre de résolution réel de Flutter / AGP.
add_candidate "$FLUTTER_CONFIG_SDK"
add_candidate "${ANDROID_HOME:-}"
add_candidate "${ANDROID_SDK_ROOT:-}"
add_candidate "$HOME/Android/Sdk"
add_candidate "$HOME/android-sdk"
add_candidate "/usr/lib/android-sdk"

if [ "$MODE" = "set" ]; then
  [ -d "$TARGET_SDK" ] || die "dossier introuvable : $TARGET_SDK"
  if [ -z "$(sdkmanager_for "$TARGET_SDK" 2>/dev/null || true)" ]; then
    warn "ce SDK n'a pas de cmdline-tools/sdkmanager : Gradle ne pourra rien \
y installer (voir tools/android-sdk-doctor.sh --fix)"
  fi
  [ -n "$FLUTTER_BIN" ] || die "flutter introuvable : voir tools/flutter-pinned.sh"
  log "flutter config --android-sdk $TARGET_SDK"
  "$FLUTTER_BIN" config --android-sdk "$TARGET_SDK"
  ok "Flutter utilisera désormais $TARGET_SDK"
  printf '    relancer : tools/android-sdk-doctor.sh\n'
  printf '    puis     : tools/build-apk.sh --install --symbols\n'
  exit 0
fi

log "SDK Flutter : ${FLUTTER_ROOT:-?}"
log "composants attendus par ce SDK : platforms;android-$COMPILE_SDK, \
ndk;$NDK_EXPECTED"

printf '\n'
log "SDK Android vus sur cette machine"
if [ "${#CANDIDATES[@]}" -eq 0 ]; then
  warn "aucun : en installer un (Android Studio, ou cmdline-tools + sdkmanager)"
  exit 1
fi
for dir in "${CANDIDATES[@]}"; do
  label="candidat"
  [ "$dir" = "$FLUTTER_CONFIG_SDK" ] && label="flutter config (prioritaire)"
  [ "$dir" = "${ANDROID_HOME:-}" ] && label="ANDROID_HOME"
  [ "$dir" = "${ANDROID_SDK_ROOT:-}" ] && label="ANDROID_SDK_ROOT"
  [ "$dir" = "$HOME/Android/Sdk" ] && label="défaut Flutter sous Linux"
  [ "$dir" = "/usr/lib/android-sdk" ] && label="paquet de la distribution"
  sdk_report "$dir" "$label"
  printf '\n'
done

EFFECTIVE="${LOCAL_PROPERTIES_SDK:-${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Android/Sdk}}}"
log "SDK utilisé par ce projet : $EFFECTIVE"
[ -f android/local.properties ] &&
  printf '    (lu dans android/local.properties — écrit par Flutter à chaque build)\n'

# Le projet compile-t-il du code natif ? (jni, apporté par
# path_provider_android >= 2.3.0). Si oui, un marqueur de NDK ne suffit pas :
# CMake exige <ndk>/build/cmake/android.toolchain.cmake.
NATIVE_PKGS=()
for pkg in jni jni_flutter; do
  if grep -q "^  $pkg:" pubspec.lock 2>/dev/null; then
    NATIVE_PKGS+=("$pkg")
  fi
done
MARKERS=""
if [ -d "$EFFECTIVE/ndk" ]; then
  for version in $(find "$EFFECTIVE/ndk" -maxdepth 1 -mindepth 1 -type d \
    -printf '%f\n' 2>/dev/null || true); do
    if [ ! -d "$EFFECTIVE/ndk/$version/toolchains" ]; then
      MARKERS="$MARKERS $version"
    fi
  done
fi
if [ -n "$MARKERS" ]; then
  if [ "${#NATIVE_PKGS[@]}" -gt 0 ]; then
    warn "NDK marqueur$MARKERS dans $EFFECTIVE, or le projet compile du code"
    warn "  natif (${NATIVE_PKGS[*]}) : le build échouera sur"
    warn "  « Could not find toolchain file ». Deux sorties :"
    warn "    a) vrai NDK (~1 Go, ~4 Go installés) :"
    for marker_version in $MARKERS; do
      warn "         rm -rf $EFFECTIVE/ndk/$marker_version"
    done
    warn "         tools/android-sdk-install.sh --sdk $EFFECTIVE"
    warn "    b) garder le disque libre : épingler path_provider_android 2.2.23"
    warn "         dependency_overrides:"
    warn "           path_provider_android: 2.2.23"
    warn "       puis flutter pub get (le marqueur devient inutile)"
  else
    warn "NDK marqueur$MARKERS dans $EFFECTIVE : suffisant tant qu'aucun paquet"
    warn "  ne compile de code natif (aucun jni dans pubspec.lock)"
  fi
fi

# Le bon candidat : celui avec cmdline-tools ET licences.
BEST=""
for dir in "${CANDIDATES[@]}"; do
  found_sm="$(sdkmanager_for "$dir" 2>/dev/null || true)"
  if [ -n "$found_sm" ] && [ -d "$dir/licenses" ]; then
    BEST="$dir"
    break
  fi
done

printf '\n'

guidance() {
  warn "aucun SDK utilisable pour installer un composant (cmdline-tools + \
licences)"
  warn "  sans cela, Gradle échoue sur « licences have not been accepted » dès \
qu'il doit installer le NDK"
  printf '    remèdes :\n'
  printf '      a) créer un SDK utilisateur complet (recommandé) :\n'
  printf '         tools/android-sdk-install.sh --zip <cmdline-tools.zip>\n'
  printf '         (ou --url <lien copié sur developer.android.com/studio>)\n'
  printf '      b) indiquer un SDK complet déjà installé :\n'
  printf '         tools/android-sdk-doctor.sh --set <dossier_du_sdk>\n'
}

if [ "$MODE" = "fix" ] && [ -n "$TARGET_SDK" ]; then
  # Dossier imposé par l'utilisateur : il prime sur la détection.
  SDKMANAGER="$(sdkmanager_for "$TARGET_SDK" || true)"
  if [ -z "$SDKMANAGER" ]; then
    warn "pas de cmdline-tools/sdkmanager dans $TARGET_SDK"
    guidance
    exit 1
  fi
  BEST="$TARGET_SDK"
  ok "SDK ciblé par --fix : $BEST"
else
  if [ -z "$BEST" ]; then
    guidance
    exit 1
  fi
  ok "SDK recommandé : $BEST"
  if [ "$EFFECTIVE" != "$BEST" ]; then
    warn "ce n'est pas celui que ce projet utilise ($EFFECTIVE)"
    printf '    corriger : tools/android-sdk-doctor.sh --set %s\n' "$BEST"
  fi
  SDKMANAGER="$(sdkmanager_for "$BEST" || true)"
  [ -n "$SDKMANAGER" ] || die "sdkmanager introuvable dans $BEST"
fi

# Un NDK déjà présent mais d'une autre version : le configurer évite un
# téléchargement d'environ 1 Go. Un dossier sans `toolchains/` est un marqueur
# posé par tools/android-sdk-install.sh --fake-ndk, pas un vrai NDK.
NDK_ALL="$(find "$BEST/ndk" -maxdepth 1 -mindepth 1 -type d -printf '%f ' \
  2>/dev/null | sed 's/ $//' || true)"
NDK_INSTALLED=""
for candidate in $NDK_ALL; do
  if [ -d "$BEST/ndk/$candidate/toolchains" ]; then
    NDK_INSTALLED="$NDK_INSTALLED $candidate"
  else
    warn "NDK $candidate dans $BEST : marqueur (aucun binaire, pas de toolchains/)"
  fi
done
NDK_INSTALLED="$(printf '%s\n' $NDK_INSTALLED | tr -s '\n' ' ' |
  sed 's/^ *//' | sed 's/ *$//')"
if [ -n "$NDK_INSTALLED" ] &&
  ! printf '%s\n' $NDK_INSTALLED | grep -qx "$NDK_EXPECTED"; then
  warn "NDK présent ($NDK_INSTALLED) mais différent de l'attendu \
($NDK_EXPECTED)"
  warn "  pour éviter le téléchargement, écrire dans android/app/build.gradle.kts"
  warn "  ndkVersion = \"$(printf '%s\n' $NDK_INSTALLED | head -n 1)\" \
(aucun module natif ici : n'importe quelle version installée convient)"
fi

if [ "$MODE" = "fix" ]; then
  printf '\n'
  log "acceptation des licences (oui à tout, dans $BEST)"
  err="$(mktemp)"
  if printf 'y\n%.0s' {1..60} |
    "$SDKMANAGER" --sdk_root="$BEST" --licenses >/dev/null 2>"$err"; then
    ok "licences traitées"
  else
    warn "certaines licences n'ont pas été acceptées : relancer --fix"
  fi
  # sdkmanager annonce sa dépréciation à chaque appel : sans intérêt ici.
  grep -vE 'deprecated|replacement for .sdkmanager|android-cli|^[[:space:]]*$' \
    "$err" >&2 || true
  rm -f "$err"

  log "installation des composants attendus"
  ANDROID_CLI="$(android_cli_in "$BEST" 2>/dev/null || true)"
  install_packages_in "$BEST" "$ANDROID_CLI" "$SDKMANAGER" \
    "platform-tools" \
    "platforms;android-$COMPILE_SDK" \
    "build-tools;$COMPILE_SDK.0.0" \
    "ndk;$NDK_EXPECTED"
  ok "composants installés"

  printf '\n'
  if [ "$EFFECTIVE" != "$BEST" ]; then
    log "pointer le projet sur ce SDK"
    printf '    tools/android-sdk-doctor.sh --set %s\n' "$BEST"
  fi
  log "puis relancer"
  printf '    tools/build-apk.sh --install --symbols\n'
else
  printf '\n'
  log "pour réparer :"
  printf '    tools/android-sdk-doctor.sh --fix %s\n' "$BEST"
fi
