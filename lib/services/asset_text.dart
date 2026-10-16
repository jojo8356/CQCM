/// Lecture des fichiers embarqués, sans mise en cache du `Future`.
///
/// `AssetBundle.loadString` (et `loadStructuredData`) garde le `Future` de
/// chaque fichier dans un cache d'instance. Pratique en production, mais
/// risqué dès qu'un test précède : un `Future` créé puis terminé dans un
/// premier test ne peut plus réveiller l'`await` du test suivant, et le
/// chargement paraît alors ne jamais se terminer.
///
/// On lit donc les octets — `load` n'est pas mis en cache — et on décode le
/// texte à chaque appel. Les fichiers concernés font quelques kilo-octets.
library;

import 'dart:convert';

import 'package:flutter/services.dart';

/// Contenu texte d'un asset (`assets/data/...`).
Future<String> loadAssetText(String key) async {
  final bytes = await rootBundle.load(key);
  return utf8.decode(
    bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
  );
}
