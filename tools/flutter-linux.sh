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
set -euo pipefail

ROOT="${CQCM_LINUX_DEPS_DIR:-$HOME/.cqcm/linux-deps}"
ENV_FILE="$ROOT/env.sh"

if [ ! -f "$ENV_FILE" ]; then
  printf '\033[1;31m[x]\033[0m %s introuvable.\n' "$ENV_FILE" >&2
  printf 'Lance d'"'"'abord :\n  tools/linux-desktop-deps.sh\n' >&2
  exit 2
fi

# shellcheck disable=SC1090
. "$ENV_FILE"

if ! command -v flutter >/dev/null 2>&1; then
  printf '\033[1;31m[x]\033[0m flutter est introuvable dans le PATH.\n' >&2
  exit 2
fi

exec flutter "$@"
