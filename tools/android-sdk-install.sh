#!/usr/bin/env bash
#
# Installe un SDK Android complet dans le dossier de l'utilisateur, sans root.
#
# Sert quand la machine n'a qu'un SDK de distribution (ex. /usr/lib/android-sdk)
# sans cmdline-tools ni licences : Gradle ne peut alors rien y installer et le
# build Flutter échoue sur « licences have not been accepted » / « ndk;… ».
#
# Usage (le premier lancement a besoin du zip des cmdline-tools) :
#   tools/android-sdk-install.sh --url '<lien du zip cmdline-tools>'
#   tools/android-sdk-install.sh --zip ~/Téléchargements/commandlinetools-linux-*.zip
#   tools/android-sdk-install.sh --sdk ~/android-sdk          # autre dossier
#   tools/android-sdk-install.sh --no-ndk                     # NDK plus tard
#   tools/android-sdk-install.sh --fake-ndk                   # marqueur au lieu
#                                                             # du NDK (1 Go)
#   tools/android-sdk-install.sh                              # SDK déjà amorcé
#
# Le lien du zip se trouve sur developer.android.com/studio, section
# « Command line tools only » (fichier commandlinetools-linux-*_latest.zip).
# Il peut aussi être déjà téléchargé : --zip, ou laisser le script le chercher
# dans ~/Téléchargements et ~/Downloads.
#
# Dossier par défaut : ~/Android/Sdk — c'est celui que Flutter cherche tout seul
# sous Linux, aucun réglage n'est donc nécessaire ensuite.
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

SDK_DIR="$HOME/Android/Sdk"
ZIP=""
URL=""
INSTALL_NDK=1
FAKE_NDK=0
JAVA_HOME_OPT=""
EXTRA_PACKAGES=()

while [ $# -gt 0 ]; do
  case "$1" in
    --sdk)
      shift
      [ $# -gt 0 ] || die "--sdk attend un dossier"
      SDK_DIR="$1"
      ;;
    --zip)
      shift
      [ $# -gt 0 ] || die "--zip attend un fichier .zip"
      ZIP="$1"
      ;;
    --url)
      shift
      [ $# -gt 0 ] || die "--url attend un lien https://…zip"
      URL="$1"
      ;;
    --no-ndk) INSTALL_NDK=0 ;;
    --fake-ndk) FAKE_NDK=1 ;;
    --packages)
      shift
      [ $# -gt 0 ] || die "--packages attend une liste « a;b;c »"
      IFS=';' read -r -a EXTRA_PACKAGES <<<"$1"
      ;;
    --java-home)
      shift
      [ $# -gt 0 ] || die "--java-home attend un dossier"
      JAVA_HOME_OPT="$1"
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

SDK_DIR="${SDK_DIR/#\~/$HOME}"

# ---------------------------------------------------------------------------
# Flutter épinglé : versions attendues (compileSdk, ndkVersion)
# ---------------------------------------------------------------------------

FLUTTER_BIN=""
if [ -x "$SCRIPT_DIR/flutter-pinned.sh" ]; then
  FLUTTER_BIN="$("$SCRIPT_DIR/flutter-pinned.sh" --print 2>/dev/null || true)"
fi
[ -n "$FLUTTER_BIN" ] || FLUTTER_BIN="$(command -v flutter || true)"

FLUTTER_ROOT=""
[ -n "$FLUTTER_BIN" ] &&
  FLUTTER_ROOT="$(cd "$(dirname "$FLUTTER_BIN")/.." && pwd)"

COMPILE_SDK=36
NDK_EXPECTED=28.2.13676358
EXT="$FLUTTER_ROOT/packages/flutter_tools/gradle/src/main/kotlin/FlutterExtension.kt"
if [ -n "$FLUTTER_ROOT" ] && [ -f "$EXT" ]; then
  value="$(sed -n 's/.*compileSdkVersion: Int = \([0-9][0-9]*\).*/\1/p' "$EXT" |
    head -n 1)"
  [ -n "$value" ] && COMPILE_SDK="$value"
  value="$(sed -n 's/.*ndkVersion: String = "\([^"]*\)".*/\1/p' "$EXT" |
    head -n 1)"
  [ -n "$value" ] && NDK_EXPECTED="$value"
fi

# ---------------------------------------------------------------------------
# Java (sdkmanager tourne sur une JVM ≥ 17)
# ---------------------------------------------------------------------------

if [ -n "$JAVA_HOME_OPT" ]; then
  export JAVA_HOME="$JAVA_HOME_OPT"
elif [ -n "${JAVA_HOME:-}" ] && [ -x "${JAVA_HOME}/bin/java" ]; then
  : # déjà fourni par l'environnement
elif [ -x "$HOME/jdk/bin/java" ]; then
  export JAVA_HOME="$HOME/jdk"
fi

JAVA_BIN=""
if [ -n "${JAVA_HOME:-}" ] && [ -x "$JAVA_HOME/bin/java" ]; then
  JAVA_BIN="$JAVA_HOME/bin/java"
else
  JAVA_BIN="$(command -v java || true)"
fi
[ -n "$JAVA_BIN" ] ||
  die "java introuvable : poser JAVA_HOME (ex. ~/jdk), ou --java-home <dossier>
sdkmanager a besoin d'une JVM 17 ou plus récente"

JAVA_MAJOR="$("$JAVA_BIN" -version 2>&1 |
  sed -n 's/.*version "\([0-9][0-9]*\).*/\1/p' | head -n 1)"
[ -n "$JAVA_MAJOR" ] || JAVA_MAJOR=0
if [ "$JAVA_MAJOR" -lt 17 ]; then
  warn "java $JAVA_MAJOR détecté : sdkmanager demande une version 17 ou plus"
fi
log "java : $JAVA_BIN (version $JAVA_MAJOR)"

# ---------------------------------------------------------------------------
# cmdline-tools : présent, ou à récupérer
# ---------------------------------------------------------------------------

sdkmanager_in() {
  local dir="$1" candidate
  for candidate in \
    "$dir/cmdline-tools/latest/bin/sdkmanager" \
    "$dir"/cmdline-tools/*/bin/sdkmanager \
    "$dir/tools/bin/sdkmanager"; do
    [ -x "$candidate" ] && printf '%s\n' "$candidate" && return 0
  done
  return 1
}

SDKMANAGER="$(sdkmanager_in "$SDK_DIR" 2>/dev/null || true)"

unpack_cmdline_tools() {
  local file="$1" work="$2"
  if command -v unzip >/dev/null 2>&1; then
    unzip -q -o "$file" -d "$work"
  elif command -v python3 >/dev/null 2>&1; then
    python3 -c "
import sys, zipfile
zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])
" "$file" "$work"
  else
    die "ni unzip ni python3 : impossible d'extraire $file"
  fi
}

if [ -z "$SDKMANAGER" ]; then
  mkdir -p "$SDK_DIR"
  [ -z "$ZIP" ] && [ -z "$URL" ] &&
    for candidate in "$HOME/Téléchargements"/commandlinetools-linux-*.zip \
      "$HOME/Downloads"/commandlinetools-linux-*.zip \
      "$HOME"/commandlinetools-linux-*.zip; do
      [ -f "$candidate" ] && ZIP="$candidate" && break
    done

  if [ -z "$ZIP" ] && [ -z "$URL" ]; then
    warn "aucun zip de cmdline-tools trouvé"
    printf '    télécharger « Command line tools only » :\n'
    printf '      https://developer.android.com/studio  (section Command line tools)\n'
    printf '    puis relancer avec le fichier ou le lien :\n'
    printf '      tools/android-sdk-install.sh --zip ~/Téléchargements/commandlinetools-linux-*.zip\n'
    printf '      tools/android-sdk-install.sh --url <lien copié depuis la page>\n'
    exit 1
  fi

  if [ -n "$URL" ]; then
    command -v curl >/dev/null 2>&1 || command -v wget >/dev/null 2>&1 ||
      die "ni curl ni wget pour télécharger $URL"
    ZIP="$HOME/Téléchargements/$(basename "${URL%%\?*}")"
    mkdir -p "$(dirname "$ZIP")"
    log "téléchargement de $URL"
    if command -v curl >/dev/null 2>&1; then
      curl -L --fail --progress-bar -o "$ZIP" "$URL"
    else
      wget -O "$ZIP" "$URL"
    fi
  fi

  [ -f "$ZIP" ] || die "fichier introuvable : $ZIP"
  log "extraction de $(basename "$ZIP")"

  WORK="$(mktemp -d)"
  unpack_cmdline_tools "$ZIP" "$WORK"

  SRC=""
  if [ -x "$WORK/cmdline-tools/bin/sdkmanager" ]; then
    SRC="$WORK/cmdline-tools"
  elif [ -x "$WORK/cmdline-tools/latest/bin/sdkmanager" ]; then
    SRC="$WORK/cmdline-tools/latest"
  else
    SRC="$(find "$WORK" -maxdepth 4 -type f -name sdkmanager -perm -u+x \
      -printf '%h\n' 2>/dev/null | head -n 1)"
    [ -n "$SRC" ] && SRC="$(dirname "$SRC")"
  fi
  [ -n "$SRC" ] && [ -d "$SRC" ] ||
    die "sdkmanager introuvable dans l'archive : $ZIP"

  mkdir -p "$SDK_DIR/cmdline-tools/latest"
  cp -a "$SRC/." "$SDK_DIR/cmdline-tools/latest/"
  rm -rf "$WORK"
  chmod +x "$SDK_DIR/cmdline-tools/latest/bin/"* 2>/dev/null || true

  SDKMANAGER="$(sdkmanager_in "$SDK_DIR" || true)"
  [ -n "$SDKMANAGER" ] || die "installation des cmdline-tools en échec"
  ok "cmdline-tools installés : $SDKMANAGER"
else
  ok "cmdline-tools déjà présents : $SDKMANAGER"
fi

# ---------------------------------------------------------------------------
# Licences puis composants
# ---------------------------------------------------------------------------

log "acceptation des licences (oui à tout, dans $SDK_DIR)"
# Un « y » par licence : sdkmanager en demande une poignée, et s'arrête à la
# fin de l'entrée standard. (Pas de `yes |` : sous `pipefail`, le SIGPIPE
# ferait échouer le pipeline alors que les licences sont acceptées.)
if printf 'y\n%.0s' {1..60} |
  "$SDKMANAGER" --sdk_root="$SDK_DIR" --licenses >/dev/null; then
  ok "licences traitées"
else
  warn "certaines licences n'ont pas été acceptées : relancer"
  printf '    printf %s | %s --sdk_root=%s --licenses\n' \
    "'y\\n' | head -60" "$SDKMANAGER" "$SDK_DIR"
fi

PACKAGES=(
  "platform-tools"
  "platforms;android-$COMPILE_SDK"
  "build-tools;$COMPILE_SDK.0.0"
)

if [ "$INSTALL_NDK" = "1" ] && [ "$FAKE_NDK" = "0" ]; then
  PACKAGES+=("ndk;$NDK_EXPECTED")
fi
if [ "${#EXTRA_PACKAGES[@]}" -gt 0 ]; then
  PACKAGES+=("${EXTRA_PACKAGES[@]}")
fi

log "installation : ${PACKAGES[*]}"
"$SDKMANAGER" --sdk_root="$SDK_DIR" --install "${PACKAGES[@]}"
ok "composants installés"

# ---------------------------------------------------------------------------
# NDK : marqueur éventuel
# ---------------------------------------------------------------------------

if [ "$FAKE_NDK" = "1" ]; then
  MARKER="$SDK_DIR/ndk/$NDK_EXPECTED"
  mkdir -p "$MARKER"
  cat > "$MARKER/source.properties" <<EOF
Pkg.Desc = Android NDK (marqueur, aucun binaire)
Pkg.Revision = $NDK_EXPECTED
EOF
  warn "marqueur de NDK posé : $MARKER/source.properties"
  warn "  le plugin Gradle de Flutter exige un NDK pour tout projet"
  warn "  d'application ; ce projet ne compile aucun code natif, donc le NDK"
  warn "  n'est jamais utilisé — ce fichier suffit et évite ~1 Go de"
  warn "  téléchargement (et ~4 Go sur le disque)"
  warn "  si un plugin natif est ajouté un jour : supprimer ce dossier, puis"
  warn "  tools/android-sdk-install.sh --sdk '$SDK_DIR' (NDK complet)"
elif [ "$INSTALL_NDK" = "1" ]; then
  ok "NDK $NDK_EXPECTED installé dans $SDK_DIR/ndk"
else
  warn "--no-ndk : le NDK n'est pas installé ; Gradle le réclamera au premier"
  warn "  build. Relancer sans --no-ndk, ou avec --fake-ndk (marqueur)."
fi

# ---------------------------------------------------------------------------
# Flutter doit utiliser ce SDK
# ---------------------------------------------------------------------------

if [ -n "$FLUTTER_BIN" ]; then
  log "flutter config --android-sdk $SDK_DIR"
  "$FLUTTER_BIN" config --android-sdk "$SDK_DIR" >/dev/null
  ok "Flutter utilisera désormais $SDK_DIR"
else
  warn "flutter introuvable : régler à la main"
  printf '    flutter config --android-sdk %s\n' "$SDK_DIR"
fi

printf '\n'
log "vérification"
printf '    tools/android-sdk-doctor.sh\n'
log "construire l'APK"
printf '    adb devices                     # téléphone autorisé ?\n'
printf '    tools/build-apk.sh --install --symbols\n'
