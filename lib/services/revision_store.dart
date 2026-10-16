/// Accès au stockage local de la progression de révision.
///
/// L'implémentation dépend de la plateforme : fichier JSON sur les
/// plateformes avec `dart:io`, mémoire volatile ailleurs (web).
library;

export 'revision_store_stub.dart'
    if (dart.library.io) 'revision_store_io.dart';
