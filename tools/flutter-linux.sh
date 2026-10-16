#!/usr/bin/env bash
#
# Lance `flutter` avec l'environnement du sysroot GTK local.
#
# Permet de compiler l'application pour Linux desktop sans droits root :
# les en-têtes GTK 3 sont extraits dans ~/.cqcm/linux-deps par
# tools/linux-desktop-deps.sh, qui écrit le fichier d'environnement utilisé ici.
#
# Usage :
#   tools/flutter-linux.sh run -d linux
#   tools/flutter-linux.sh build linux --release
#   tools/flutter-linux.sh doctor
#
# Tous les arguments sont transmis tels quels à `flutter`.
#
# Version de Flutter utilisée, dans l'ordre : `$CQCM_FLUTTER`, puis le SDK
# épinglé par .flutter-version (tools/flutter-pinned.sh), puis celui du PATH.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ROOT="${CQCM_LINUX_DEPS_DIR:-$HOME/.cqcm/linux-deps}"
ENV_FILE="$ROOT/env.sh"

if [ ! -f "$ENV_FILE" ]; then
  printf '\033[1;31m[x]\033[0m %s introuvable.\n' "$ENV_FILE" >&2
  printf "Lance d'abord :\n  tools/linux-desktop-deps.sh\n" >&2
  exit 2
fi

# shellcheck disable=SC1090
. "$ENV_FILE"

PINNED=0
FLUTTER_BIN="${CQCM_FLUTTER:-}"
if [ -z "$FLUTTER_BIN" ] && [ -x "$SCRIPT_DIR/flutter-pinned.sh" ]; then
  FLUTTER_BIN="$("$SCRIPT_DIR/flutter-pinned.sh" --print 2>/dev/null || true)"
  [ -n "$FLUTTER_BIN" ] && PINNED=1
fi
if [ -z "$FLUTTER_BIN" ]; then
  FLUTTER_BIN="$(command -v flutter || true)"
fi

if [ -z "$FLUTTER_BIN" ] || [ ! -x "$FLUTTER_BIN" ]; then
  printf '\033[1;31m[x]\033[0m flutter est introuvable :\n' >&2
  printf '  - soit dans le PATH,\n' >&2
  printf '  - soit épinglé (voir .flutter-version et tools/flutter-pinned.sh),\n' >&2
  printf '  - soit imposé par CQCM_FLUTTER=/chemin/vers/flutter.\n' >&2
  exit 2
fi

if [ "$PINNED" = "1" ]; then
  printf '\033[1;34m==>\033[0m %s\n' \
    "SDK épinglé (.flutter-version) : $FLUTTER_BIN" >&2
fi

exec "$FLUTTER_BIN" "$@"
