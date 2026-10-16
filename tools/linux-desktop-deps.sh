#!/usr/bin/env bash
#
# Prépare Flutter Linux Desktop SANS droits root.
#
# `flutter doctor` réclame les en-têtes GTK 3 (`apt install libgtk-3-dev`), ce
# qui exige sudo. Ce script télécharge les paquets .deb nécessaires (sans les
# installer) et les extrait dans un « sysroot » personnel, puis écrit un
# fichier d'environnement à sourcer. Rien n'est modifié dans /usr.
#
# Usage :
#   tools/linux-desktop-deps.sh              # GTK 3 (+ lzma) : l'essentiel
#   tools/linux-desktop-deps.sh --all        # + clang/ninja/cmake/pkg-config
#   tools/linux-desktop-deps.sh --mesa-utils # + eglinfo (avertissement doctor)
#   tools/linux-desktop-deps.sh --with-runtime  # + bibliothèques d'exécution
#                                            #   (si un .so manque au link)
#   tools/linux-desktop-deps.sh --clean      # repart de zéro
#   tools/linux-desktop-deps.sh --root DIR   # autre emplacement du sysroot
#
# Ensuite :
#   source ~/.cqcm/linux-deps/env.sh
#   flutter run -d linux
#
# ou, en une commande (wrapper fourni) :
#   tools/flutter-linux.sh run -d linux
#
set -euo pipefail

# ---------------------------------------------------------------------------
# Utilitaires
# ---------------------------------------------------------------------------

log() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
ok() { printf '\033[1;32m ok\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*" >&2; }
die() {
  printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2
  exit 1
}

usage() {
  awk 'NR > 2 { if ($0 !~ /^#/) exit; sub(/^# ?/, ""); print }' "${BASH_SOURCE[0]}"
}

# ---------------------------------------------------------------------------
# Options
# ---------------------------------------------------------------------------

ROOT="${CQCM_LINUX_DEPS_DIR:-$HOME/.cqcm/linux-deps}"
WITH_ALL=0
WITH_MESA=0
WITH_RUNTIME=0
CLEAN=0

while [ $# -gt 0 ]; do
  case "$1" in
    --all) WITH_ALL=1 ;;
    --mesa-utils) WITH_MESA=1 ;;
    --with-runtime) WITH_RUNTIME=1 ;;
    --clean) CLEAN=1 ;;
    --root)
      shift
      [ $# -gt 0 ] || die "--root attend un chemin"
      ROOT="$1"
      ;;
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

DEBS="$ROOT/debs"
SYSROOT="$ROOT/sysroot"
ENV_FILE="$ROOT/env.sh"

# ---------------------------------------------------------------------------
# Outils attendus (tous fournis par la distribution, aucun privilège requis)
# ---------------------------------------------------------------------------

for tool in apt-get apt-cache dpkg; do
  command -v "$tool" >/dev/null 2>&1 ||
    die "« $tool » est introuvable : ce script vise Debian/Ubuntu (apt)."
done

if [ "$CLEAN" = 1 ]; then
  log "Nettoyage de $ROOT"
  rm -rf "$ROOT"
fi

mkdir -p "$DEBS" "$SYSROOT"

# ---------------------------------------------------------------------------
# Paquets à récupérer
# ---------------------------------------------------------------------------

PACKAGES=(libgtk-3-dev liblzma-dev)

if [ "$WITH_ALL" = 1 ]; then
  command -v pkg-config >/dev/null 2>&1 || PACKAGES+=(pkg-config)
  command -v ninja >/dev/null 2>&1 || PACKAGES+=(ninja-build)
  command -v cmake >/dev/null 2>&1 || PACKAGES+=(cmake)
  command -v clang >/dev/null 2>&1 || PACKAGES+=(clang)
fi

if [ "$WITH_MESA" = 1 ]; then
  command -v eglinfo >/dev/null 2>&1 || PACKAGES+=(mesa-utils)
fi

for wanted in "${PACKAGES[@]}"; do
  # `apt-cache show` évite toute dépendance à la langue de sortie
  # (« Candidate: » / « Candidat : » selon la locale).
  apt-cache show "$wanted" >/dev/null 2>&1 ||
    warn "aucun paquet candidat pour « $wanted » (listes apt à rafraîchir ?)"
done

# ---------------------------------------------------------------------------
# Fermeture des dépendances, puis filtrage de ce qui est déjà installé
# ---------------------------------------------------------------------------

log "Calcul des dépendances (${PACKAGES[*]})"
mapfile -t CLOSURE < <(
  {
    printf '%s\n' "${PACKAGES[@]}"
    apt-cache depends --recurse --no-recommends --no-suggests \
      --no-conflicts --no-breaks --no-replaces --no-enhances \
      "${PACKAGES[@]}" 2>/dev/null |
      grep -E '^[a-zA-Z0-9]' || true
  } | sed -e 's/:.*$//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' |
    grep -E '^[a-z0-9][a-z0-9.+-]*$' | sort -u
)

TO_FETCH=()
if [ "$WITH_RUNTIME" = 1 ]; then
  # Repli : on extrait aussi les paquets déjà installés (bibliothèques
  # d'exécution), utile si un lien symbolique du sysroot pointe vers une
  # bibliothèque absente du système.
  TO_FETCH=("${CLOSURE[@]}")
else
  for pkg in "${CLOSURE[@]}"; do
    if dpkg -s "$pkg" 2>/dev/null | grep -q '^Status: install ok installed'; then
      continue
    fi
    TO_FETCH+=("$pkg")
  done
fi

if [ "${#TO_FETCH[@]}" -eq 0 ]; then
  log "Toutes les dépendances sont déjà présentes sur le système"
else
  log "${#TO_FETCH[@]} paquet(s) à récupérer dans $DEBS"
fi

# ---------------------------------------------------------------------------
# Téléchargement (apt-get download écrit dans le dossier courant)
# ---------------------------------------------------------------------------

FAILED=()
if [ "${#TO_FETCH[@]}" -gt 0 ]; then
  cd "$DEBS"
  for pkg in "${TO_FETCH[@]}"; do
    if compgen -G "${pkg}_*.deb" >/dev/null; then
      continue
    fi
    if apt-get download "$pkg" >/dev/null 2>&1; then
      printf '  · %s\n' "$pkg"
    else
      FAILED+=("$pkg")
    fi
  done
  cd - >/dev/null
fi

if [ "${#FAILED[@]}" -gt 0 ]; then
  warn "non téléchargé(s) : ${FAILED[*]}"
  warn "si les listes apt sont vides, un « apt-get update » (sudo, une fois)"
  warn "est nécessaire — il n'y a pas d'autre source pour les .deb."
fi

# ---------------------------------------------------------------------------
# Extraction dans le sysroot
# ---------------------------------------------------------------------------

log "Extraction dans $SYSROOT"
COUNT=0
shopt -s nullglob
for deb in "$DEBS"/*.deb; do
  dpkg -x "$deb" "$SYSROOT"
  COUNT=$((COUNT + 1))
done
shopt -u nullglob

ok "$COUNT paquet(s) extrait(s)"

# ---------------------------------------------------------------------------
# Architecture (x86_64-linux-gnu, aarch64-linux-gnu, …)
# ---------------------------------------------------------------------------

MULTIARCH="$(gcc -print-multiarch 2>/dev/null || true)"
if [ -z "$MULTIARCH" ]; then
  MULTIARCH="$(basename "$(
    find /usr/lib -maxdepth 1 -name '*-linux-gnu' 2>/dev/null | head -1
  )")"
fi
if [ -z "$MULTIARCH" ]; then
  MULTIARCH="$(basename "$(
    find "$SYSROOT/usr/lib" -maxdepth 1 -name '*-linux-gnu' 2>/dev/null | head -1
  )")"
fi
[ -n "$MULTIARCH" ] || die "architecture multiarch indéterminée"

LIBDIR="$SYSROOT/usr/lib/$MULTIARCH"
INCDIR="$SYSROOT/usr/include"

# ---------------------------------------------------------------------------
# Réécriture des fichiers .pc
#
# Les paquets de développement sont compilés pour un préfixe /usr : leurs .pc
# déclarent `includedir=/usr/include`, donc `pkg-config --cflags gtk+-3.0`
# renvoie « -I/usr/include/gtk-3.0 ». Ce dossier n'existe pas sur une machine
# sans libgtk-3-dev, et CMake refuse alors la cible Imported
# « PkgConfig::GTK includes non-existent path ». On réécrit donc les .pc de
# façon à ce qu'ils désignent le sysroot.
# ---------------------------------------------------------------------------

log "Réécriture des fichiers .pc vers le sysroot"
PC_COUNT=0
shopt -s nullglob
for pc in "$SYSROOT"/usr/lib/*/pkgconfig/*.pc \
  "$SYSROOT"/usr/lib/pkgconfig/*.pc \
  "$SYSROOT"/usr/share/pkgconfig/*.pc; do
  sed -i \
    -e "s|=\s*/usr|=$SYSROOT/usr|g" \
    -e "s| -I/usr/| -I$SYSROOT/usr/|g" \
    -e "s| -L/usr/| -L$SYSROOT/usr/|g" \
    -e "s|=/lib|=$SYSROOT/lib|g" \
    "$pc"
  PC_COUNT=$((PC_COUNT + 1))
done
shopt -u nullglob
ok "$PC_COUNT fichier(s) .pc pointé(s) vers $SYSROOT"

# ---------------------------------------------------------------------------
# Réparation des liens symboliques fournis par les paquets -dev
#
# `libgtk-3.so` est un lien vers `libgtk-3.so.0`, que seul le paquet
# d'exécution fournit — et il est déjà installé dans /usr, donc non extrait
# ici. Sans ce lien rétabli, l'édition de liens échouerait sur « -lgtk-3 ».
# ---------------------------------------------------------------------------

log "Rétablissement des liens vers les bibliothèques du système"
LINK_COUNT=0
shopt -s nullglob
for libdir in "$SYSROOT"/usr/lib/*-linux-gnu "$SYSROOT"/usr/lib "$SYSROOT"/usr/lib64; do
  [ -d "$libdir" ] || continue
  for link in "$libdir"/*.so; do
    # Un lien qui se résout n'a pas besoin d'aide.
    [ -L "$link" ] && [ ! -e "$link" ] || continue
    target="$(basename "$(readlink "$link")")"
    for sysdir in "/usr/lib/$MULTIARCH" "/lib/$MULTIARCH" /usr/lib /lib \
      /usr/lib64 /lib64; do
      if [ -e "$sysdir/$target" ]; then
        ln -sfn "$sysdir/$target" "$link"
        LINK_COUNT=$((LINK_COUNT + 1))
        break
      fi
    done
  done
done
shopt -u nullglob
ok "$LINK_COUNT lien(s) rétabli(s)"

# ---------------------------------------------------------------------------
# Fichier d'environnement
# ---------------------------------------------------------------------------

log "Écriture de $ENV_FILE"
cat >"$ENV_FILE" <<'TEMPLATE'
# Généré par tools/linux-desktop-deps.sh — à sourcer, jamais à exécuter :
#   source ~/.cqcm/linux-deps/env.sh
# Rend visibles (sans rien installer dans /usr) les en-têtes GTK 3 et les
# bibliothèques de développement extraites dans le sysroot personnel.

export CQCM_LINUX_DEPS="@ROOT@"
export PKG_CONFIG_PATH="@LIB@/pkgconfig:@SYSROOT@/usr/lib/pkgconfig:@SYSROOT@/usr/share/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
export CMAKE_PREFIX_PATH="@SYSROOT@/usr${CMAKE_PREFIX_PATH:+:$CMAKE_PREFIX_PATH}"
export CPATH="@INCDIR@:@INCDIR@/@MULTIARCH@${CPATH:+:$CPATH}"
export C_INCLUDE_PATH="$CPATH"
export CPLUS_INCLUDE_PATH="$CPATH"
export LIBRARY_PATH="@LIB@${LIBRARY_PATH:+:$LIBRARY_PATH}"
export LD_LIBRARY_PATH="${LD_LIBRARY_PATH:+$LD_LIBRARY_PATH:}@LIB@"
export PATH="@SYSROOT@/usr/bin${PATH:+:$PATH}"
TEMPLATE

sed -i \
  -e "s|@ROOT@|$ROOT|g" \
  -e "s|@SYSROOT@|$SYSROOT|g" \
  -e "s|@LIB@|$LIBDIR|g" \
  -e "s|@INCDIR@|$INCDIR|g" \
  -e "s|@MULTIARCH@|$MULTIARCH|g" \
  "$ENV_FILE"

# ---------------------------------------------------------------------------
# Vérification
# ---------------------------------------------------------------------------

log "Vérification"
# shellcheck disable=SC1090
. "$ENV_FILE"

if ! command -v pkg-config >/dev/null 2>&1; then
  warn "pkg-config est absent : relance ce script avec --all"
elif ! pkg-config --exists gtk+-3.0; then
  warn "gtk+-3.0 reste introuvable : la compilation Linux échouera."
  if [ "${#FAILED[@]}" -gt 0 ] &&
    printf '%s\n' "${FAILED[@]}" | grep -q '^libgtk-3-dev$'; then
    warn "→ libgtk-3-dev n'a pas pu être téléchargé : vérifie ta connexion,"
    warn "  puis relance (les .deb déjà récupérés sont réutilisés)."
  fi
  warn "→ si les listes apt sont vides, un « apt-get update » (sudo, une fois)"
  warn "  est indispensable : les .deb ne viennent que des dépôts."
else
  VERSION="$(pkg-config --modversion gtk+-3.0)"
  ORIGIN="$(pkg-config --variable=pcfiledir gtk+-3.0 2>/dev/null || true)"
  ok "gtk+-3.0 $VERSION détecté"
  case "$ORIGIN" in
    '') : ;;
    "$SYSROOT"*) ok "fourni par le sysroot ($ORIGIN)" ;;
    *) ok "fourni par le système ($ORIGIN)" ;;
  esac
  ok "les drapeaux de compilation GTK 3 sont disponibles"

  # CMake refuse qu'une cible déclare un dossier d'en-têtes inexistant :
  # on vérifie donc chaque -I et chaque -l avant de lancer Flutter.
  MISSING_INCLUDE=()
  for include in $(pkg-config --cflags-only-I gtk+-3.0 2>/dev/null |
    tr ' ' '\n' | sed -n 's/^-I//p'); do
    [ -d "$include" ] || MISSING_INCLUDE+=("$include")
  done

  MISSING_LIB=()
  LIBS="$(pkg-config --libs gtk+-3.0 2>/dev/null || true)"
  LIB_DIRS=()
  while IFS= read -r dir; do
    [ -n "$dir" ] && LIB_DIRS+=("$dir")
  done < <(printf '%s' "$LIBS" | tr ' ' '\n' | sed -n 's/^-L//p')

  while IFS= read -r name; do
    [ -n "$name" ] || continue
    FOUND=0
    for dir in "${LIB_DIRS[@]:-}" "/usr/lib/$MULTIARCH" "/lib/$MULTIARCH" \
      /usr/lib /lib; do
      [ -e "$dir/lib$name.so" ] && {
        FOUND=1
        break
      }
    done
    [ "$FOUND" = 1 ] || MISSING_LIB+=("$name")
  done < <(printf '%s' "$LIBS" | tr ' ' '\n' | sed -n 's/^-l//p')

  if [ "${#MISSING_INCLUDE[@]}" -gt 0 ]; then
    warn "dossier(s) d'en-têtes introuvable(s) :"
    printf '   %s\n' "${MISSING_INCLUDE[@]}" >&2
    warn "CMake échouerait avec « non-existent path »."
  else
    ok "tous les dossiers d'en-têtes déclarés existent"
  fi

  if [ "${#MISSING_LIB[@]}" -gt 0 ]; then
    warn "bibliothèque(s) introuvable(s) : ${MISSING_LIB[*]}"
    warn "l'édition de liens risque d'échouer."
  else
    ok "toutes les bibliothèques déclarées sont résolues"
  fi
fi

if command -v eglinfo >/dev/null 2>&1; then
  ok "eglinfo disponible"
else
  warn "eglinfo absent : « flutter doctor » gardera son avertissement"
  warn "non bloquant, à corriger avec --mesa-utils si tu veux"
fi

# ---------------------------------------------------------------------------
# Récapitulatif
# ---------------------------------------------------------------------------

cat <<EOF

$(printf '\033[1;32mPrêt.\033[0m')

Sysroot : $SYSROOT
Environnement : $ENV_FILE

Lancer la compilation Linux :
  source "$ENV_FILE"
  flutter doctor            # « Linux toolchain » doit passer au vert
  flutter run -d linux

Ou en une commande (wrapper fourni avec le projet) :
  tools/flutter-linux.sh run -d linux

Pour rendre l'environnement permanent, ajoute dans ~/.bashrc :
  [ -f "$ENV_FILE" ] && . "$ENV_FILE"
EOF
