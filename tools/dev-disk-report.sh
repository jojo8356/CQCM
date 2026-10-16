#!/usr/bin/env bash
#
# Rapport d'occupation disque de la machine de développement.
#
# N'EFFACE RIEN : le script mesure, puis affiche les commandes de nettoyage
# prêtes à copier, avec le gain estimé et le coût réel de chacune.
#
# Usage :
#   tools/dev-disk-report.sh              # rapport complet
#   tools/dev-disk-report.sh --commands   # seulement les lignes de commandes
#   tools/dev-disk-report.sh --root DIR   # autre dossier personnel
#
# Pourquoi : sur une machine Flutter/Android, ~/.gradle, ~/android-sdk,
# ~/.cache et ~/.pub-cache font l'essentiel du volume — et seuls les dossiers
# VISIBLES apparaissent dans `du -sh */`, ce qui les rend faciles à manquer.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
HOME_DIR="${HOME}"
COMMANDS_ONLY=0

while [ $# -gt 0 ]; do
  case "$1" in
    --commands) COMMANDS_ONLY=1 ;;
    --root)
      shift
      [ $# -gt 0 ] || {
        printf '[x] --root attend un chemin\n' >&2
        exit 2
      }
      HOME_DIR="$1"
      ;;
    -h | --help)
      awk 'NR > 2 { if ($0 !~ /^#/) exit; sub(/^# ?/, ""); print }' \
        "${BASH_SOURCE[0]}"
      exit 0
      ;;
    *)
      printf '[x] option inconnue : %s\n' "$1" >&2
      exit 2
      ;;
  esac
  shift
done

log() { [ "$COMMANDS_ONLY" = "1" ] || printf '\033[1;34m==>\033[0m %s\n' "$*"; }
note() { [ "$COMMANDS_ONLY" = "1" ] || printf '\033[1;36m --\033[0m %s\n' "$*"; }
cmd() { printf '%s\n' "$*"; }

fmt() { # octets -> lisible
  if command -v numfmt >/dev/null 2>&1; then
    numfmt --to=iec --suffix=B "$1"
  else
    printf '%s octets' "$1"
  fi
}

bytes_of() { # taille en octets, 0 si absent
  [ -e "$1" ] || {
    printf '0'
    return 0
  }
  du -sbx "$1" 2>/dev/null | cut -f1 || printf '0'
}

TILDE='~' # variable dédiée : un « ~ » écrit en clair serait expansé par bash

line() { # line LIBELLE CHEMIN
  local size
  [ "$COMMANDS_ONLY" = "1" ] && return 0
  size="$(bytes_of "$2")"
  printf '  %-9s %s  (%s)\n' "$(fmt "$size")" "$1" "${2/#$HOME_DIR/$TILDE}"
}

# Versions Gradle du projet : on ne propose de supprimer que les autres.
WRAPPER_PROPS="$PROJECT_DIR/android/gradle/wrapper/gradle-wrapper.properties"
KEEP_GRADLE=""
[ -f "$WRAPPER_PROPS" ] &&
  KEEP_GRADLE="$(grep -oE 'gradle-[0-9]+(\.[0-9]+)+' "$WRAPPER_PROPS" |
    head -n 1 | sed 's/^gradle-//' || true)"

# ---------------------------------------------------------------------------
# Vue d'ensemble
# ---------------------------------------------------------------------------
log "Espace disque"
if [ "$COMMANDS_ONLY" = "0" ]; then
  df -h "$HOME_DIR" | awk 'NR == 1 { next } { print "  " $0 }'
fi

log "Dossiers personnels (du -xh --max-depth=1, gros en dernier)"
if [ "$COMMANDS_ONLY" = "0" ]; then
  du -xh --max-depth=1 "$HOME_DIR" 2>/dev/null | sort -h | tail -n 12
fi

log "Postes connus"
line ".gradle" "$HOME_DIR/.gradle"
line "  dont caches" "$HOME_DIR/.gradle/caches"
line "  dont wrapper/dists" "$HOME_DIR/.gradle/wrapper/dists"
line ".pub-cache" "$HOME_DIR/.pub-cache"
line ".npm" "$HOME_DIR/.npm"
line ".cache" "$HOME_DIR/.cache"
line ".local/share" "$HOME_DIR/.local/share"
line ".config/Code" "$HOME_DIR/.config/Code"
line ".vscode/extensions" "$HOME_DIR/.vscode/extensions"
line "android-sdk" "$HOME_DIR/android-sdk"
line "Android" "$HOME_DIR/Android"
line ".cqcm (sysroot GTK)" "$HOME_DIR/.cqcm"
line "Documents" "$HOME_DIR/Documents"

# ---------------------------------------------------------------------------
# Suggestions
# ---------------------------------------------------------------------------
log "Nettoyage possible (le script n'efface rien, il imprime)"

any=0
suggest() { # suggest GAIN TEXTE COMMANDE...
  any=1
  note "$1 — $2"
  cmd "$3"
}

# --- Gradle : distributions inutiles --------------------------------------
if [ -d "$HOME_DIR/.gradle/wrapper/dists" ]; then
  stale="$(ls -d "$HOME_DIR"/.gradle/wrapper/dists/*/ 2>/dev/null |
    grep -v "gradle-${KEEP_GRADLE:-inconnu}-all/$" || true)"
  if [ -n "$stale" ]; then
    size=0
    for dir in $stale; do
      size=$((size + $(bytes_of "$dir")))
    done
    command_line="rm -rf"
    for dir in $stale; do command_line="$command_line ${dir%/}"; done
    suggest "$(fmt "$size")" "distributions Gradle non utilisées \
(le projet est en ${KEEP_GRADLE:-?})" "$command_line"
  fi
fi

# --- Gradle : caches par version ------------------------------------------
if [ -d "$HOME_DIR/.gradle/caches" ]; then
  stale="$(ls -d "$HOME_DIR"/.gradle/caches/*/ 2>/dev/null |
    grep -vE '/(modules-2|jars-[0-9]+|journal-1|transforms[^/]*|build-cache-[0-9]+)/$' |
    grep -v "/${KEEP_GRADLE:-gradle-inconnu}/$" || true)"
  if [ -n "$stale" ]; then
    size=0
    for dir in $stale; do
      size=$((size + $(bytes_of "$dir")))
    done
    command_line="rm -rf"
    for dir in $stale; do command_line="$command_line ${dir%/}"; done
    suggest "$(fmt "$size")" "caches des versions de Gradle abandonnées \
(recalculés à la demande, aucune dépendance retéléchargée : modules-2 est \
partagé)" "$command_line"
  fi
fi

# --- Caches régénérables ---------------------------------------------------
for pair in \
  ".cache/Google" \
  ".cache/pip" \
  ".cache/thumbnails" \
  ".cache/mesa_shader_cache" \
  ".config/Code/CachedData" \
  ".config/Code/logs" \
  ".config/Code/workspaceStorage" \
  ".npm/_cacache" \
  ".local/share/Trash"; do
  if [ -d "$HOME_DIR/$pair" ]; then
    size="$(bytes_of "$HOME_DIR/$pair")"
    if [ "$size" -gt $((20 * 1024 * 1024)) ]; then
      suggest "$(fmt "$size")" "cache régénérable" "rm -rf $HOME_DIR/$pair"
    fi
  fi
done

# --- SDK Android : ce qui ne sert pas pour compiler ------------------------
for pair in system-images emulator sources docs; do
  if [ -d "$HOME_DIR/android-sdk/$pair" ]; then
    size="$(bytes_of "$HOME_DIR/android-sdk/$pair")"
    if [ "$size" -gt $((50 * 1024 * 1024)) ]; then
      suggest "$(fmt "$size")" "android-sdk/$pair : utile aux émulateurs et à \
la documentation, pas à la compilation" \
        "rm -rf $HOME_DIR/android-sdk/$pair"
    fi
  fi
done

# --- Extensions VS Code : tri manuel dans l'éditeur -----------------------
if [ -d "$HOME_DIR/.vscode/extensions" ]; then
  vscode_size="$(bytes_of "$HOME_DIR/.vscode/extensions")"
  if [ "$vscode_size" -gt $((300 * 1024 * 1024)) ]; then
    any=1
    note "extensions VS Code ($(fmt "$vscode_size")) : à trier dans l'éditeur \
(Extensions → désinstaller celles qui ne servent pas)"
    cmd "du -sh $HOME_DIR/.vscode/extensions/*/ | sort -h"
  fi
fi

# --- Dépôt : artefacts de build -------------------------------------------
for pair in build .dart_tool android/.gradle; do
  if [ -e "$PROJECT_DIR/$pair" ]; then
    suggest "$(fmt "$(bytes_of "$PROJECT_DIR/$pair")")" \
      "artefacts de build du dépôt" \
      "rm -rf $PROJECT_DIR/$pair"
  fi
done

if [ "$any" = "0" ]; then
  note "rien de gros à signaler"
fi

log "À ne pas supprimer"
note "~/.gradle/gradle.properties, ~/.gradle/init.d (configuration des builds)"
note "~/.pub-cache (hors ligne), ~/flutter-<version> (SDK épinglé), ~/jdk"
note "~/.android/adbkey (appareil appairé), ~/.config/google-chrome (profil)"

if [ "$COMMANDS_ONLY" = "0" ]; then
  log "Rappel des tailles après nettoyage"
  note "df -h ~ && du -xh --max-depth=1 ~ | sort -h | tail -15"
fi
