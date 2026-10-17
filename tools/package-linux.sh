#!/usr/bin/env bash
#
# Empaquette l'application Linux : .deb (pour Debian/Ubuntu) et AppImage.
#
# Les deux formats répondent à des besoins différents :
#
#   .deb       → petit paquet (≈ 10 Mo), mais il DECLARE ses dépendances :
#                Debian installe les bibliothèques système (GTK, mpv, …) et
#                l'application embarque seulement le moteur Flutter, le code
#                AOT et ses assets. C'est la forme « optimisée » demandée.
#   AppImage   → un seul fichier exécutable qui EMBARQUE les bibliothèques
#                (sauf glibc et pilotes graphiques, qu'il ne faut jamais
#                embarquer). Fonctionne sur n'importe quelle distribution.
#
# Usage :
#   tools/package-linux.sh --deb            # construit puis crée le .deb
#   tools/package-linux.sh --appimage       # construit puis crée l'AppImage
#   tools/package-linux.sh --all            # les deux
#   tools/package-linux.sh --deb --no-build # réutilise build/linux/.../bundle
#
# Options :
#   --release | --debug   mode de compilation Flutter (release par défaut)
#   --version 1.2.3       version Debian (défaut : celle de pubspec.yaml)
#   --revision 2          révision Debian (défaut : 1)
#   --arches "amd64 arm64" architectures visées par le .deb (défaut : machine)
#   --out DIR             dossier de sortie (défaut : build/packages)
#   --keep                conserve le dossier de travail
#
# Mise en production :
#   --maintainer "Nom <email>"  responsable du paquet (défaut : git config, ou
#                               CQCM_MAINTAINER)
#   --strip                réduit la taille installée (strip --strip-unneeded)
#   --lintian              contrôle le .deb avec lintian, s'il est installé
#
# Répartition, dans les deux cas :
#   EMBARQUÉ   → moteur Flutter, code AOT, assets, icônes, .desktop
#   DÉCLARÉ    → tout le reste des NEEDED, nommé dans « Depends » (.deb)
#   LAISSÉ AU SYSTÈME → liste officielle AppImage (glibc, libstdc++, libz,
#                X11, pilotes graphiques). Les embarquer rend une AppImage
#                plus fragile que la machine hôte : ABI et symboles changent.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_DIR"

APP_NAME="cqcm"
APP_TITLE="CQCM"
APP_ID="com.cqcm.cqcm"
BIN_NAME="cqcm"

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

# ---------------------------------------------------------------------------
# Options
# ---------------------------------------------------------------------------

DO_DEB=0
DO_APPIMAGE=0
DO_BUILD=1
MODE="release"
VERSION=""
REVISION="1"
ARCHES=""
OUT_DIR="build/packages"
KEEP=0
STRIP=0
RUN_LINTIAN=0
MAINTAINER_ARG=""

while [ $# -gt 0 ]; do
  case "$1" in
    --deb) DO_DEB=1 ;;
    --appimage) DO_APPIMAGE=1 ;;
    --all) DO_DEB=1; DO_APPIMAGE=1 ;;
    --no-build) DO_BUILD=0 ;;
    --release) MODE="release" ;;
    --debug) MODE="debug" ;;
    --version)
      shift
      [ $# -gt 0 ] || die "--version attend une valeur (ex. 1.2.3)"
      VERSION="$1"
      ;;
    --revision)
      shift
      [ $# -gt 0 ] || die "--revision attend un nombre"
      REVISION="$1"
      ;;
    --arches)
      shift
      [ $# -gt 0 ] || die "--arches attend une liste (ex. \"amd64 arm64\")"
      ARCHES="$1"
      ;;
    --out)
      shift
      [ $# -gt 0 ] || die "--out attend un dossier"
      OUT_DIR="$1"
      ;;
    --keep) KEEP=1 ;;
    --strip) STRIP=1 ;;
    --lintian) RUN_LINTIAN=1 ;;
    --maintainer)
      shift
      [ $# -gt 0 ] || die "--maintainer attend « Nom <email> »"
      MAINTAINER_ARG="$1"
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

[ "$DO_DEB" = "1" ] || [ "$DO_APPIMAGE" = "1" ] ||
  die "rien à faire : préciser --deb, --appimage ou --all"

case "$(uname -m)" in
  x86_64) HOST_ARCH="amd64" ;;
  aarch64 | arm64) HOST_ARCH="arm64" ;;
  i686 | i386) HOST_ARCH="i386" ;;
  *) HOST_ARCH="$(dpkg --print-architecture 2>/dev/null || uname -m)" ;;
esac
[ -n "$ARCHES" ] || ARCHES="$HOST_ARCH"

if [ -z "$VERSION" ]; then
  VERSION="$(sed -n 's/^version: *\([0-9][^-+ ]*\).*/\1/p' pubspec.yaml |
    head -n 1)"
  [ -n "$VERSION" ] || die "version introuvable : passer --version"
fi
case "$VERSION" in
  *[!0-9.]* | .* | *.) die "version Debian invalide : $VERSION" ;;
esac

# Responsable du paquet : la valeur explicite d'abord, sinon l'identité git du
# dépôt (celle qui signe les commits), sinon un repli neutre. Debian attend un
# couple « Nom <email> » ; une adresse en localhost est refusée par lintian.
MAINTAINER="${MAINTAINER_ARG:-${CQCM_MAINTAINER:-}}"
if [ -z "$MAINTAINER" ]; then
  git_name="$(git config user.name 2>/dev/null || true)"
  git_email="$(git config user.email 2>/dev/null || true)"
  if [ -n "$git_email" ]; then
    MAINTAINER="${git_name:-CQCM} <$git_email>"
  else
    MAINTAINER="CQCM <cqcm@localhost>"
    warn "aucune identité git : responsable du paquet = $MAINTAINER"
    warn "renseigner : git config --global user.email \"vous@exemple.fr\""
  fi
fi
case "$MAINTAINER" in
  *@localhost* | *@localhost.localdomain*)
    warn "adresse en localhost : lintian le signalera (défaut acceptable en local)"
    ;;
esac

# Page du projet : déduite du dépôt git, pour que le paquet la déclare.
HOMEPAGE=""
if git rev-parse --git-dir >/dev/null 2>&1; then
  origin_url="$(git config --get remote.origin.url 2>/dev/null || true)"
  case "$origin_url" in
    git@github.com:*) HOMEPAGE="https://github.com/${origin_url#git@github.com:}" ;;
    ssh://git@github.com/*) HOMEPAGE="https://github.com/${origin_url#ssh://git@github.com/}" ;;
    https://*) HOMEPAGE="$origin_url" ;;
  esac
  HOMEPAGE="${HOMEPAGE%.git}"
fi

# ---------------------------------------------------------------------------
# Compilation
# ---------------------------------------------------------------------------

# Résolution du SDK, dans l'ordre :
#   1. CQCM_FLUTTER           (chemin explicite de l'exécutable)
#   2. tools/flutter-linux.sh (SDK épinglé + sysroot GTK local, si préparé)
#   3. SDK épinglé            (tools/flutter-pinned.sh --print)
#   4. flutter du PATH
FLUTTER_CMD=()
LINUX_DEPS_ENV="${CQCM_LINUX_DEPS_DIR:-$HOME/.cqcm/linux-deps}/env.sh"

if [ -n "${CQCM_FLUTTER:-}" ] && [ -x "${CQCM_FLUTTER}" ]; then
  FLUTTER_CMD=("${CQCM_FLUTTER}")
elif [ -x tools/flutter-linux.sh ] && [ -f "$LINUX_DEPS_ENV" ]; then
  # Le sysroot local est prêt : il fournit les en-têtes GTK sans root.
  FLUTTER_CMD=(tools/flutter-linux.sh)
elif [ -x tools/flutter-pinned.sh ] &&
  PINNED_BIN="$(tools/flutter-pinned.sh --print 2>/dev/null)" &&
  [ -n "$PINNED_BIN" ]; then
  FLUTTER_CMD=("$PINNED_BIN")
elif command -v flutter >/dev/null 2>&1; then
  FLUTTER_CMD=("$(command -v flutter)")
fi

if [ "$DO_BUILD" = "1" ]; then
  if [ "${#FLUTTER_CMD[@]}" = "0" ]; then
    warn "flutter introuvable"
    if [ -x tools/flutter-pinned.sh ]; then
      tools/flutter-pinned.sh --check >&2 || true
    fi
    die "aucun SDK Flutter utilisable. Solutions :
  1. mettre le SDK dans le PATH (ajouter à ~/.zshrc ou ~/.bashrc) :
       export PATH=\"\$HOME/flutter-3.47/bin:\$PATH\"
  2. ou pointer un SDK existant, sans toucher au PATH :
       CQCM_FLUTTER_SDK=\$HOME/flutter-3.47 tools/package-linux.sh --all
  3. ou préparer l'environnement Linux sans root, puis relancer :
       tools/linux-desktop-deps.sh"
  fi
  log "compilation : ${FLUTTER_CMD[*]} build linux --$MODE"
  if ! "${FLUTTER_CMD[@]}" build linux "--$MODE"; then
    die "compilation Flutter échouée :
  - prérequis Linux (clang, cmake, ninja, pkg-config, GTK 3) :
      tools/linux-desktop-deps.sh puis tools/flutter-linux.sh build linux --release
  - diagnostic détaillé : tools/flutter-linux.sh doctor
  - dépannage : docs/linux-sans-root.md"
  fi
fi
# Nom du dossier d'architecture : Flutter 3.47 écrit « x64 » là où les versions
# précédentes écrivaient « x86_64 » (et « arm64 » vs « aarch64 »). On accepte
# les deux, et on préfère le dossier réellement produit pour la machine.
BUNDLE=""
for alt in "x64:x86_64" "arm64:aarch64" "x86_64:x64" "aarch64:arm64"; do
  first="${alt%%:*}"
  second="${alt##*:}"
  for name in "$first" "$second"; do
    candidate="build/linux/$name/$MODE/bundle"
    if [ -x "$candidate/$BIN_NAME" ]; then
      BUNDLE="$candidate"
      break 2
    fi
  done
done

if [ -z "$BUNDLE" ]; then
  # Dernier recours : n'importe quel dossier <mode>/bundle contenant le binaire.
  BUNDLE="$(find build/linux -maxdepth 3 -type d -name bundle 2>/dev/null |
    while IFS= read -r d; do
      [ -x "$d/$BIN_NAME" ] && echo "$d" && break
    done | head -n 1)"
fi
[ -n "$BUNDLE" ] ||
  die "bundle introuvable dans build/linux/*/$MODE/bundle (compiler d'abord)"
ok "bundle : $BUNDLE"

# Un binaire de release ne doit pas pointer vers les bibliothèques locales du
# SDK : vérifié, car ce serait un plantage chez l'utilisateur.
if readelf -d "$BUNDLE/$BIN_NAME" 2>/dev/null | grep -q "$HOME"; then
  die "le binaire référence $HOME (RPATH de compilation) :
il faut compiler avec tools/flutter-linux.sh et sans dépendance locale"
fi

mkdir -p "$OUT_DIR"
OUT_DIR="$(cd "$OUT_DIR" && pwd)"

# ---------------------------------------------------------------------------
# Contenu commun : arborescence « bundle » + icône + fichier .desktop
# ---------------------------------------------------------------------------

WORK="$(mktemp -d -t cqcm-pkg-XXXXXX)"
trap '[ "$KEEP" = "1" ] || rm -rf "$WORK"' EXIT

human() {
  awk -v n="$1" 'BEGIN {
    split("o Ko Mo Go", u, " ")
    i = 1
    while (n >= 1024 && i < 4) { n /= 1024; i++ }
    printf (i == 1 ? "%d %s" : "%.1f %s"), n, u[i]
  }'
}

# Icône PNG de référence, sans dépendance : redimensionnée depuis une source
# déjà présente dans le dépôt (Android/iOS), par un petit script Python.
SOURCE_ICON=""
for candidate in \
  "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png" \
  "android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png" \
  "android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png"; do
  [ -f "$candidate" ] && SOURCE_ICON="$candidate" && break
done
[ -n "$SOURCE_ICON" ] || warn "aucune icône source trouvée dans le dépôt"

ICON_256=""
make_icon() { # make_icon <taille> <chemin de sortie>
  [ -n "$SOURCE_ICON" ] || return 1
  if command -v python3 >/dev/null 2>&1; then
    python3 "$SCRIPT_DIR/lib/png_resize.py" "$SOURCE_ICON" "$2" "$1" \
      >/dev/null 2>&1 && return 0
  fi
  if command -v convert >/dev/null 2>&1; then
    convert "$SOURCE_ICON" -resize "${1}x${1}" "$2" 2>/dev/null && return 0
  fi
  return 1
}

# Copie du bundle dans /usr/lib/cqcm : l'exécutable trouve ses données via
# $ORIGIN/lib, donc l'arborescence doit être conservée à l'identique. Le lien
# est écrit en absolu pour le .deb ; pour l'AppImage, un /usr/bin relatif est
# équivalent après relocation (le fichier .desktop pointe sur le nom seul).
install_tree() { # install_tree <racine, sans slash final>
  local root="$1"
  install -d "$root/usr/lib/$APP_NAME" "$root/usr/bin"
  cp -a "$BUNDLE/." "$root/usr/lib/$APP_NAME/"
  ln -sfn "/usr/lib/$APP_NAME/$BIN_NAME" "$root/usr/bin/$BIN_NAME"
}

write_desktop() { # write_desktop <fichier> [exec]
  local file="$1" exec_path="${2:-/usr/bin/$BIN_NAME}"
  cat > "$file" <<EOF
[Desktop Entry]
Type=Application
Name=$APP_TITLE
GenericName=QCM et révision
Comment=Questionnaires à choix multiples et révision de user stories
Exec=$exec_path
Icon=$APP_ID
Terminal=false
Categories=Education;
Keywords=cqcm;qcm;quiz;revision;
StartupWMClass=$APP_ID
EOF
}

# ---------------------------------------------------------------------------
# Dépendances : ce qu'il faut DÉCLARER au lieu de l'embarquer
# ---------------------------------------------------------------------------

# Versions de symboles ELF requises par un objet, ex. 2.34 pour GLIBC_2.34.
# La version la plus haute est celle qui contraint la distribution minimale.
elf_max_version() { # elf_max_version <fichier> <préfixe>
  readelf -V "$1" 2>/dev/null |
    sed -n "s/.*Name: ${2}\([0-9][0-9.]*\).*/\1/p" |
    sort -V | tail -n 1
}

# Architecture de l'ELF, au format dpkg (amd64, arm64…), vide si indéterminée.
elf_arch() {
  local machine
  machine="$(readelf -h "$1" 2>/dev/null |
    sed -n 's/.*Machine:[[:space:]]*\(.*\)$/\1/p' | head -n 1)"
  case "$machine" in
    *X86-64*) echo amd64 ;;
    *AArch64*) echo arm64 ;;
    *ARM*) echo armhf ;;
    80386* | *i386*) echo i386 ;;
    *) echo "" ;;
  esac
}

# Un fichier est-il un objet ELF ? (évite de lire les icônes et le .desktop)
# readelf renvoie 1 sur tout ce qui n'est pas ELF : pas besoin de lire les
# quatre octets magiques, ce qui déclenchait « octet nul ignoré » sur icudtl.dat.
elf_magic() {
  [ -f "$1" ] && readelf -h "$1" >/dev/null 2>&1
}

# Nom d'architecture AppImage (assets GitHub) depuis celui de dpkg.
appimage_arch() {
  case "$1" in
    amd64) echo x86_64 ;;
    arm64) echo aarch64 ;;
    armhf) echo armhf ;;
    i386) echo i686 ;;
    *) echo "$1" ;;
  esac
}

# Noms des bibliothèques partagées dont dépend un fichier.
elf_needed() {
  readelf -d "$1" 2>/dev/null | sed -n 's/.*(NEEDED).*\[\(.*\)\]/\1/p'
}

# Bibliothèques jamais embarquées dans une AppImage : liste officielle
# AppImage/pkg2appimage (excludelist). glibc, libstdc++, libz, X11, pilotes
# graphiques… doivent venir du système, sinon l'AppImage devient plus fragile
# que la machine hôte (symboles manquants, ABI différente).
APPIMAGE_EXCLUDE_RE='^(ld-linux.*|libanl\.so\.1|libBrokenLocale\.so\.1|libcidn\.so\.1|libc\.so\.6|libdl\.so\.2|libm\.so\.6|libmvec\.so\.1|libnss_.*|libpthread\.so\.0|libresolv\.so\.2|librt\.so\.1|libthread_db\.so\.1|libutil\.so\.1|libstdc\+\+\.so\.6|libGL\.so\.1|libEGL\.so\.1|libGLdispatch\.so\.0|libGLX\.so\.0|libOpenGL\.so\.0|libdrm\.so\.2|libglapi\.so\.0|libgbm\.so\.1|libxcb\.so\.1|libX11\.so\.6|libX11-xcb\.so\.1|libwayland-client\.so\.0|libasound\.so\.2|libfontconfig\.so\.1|libfreetype\.so\.6|libharfbuzz\.so\.0|libcom_err\.so\.2|libexpat\.so\.1|libgcc_s\.so\.1|libgpg-error\.so\.0|libICE\.so\.6|libSM\.so\.6|libusb-1\.0\.so\.0|libuuid\.so\.1|libz\.so\.1|libjack\.so\.0|libpipewire-0\.3\.so\.0|libxcb-dri3\.so\.0|libxcb-dri2\.so\.0|libfribidi\.so\.0|libgmp\.so\.10)$'

appimage_skip_lib() {
  printf '%s' "$1" | grep -Eq "$APPIMAGE_EXCLUDE_RE"
}

# Bibliothèques fournies intrinsèquement par libc6 : inutile de chercher un
# paquet pour elles, libc6 est ajouté directement au Depends.
libc_provided_lib() {
  case "$1" in
    ld-linux* | libc.so* | libm.so* | libpthread.so* | libdl.so* | librt.so* | \
      libresolv.so* | libutil.so* | libanl.so* | libnsl.so* | libcrypt.so* | \
      libmvec.so* | linux-vdso*)
      return 0
      ;;
  esac
  return 1
}

# Une bibliothèque livrée DANS le bundle (moteur Flutter, plugins du projet) :
# le runner la référence par son nom, mais elle voyage avec l'application.
bundle_lib() {
  [ -n "$BUNDLE" ] && [ -e "$BUNDLE/lib/$1" ]
}

# Recherche une bibliothèque fournie par le système (pour l'AppImage : on la
# laisse au système ; pour le .deb : on cherche son paquet Debian).
find_system_lib() {
  local name="$1" path
  if command -v ldconfig >/dev/null 2>&1; then
    path="$(ldconfig -p 2>/dev/null |
      awk -v n="$name" '$1 == n { print $NF; exit }')"
    [ -n "$path" ] && echo "$path" && return 0
  fi
  for dir in /lib/x86_64-linux-gnu /usr/lib/x86_64-linux-gnu \
    /lib/aarch64-linux-gnu /usr/lib/aarch64-linux-gnu /usr/lib64 /usr/lib /lib; do
    [ -e "$dir/$name" ] && echo "$dir/$name" && return 0
  done
  return 1
}

# Paquet Debian qui fournit un fichier (via dpkg -S, sinon la table des noms).
debian_package_of() { # debian_package_of <chemin de bibliothèque> <son nom>
  local path="$1" name="$2" pkg=""
  if command -v dpkg >/dev/null 2>&1; then
    pkg="$(dpkg -S "$(readlink -f "$path")" 2>/dev/null |
      sed -n 's/^\([^:]*\):.*/\1/p' | head -n 1)"
  fi
  if [ -z "$pkg" ]; then
    # Repli quand le fichier n'est pas installé ici (ex. autre architecture).
    case "$name" in
      libgtk-3.so*) pkg="libgtk-3-0" ;;
      libgdk-3.so*) pkg="libgtk-3-0" ;;
      libglib-2.0.so*) pkg="libglib2.0-0" ;;
      libgobject-2.0.so*) pkg="libglib2.0-0" ;;
      libgio-2.0.so*) pkg="libglib2.0-0" ;;
      libgmodule-2.0.so*) pkg="libglib2.0-0" ;;
      libblkid.so*) pkg="libblkid1" ;;
      libmount.so*) pkg="libmount1" ;;
      libselinux.so*) pkg="libselinux1" ;;
      libpcre2-8.so*) pkg="libpcre2-8-0" ;;
      libX11.so* | libX11-xcb.so*) pkg="libx11-6" ;;
      libXext.so*) pkg="libxext6" ;;
      libXau.so*) pkg="libxau6" ;;
      libXdmcp.so*) pkg="libxdmcp6" ;;
      libxcb.so*) pkg="libxcb1" ;;
      libXrender.so*) pkg="libxrender1" ;;
      libXrandr.so*) pkg="libxrandr2" ;;
      libXi.so*) pkg="libxi6" ;;
      libXfixes.so*) pkg="libxfixes3" ;;
      libXcursor.so*) pkg="libxcursor1" ;;
      libXcomposite.so*) pkg="libxcomposite1" ;;
      libXdamage.so*) pkg="libxdamage1" ;;
      libXinerama.so*) pkg="libxinerama1" ;;
      libXss.so*) pkg="libxss1" ;;
      libXtst.so*) pkg="libxtst6" ;;
      libICE.so*) pkg="libice6" ;;
      libSM.so*) pkg="libsm6" ;;
      libxkbcommon.so*) pkg="libxkbcommon0" ;;
      libxkbcommon-x11.so*) pkg="libxkbcommon-x11-0" ;;
      libnss3.so* | libnssutil3.so* | libsmime3.so*) pkg="libnss3" ;;
      libnspr4.so* | libplc4.so* | libplds4.so*) pkg="libnspr4" ;;
      libdbus-1.so*) pkg="libdbus-1-3" ;;
      libudev.so*) pkg="libudev1" ;;
      libcap.so*) pkg="libcap2" ;;
      libgcrypt.so*) pkg="libgcrypt20" ;;
      libgpg-error.so*) pkg="libgpg-error0" ;;
      libz.so*) pkg="zlib1g" ;;
      libbz2.so*) pkg="libbz2-1.0" ;;
      liblzma.so*) pkg="liblzma5" ;;
      liblz4.so*) pkg="liblz4-1" ;;
      libzstd.so*) pkg="libzstd1" ;;
      libexpat.so*) pkg="libexpat1" ;;
      libffi.so*) pkg="libffi8" ;;
      libsystemd.so*) pkg="libsystemd0" ;;
      libuuid.so*) pkg="libuuid1" ;;
      libGL.so* | libGLX.so* | libGLdispatch.so*) pkg="libgl1" ;;
      libEGL.so*) pkg="libegl1" ;;
      libvulkan.so*) pkg="libvulkan1" ;;
      libdrm.so*) pkg="libdrm2" ;;
      libgbm.so*) pkg="libgbm1" ;;
      libwayland-client.so* | libwayland-server.so* | libwayland-egl.so* | \
        libwayland-cursor.so*) pkg="libwayland-client0" ;;
      libstdc++.so*) pkg="libstdc++6" ;;
      libgcc_s.so*) pkg="libgcc-s1" ;;
      libgomp.so*) pkg="libgomp1" ;;
      # Le moteur Flutter utilise lui-même le décodeur vidéo mpv.
      libmpv.so*) pkg="libmpv2" ;;
    esac
  fi
  [ -n "$pkg" ] && echo "$pkg"
  return 0
}

# Dépendances calculées sur les objets réellement expédiés : chaque
# bibliothèque non fournie par le bundle est cherchée sur la machine, puis
# attribuée à son paquet Debian. C'est ce qui rend le .deb petit : il déclare
# au lieu d'embarquer.
collect_deps() { # collect_deps <fichier de sortie>
  : > "$1"
  local objects=() f
  while IFS= read -r -d '' f; do
    elf_magic "$f" || continue
    objects+=("$f")
  done < <(find "$BUNDLE" -maxdepth 2 -type f -print0)

  local needed="" lib
  for f in "${objects[@]}"; do
    needed+="$(elf_needed "$f")"$'\n'
  done
  needed="$(printf '%s' "$needed" | sed '/^$/d' | sort -u)"

  local pkgs="" glibc=""
  # Le moteur Flutter et le runner sont compilés contre glibc : la version de
  # symboles la plus haute fixe la distribution minimale.
  for f in "${objects[@]}"; do
    local v
    v="$(elf_max_version "$f" GLIBC_)"
    if [ -n "$v" ] && { [ -z "$glibc" ] || [ "$(printf '%s\n%s\n' "$v" "$glibc" |
      sort -V | tail -n 1)" = "$v" ]; }; then
      glibc="$v"
    fi
  done
  while IFS= read -r lib; do
    [ -n "$lib" ] || continue
    libc_provided_lib "$lib" && continue
    # libc6 est déjà ajouté ci-dessus avec sa version minimale.
    [ "$lib" = "libc.so.6" ] && continue
    # Moteur Flutter et plugins : expédiés avec l'application.
    bundle_lib "$lib" && continue
    local path pkg
    path="$(find_system_lib "$lib" || true)"
    if [ -z "$path" ]; then
      warn "bibliothèque introuvable sur cette machine : $lib (dépendance non déclarée)"
      continue
    fi
    pkg="$(debian_package_of "$path" "$lib")"
    if [ -n "$pkg" ]; then
      pkgs+="$pkg"$'\n'
    else
      warn "paquet Debian inconnu pour $lib"
    fi
  done <<< "$needed"

  {
    local list
    list="$(printf '%s' "$pkgs" | sed '/^$/d' | sort -u | paste -sd, - |
      sed 's/,/, /g')"
    # libc6 figure une seule fois, avec sa version minimale.
    if [ -n "$glibc" ] && [ -n "$list" ]; then
      echo "Depends: libc6 (>= $glibc), $list"
    elif [ -n "$glibc" ]; then
      echo "Depends: libc6 (>= $glibc)"
    else
      echo "Depends: $list"
    fi
    echo "# glibc minimal requis : $glibc"
  } > "$1"
}

# Réduction de la taille installée : les symboles inutiles partent, les
# symboles dynamiques (utilisés par le chargeur) restent. Le bundle d'origine
# n'est pas modifié, seule la copie empaquetée l'est.
strip_tree() { # strip_tree <racine>
  local root="$1" f before after
  command -v strip >/dev/null 2>&1 || {
    warn "strip absent : paquet non allégé (binutils)"
    return 0
  }
  before="$(du -sk "$root" | cut -f1)"
  while IFS= read -r -d '' f; do
    elf_magic "$f" || continue
    strip --strip-unneeded "$f" 2>/dev/null || true
  done < <(find "$root" -type f -print0)
  after="$(du -sk "$root" | cut -f1)"
  if [ "$before" -gt "$after" ]; then
    ok "strip : $((before - after)) Ko de symboles en moins"
  fi
}

# ---------------------------------------------------------------------------
# .deb
# ---------------------------------------------------------------------------

build_deb() { # build_deb <architecture dpkg>
  command -v dpkg-deb >/dev/null 2>&1 ||
    die "dpkg-deb absent : installer dpkg (Debian/Ubuntu)"
  local arch="$1"
  local stem="${APP_NAME}_${VERSION}-${REVISION}_${arch}"

  # Étiqueter un binaire ARM en amd64 produirait un paquet qui ne démarre pas.
  local real_arch
  real_arch="$(elf_arch "$BUNDLE/$BIN_NAME")"
  if [ -n "$real_arch" ] && [ "$real_arch" != "$arch" ]; then
    die "le binaire est compilé pour $real_arch, pas $arch :
$([ "$real_arch" = "armhf" ] && echo "sous Debian, ARM 32 bits = armhf" || true)
relancer la compilation sur une machine $arch (compilation croisée non gérée)"
  fi
  local root="$WORK/deb-$arch"
  local debfile="$OUT_DIR/${stem}.deb"

  log "assemblage du .deb ($arch)"
  rm -rf "$root"
  install_tree "$root"
  [ "$STRIP" = "1" ] && strip_tree "$root"

  # Icônes et entrée de menu.
  local icons="$root/usr/share/icons/hicolor"
  for size in 16 24 32 48 64 128 256 512; do
    install -d "$icons/${size}x${size}/apps"
    make_icon "$size" "$icons/${size}x${size}/apps/$APP_ID.png" || true
  done
  install -d "$root/usr/share/applications"
  write_desktop "$root/usr/share/applications/$APP_ID.desktop"

  # Documentation : Debian attend un changelog (gzip), un copyright et un
  # fichier de licence.
  local doc="$root/usr/share/doc/$APP_NAME"
  install -d "$doc"
  {
    echo "$APP_NAME ($VERSION-$REVISION) unstable; urgency=medium"
    echo
    echo "  * Version $VERSION, empaquetée pour Linux ($arch)."
    echo
    echo " -- CQCM <cqcm@localhost>  $(date -R)"
  } > "$doc/changelog"
  gzip -9n "$doc/changelog"
  cat > "$doc/copyright" <<EOF
Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
Upstream-Name: $APP_TITLE

Files: *
Copyright: $(date +%Y) $APP_TITLE
License: non spécifiée par le projet (voir le dépôt du projet)
EOF
  ln -sfn "../doc/$APP_NAME/changelog.gz" "$doc/changelog.Debian.gz"

  # DEBIAN/control.
  local deps_file="$WORK/Depends-$arch"
  collect_deps "$deps_file"
  local depends
  depends="$(sed -n 's/^Depends: //p' "$deps_file")"
  local glibc
  glibc="$(sed -n 's/^# glibc minimal requis : //p' "$deps_file")"
  # Pas de « libc6 (>= ) » vide si readelf n'a rien trouvé.
  depends="$(printf '%s' "$depends" | sed 's/libc6 (>= ), //; s/, libc6 (>= )//')"
  local installed_kb
  installed_kb="$(du -sk --apparent-size "$root" | cut -f1)"

  local control="$root/DEBIAN/control"
  install -d "$root/DEBIAN"
  {
    echo "Package: $APP_NAME"
    echo "Version: $VERSION-$REVISION"
    echo "Section: education"
    echo "Priority: optional"
    echo "Architecture: $arch"
    echo "Maintainer: $MAINTAINER"
    echo "Installed-Size: $installed_kb"
    [ -n "$HOMEPAGE" ] && echo "Homepage: $HOMEPAGE"
    [ -n "$depends" ] && echo "Depends: $depends"
    echo "Description: $APP_TITLE — QCM et révision de user stories"
    echo " Application de révision : questionnaires à choix multiples, recopie de"
    echo " texte au mot près, suivi de progression et rappels de révision."
    echo " ."
    echo " Ce paquet embarque le moteur Flutter et le code de l'application ; les"
    echo " bibliothèques GTK et graphiques habituelles sont fournies par Debian"
    echo " (voir Depends)."
  } > "$control"

  # Extensible : l'application peut enregistrer un complément de dépendances.
  local caps="$root/DEBIAN/postinst"
  cat > "$caps" <<'EOF'
#!/bin/sh
set -e
# Rafraîchit le cache des icônes et des entrées de menu, si l'outil existe.
if [ -x /usr/bin/gtk-update-icon-cache ]; then
  gtk-update-icon-cache -q /usr/share/icons/hicolor 2>/dev/null || true
fi
if [ -x /usr/bin/update-desktop-database ]; then
  update-desktop-database -q /usr/share/applications 2>/dev/null || true
fi
exit 0
EOF
  chmod 755 "$caps"

  # xz par défaut : lisible par tous les dpkg. zstd donne un .deb plus gros à
  # installer plus vite ; CQCM_COMPRESS=zstd le choisit quand dpkg le gère.
  local compress="xz"
  if [ "${CQCM_COMPRESS:-}" = "zstd" ]; then
    if dpkg-deb --help 2>/dev/null | grep -q -- '--compress-level'; then
      compress="zstd"
    else
      warn "zstd non géré par ce dpkg : repli sur xz"
    fi
  fi
  dpkg-deb -Z "$compress" --root-owner-group -b "$root" "$debfile" >/dev/null

  local size
  size="$(stat -c '%s' "$debfile")"
  ok ".deb : $debfile"
  printf '    %-22s %s\n' "taille" "$(human "$size")"
  printf '    %-22s %s\n' "installé" "$(human $((installed_kb * 1024)))"
  printf '    %-22s %s\n' "dépendances" "${depends:-aucune}"
  [ -n "$glibc" ] && printf '    %-22s %s\n' "glibc minimal" "$glibc"
  printf '    %-22s sudo apt install ./%s\n' "installer" "$(basename "$debfile")"

  if [ "$RUN_LINTIAN" = "1" ]; then
    if command -v lintian >/dev/null 2>&1; then
      local report
      report="$(lintian --no-cfg "$debfile" 2>/dev/null || true)"
      if [ -z "$report" ]; then
        ok "lintian : aucun défaut"
      else
        warn "lintian : $(printf '%s\n' "$report" | wc -l) remarque(s)"
        printf '%s\n' "$report" | sed -n '1,12p' | sed 's/^/    /'
      fi
    else
      warn "lintian absent : sudo apt install lintian"
    fi
  fi
}

# ---------------------------------------------------------------------------
# AppImage
# ---------------------------------------------------------------------------

# Récupère appimagetool (petit, AppImage autonome) si absent. Vérification du
# sha256 publié quand le fichier .sha256 est disponible.
get_appimagetool() {
  if [ -n "${APPIMAGETOOL:-}" ] && [ -x "$APPIMAGETOOL" ]; then
    echo "$APPIMAGETOOL"
    return 0
  fi
  if command -v appimagetool >/dev/null 2>&1; then
    command -v appimagetool
    return 0
  fi
  local dir="$HOME/.cache/cqcm-tools"
  mkdir -p "$dir"
  # Les assets du dépôt AppImage/appimagetool sont nommés comme l'architecture
  # AppImage (x86_64, aarch64, armhf, i686), pas comme dpkg (amd64, arm64).
  local ai_arch out
  ai_arch="$(appimage_arch "$HOST_ARCH")"
  out="$dir/appimagetool-$ai_arch.AppImage"
  if [ -x "$out" ]; then
    echo "$out"
    return 0
  fi

  local url="https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-$ai_arch.AppImage"
  local log="$dir/download.log"
  : > "$log"
  log "téléchargement d'appimagetool ($ai_arch)" >&2

  local ok_dl=0
  if command -v curl >/dev/null 2>&1; then
    curl -fL --retry 2 --connect-timeout 20 -o "$out" "$url" >>"$log" 2>&1 ||
      ok_dl=1
  elif command -v wget >/dev/null 2>&1; then
    wget -O "$out" "$url" >>"$log" 2>&1 || ok_dl=1
  else
    warn "ni curl ni wget pour télécharger appimagetool" >&2
    warn "installer curl, ou fournir APPIMAGETOOL=/chemin/appimagetool" >&2
    return 1
  fi

  if [ "$ok_dl" != "0" ] || [ ! -s "$out" ]; then
    warn "téléchargement d'appimagetool impossible : $url" >&2
    sed -n '1,3p' "$log" | sed 's/^/      /' >&2
    rm -f "$out"
    return 1
  fi
  chmod +x "$out"
  echo "$out"
}

# Embarque les bibliothèques non système : le bundle Flutter contient déjà le
# moteur, mais l'AppImage doit aussi fournir les bibliothèques GTK et leurs
# dépendances directes, sinon elle ne démarre pas sur une distribution nue.
bundle_shared_libs() { # bundle_shared_libs <AppDir>
  local appdir="$1"
  local libdir="$appdir/usr/lib/cqcm/lib"
  local exe="$appdir/usr/lib/cqcm/$BIN_NAME"
  local seen="" total=0 copied=0

  # Fermeture transitive, profondeur limitée à 3 : au-delà, on embarque des
  # paquets entiers (et souvent des doublons de glibc), donc les dépendances
  # résiduelles restent au système.
  # Graine : l'exécutable ET les bibliothèques déjà présentes dans le bundle
  # (le moteur Flutter est livré en .so, il porte l'essentiel des NEEDED).
  local queue="" f
  for f in "$exe" "$libdir"/*.so*; do
    [ -f "$f" ] || continue
    queue+="$(elf_needed "$f")"$'\n'
  done
  queue="$(printf '%s' "$queue" | sed '/^$/d' | sort -u)"
  local depth=0
  while [ -n "$queue" ] && [ "$depth" -lt 3 ]; do
    local next=""
    while IFS= read -r lib; do
      [ -n "$lib" ] || continue
      case " $seen " in *" $lib "*) continue ;; esac
      seen="$seen $lib"
      if appimage_skip_lib "$lib"; then
        continue
      fi
      # Déjà dans le bundle : rien à copier ni à signaler.
      [ -e "$libdir/$lib" ] && continue
      local src
      src="$(find_system_lib "$lib" || true)"
      if [ -z "$src" ]; then
        warn "bibliothèque introuvable, laissée au système : $lib"
        continue
      fi
      cp -L "$src" "$libdir/$lib"
      copied=$((copied + 1))
      next+="$(elf_needed "$src")"$'\n'
    done <<< "$queue"
    queue="$(printf '%s' "$next" | sed '/^$/d')"
    depth=$((depth + 1))
  done
  total=$copied

  # Les plugins GTK chargés dynamiquement (gdk-pixbuf, thèmes) ne figurent dans
  # aucun NEEDED : les inclure évite une fenêtre sans icônes ni thème.
  local rel
  for rel in \
    usr/lib/x86_64-linux-gnu/gdk-pixbuf-2.0 \
    usr/lib/x86_64-linux-gnu/gtk-3.0 \
    usr/lib/aarch64-linux-gnu/gdk-pixbuf-2.0 \
    usr/lib/aarch64-linux-gnu/gtk-3.0; do
    [ -d "/$rel" ] || continue
    cp -a "/$rel" "$libdir/" 2>/dev/null || true
  done

  printf '    %-22s %d bibliothèques embarquées\n' "compléments" "$total"

  # Le moteur Flutter et le code utilisateur restent ceux du bundle ; le
  # LD_LIBRARY_PATH de l'AppRun les fait trouver dans lib/.
  cat > "$appdir/AppRun" <<'EOF'
#!/bin/sh
# AppRun : point d'entrée de l'AppImage.
# Les bibliothèques embarquées passent avant celles du système, sans jamais
# embarquer glibc (voir la liste EXCLUE dans tools/package-linux.sh).
HERE="$(dirname "$(readlink -f "$0")")"
export LD_LIBRARY_PATH="$HERE/usr/lib/cqcm/lib:${LD_LIBRARY_PATH:-}"
# Les greffons gdk-pixbuf embarqués ont leur propre index ; s'il manque, on
# laisse GTK chercher celui du système plutôt que de le lui interdire.
if [ -f "$HERE/usr/lib/cqcm/lib/gdk-pixbuf-2.0/2.10.0/loaders.cache" ]; then
  export GDK_PIXBUF_MODULE_FILE="$HERE/usr/lib/cqcm/lib/gdk-pixbuf-2.0/2.10.0/loaders.cache"
fi
exec "$HERE/usr/lib/cqcm/cqcm" "$@"
EOF
  chmod 755 "$appdir/AppRun"
}

build_appimage() {
  local toolstem="$1"
  log "assemblage de l'AppImage"

  local appdir="$WORK/CQCM.AppDir"
  rm -rf "$appdir"
  install_tree "$appdir"
  # L'entrée AppImage (AppRun, icône, .desktop) est à la racine de l'AppDir.
  make_icon 256 "$appdir/$APP_ID.png" ||
    die "icône introuvable : impossible de produire l'AppImage"
  cp "$appdir/$APP_ID.png" "$appdir/.DirIcon"
  # Ce .desktop (racine de l'AppDir) est celui que l'AppImage embarque ; son
  # Exec est résolu par AppRun, donc le nom du binaire suffit.
  cat > "$appdir/$APP_ID.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=$APP_TITLE
GenericName=QCM et révision
Comment=Questionnaires à choix multiples et révision de user stories
Exec=$BIN_NAME
Icon=$APP_ID
Terminal=false
Categories=Education;
Keywords=cqcm;qcm;quiz;revision;
X-AppImage-Name=$APP_TITLE
X-AppImage-Version=$VERSION
EOF

  bundle_shared_libs "$appdir"

  local image_arch image_label
  image_arch="$(elf_arch "$BUNDLE/$BIN_NAME")"
  image_label="${image_arch:-$HOST_ARCH}"
  if [ -n "$image_arch" ] && [ "$image_arch" != "$HOST_ARCH" ]; then
    warn "binaire $image_arch sur une machine $HOST_ARCH : AppImage pour $image_arch"
    warn "appimagetool est lancé avec ARCH=$image_label (binaire $HOST_ARCH requis)"
  fi
  local out="$OUT_DIR/${APP_TITLE}-${VERSION}-${image_label}.AppImage"
  local tool
  tool="$(get_appimagetool || true)"
  if [ -z "$tool" ]; then
    warn "appimagetool indisponible : AppDir conservée dans $appdir"
    warn "l'AppDir est une application fonctionnelle : ./AppRun la lance"
    warn "pour produire l'AppImage, fournir appimagetool :"
    warn "  APPIMAGETOOL=/chemin/vers/appimagetool tools/package-linux.sh --appimage --no-build"
    KEEP=1
    return 1
  fi

  # APPIMAGE_EXTRACT_AND_RUN évite le besoin de FUSE (absent en conteneur et
  # fréquent sur les machines sans noyau FUSE activé).
  APPIMAGE_EXTRACT_AND_RUN=1 ARCH="$image_label" "$tool" --no-appstream \
    "$appdir" "$out" >"$WORK/appimagetool.log" 2>&1 || {
    sed -n '1,20p' "$WORK/appimagetool.log" >&2
    die "appimagetool a échoué (journal : $WORK/appimagetool.log)"
  }
  chmod +x "$out"
  local size
  size="$(stat -c '%s' "$out")"
  ok "AppImage : $out"
  printf '    %-22s %s\n' "taille" "$(human "$size")"
  printf '    %-22s %s\n' "lancer" "./$(basename "$out")"
  printf '    %-22s %s\n' "intégrer au menu" \
    "./$(basename "$out") --appimage-integrate"
}

# ---------------------------------------------------------------------------
# Exécution
# ---------------------------------------------------------------------------

printf '\n'
log "paquet $APP_TITLE $VERSION-$REVISION ($MODE, $HOST_ARCH)"

if [ "$DO_DEB" = "1" ]; then
  IFS=' ' read -r -a arch_list <<< "$ARCHES"
  if [ "${#arch_list[@]}" -gt 1 ]; then
    warn "compilation croisée non gérée : seul $HOST_ARCH (machine locale)
est empaqueté ; lancer le script sur une machine $([ "$HOST_ARCH" = amd64 ] && echo arm64 || echo amd64) pour l'autre .deb"
  fi
  for arch in "${arch_list[@]}"; do
    if [ "$arch" != "$HOST_ARCH" ]; then
      warn "$arch : paquet non produit (binaires absents)"
      continue
    fi
    build_deb "$arch"
  done
fi

if [ "$DO_APPIMAGE" = "1" ]; then
  build_appimage "$HOST_ARCH" || true
fi

printf '\n'
ls -lh "$OUT_DIR" 2>/dev/null | sed '1d' | awk '{printf "    %-8s %s\n", $5, $9}'
