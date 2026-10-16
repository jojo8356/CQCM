#!/usr/bin/env bash
#
# Débloque l'accès USB d'un téléphone Android pour son utilisateur courant.
#
# Symptôme visé :
#   error: insufficient permissions for device: user in plugdev group;
#   are your udev rules wrong?
#   ... WP32Pro00014930  no permissions (user in plugdev group ...)
#
# Le câble et le port fonctionnent : seules les règles udev de la machine
# n'autorisent l'accès qu'à root. Ce script identifie le fabricant du
# téléphone branché et produit (ou repose, avec --install) la règle udev
# correspondante.
#
# Usage :
#   tools/android-udev-rule.sh                  # détecte et affiche la règle
#   tools/android-udev-rule.sh --vendor 1782    # idVendor forcé (lsusb)
#   tools/android-udev-rule.sh --match oukitel  # filtre lsusb personnalisé
#   tools/android-udev-rule.sh --install        # pose la règle (sudo demandé)
#   tools/android-udev-rule.sh --list           # tous les appareils USB vus
#   tools/android-udev-rule.sh --target FICHIER # autre fichier de règles
#
# Sans option, rien n'est modifié sur le système : la règle est seulement
# affichée.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

DEFAULT_TARGET="/etc/udev/rules.d/51-android.rules"
# Fabricants Android courants, quand la description lsusb ne dit rien.
KNOWN_VENDORS="18d1 04e8 2717 22b8 0bb4 12d1 1782 2207 2a70 2ae5 05c6 0fce 2916 2d95"

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

MODE=detect
VENDOR=""
MATCH="unisoc|spreadtrum|oukitel|android|adb|google|samsung|xiaomi"
TARGET="$DEFAULT_TARGET"

while [ $# -gt 0 ]; do
  case "$1" in
    --vendor)
      shift
      [ $# -gt 0 ] || die "--vendor attend un id à 4 chiffres (ex. 1782)"
      VENDOR="$1"
      ;;
    --match)
      shift
      [ $# -gt 0 ] || die "--match attend une expression (grep -Ei)"
      MATCH="$1"
      ;;
    --target)
      shift
      [ $# -gt 0 ] || die "--target attend un chemin de fichier"
      TARGET="$1"
      ;;
    --install) MODE=install ;;
    --list) MODE=list ;;
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
# Appareils USB visibles
# ---------------------------------------------------------------------------

command -v lsusb >/dev/null 2>&1 || die "lsusb introuvable (paquet usbutils)"

mapfile -t USB_LINES < <(lsusb)
[ "${#USB_LINES[@]}" -gt 0 ] || die "lsusb ne renvoie rien"

if [ "$MODE" = "list" ]; then
  log "appareils USB vus par la machine"
  printf '    %s\n' "${USB_LINES[@]}"
  exit 0
fi

# ---------------------------------------------------------------------------
# Fabricant du téléphone
# ---------------------------------------------------------------------------

if [ -z "$VENDOR" ]; then
  VENDORS=""
  for line in "${USB_LINES[@]}"; do
    if printf '%s' "$line" | grep -qiE "$MATCH"; then
      id="$(printf '%s' "$line" |
        sed -n 's/.*ID \([0-9a-fA-F]\{4\}\):[0-9a-fA-F]\{4\}.*/\1/p')"
      [ -n "$id" ] && VENDORS="$VENDORS $id"
      printf '    %s\n' "$line" >&2
    fi
  done
  # À défaut de description parlante, un idVendor Android connu.
  if [ -z "${VENDORS// /}" ]; then
    for line in "${USB_LINES[@]}"; do
      id="$(printf '%s' "$line" |
        sed -n 's/.*ID \([0-9a-fA-F]\{4\}\):[0-9a-fA-F]\{4\}.*/\1/p')"
      [ -n "$id" ] || continue
      case " $KNOWN_VENDORS " in
        *" $id "*) VENDORS="$VENDORS $id" ;;
      esac
    done
  fi
  VENDORS="$(printf '%s\n' $VENDORS | sort -u | tr '\n' ' ')"
  VENDORS="${VENDORS% }"
  if [ -z "$VENDORS" ]; then
    warn "aucun appareil Android reconnu dans lsusb"
    warn "  brancher/débrancher le téléphone puis relancer, ou forcer :"
    warn "    tools/android-udev-rule.sh --vendor XXXX"
    warn "  l'idVendor se lit : lsusb -v 2>/dev/null | grep -i idVendor"
    exit 1
  fi
else
  VENDORS="$VENDOR"
fi

# ---------------------------------------------------------------------------
# Règle
# ---------------------------------------------------------------------------

RULES=""
for id in $VENDORS; do
  RULES="${RULES}SUBSYSTEM==\"usb\", ATTR{idVendor}==\"$id\", MODE=\"0666\", GROUP=\"plugdev\"\n"
done

log "idVendor détecté : $VENDORS"

printf '\n'
printf 'Règle udev :\n\n'
printf '%b' "$RULES" | sed 's/^/  /'
printf '\n'

# Sans sudo, la règle reste à poser à la main : c'est déjà une réussite.
if [ "$MODE" != "install" ]; then
  log "pour l'appliquer (droits root nécessaires) :"
  printf '    tools/android-udev-rule.sh --install\n'
  printf '  ou manuellement :\n'
  printf '    printf %s | sudo tee %s\n' "'<les lignes ci-dessus>'" "$TARGET"
  printf '    sudo udevadm control --reload-rules && sudo udevadm trigger\n'
  printf '    adb kill-server && adb devices\n'
  exit 0
fi

if [ "$(id -u)" -eq 0 ]; then
  SUDO=()
elif command -v sudo >/dev/null 2>&1; then
  SUDO=(sudo)
else
  die "sudo introuvable et pas root : poser la règle à la main dans $TARGET"
fi

# Le groupe plugdev doit exister et contenir l'utilisateur, sinon GROUP=
# échoue silencieusement.
HAS_PLUGDEV=1
if ! getent group plugdev >/dev/null 2>&1; then
  HAS_PLUGDEV=0
  warn "le groupe plugdev n'existe pas sur cette machine"
  warn "  la règle utilisera GROUP=\"$(id -gn)\" à la place"
elif ! id -nG | tr ' ' '\n' | grep -qx plugdev; then
  HAS_PLUGDEV=0
  warn "l'utilisateur $(id -un) n'est pas dans le groupe plugdev"
  warn "  la règle utilisera GROUP=\"$(id -gn)\" à la place"
fi

if [ "$HAS_PLUGDEV" = "0" ]; then
  RULES=""
  for id in $VENDORS; do
    RULES="${RULES}SUBSYSTEM==\"usb\", ATTR{idVendor}==\"$id\", MODE=\"0666\", GROUP=\"$(id -gn)\"\n"
  done
  printf 'Règle retenue :\n\n'
  printf '%b' "$RULES" | sed 's/^/  /'
  printf '\n'
fi

log "écriture de $TARGET"
printf '%b' "$RULES" | "${SUDO[@]}" tee "$TARGET" >/dev/null
ok "règle posée : $TARGET"

log "rechargement des règles udev"
"${SUDO[@]}" udevadm control --reload-rules
"${SUDO[@]}" udevadm trigger

ADB_BIN=""
for candidate in "$HOME/platform-tools/adb" \
  "$HOME/android-sdk/platform-tools/adb" \
  "$HOME/Android/Sdk/platform-tools/adb"; do
  [ -x "$candidate" ] && ADB_BIN="$candidate" && break
done
ADB_BIN="${ADB_BIN:-$(command -v adb || true)}"

if [ -n "$ADB_BIN" ]; then
  "$ADB_BIN" kill-server >/dev/null 2>&1 || true
  ok "serveur adb redémarré"
fi

printf '\n'
log "débrancher puis rebrancher le câble USB, puis :"
printf '    adb devices\n'
printf '    tools/build-apk.sh --install --symbols\n'
