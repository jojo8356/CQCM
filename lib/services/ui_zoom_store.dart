/// Mémorisation du zoom de l'interface, en JSON.
///
/// Fichier : `<dossier de données>/ui.json`, à côté de `progress.json` et de
/// `notifications.json`. Il est donc surchargeable par `CQCM_REVISION_DIR` et
/// lisible à la main :
///
/// ```json
/// {
///   "zoom": 1.1
/// }
/// ```
///
/// Fichier absent ou illisible : l'application repart à 100 %, sans message
/// d'erreur — un réglage d'affichage ne doit jamais empêcher le démarrage.
library;

import 'dart:convert';

import 'revision_store.dart';

class UiZoomStore {
  static const String fileName = 'ui.json';
  static const String zoomKey = 'zoom';

  /// Lit le zoom enregistré.
  ///
  /// Renvoie `null` si le fichier n'existe pas, n'est pas du JSON, ou ne
  /// contient pas un nombre sous la clé `zoom`.
  static Future<double?> loadZoom({String? directoryPath}) async {
    final raw = await readRevisionDataFile(
      fileName,
      directoryPath: directoryPath,
    );
    if (raw == null || raw.trim().isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        return null;
      }
      final value = decoded[zoomKey];
      if (value is! num) {
        return null;
      }
      return value.toDouble();
    } on FormatException {
      return null;
    }
  }

  /// Enregistre le zoom, arrondi à deux décimales pour rester lisible.
  static Future<bool> saveZoom(double zoom, {String? directoryPath}) {
    final data = <String, Object?>{
      zoomKey: double.parse(zoom.toStringAsFixed(2)),
    };
    final contents = '${const JsonEncoder.withIndent('  ').convert(data)}\n';
    return writeRevisionDataFile(
      fileName,
      contents,
      directoryPath: directoryPath,
    );
  }
}
