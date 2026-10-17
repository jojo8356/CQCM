# Zoom de l'interface

Ctrl + `+` agrandit l'écran de 5 %, Ctrl + `-` le réduit de 5 %, Ctrl + `0`
revient à 100 %. La molette de la souris fait la même chose quand Ctrl est
enfoncé : un cran de molette, un cran de zoom.

## Raccourcis

| Raccourci | Effet |
| --- | --- |
| `Ctrl` + `+` | agrandir de 5 %, jusqu'à 200 % |
| `Ctrl` + `-` | réduire de 5 %, jusqu'à 50 % |
| `Ctrl` + `0` | revenir à 100 % |
| `Ctrl` + molette vers le haut | agrandir |
| `Ctrl` + molette vers le bas | réduire |

Selon le clavier, `+` est `Ctrl` + `=` (QWERTY) ou la touche `+` seule
(AZERTY) : les deux formes sont reconnues, ainsi que le pavé numérique.

Sans Ctrl, les touches et la molette gardent leur rôle habituel : la molette
fait défiler les listes, `+` et `-` ne font rien.

## Ce que le zoom change vraiment

Le zoom ne se contente pas d'agrandir l'image : la mise en page se
réorganise, comme dans un navigateur.

- agrandir → les écrans disposent virtuellement de moins de place, les textes
  occupent une part plus grande, les colonnes se resserrent ;
- réduire → plus de contenu tient à l'écran.

C'est obtenu en donnant aux écrans une taille virtuelle (fenêtre ÷ zoom) puis
en agrandissant le rendu à la taille réelle (`FittedBox`). Un simple
`Transform` aurait laissé la mise en page inchangée : le texte serait devenu
flou et les boutons auraient débordé de la fenêtre.

## Mémorisation du réglage

Le niveau est conservé d'un lancement à l'autre dans
`<dossier de données>/ui.json`, à côté de `progress.json` et de
`notifications.json` — donc surchargeable par `CQCM_REVISION_DIR` :

```json
{
  "zoom": 1.05
}
```

Fichier absent ou illisible : l'application repart à 100 %, sans message. Un
réglage d'affichage ne doit jamais empêcher le démarrage.

## Où c'est dans le code

| Fichier | Rôle |
| --- | --- |
| `lib/services/ui_zoom_controller.dart` | niveau courant, pas de 5 %, bornes 50–200 % |
| `lib/services/ui_zoom_store.dart` | lecture/écriture de `ui.json` |
| `lib/widgets/ui_zoom_scope.dart` | raccourcis clavier, molette, mise en page |
| `lib/main.dart` | branchement dans `MaterialApp.builder` |

`UiZoomScope` est placé dans `MaterialApp.builder`, au-dessus du `Navigator` :
le zoom vaut donc pour le menu **et** pour tous les écrans empilés, sans avoir
à répéter quoi que ce soit dans chaque écran.

## Utilisation programmatique

```dart
final controller = UiZoomController(); // 100 %
controller.zoomIn(); // 105 %
controller.zoomOut(); // 100 %
controller.setZoom(1.5); // 150 %

// Réagir aux changements (ChangeNotifier) :
controller.addListener(() => print('${controller.percent} %'));
```

Dans un test, injecter un contrôleur évite d'écrire un fichier :

```dart
await tester.pumpWidget(MaterialApp(
  builder: (context, child) => UiZoomScope(
    controller: controller,
    persist: false,
    child: child,
  ),
  home: const MonEcran(),
));
```

## Limites connues

- **Au-dessus d'une liste** : Flutter transmet la molette à la fois au zoom et
  à la liste, qui peut donc défiler d'un cran en même temps qu'elle zoome.
  Le zoom fonctionne dans tous les cas.
- **Bornes** : 50 % à 200 %. En dessous, la mise en page devient illisible ;
  au-delà, les écrans de téléphone (360 dp) n'ont plus assez de place.
- **Téléphone** : sans clavier ni molette, le zoom reste à 100 %. Rien ne
  change pour le mode tactile.
- **Partage d'écran** : agrandir ne change pas la taille de la fenêtre, donc
  une capture d'écran contient le même nombre de pixels, avec un contenu plus
  grand.
