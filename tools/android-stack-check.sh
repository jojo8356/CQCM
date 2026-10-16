#!/usr/bin/env bash
#
# Diagnostic de la chaîne Android (Gradle / AGP / Kotlin / Java) avant build.
#
# Compare ce que le projet déclare avec ce que le SDK Flutter installé exige
# (minimums bloquants) et recommande (versions des gabarits `flutter create`),
# puis dit si la bascule AGP 9 est possible ou non. À relancer après chaque
# `flutter upgrade` : c'est le seul moyen de savoir si le plancher a bougé,
# puisque `skipDependencyChecks=true` masque les messages de Flutter.
#
# Usage :
#   tools/android-stack-check.sh                 # projet courant
#   tools/android-stack-check.sh --json          # sortie JSON
#   tools/android-stack-check.sh --flutter-root ~/flutter
#   tools/android-stack-check.sh --project AUTRE/DEPOT
#
# Codes de sortie :
#   0  chaîne au-dessus des minimums Flutter
#   1  au moins un réglage est en dessous d'un minimum : le build va échouer
#   2  SDK Flutter ou fichiers du projet introuvables
#
set -euo pipefail

# ---------------------------------------------------------------------------
# Utilitaires
# ---------------------------------------------------------------------------

log() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
ok() { printf '\033[1;32m ok\033[0m %s\n' "$*"; }
note() { printf '\033[1;36m --\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*" >&2; }
die() {
  printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2
  exit "${2:-1}"
}

usage() {
  awk 'NR > 2 { if ($0 !~ /^#/) exit; sub(/^# ?/, ""); print }' \
    "${BASH_SOURCE[0]}"
}

# ---------------------------------------------------------------------------
# Options
# ---------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SDK_ROOT="${FLUTTER_ROOT:-}"
JSON=0
QUIET=0

while [ $# -gt 0 ]; do
  case "$1" in
    --flutter-root)
      shift
      [ $# -gt 0 ] || die "--flutter-root attend un chemin"
      SDK_ROOT="$1"
      ;;
    --project)
      shift
      [ $# -gt 0 ] || die "--project attend un chemin"
      PROJECT_DIR="$(cd "$1" && pwd)"
      ;;
    --json) JSON=1 ;;
    --quiet) QUIET=1 ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      warn "option inconnue : $1"
      usage
      exit 2
      ;;
  esac
  shift
done

# ---------------------------------------------------------------------------
# Comparaison de versions
# ---------------------------------------------------------------------------

# version_ge A B : vrai si A >= B (« sort -V » compare les composants).
version_ge() {
  [ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | tail -n 1)" = "$1" ]
}

# Extrait « 1.2.3 » après un motif de type « Version(1, 2, 3) ».
kt_tuple() { # kt_tuple FICHIER PREFIXE
  [ -f "$1" ] || return 1
  sed -n "s/.*$2[^0-9]*\([0-9][0-9]*\), *\([0-9][0-9]*\), *\([0-9][0-9]*\).*/\1.\2.\3/p" \
    "$1" | head -n 1
}

# Extrait « 1.2.3 » ou « 17 » après un motif quelconque.
kt_scalar() { # kt_scalar FICHIER PREFIXE
  [ -f "$1" ] || return 1
  sed -n "s/.*$2[^0-9]*\([0-9][0-9.]*\).*/\1/p" "$1" | head -n 1
}

# ---------------------------------------------------------------------------
# Lecture du projet
# ---------------------------------------------------------------------------

ANDROID_DIR="$PROJECT_DIR/android"
WRAPPER="$ANDROID_DIR/gradle/wrapper/gradle-wrapper.properties"
SETTINGS="$ANDROID_DIR/settings.gradle.kts"
[ -f "$SETTINGS" ] || SETTINGS="$ANDROID_DIR/settings.gradle"
APP_GRADLE="$ANDROID_DIR/app/build.gradle.kts"
[ -f "$APP_GRADLE" ] || APP_GRADLE="$ANDROID_DIR/app/build.gradle"
PROPS="$ANDROID_DIR/gradle.properties"

[ -d "$ANDROID_DIR" ] || die "dossier android/ introuvable dans $PROJECT_DIR" 2

P_GRADLE="$(grep -oE 'gradle-[0-9]+(\.[0-9]+)+' "$WRAPPER" 2>/dev/null |
  head -n 1 | sed 's/^gradle-//' || true)"
P_AGP="$(grep -oE 'com\.android\.application[^0-9]*[0-9][0-9.]*' \
  "$SETTINGS" 2>/dev/null | grep -oE '[0-9][0-9.]*$' | head -n 1 || true)"
P_KGP="$(grep -oE 'org\.jetbrains\.kotlin\.android[^0-9]*[0-9][0-9.]*' \
  "$SETTINGS" 2>/dev/null | grep -oE '[0-9][0-9.]*$' | head -n 1 || true)"
P_JAVA="$(grep -oE 'JavaVersion\.VERSION_[0-9]+' "$APP_GRADLE" 2>/dev/null |
  head -n 1 | grep -oE '[0-9]+' || true)"
P_JVM="$(grep -oE 'JvmTarget\.JVM_[0-9]+|jvmTarget *= *"?[0-9]+' "$APP_GRADLE" \
  2>/dev/null | head -n 1 | grep -oE '[0-9]+$' || true)"
P_COMPILE_SDK="$(grep -oE 'compileSdk *=.*' "$APP_GRADLE" 2>/dev/null |
  head -n 1 | sed 's/^[[:space:]]*//' || true)"

has_prop() { # has_prop NOM -> vrai si « nom=vrai » dans gradle.properties
  [ -f "$PROPS" ] || return 1
  grep -qiE "^[[:space:]]*$1[[:space:]]*=[[:space:]]*true" "$PROPS"
}

HAS_SKIP=0
has_prop skipDependencyChecks && HAS_SKIP=1
HAS_NEWDSL=0
has_prop android.newDsl && HAS_NEWDSL=1

JVM_MAJOR=""
if command -v java >/dev/null 2>&1; then
  JVM_MAJOR="$(java -version 2>&1 | head -n 1 |
    sed -n 's/.*version "\([0-9][0-9]*\).*/\1/p' || true)"
  [ "$JVM_MAJOR" = "1" ] && JVM_MAJOR="8"
fi

# ---------------------------------------------------------------------------
# Lecture du SDK Flutter
# ---------------------------------------------------------------------------

if [ -z "$SDK_ROOT" ]; then
  FLUTTER_BIN="$(command -v flutter || true)"
  if [ -n "$FLUTTER_BIN" ]; then
    FLUTTER_BIN="$(readlink -f "$FLUTTER_BIN")"
    # .../bin/flutter -> racine du SDK
    SDK_ROOT="$(cd "$(dirname "$FLUTTER_BIN")/.." && pwd)"
  fi
fi

if [ -z "$SDK_ROOT" ] || [ ! -d "$SDK_ROOT/packages/flutter_tools" ]; then
  die "SDK Flutter introuvable : passe --flutter-root DIR (ou FLUTTER_ROOT)" 2
fi

KOTLIN_DIR="$SDK_ROOT/packages/flutter_tools/gradle/src/main/kotlin"
DVC="$KOTLIN_DIR/DependencyVersionChecker.kt"
EXT="$KOTLIN_DIR/FlutterExtension.kt"
UTILS="$SDK_ROOT/packages/flutter_tools/lib/src/android/gradle_utils.dart"

[ -f "$DVC" ] || die "DependencyVersionChecker.kt introuvable sous $KOTLIN_DIR" 2

MIN_GRADLE="$(kt_tuple "$DVC" errorGradleVersion || true)"
WARN_GRADLE="$(kt_tuple "$DVC" warnGradleVersion || true)"
MIN_AGP="$(kt_tuple "$DVC" errorAGPVersion || true)"
WARN_AGP="$(kt_tuple "$DVC" warnAGPVersion || true)"
MIN_KGP="$(kt_tuple "$DVC" errorKGPVersion || true)"
WARN_KGP="$(kt_tuple "$DVC" warnKGPVersion || true)"
MIN_JAVA="$(kt_scalar "$DVC" errorJavaVersion || true)"
MIN_SDK="$(kt_scalar "$DVC" errorMinSdkVersion || true)"

TPL_GRADLE="$(kt_scalar "$UTILS" templateDefaultGradleVersion || true)"
TPL_AGP="$(kt_scalar "$UTILS" templateAndroidGradlePluginVersion || true)"
TPL_KGP="$(kt_scalar "$UTILS" templateKotlinGradlePluginVersion || true)"

SDK_COMPILE="$(kt_scalar "$EXT" compileSdkVersion || true)"
SDK_MIN="$(kt_scalar "$EXT" minSdkVersion || true)"

# Le plugin Gradle de Flutter utilise-t-il encore l'API de variantes
# historique ? Tant que oui, AGP 9 exige android.newDsl=false.
LEGACY_FILES="$(grep -rlE 'applicationVariants|libraryVariants|testVariants|unitTestVariants' \
  "$KOTLIN_DIR" 2>/dev/null || true)"
LEGACY_COUNT=0
[ -n "$LEGACY_FILES" ] && LEGACY_COUNT="$(printf '%s\n' "$LEGACY_FILES" |
  grep -c . || true)"

# ---------------------------------------------------------------------------
# Contrôles
# ---------------------------------------------------------------------------

STATUS=0 # 0 = tout va bien ; 1 = un minimum n'est pas atteint
ITEMS="" # lignes JSON
ITEMS_SEP=""

add_item() { # add_item NOM PROJET MINIMUM RECOMMANDE ETAT MESSAGE
  local name="$1" project="$2" minimum="$3" recommended="$4"
  local status="$5" message="$6"
  ITEMS="$ITEMS$ITEMS_SEP  {\"name\": \"$name\", \"project\": \"$project\""
  ITEMS="$ITEMS, \"minimum\": \"$minimum\""
  ITEMS="$ITEMS, \"recommended\": \"$recommended\""
  ITEMS="$ITEMS, \"status\": \"$status\", \"message\": \"$message\"}"
  ITEMS_SEP=",
"
  [ "$status" = "ko" ] && STATUS=1
  return 0
}

# check_version VALEUR MINIMUM RECOMMANDE
check_version() {
  local value="$1" minimum="$2" recommended="$3"
  if [ -z "$value" ]; then
    printf 'inconnu'
    return 0
  fi
  if ! version_ge "$value" "$minimum"; then
    printf 'ko'
    return 0
  fi
  if [ -n "$recommended" ] && ! version_ge "$value" "$recommended"; then
    printf 'avertissement'
    return 0
  fi
  printf 'ok'
}

line() { # line ETAT NOM DETAIL
  local status="$1" name="$2" detail="$3"
  [ "$JSON" = "1" ] && return 0
  case "$status" in
    ok) [ "$QUIET" = "1" ] || ok "$name : $detail" ;;
    avertissement)
      [ "$QUIET" = "1" ] ||
        printf '\033[1;33m[!]\033[0m %s : %s\n' "$name" "$detail"
      ;;
    ko) printf '\033[1;31m KO\033[0m %s : %s\n' "$name" "$detail" ;;
    *) [ "$QUIET" = "1" ] || note "$name : $detail" ;;
  esac
}

[ "$JSON" = "1" ] || log "Projet : $PROJECT_DIR"
[ "$JSON" = "1" ] || log "SDK Flutter : $SDK_ROOT"

# --- Gradle ---------------------------------------------------------------
S_GRADLE="$(check_version "$P_GRADLE" "$MIN_GRADLE" "$WARN_GRADLE")"
MSG="minimum Flutter $MIN_GRADLE, recommandé $WARN_GRADLE"
case "$S_GRADLE" in
  ko)
    MSG="projet $P_GRADLE < minimum Flutter $MIN_GRADLE : build refuse"
    ;;
  avertissement)
    MSG="projet $P_GRADLE >= $MIN_GRADLE : accepté, sous le seuil de $WARN_GRADLE"
    [ "$HAS_SKIP" = "1" ] && MSG="$MSG (avertissement masqué)"
    ;;
  ok)
    MSG="projet $P_GRADLE >= $WARN_GRADLE : au niveau recommandé"
    [ "$HAS_SKIP" = "1" ] &&
      MSG="$MSG, skipDependencyChecks peut être retiré"
    ;;
esac
line "$S_GRADLE" "Gradle $P_GRADLE" "$MSG"
add_item "Gradle" "$P_GRADLE" "$MIN_GRADLE" "$WARN_GRADLE" "$S_GRADLE" \
  "$(printf '%s' "$MSG" | tr -d '"')"

# --- AGP ------------------------------------------------------------------
S_AGP="$(check_version "$P_AGP" "$MIN_AGP" "$WARN_AGP")"
case "$S_AGP" in
  ko) MSG="projet $P_AGP < minimum Flutter $MIN_AGP : build refuse" ;;
  avertissement) MSG="projet $P_AGP >= $MIN_AGP : accepté, sous $WARN_AGP" ;;
  ok) MSG="projet $P_AGP >= $WARN_AGP : au niveau recommandé" ;;
  *) MSG="version absente de $SETTINGS" ;;
esac
line "$S_AGP" "AGP $P_AGP" "$MSG"
add_item "AGP" "$P_AGP" "$MIN_AGP" "$WARN_AGP" "$S_AGP" \
  "$(printf '%s' "$MSG" | tr -d '"')"

# --- Kotlin ---------------------------------------------------------------
S_KGP="$(check_version "$P_KGP" "$MIN_KGP" "$WARN_KGP")"
case "$S_KGP" in
  ko) MSG="projet $P_KGP < minimum Flutter $MIN_KGP : build refuse" ;;
  avertissement) MSG="projet $P_KGP >= $MIN_KGP : accepté, sous $WARN_KGP" ;;
  ok) MSG="projet $P_KGP >= $WARN_KGP : au niveau recommandé" ;;
  *) MSG="version absente de $SETTINGS" ;;
esac
line "$S_KGP" "Kotlin $P_KGP" "$MSG"
add_item "Kotlin" "$P_KGP" "$MIN_KGP" "$WARN_KGP" "$S_KGP" \
  "$(printf '%s' "$MSG" | tr -d '"')"

# --- Java -----------------------------------------------------------------
if [ -z "$JVM_MAJOR" ]; then
  line avertissement "Java" "java introuvable dans le PATH : Flutter utilisera \
le JDK de ses réglages (flutter config --jdk-dir)"
  add_item "Java" "" "$MIN_JAVA" "" "inconnu" "java introuvable dans le PATH"
else
  S_JAVA="ok"
  version_ge "$JVM_MAJOR" "$MIN_JAVA" || S_JAVA="ko"
  if [ "$S_JAVA" = "ko" ]; then
    line ko "Java $JVM_MAJOR" "JVM de Gradle < $MIN_JAVA : build refuse"
  else
    line ok "Java $JVM_MAJOR" "JVM de Gradle >= $MIN_JAVA (minimum Flutter)"
  fi
  add_item "Java" "$JVM_MAJOR" "$MIN_JAVA" "" "$S_JAVA" \
    "JVM utilisee par Gradle"
fi

# --- compileOptions / jvmTarget -------------------------------------------
S_OPT="ok"
DETAIL="compileOptions Java $P_JAVA"
[ -n "$P_JVM" ] && DETAIL="$DETAIL, jvmTarget $P_JVM"
if [ -z "$P_JAVA" ] || ! version_ge "$P_JAVA" "$MIN_JAVA"; then
  S_OPT="ko"
  DETAIL="$DETAIL : passer a Java $MIN_JAVA (modele Flutter actuel)"
elif [ -n "$P_JVM" ] && [ "$P_JVM" != "$P_JAVA" ]; then
  S_OPT="ko"
  DETAIL="$DETAIL : jvmTarget et compileOptions doivent etre identiques"
fi
line "$S_OPT" "Compilation Kotlin/Java" "$DETAIL"
add_item "compileOptions" "$P_JAVA" "$MIN_JAVA" "" "$S_OPT" \
  "$(printf '%s' "$DETAIL" | tr -d '"')"

# --- minSdk / compileSdk --------------------------------------------------
DETAIL="$P_COMPILE_SDK"
[ -n "$SDK_MIN" ] && DETAIL="$DETAIL, minSdk Flutter $SDK_MIN >= $MIN_SDK"
line info "SDK Android" "$DETAIL"
add_item "compileSdk" "$(printf '%s' "$P_COMPILE_SDK" | tr -d '"')" \
  "" "$SDK_COMPILE" "ok" "$(printf '%s' "$DETAIL" | tr -d '"')"

# --- Bascule AGP 9 --------------------------------------------------------
if [ "$LEGACY_COUNT" != "0" ]; then
  line avertissement "AGP 9" "pas encore : $LEGACY_COUNT fichier(s) du plugin \
Gradle de Flutter utilisent l'API de variantes historique (flutter#166550). \
Garder android.newDsl=false"
  add_item "AGP 9" "" "" "" "avertissement" \
    "API de variantes historique encore utilisee par le plugin Flutter"
else
  line ok "AGP 9" "bascule possible : le plugin Gradle de Flutter n'utilise \
plus l'API de variantes historique (voir docs/android-gradle.md § 4)"
  add_item "AGP 9" "" "" "" "ok" "bascule possible"
fi

# ---------------------------------------------------------------------------
# Synthèse
# ---------------------------------------------------------------------------

if [ "$JSON" = "1" ]; then
  printf '{"ok": %s, "project": "%s", "flutterRoot": "%s", "checks": [' \
    "$([ "$STATUS" = "0" ] && printf true || printf false)" \
    "$PROJECT_DIR" "$SDK_ROOT"
  printf '%s\n' "$ITEMS"
  printf ']}\n'
  exit "$STATUS"
fi

printf '\n'
if [ "$STATUS" = "0" ]; then
  ok "chaîne Android au-dessus des minimums de ce SDK Flutter"
  note "recommandé par le SDK : Gradle $TPL_GRADLE / AGP $TPL_AGP / \
Kotlin $TPL_KGP"
  note "prochain contrôle : après chaque « flutter upgrade »"
else
  warn "au moins un réglage est sous le minimum : le build va échouer"
  note "le masquage (skipDependencyChecks) empêche le message explicite, \
pas l'échec"
  note "corriger les fichiers, puis « flutter clean » et \
« rm -rf android/.gradle »"
fi
exit "$STATUS"
