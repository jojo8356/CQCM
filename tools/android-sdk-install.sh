#!/usr/bin/env bash
#
# Installe un SDK Android complet dans le dossier de l'utilisateur, sans root.
#
# Sert quand la machine n'a qu'un SDK de distribution (ex. /usr/lib/android-sdk)
# sans cmdline-tools ni licences : Gradle ne peut alors rien y installer et le
# build Flutter échoue sur « licences have not been accepted » / « ndk;… ».
#
# Usage (le premier lancement récupère les cmdline-tools) :
#   tools/android-sdk-install.sh                              # recommandé
#   tools/android-sdk-install.sh --zip ~/Téléchargements/commandlinetools-linux-*.zip
#   tools/android-sdk-install.sh --url 'https://dl.google.com/…zip'
#   tools/android-sdk-install.sh --sdk ~/android-sdk          # autre dossier
#   tools/android-sdk-install.sh --no-ndk                     # NDK plus tard
#   tools/android-sdk-install.sh --fake-ndk                   # marqueur au lieu
#                                                             # du NDK (1 Go)
#
# Sans option, le script cherche un zip déjà téléchargé dans ~/Téléchargements,
# ~/Downloads et ~, puis sinon retrouve le lien courant tout seul sur
# dl.google.com (index du dépôt Android, avec repli sur la page
# developer.android.com/studio). --url et --zip servent à forcer un fichier
# précis (poste sans accès réseau, version particulière).
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

# Un lien recopié depuis un exemple ne doit pas partir en 404 silencieux.
if [ -n "$URL" ]; then
  case "$URL" in
    *…* | *'...'* | *'<lien'* | *'<'* | *COLLER* | *'VOTRE'* | *'votre_lien'*)
      die "ce lien est un exemple, pas un vrai lien : $URL
  le vrai lien peut être trouvé automatiquement : lancer sans --url
  ou récupérer le zip : developer.android.com/studio → « Command line tools only »"
      ;;
    http://* | https://*) ;;
    *) die "--url attend un lien http(s) (…zip) : $URL" ;;
  esac
fi

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

# ---------------------------------------------------------------------------
# Trouver le lien du zip des cmdline-tools
# ---------------------------------------------------------------------------

REPO_BASE="https://dl.google.com/android/repository"
REPO_XML="$REPO_BASE/repository2-3.xml"
STUDIO_PAGE="https://developer.android.com/studio"

# Depuis un contenu (index du dépôt ou page HTML) sur l'entrée standard :
# le nom du zip le plus récent, d'après son numéro de build.
pick_cmdline_tools() {
  local picked
  picked="$(grep -oE 'commandlinetools-linux-[0-9]+_latest\.zip' 2>/dev/null |
    sort -u |
    sed 's/^commandlinetools-linux-\([0-9]*\)_latest\.zip$/\1 &/' |
    sort -k1,1n | tail -n 1 | cut -d' ' -f2 || true)"
  [ -n "$picked" ] || return 1
  printf '%s\n' "$picked"
}

fetch_page() {
  case "$1" in
    curl) curl -fsSL --connect-timeout 20 --max-time 60 "$2" 2>/dev/null || true ;;
    wget) wget -qO- --timeout=60 "$2" 2>/dev/null || true ;;
  esac
}

# Retourne l'URL complète du zip, ou rien.
discover_cmdline_tools_url() {
  local tool picked
  for tool in curl wget; do
    command -v "$tool" >/dev/null 2>&1 || continue

    # a) index du dépôt Android : il liste toutes les révisions publiées.
    picked="$(fetch_page "$tool" "$REPO_XML" | pick_cmdline_tools || true)"
    if [ -n "$picked" ]; then
      printf '%s/%s\n' "$REPO_BASE" "$picked"
      return 0
    fi

    # b) page de téléchargement d'Android Studio (mise en page HTML).
    picked="$(fetch_page "$tool" "$STUDIO_PAGE" |
      grep -oE 'https://dl\.google\.com/android/repository/commandlinetools-linux-[0-9]+_latest\.zip' |
      sed 's|.*/||' | pick_cmdline_tools || true)"
    if [ -n "$picked" ]; then
      printf '%s/%s\n' "$REPO_BASE" "$picked"
      return 0
    fi
  done
  return 1
}

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
    log "recherche d'un zip déjà téléchargé (~/Téléchargements, ~/Downloads, ~)"
    for candidate in "$HOME/Téléchargements"/commandlinetools-linux-*.zip \
      "$HOME/Downloads"/commandlinetools-linux-*.zip \
      "$HOME"/commandlinetools-linux-*.zip; do
      if [ -f "$candidate" ]; then
        ZIP="$candidate"
        ok "zip trouvé : $ZIP"
        break
      fi
    done
  fi

  if [ -z "$ZIP" ] && [ -z "$URL" ]; then
    log "recherche du lien courant sur dl.google.com"
    URL="$(discover_cmdline_tools_url || true)"
    if [ -n "$URL" ]; then
      ok "lien retenu : $URL"
    else
      warn "lien introuvable automatiquement (réseau coupé, ou page modifiée)"
      printf '    à la main : %s\n' "$STUDIO_PAGE"
      printf '      section « Command line tools only » → Linux → noter le lien\n'
      printf '    puis relancer :\n'
      printf '      tools/android-sdk-install.sh --url <lien copié>\n'
      printf '      tools/android-sdk-install.sh --zip ~/Téléchargements/commandlinetools-linux-*.zip\n'
      exit 1
    fi
  fi

  if [ -n "$URL" ]; then
    ZIP="$HOME/Téléchargements/$(basename "${URL%%\?*}")"
    mkdir -p "$(dirname "$ZIP")"
    log "téléchargement de $URL"
    download_ok=0
    if command -v curl >/dev/null 2>&1; then
      curl -fL --connect-timeout 30 --retry 2 --progress-bar -o "$ZIP" "$URL" &&
        download_ok=1
    elif command -v wget >/dev/null 2>&1; then
      wget -O "$ZIP" "$URL" && download_ok=1
    else
      die "ni curl ni wget pour télécharger $URL"
    fi
    if [ "$download_ok" != "1" ]; then
      rm -f "$ZIP"
      die "téléchargement en échec : $URL
  lien périmé ? relancer sans --url pour le retrouver automatiquement
  (le script interroge $REPO_XML puis $STUDIO_PAGE)"
    fi
    ok "téléchargé : $ZIP ($(du -h "$ZIP" | cut -f1))"
  fi

  [ -f "$ZIP" ] || die "fichier introuvable : $ZIP"

  # Archive intacte ? Un téléchargement tronqué donnerait une erreur obscure.
  if command -v unzip >/dev/null 2>&1; then
    unzip -tq "$ZIP" >/dev/null 2>&1 ||
      die "archive illisible (téléchargement incomplet ?) : $ZIP
  supprimer le fichier et relancer pour le retélécharger"
  fi

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
  warn "  d'application ; ce fichier évite ~1 Go de téléchargement (et ~4 Go"
  warn "  sur le disque) TANT QU'aucun paquet ne compile de code natif."
  if grep -qE '^  (jni|jni_flutter):' pubspec.lock 2>/dev/null; then
    warn "  ATTENTION : ce projet en a (jni, via path_provider_android >= 2.3.0)."
    warn "  Il faut donc le vrai NDK, ou épingler path_provider_android 2.2.23 :"
    warn "    dependency_overrides:"
    warn "      path_provider_android: 2.2.23"
    warn "  puis flutter pub get ; le marqueur devient alors inutile."
  else
    warn "  Vérifier : grep -E '^  (jni|jni_flutter):' pubspec.lock"
  fi
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
log "adb : utiliser celui du SDK (plus récent que celui du système)"
printf '    export PATH="%s/platform-tools:$PATH"\n' "$SDK_DIR"
log "construire l'APK"
printf '    adb devices                     # téléphone autorisé ?\n'
printf '    tools/build-apk.sh --install --symbols\n'
