#!/usr/bin/env bash
#
# Lance la version de Flutter épinglée pour ce dépôt (voir `.flutter-version`).
#
# Pourquoi : les minimums de Gradle / AGP / Kotlin viennent du SDK Flutter
# installé. Épingler une version connue pour marcher rend les builds
# reproductibles et transforme chaque montée de version en décision.
#
# Le SDK attendu est un clone du dépôt à la version épinglée :
#   git clone -b <version> --depth 1 \
#     https://github.com/flutter/flutter.git ~/flutter-<version>
# (l'état « HEAD détachée » affiché par git est normal sur un tag)
#
# Usage :
#   tools/flutter-pinned.sh run -d linux
#   tools/flutter-pinned.sh test
#   tools/flutter-pinned.sh --dart run bin/test_summary.dart
#   tools/flutter-pinned.sh --check      # où est le SDK, quelle version
#   tools/flutter-pinned.sh --print      # chemin de l'exécutable, sans logs
#
# Emplacements essayés, dans l'ordre : $CQCM_FLUTTER_SDK,
# ~/flutter-<version>, ~/.cqcm/flutter/<version>, /opt/flutter-<version>.
# `CQCM_FLUTTER_SDK` doit pointer la RACINE du SDK (le dossier qui contient
# bin/flutter), ce qui permet aussi d'utiliser un SDK géré par FVM.
#
# Codes de sortie : 0 lancement normal, 2 SDK introuvable ou mal configuré.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
VERSION_FILE="$PROJECT_DIR/.flutter-version"

log() { printf '\033[1;34m==>\033[0m %s\n' "$*" >&2; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*" >&2; }
die() {
  printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2
  exit 2
}

usage() {
  awk 'NR > 2 { if ($0 !~ /^#/) exit; sub(/^# ?/, ""); print }' \
    "${BASH_SOURCE[0]}"
}

MODE=run
case "${1:-}" in
  -h | --help)
    usage
    exit 0
    ;;
  --check) MODE=check ;;
  --print) MODE=print ;;
  --dart) MODE=dart ;;
esac
[ "$MODE" = "run" ] || shift

# ---------------------------------------------------------------------------
# Version épinglée
# ---------------------------------------------------------------------------

[ -f "$VERSION_FILE" ] || die "$VERSION_FILE introuvable."

PINNED="$(awk '
  /^[[:space:]]*#/ { next }
  /^[[:space:]]*$/ { next }
  { print $1; exit }
' "$VERSION_FILE")"
[ -n "$PINNED" ] || die "$VERSION_FILE ne contient aucune version."

# ---------------------------------------------------------------------------
# Résolution du SDK
# ---------------------------------------------------------------------------

CANDIDATES=()
[ -n "${CQCM_FLUTTER_SDK:-}" ] && CANDIDATES+=("$CQCM_FLUTTER_SDK")
CANDIDATES+=(
  "$HOME/flutter-$PINNED"
  # Nom du dossier sans le correctif (clone « ~/flutter-3.47 » pour 3.47.5).
  "$HOME/flutter-${PINNED%.*}"
  "$HOME/.cqcm/flutter/$PINNED"
  "/opt/flutter-$PINNED"
)

SDK_ROOT=""
for candidate in "${CANDIDATES[@]}"; do
  if [ -x "$candidate/bin/flutter" ]; then
    SDK_ROOT="$candidate"
    break
  fi
done

if [ -z "$SDK_ROOT" ]; then
  printf '\033[1;31m[x]\033[0m Aucun SDK Flutter épinglé trouvé (version %s).\n' \
    "$PINNED" >&2
  printf 'Emplacements essayés :\n' >&2
  for candidate in "${CANDIDATES[@]}"; do printf '  %s\n' "$candidate" >&2; done
  printf '\nLe créer :\n  git clone -b %s --depth 1 \\\n' "$PINNED" >&2
  printf '    https://github.com/flutter/flutter.git ~/flutter-%s\n' \
    "${PINNED%.*}" >&2
  printf 'Ou pointer un SDK existant :\n  CQCM_FLUTTER_SDK=/chemin/du/sdk %s\n' \
    "${BASH_SOURCE[0]}" >&2
  exit 2
fi

# Contrôle purement informatif : le tag doit correspondre à la version épinglée.
FOUND="$(git -C "$SDK_ROOT" describe --tags 2>/dev/null || true)"
if [ -n "$FOUND" ] && [ "$FOUND" != "$PINNED" ]; then
  case "$FOUND" in
    "$PINNED"-*) ;;
    *) warn "SDK $SDK_ROOT est en $FOUND (épinglé : $PINNED)." ;;
  esac
fi

FLUTTER_BIN="$SDK_ROOT/bin/flutter"
DART_BIN="$SDK_ROOT/bin/dart"

case "$MODE" in
  print)
    printf '%s\n' "$FLUTTER_BIN"
    exit 0
    ;;
  check)
    log "version épinglée : $PINNED (.flutter-version)"
    log "racine du SDK    : $SDK_ROOT"
    log "flutter          : $FLUTTER_BIN"
    [ -x "$DART_BIN" ] && log "dart             : $DART_BIN"
    exit 0
    ;;
  dart)
    [ -x "$DART_BIN" ] || die "$DART_BIN introuvable : le SDK vient peut-être d'être cloné, lance « $FLUTTER_BIN --version » une première fois pour télécharger le Dart SDK."
    # Le SDK épinglé passe en tête du PATH : un `dart` appelé par un outil
    # interne (build_runner, test…) résout la même version.
    export PATH="$SDK_ROOT/bin:$PATH"
    exec "$DART_BIN" "$@"
    ;;
  *)
    export PATH="$SDK_ROOT/bin:$PATH"
    exec "$FLUTTER_BIN" "$@"
    ;;
esac
