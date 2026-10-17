# Livrer CQCM sur Linux : .deb et AppImage

## 0. Prérequis : trouver Flutter

Le script cherche le SDK dans cet ordre, et le dit dans son message de build :

1. `CQCM_FLUTTER=/chemin/vers/flutter` (exécutable explicite) ;
2. `tools/flutter-linux.sh`, si `~/.cqcm/linux-deps/env.sh` existe (SDK épinglé
   plus en-têtes GTK extraits sans root) ;
3. **le SDK épinglé** de `.flutter-version`, cherché par
   `tools/flutter-pinned.sh` dans `~/flutter-<version>`, `~/flutter-<majeure.mineure>`,
   `~/.cqcm/flutter/<version>`, `/opt/flutter-<version>` ;
4. `flutter` du `PATH`.

Autrement dit, pas besoin de `PATH` : un clone dans `~/flutter-3.47` suffit
(c'est le dossier « sans le correctif », reconnu pour la version 3.47.5).
Si vraiment le `PATH` est préféré :

```bash
line='export PATH="$HOME/flutter-3.47/bin:$PATH"'
for rc in ~/.zshrc ~/.bashrc; do
  grep -qF 'flutter-3.47/bin' "$rc" 2>/dev/null || printf '%s\n' "$line" >> "$rc"
done
```

Puis ouvrir un nouveau terminal (`source ~/.zshrc` ou `source ~/.bashrc`
suffit dans celui-ci). À noter : `flutter` n'est qu'un script ; ce sont
`flutter build linux` et `flutter doctor` qui signalent les prérequis system
manquants (clang, cmake, ninja, pkg-config, GTK 3).

Deux formats, deux philosophies. Le `.deb` est **petit** parce qu'il déclare ses
dépendances ; l'AppImage est **autonome** parce qu'elle embarque tout ce qu'elle
peut. Un seul script produit les deux :

```bash
cd ~/Documents/Projets/CQCM
tools/package-linux.sh --all
```

Si Flutter n'est pas dans le `PATH` (cas normal), rien à faire : le SDK épinglé
est trouvé tout seul. Pour en imposer un :

```bash
CQCM_FLUTTER_SDK=~/flutter-3.47 tools/package-linux.sh --all
```

Sortie dans `build/packages/` :

```text
cqcm_1.0.0-1_amd64.deb          # paquet Debian/Ubuntu, ~15 Mo
CQCM-1.0.0-amd64.AppImage       # exécutable portable, ~25 Mo
```

## 1. Ce que chaque paquet contient

| Élément | .deb | AppImage |
| --- | --- | --- |
| Moteur Flutter (`libflutter_linux_gtk.so`) | embarqué | embarqué |
| Code AOT, assets, JSON | embarqué | embarqué |
| Icônes + entrée de menu | oui (hicolor 16→512) | oui |
| Bibliothèques GTK et leurs dépendances | **déclarées** (`Depends`) | embarquées |
| Moteur et plugins Flutter (`libflutter_linux_gtk.so`, `lib*_linux_plugin.so`) | embarqués | embarqués |
| glibc, libstdc++, libz, X11, pilotes graphiques | fournis par le système | **laissés au système** |

C'est exactement la demande « .deb optimisé juste pour les bibliothèques et
codes absents des dépôts Debian » : le paquet ne contient que ce que Debian ne
fournit pas, et nomme le reste dans son champ `Depends`.

La liste des bibliothèques jamais embarquées est celle de l'AppImage
(`AppImage/pkg2appimage`, fichier `excludelist`) : glibc, `libstdc++`,
`libgcc_s`, `libz`, `libX11`/`libxcb`, `libGL`/`libEGL`/`libdrm`/`libgbm`,
`libfontconfig`/`freetype`/`harfbuzz`, `libasound`, `libuuid`, `libexpat`…
Les embarquer rendrait l'AppImage plus fragile que la machine hôte.

## 2. Le .deb

```bash
tools/package-linux.sh --deb            # compile puis empaquette
sudo apt install ./build/packages/cqcm_1.0.0-1_amd64.deb
```

`apt install ./fichier.deb` installe aussi les dépendances manquantes, là où
`dpkg -i` s'arrête en laissant le paquet à moitié configuré. Si cela arrive
quand même : `sudo apt --fix-broken install` répare l'état.

Arborescence posée par le paquet :

```text
/usr/lib/cqcm/            bundle Flutter intact (cqcm, lib/, data/)
/usr/bin/cqcm             lien vers /usr/lib/cqcm/cqcm
/usr/share/applications/com.cqcm.cqcm.desktop
/usr/share/icons/hicolor/{16..512}/apps/com.cqcm.cqcm.png
/usr/share/doc/cqcm/      changelog.gz, changelog.Debian.gz, copyright
```

Le bundle est conservé tel quel parce que le binaire a un `RPATH` de `$ORIGIN/lib`
(`linux/CMakeLists.txt`) : il trouve ses données à côté de lui, pas dans un
chemin absolu.

### D'où viennent les `Depends`

Le script lit les `NEEDED` de l'exécutable et du moteur (`readelf -d`), écarte
ce que Flutter fournit déjà, puis cherche chaque bibliothèque sur la machine
(`ldconfig -p`) et son paquet Debian (`dpkg -S`, avec une table de noms en
repli). Il ajoute aussi la version minimale de glibc lue dans les symboles
`GLIBC_2.xx` :

```text
Depends: libc6 (>= 2.34), zlib1g, libgtk-3-0, libglib2.0-0, libx11-6, ...
```

Conséquence utile : un `.deb` construit sur Debian est installable sur Debian et
Ubuntu **plus récents**, pas plus anciens. Pour couvrir large, compiler sur la
plus vieille distribution visée (Debian 12, Ubuntu 22.04).

### Version, révision, architecture

Le script lit l'architecture réelle du binaire (`readelf -h`) et refuse
d'étiqueter un binaire ARM en `amd64` : un tel paquet s'installerait sans
erreur pour échouer au lancement. Il reconnaît aussi le nom de dossier produit
par Flutter 3.47 (`build/linux/x64/…`) comme l'ancien (`x86_64`), ainsi que
`arm64`/`aarch64`.


```bash
tools/package-linux.sh --deb --version 1.2.0 --revision 2
tools/package-linux.sh --deb --arches amd64
```

La version par défaut est celle de `pubspec.yaml` (`1.0.0+1` → `1.0.0`).
La compilation croisée n'est pas gérée : lancer le script sur une machine de
l'architecture visée (x86_64 pour `amd64`, ARM64 pour `arm64`).

### Comprimer plus vite

```bash
CQCM_COMPRESS=zstd tools/package-linux.sh --deb
```

`zstd` produit un `.deb` un peu plus gros mais s'installe plus vite (Debian 12+,
Ubuntu 21.10+). Par défaut : `xz`, lisible partout.

## 3. L'AppImage

```bash
tools/package-linux.sh --appimage
./build/packages/CQCM-1.0.0-amd64.AppImage
```

Pour l'intégrer au menu d'applications :

```bash
./build/packages/CQCM-1.0.0-amd64.AppImage --appimage-integrate
```

Le script fabrique une `AppDir` (`AppRun`, `.DirIcon`, `.desktop`), y copie le
bundle, puis embarque les bibliothèques non système en suivant les `NEEDED` sur
trois niveaux, et ajoute les greffons `gdk-pixbuf`/`gtk-3.0` s'ils existent.
`AppRun` place `lib/` en tête de `LD_LIBRARY_PATH`.

`appimagetool` est téléchargé automatiquement dans
`~/.cache/cqcm-tools/` (dépôt `AppImage/appimagetool`, version `continuous`).
Le nom du fichier suit l'architecture AppImage, pas celle de Debian :
`appimagetool-x86_64.AppImage` sur un PC `amd64`, `appimagetool-aarch64.AppImage`
sur un `arm64`. En cas d'échec, le script imprime l'URL et la réponse du
serveur au lieu d'un simple « indisponible ».
Il est lancé avec `APPIMAGE_EXTRACT_AND_RUN=1`, donc **FUSE n'est pas
nécessaire** pour construire.

Pour utiliser un binaire déjà présent :

```bash
APPIMAGETOOL=/usr/local/bin/appimagetool tools/package-linux.sh --appimage
```

### Ce que l'AppImage ne peut pas résoudre

Une AppImage compile contre la glibc de ta machine : elle démarre sur une
distribution au moins aussi récente. Le remède est le même que pour le `.deb` :
construire sur une distribution ancienne.

## 4. Sans recompiler

Les deux commandes réutilisent le bundle existant :

```bash
tools/package-linux.sh --all --no-build
```

Pratique pour retoucher un numéro de version ou comparer deux compressions.

## 5. Icônes

Aucune dépendance externe : `tools/lib/png_resize.py` redimensionne les PNG déjà
versionnés pour Android/iOS (8 bits, palette, RGB ou RGBA). Si le rendu ne
convient pas, remplacer `assets/icon/icon.png` par un carré 1024×1024 et les
tailles en découleront. `ImageMagick` n'est utilisé qu'en repli s'il est présent.

## 6. Dépannage

| Symptôme | Cause | Remède |
| --- | --- | --- |
| `dpkg: dependency problems` | paquet GTK absent | `sudo apt --fix-broken install` |
| `error while loading shared libraries` (AppImage) | bibliothèque non embarquée ni système | relancer le script en verbose, vérifier `excludelist` |
| `appimagetool indisponible` | téléchargement bloqué | lire le message : le script affiche l'URL et l'erreur ; `java`-free : `APPIMAGETOOL=/chemin/appimagetool` |
| `FUSE` / `libfuse.so.2` | FUSE absent (conteneur) | `APPIMAGE_EXTRACT_AND_RUN=1`, ou `--appimage-extract` |
| L'icône du menu est vide | cache non rafraîchi | `sudo gtk-update-icon-cache -f /usr/share/icons/hicolor` |
| `appimagetool: command not found` | binaire absent | laissé à faire par le script, voir ci-dessus |
| `Le fichier donné … n'est pas compris sur la ligne de commande` | le chemin n'existe pas (mauvais numéro de version dans le nom) | `ls build/packages/` puis relancer avec le nom affiché, ou utiliser `--version` pour le maîtriser |
| L'app se ferme aussitôt | plantage natif ou fenêtre fermée | lancer `./build/linux/x64/release/bundle/cqcm` et lire l'erreur (§8) |
| `flutter : commande introuvable` | SDK hors `PATH` | `CQCM_FLUTTER_SDK=~/flutter-3.47 tools/package-linux.sh --all` (§0) |

Après installation, les journaux du lanceur :

```bash
journalctl --user -f | grep -i cqcm
```

## 7. Vérifier un paquet

```bash
dpkg-deb -I build/packages/*.deb      # métadonnées, Depends, taille installée
dpkg-deb -c build/packages/*.deb      # contenu
dpkg -x  build/packages/*.deb /tmp/x  # extraction sans installation
```

Pour l'AppImage :

```bash
./CQCM-*.AppImage --appimage-extract >/dev/null && ls squashfs-root
```

## 8. Mettre en production

Un `.deb` de production réunit trois choses : un bundle **release**, des
métadonnées justes, et une installation qui passe par `apt` (donc par la base
des paquets, pas une copie à la main).

### La séquence complète

La version vient de `pubspec.yaml`, numéro de build compris : avec
`version: 1.0.0+2`, le paquet s'appelle `cqcm_1.0.0+2-1_amd64.deb`. Incrémenter
le `+n` suffit donc à produire une version plus récente aux yeux d'`apt` — mais
il faut le faire **avant** de construire.

Tout en une commande, avec une version explicite (le paquet est construit puis
installé, `sudo` n'étant demandé qu'à la fin) :

```bash
tools/package-linux.sh --deb --strip --install --version 1.0.1
```

L'équivalent en trois temps :

```bash
tools/package-linux.sh --deb --strip --version 1.0.1
sudo apt install ./build/packages/cqcm_1.0.1-1_amd64.deb
dpkg -s cqcm | grep -E 'Status|Version|Depends'
```

Sans `--version`, le script reprend `pubspec.yaml` : le nom du fichier change
avec la version, il ne faut donc pas le recopier à la main d'une fois sur
l'autre. `ls build/packages/` donne le nom exact.

L'application apparaît alors dans le menu (entrée « CQCM ») et se lance aussi
par la commande `cqcm`. Le paquet est enregistré : `apt remove` le retire
proprement, `apt list --installed | grep cqcm` le montre comme n'importe quelle
application.

### Ce que change `--strip` (peu, en pratique)

Le bundle **release** de Flutter est déjà allégé : mesuré sur ce projet,
`--strip` retire 24 Ko sur 26,8 Mo installés. C'est une ceinture de sécurité,
pas une optimisation — elle ne produit un gain net que si le build a été fait
avec des informations de débogage (`--debug`, ou un profil de compilation
particulier).

Les 26,8 Mo se répartissent autrement :

| Élément | Poids installé approximatif |
| --- | --- |
| `libflutter_linux_gtk.so` (moteur Flutter) | ~20 Mo |
| `data/icudtl.dat` (données Unicode) | ~10 Mo selon version |
| `data/flutter_assets/` (code AOT, assets, JSON) | quelques Mo |
| `cqcm` (le runner) | ~100 Ko |

Le `.deb` de 7,9 Mo contient les mêmes fichiers **compressés** : c'est le
téléchargement, pas l'occupation disque.

Conserver les symboles aide à analyser un plantage natif avec `gdb` : sans eux,
une trace ne donne que des adresses.

### Ce que contrôle `lintian`

Installé par `sudo apt install lintian`, il vérifie la conformité Debian :
permissions, fichiers obligatoires, champs de contrôle, dépendances inutiles.
Les remarques les plus fréquentes et leur sens :

| Remarque | Sens |
| --- | --- |
| `maintainer-address-is-on-localhost` | renseigner `git config user.email` |
| `no-manual-page` | l'application n'a pas de page `man` (non bloquant) |
| `embedded-library` | une bibliothèque embarquée existe aussi en paquet Debian |
| `package-name-doesnt-match-sonames` | sans objet ici (application, pas bibliothèque) |

Le script utilise l'identité git du dépôt comme responsable (`Maintainer`) et
l'URL de `origin` comme `Homepage`. Pour forcer :

```bash
tools/package-linux.sh --deb --maintainer "Prénom Nom <vous@exemple.fr>" --lintian
```

### Mises à jour

Rebâtir avec un numéro plus élevé puis réinstaller :

```bash
tools/package-linux.sh --deb --strip --install --version 1.0.2
```

`apt` remplace l'ancienne version. **Les données sont conservées** : elles ne
sont pas dans le paquet mais dans le dossier personnel.

### Où vivent les données

```text
~/.local/share/com.cqcm.cqcm/cqcm-revision-data/
├── progress.json        progression de révision
├── notifications.json   surcharge des rappels
├── ui.json              zoom de l'interface
└── data.json            quiz importés
```

C'est le même dossier qu'avec `flutter run` (même identifiant d'application
`com.cqcm.cqcm`, `linux/CMakeLists.txt`), donc passer du lancement par Flutter à
l'application installée ne perd rien. Sauvegarde :

```bash
tar czf cqcm-donnees.tgz -C ~/.local/share/com.cqcm.cqcm cqcm-revision-data
```

Désinstallation en gardant les données (c'est le cas normal) :

```bash
sudo apt remove cqcm
```

### Distribuer à d'autres machines : le dépôt APT

`apt install ./fichier.deb` suffit pour une machine. Pour que d'autres fassent
`sudo apt install cqcm` et reçoivent les mises à jour, il faut un **dépôt
signé** — ce n'est pas fourni par le script, car cela demande une clé GPG et un
hébergement :

1. ranger les `.deb` dans un dossier servi en HTTP ;
2. générer l'index : `dpkg-scanpackages . /dev/null | gzip -9c > Packages.gz` ;
3. signer : `gpg --batch --yes --detach-sign -o InRelease Packages.gz` (ou
   `apt-ftparchive release .` pour le fichier `Release` complet) ;
4. côté client : `deb [signed-by=/chemin/cle.gpg] https://… stable main` dans
   `/etc/apt/sources.list.d/cqcm.list`.

Tant que ce dépôt n'existe pas, `apt update` ignore le paquet : la distribution
reste manuelle, fichier par fichier.

### L'application se ferme aussitôt

`Lost connection to device` dans `flutter run` signifie simplement que le
processus de l'application s'est arrêté — souvent parce que la fenêtre a été
fermée, parfois à cause d'un plantage. Pour trancher, lancer le binaire à la
main : ses messages d'erreur s'affichent alors en clair dans le terminal.

```bash
./build/linux/x64/release/bundle/cqcm
```

Si le message parle d'OpenGL, de Wayland ou de pilote, essayer successivement :

```bash
GDK_BACKEND=x11 ./build/linux/x64/release/bundle/cqcm
LIBGL_ALWAYS_SOFTWARE=1 ./build/linux/x64/release/bundle/cqcm
```

À noter : l'option `--no-enable-impeller` de `flutter run` **est ignorée sur
Linux** (elle ne concerne qu'Android et iOS) ; inutile de la chercher.

## 9. Ce qui n'est pas fait

- **Pas de dépôt APT** : le `.deb` s'installe à la main. Pour une distribution
  large, il faudrait signer un `Release`/`InRelease` et héberger `Packages`.
- **Pas de `.flatpak` / `.snap`** : formats différents (sandbox, runtimes),
  hors périmètre de ces deux commandes.
- **Pas de compilation croisée** : un paquet par architecture, sur sa machine.
- **Pas de signature GPG** des `.deb` : `dpkg -i` fonctionne, `apt` sans dépôt
  signé refuserait.
