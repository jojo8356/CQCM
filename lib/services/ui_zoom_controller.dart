import 'package:flutter/foundation.dart';

/// Niveau de zoom de l'interface, réglé par pas de 5 %.
///
/// Le zoom porte sur toute la fenêtre (textes, boutons, marges) et la mise en
/// page se réorganise, comme le zoom d'un navigateur : quand on agrandit, les
/// écrans disposent virtuellement de moins de place et refluent.
///
/// Les raccourcis sont installés par `UiZoomScope` :
///
/// * Ctrl + `+` (ou Ctrl + `=`, ou Ctrl + pavé `+`) : agrandir ;
/// * Ctrl + `-` (ou Ctrl + pavé `-`) : réduire ;
/// * Ctrl + `0` : revenir à 100 % ;
/// * Ctrl + molette : un cran par seuil de défilement.
class UiZoomController extends ChangeNotifier {
  UiZoomController({double zoom = 1.0}) : _zoom = _normalize(zoom);

  /// Pas d'un cran : 5 %.
  static const int stepPercent = 5;

  /// Bornes : 50 % (tout voir) et 200 % (lisibilité maximale).
  static const int minPercent = 50;
  static const int maxPercent = 200;

  double _zoom;

  /// Facteur appliqué (1.0 = taille normale).
  double get zoom => _zoom;

  /// Pourcentage entier, tel qu'on l'affiche (« 105 »).
  int get percent => (_zoom * 100).round();

  bool get canZoomIn => percent < maxPercent;

  bool get canZoomOut => percent > minPercent;

  /// Agrandit d'un cran, sans dépasser [maxPercent].
  void zoomIn() => _setPercent(percent + stepPercent);

  /// Réduit d'un cran, sans descendre sous [minPercent].
  void zoomOut() => _setPercent(percent - stepPercent);

  /// Revient à 100 %.
  void reset() => _setPercent(100);

  /// Applique un facteur quelconque, borné et arrondi au pour cent.
  void setZoom(double zoom) => _setPercent((zoom * 100).round());

  void _setPercent(int percent) {
    final bounded = percent.clamp(minPercent, maxPercent);
    // Passer par les pourcentages entiers évite d'accumuler les erreurs de
    // flottants : 1.05 + 0.05 ne vaut pas exactement 1.10.
    final next = bounded / 100;
    if (next == _zoom) {
      return;
    }
    _zoom = next;
    notifyListeners();
  }

  static double _normalize(double zoom) =>
      (zoom * 100).round().clamp(minPercent, maxPercent) / 100;
}
