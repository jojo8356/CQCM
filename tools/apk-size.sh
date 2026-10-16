#!/usr/bin/env bash
#
# Détaille la taille de l'application : APK sur le disque, répartition interne,
# et taille réellement occupée sur le téléphone.
#
# Trois « tailles » différentes, souvent confondues :
#   1. le fichier APK (ce qu'on copie) ;
#   2. ce qui est installé sur le téléphone (APK + code compilé, généralement
#      un peu plus gros) ;
#   3. les données de l'application (progression de révision, QCM importés).
#
# Usage :
#   tools/apk-size.sh                      # dernier APK release du projet
#   tools/apk-size.sh --apk <fichier.apk>
#   tools/apk-size.sh --split              # détail par bibliothèque native
#   tools/apk-size.sh --top 20             # 20 plus gros fichiers internes
#   tools/apk-size.sh --device SERIAL      # appareil précis (plusieurs branchés)
#   tools/apk-size.sh --no-device          # seulement la partie locale
#
# Pour la répartition fine du *code* Dart (paquets les plus lourds), il faut
# reconstruire avec l'analyse activée :
#   tools/build-apk.sh --abi arm64 --analyze-size
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_DIR"

PKG="com.cqcm.cqcm"

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

APK=""
DEVICE=""
USE_DEVICE=1
TOP=12
SPLIT=0

while [ $# -gt 0 ]; do
  case "$1" in
    --apk)
      shift
      [ $# -gt 0 ] || die "--apk attend un fichier"
      APK="$1"
      ;;
    --device)
      shift
      [ $# -gt 0 ] || die "--device attend un numéro de série (adb devices)"
      DEVICE="$1"
      ;;
    --no-device) USE_DEVICE=0 ;;
    --top)
      shift
      [ $# -gt 0 ] || die "--top attend un nombre"
      TOP="$1"
      ;;
    --split) SPLIT=1 ;;
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
# APK à mesurer
# ---------------------------------------------------------------------------

if [ -z "$APK" ]; then
  DIR="build/app/outputs/flutter-apk"
  [ -d "$DIR" ] || die "aucun APK : compiler d'abord (tools/build-apk.sh)"
  APK="$(find "$DIR" -maxdepth 1 -name '*.apk' -printf '%T@ %p\n' 2>/dev/null |
    sort -rn | head -n 1 | cut -d' ' -f2-)"
fi
[ -n "$APK" ] && [ -f "$APK" ] || die "APK introuvable : ${APK:-aucun}"

SIZE_BYTES="$(stat -c '%s' "$APK")"

human() {
  # octets → lisible (Ko/Mo/Go, base 1024)
  awk -v n="$1" 'BEGIN {
    split("o Ko Mo Go", u, " ")
    i = 1
    while (n >= 1024 && i < 4) { n /= 1024; i++ }
    printf (i == 1 ? "%d %s" : "%.1f %s"), n, u[i]
  }'
}

printf '\n'
log "APK : $APK"
printf '    %s (%s octets)\n' "$(human "$SIZE_BYTES")" "$SIZE_BYTES"
printf '    %s\n' "sha256 : $(sha256sum "$APK" | cut -d' ' -f1)"

# ---------------------------------------------------------------------------
# Taille de téléchargement + répartition interne
# ---------------------------------------------------------------------------

APKANALYZER=""
for candidate in \
  "${ANDROID_HOME:-}/cmdline-tools/latest/bin/apkanalyzer" \
  "${ANDROID_SDK_ROOT:-}/cmdline-tools/latest/bin/apkanalyzer" \
  "$HOME/Android/Sdk/cmdline-tools/latest/bin/apkanalyzer" \
  "$HOME/android-sdk/cmdline-tools/latest/bin/apkanalyzer"; do
  [ -n "$candidate" ] && [ -x "$candidate" ] && APKANALYZER="$candidate" && break
done
if [ -z "$APKANALYZER" ] && [ -n "${ANDROID_HOME:-}" ]; then
  APKANALYZER="$(find "$ANDROID_HOME/cmdline-tools" -maxdepth 3 -name apkanalyzer \
    -type f -perm -u+x 2>/dev/null | head -n 1 || true)"
fi

DL=""
if [ -n "$APKANALYZER" ]; then
  DL="$("$APKANALYZER" apk download-size "$APK" 2>/dev/null || true)"
fi
if [ -n "$DL" ]; then
  printf '    %s\n' "taille de téléchargement : $(human "$DL") ($DL octets, apkanalyzer)"
else
  # Estimation : ce que pèserait l'APK transféré tel quel.
  EST="$(gzip -9 -c "$APK" | wc -c)"
  printf '    %s\n' "taille de téléchargement : ≈ $(human "$EST") (estimation gzip)"
fi

printf '\n'
log "répartition interne (par dossier de l'APK)"
python3 - "$APK" "$TOP" "$SPLIT" <<'PY'
import collections, sys, zipfile

apk, top_n, split = sys.argv[1], int(sys.argv[2]), sys.argv[3] == "1"
total = 0
by_dir = collections.Counter()
by_entry = []

with zipfile.ZipFile(apk) as z:
    for info in z.infolist():
        if info.is_dir():
            continue
        size = info.compress_size  # poids réellement stocké
        total += size
        parts = info.filename.split("/")
        # Regroupement utile : lib/<abi>, assets/flutter_assets/..., etc.
        if parts[0] == "lib" and len(parts) > 2:
            key = f"{parts[0]}/{parts[1]}"
        elif parts[0] == "assets" and len(parts) > 1:
            key = f"{parts[0]}/{parts[1]}"
        elif len(parts) > 1:
            key = parts[0] + "/"
        else:
            key = parts[0]
        by_dir[key] += size
        by_entry.append((size, info.filename, info.compress_size))


def human(n):
    for unit in ("o", "Ko", "Mo", "Go"):
        if n < 1024 or unit == "Go":
            return f"{n:.0f} {unit}" if unit == "o" else f"{n:.1f} {unit}"
        n /= 1024
    return f"{n:.1f} Go"


print(f"    total stocké : {human(total)}")
print()
for key, size in by_dir.most_common(12):
    share = 100.0 * size / total if total else 0
    bar = "#" * int(round(share / 4))
    print(f"    {human(size):>10}  {share:5.1f}%  {key:<28} {bar}")

print()
print(f"    {len(by_entry)} fichiers dans l'APK")

# Détail des plus gros fichiers : le « qui pèse quoi » concret.
print()
print(f"    {top_n} plus gros fichiers :")
for size, name, stored in sorted(by_entry, reverse=True)[:top_n]:
    print(f"    {human(size):>10}  {name}")

if split:
    print()
    print("    fichiers par paquet Dart (assets/flutter_assets) :")
    # Les bibliothèques .so de Flutter sont dans lib/<abi>/ ; les paquets Dart
    # n'y figurent pas séparément : ce sont les assets et le snapshot AOT.
    files = [(n, s) for s, n, _ in by_entry
             if n.startswith("lib/") or n.endswith(".dex")]
    for name, size in sorted(files, key=lambda x: -x[1])[:20]:
        print(f"    {human(size):>10}  {name}")
PY

# ---------------------------------------------------------------------------
# Taille sur le téléphone
# ---------------------------------------------------------------------------

if [ "$USE_DEVICE" != "1" ]; then
  printf '\n'
  log "partie téléphone ignorée (--no-device)"
  exit 0
fi

ADB_BIN=""
adb_version() {
  local bin="$1"
  "$bin" version 2>/dev/null |
    sed -n 's/.*Version \([0-9][0-9]*\)\..*/\1/p' | head -n 1
}
ADB_MAJOR=-1
for candidate in "$(command -v adb 2>/dev/null || true)" \
  "$HOME/Android/Sdk/platform-tools/adb" \
  "$HOME/android-sdk/platform-tools/adb" \
  "$HOME/platform-tools/adb" \
  "${ANDROID_HOME:-}/platform-tools/adb" \
  "${ANDROID_SDK_ROOT:-}/platform-tools/adb"; do
  [ -n "$candidate" ] && [ -x "$candidate" ] || continue
  version="$(adb_version "$candidate")"
  [ -n "$version" ] || version=0
  if [ "$version" -gt "$ADB_MAJOR" ]; then
    ADB_MAJOR="$version"
    ADB_BIN="$candidate"
  fi
done

printf '\n'
if [ -z "$ADB_BIN" ]; then
  warn "adb introuvable : pas de mesure côté téléphone"
  printf '    %s\n' "lancer l'app installée : Settings → Applications → CQCM"
  exit 0
fi

ADB=("$ADB_BIN")
[ -n "$DEVICE" ] && ADB+=("-s" "$DEVICE")

STATE="$("${ADB[@]}" get-state 2>/dev/null || true)"
if [ "$STATE" != "device" ]; then
  warn "téléphone non accessible (état : ${STATE:-aucun})"
  printf '    %s\n' "brancher/autoriser l appareil, ou --no-device"
  exit 0
fi

if ! "${ADB[@]}" shell pm path "$PKG" >/dev/null 2>&1; then
  warn "$PKG n'est pas installé sur cet appareil"
  exit 0
fi

CODE_PATH="$("${ADB[@]}" shell pm path "$PKG" 2>/dev/null | tr -d '\r' |
  sed -n 's/^package://p' | head -n 1)"
VERSION_NAME="$("${ADB[@]}" shell dumpsys package "$PKG" 2>/dev/null |
  tr -d '\r' | sed -n 's/.*versionName=\([^ ]*\).*/\1/p' | head -n 1)"

log "sur le téléphone"
printf '    %s\n' "version installée : ${VERSION_NAME:-inconnue}"
printf '    %s\n' "APK installé      : $CODE_PATH"

if [ -n "$CODE_PATH" ]; then
  DIR_APK="$(dirname "$CODE_PATH")"
  # Souvent refusé (permissions), donc sans conséquence en cas d'échec.
  DU="$("${ADB[@]}" shell "du -sk '$DIR_APK' 2>/dev/null" 2>/dev/null |
    tr -d '\r' | head -n 1 || true)"
  KB="$(printf '%s' "$DU" | awk '{print $1}')"
  if [ -n "$KB" ] && [ "$KB" -gt 0 ] 2>/dev/null; then
    printf '    %s\n' "occupation de l'APK installé : $(human $((KB * 1024)))"
  fi
fi

# dumpsys diskstats donne, par paquet, taille du code, des données et du cache.
DISK="$("${ADB[@]}" shell dumpsys diskstats 2>/dev/null | tr -d '\r' || true)"
if [ -n "$DISK" ]; then
  PARSED="$(printf '%s\n' "$DISK" | python3 -c "
import re, sys

pkg = sys.argv[1]
text = sys.stdin.read()
human = lambda n: (f'{n} o' if n < 1024 else
                   f'{n / 1024:.1f} Ko' if n < 1024 ** 2 else
                   f'{n / 1024 ** 2:.1f} Mo' if n < 1024 ** 3 else
                   f'{n / 1024 ** 3:.2f} Go')

# Format 1 (Android 8-12) : blocs « Pkg Name: … » avec Pkg_size / Data_size /
# Cache_size.
block = re.search(
    r'Pkg Name:\s*' + re.escape(pkg) + r'\b(.*?)(?=\n\s*Pkg Name:|\Z)',
    text, re.S)
if block:
    values = dict(re.findall(r'(\w+)=(\d+)', block.group(1)))
    code = int(values.get('Pkg_size', 0))
    data = int(values.get('Data_size', 0))
    cache = int(values.get('Cache_size', 0))
    if code or data or cache:
        print(f'    code (APK + compilation) : {human(code)} ({code} o)')
        print(f'    données de l\\'application : {human(data)} ({data} o)')
        print(f'    cache                     : {human(cache)} ({cache} o)')
        print(f'    total installé            : {human(code + data + cache)}')
        sys.exit(0)

# Format 2 (Android 13+) : lignes « App Sizes: [..] » alignées par index.
def parse_list(name):
    m = re.search(r'^\\s*' + name + r':\\s*\\[(.*?)\\]', text, re.S | re.M)
    if not m:
        return []
    return [int(x) for x in re.findall(r'\\d+', m.group(1))]

names = re.search(r'^\\s*Package Names:\\s*\\[(.*?)\\]', text, re.S | re.M)
if names:
    packages = re.findall(r'\"([^\"]+)\"', names.group(1))
    code_list = parse_list('App Sizes')
    data_list = parse_list('App Data Sizes')
    cache_list = parse_list('Cache Sizes')
    if pkg in packages:
        i = packages.index(pkg)
        code = code_list[i] if i < len(code_list) else 0
        data = data_list[i] if i < len(data_list) else 0
        cache = cache_list[i] if i < len(cache_list) else 0
        print(f'    code (APK + compilation) : {human(code)} ({code} o)')
        print(f'    données de l\\'application : {human(data)} ({data} o)')
        print(f'    cache                     : {human(cache)} ({cache} o)')
        print(f'    total installé            : {human(code + data + cache)}')
        sys.exit(0)

print('    (dumpsys diskstats ne détaille pas ce paquet sur cet appareil)')
" "$PKG" || true)"
  if [ -n "$PARSED" ]; then
    printf '%s\n' "$PARSED"
  fi
else
  warn "dumpsys diskstats indisponible"
fi

printf '\n'
log "répartition fine du code Dart : reconstruire avec"
printf '    tools/build-apk.sh --abi arm64 --analyze-size\n'
printf '    (rapport JSON dans ~/.flutter-devtools/ + commande DevTools)\n'
