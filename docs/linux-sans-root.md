# Flutter Linux desktop sans droits root

`flutter doctor` réclame les en-têtes GTK 3 :

```
[✗] Linux toolchain - develop for Linux desktop
    ✗ GTK 3.0 development libraries are required for Linux development.
      They are likely available from your distribution (e.g.: apt install libgtk-3-dev)
```

Sur une machine où l'on n'a pas `sudo`, l'installation système est impossible.
Ce document décrit la solution mise en place : **extraire les paquets `.deb`
dans un dossier personnel** et pointer `pkg-config`/CMake dessus. Rien n'est
écrit dans `/usr`.

## Mise en place

```bash
cd CQCM
tools/linux-desktop-deps.sh
```

Le script :

1. calcule la fermeture des dépendances de `libgtk-3-dev` (+ `liblzma-dev`)
   avec `apt-cache depends --recurse` ;
2. ignore ce qui est **déjà installé** sur le système (`dpkg -s`) ;
3. télécharge les `.deb` manquants avec `apt-get download` (aucun privilège
   requis, les fichiers vont dans le dossier courant) ;
4. les extrait avec `dpkg -x` dans `~/.cqcm/linux-deps/sysroot` ;
5. écrit `~/.cqcm/linux-deps/env.sh`, qui expose en-têtes, `.pc` et
   bibliothèques de développement.

Options :

| Option | Effet |
| --- | --- |
| `--all` | ajoute `pkg-config`, `ninja-build`, `cmake`, `clang` s'ils manquent |
| `--mesa-utils` | ajoute `eglinfo` (avertissement non bloquant de `flutter doctor`) |
| `--clean` | supprime le sysroot avant de recommencer |
| `--root DIR` | autre emplacement du sysroot |

## Utilisation

```bash
source ~/.cqcm/linux-deps/env.sh
flutter doctor          # « Linux toolchain » doit passer au vert
flutter run -d linux
```

Ou, en une commande, avec le wrapper fourni (il source l'environnement à votre
place et transmet tous les arguments à `flutter`) :

```bash
tools/flutter-linux.sh run -d linux
tools/flutter-linux.sh build linux --release
```

Pour rendre l'environnement permanent, dans `~/.bashrc` :

```bash
[ -f "$HOME/.cqcm/linux-deps/env.sh" ] && . "$HOME/.cqcm/linux-deps/env.sh"
```

## Variables exportées

| Variable | Rôle |
| --- | --- |
| `PKG_CONFIG_PATH` | fait trouver les `.pc` du sysroot en premier (dont `gtk+-3.0.pc`) |
| `CMAKE_PREFIX_PATH` | aide `find_package` de CMake |
| `CPATH`, `C_INCLUDE_PATH`, `CPLUS_INCLUDE_PATH` | en-têtes (`gtk/gtk.h`, `gdk/gdk.h`, …) |
| `LIBRARY_PATH` | édition de liens (`libgtk-3.so`, symlink fourni par les paquets `-dev`) |
| `LD_LIBRARY_PATH` | secours à l'exécution |
| `PATH` | binaires éventuellement extraits (`ninja`, `clang`, `eglinfo`) |
| `CQCM_LINUX_DEPS` | racine du sysroot (réutilisée par `tools/flutter-linux.sh`) |

## Comment ça marche

Les `.pc` extraits déclarent `libdir=/usr/lib/<arch>` : ces chemins absolus
désignent les bibliothèques d'exécution **déjà présentes** sur la machine. Seuls
les éléments fournis par les paquets `-dev` (en-têtes et symlinks `.so`) vivent
dans le sysroot ; ils sont trouvés grâce à `CPATH` et `LIBRARY_PATH`. Aucun
conflit de version n'est possible : les `.deb` récupérés sont ceux du dépôt de
la distribution installée.

## CMake 4

Rien à faire : les `CMakeLists.txt` concernés demandent `3.13`, `3.10` et
`3.13` (projet, `linux/flutter`, `linux/runner`), et `file_selector_linux`
déclare `3.10` avec `cmake_policy(VERSION 3.10...3.24)`. CMake 4 refuse la
compatibilité en dessous de 3.5 uniquement. Le plugin Linux des notifications
(`flutter_local_notifications_linux`) est **pur Dart** : aucun CMake.

## Limites et dépannage

- **« listes apt vides »** : `apt-get download` a besoin des index de paquets,
  qui ne sont rafraîchis que par `apt-get update` (root, une fois). Sans eux,
  aucun `.deb` ne peut être récupéré ; le script l'indique.
- **Espace disque** : environ 200 à 300 Mo pour `~/.cqcm/linux-deps` (les
  `.deb` restent en cache et sont réutilisés aux exécutions suivantes).
- **Nettoyage** : `rm -rf ~/.cqcm/linux-deps`, ou `--clean` pour tout reprendre.
- **Retour à la normale** : si `libgtk-3-dev` est installé un jour par
  l'administration, le script n'extrait plus rien et l'environnement devient
  inutile ; il peut alors être supprimé (ou gardé, il est inoffensif).
- **eglinfo** : l'avertissement `Unable to access driver information` n'empêche
  pas la compilation ; `--mesa-utils` fournit le binaire si besoin.
- **Recommandation** : pour les rappels de notifications réellement programmés,
  Android reste la cible la plus complète — voir `docs/notifications.md`.
