/// Chargement des réglages de rappels : tout passe par du JSON.
///
/// - `assets/data/notifications.json` : valeurs par défaut embarquées ;
/// - `<dossier de données>/notifications.json` : surcharge locale, écrite au
///   premier lancement si elle n'existe pas, puis relue à chaque démarrage.
///
/// Le fichier de surcharge est écrit dans le même dossier que
/// `progress.json`, donc surchargeable par `CQCM_REVISION_DIR`.
library;

import 'dart:convert';

import '../models/notification_settings.dart';
import 'asset_text.dart';
import 'revision_store.dart';

class NotificationSettingsBundle {
  /// Réglages effectifs (défauts + surcharge).
  final NotificationSettings settings;

  /// Contenu JSON des valeurs par défaut (affiché tel quel dans l'app).
  final String defaultsJson;

  /// Contenu JSON de la surcharge locale, si elle existe.
  final String? overrideJson;

  /// Chemin du fichier de surcharge (null si la plateforme n'a pas de
  /// stockage de fichier).
  final String? overridePath;

  const NotificationSettingsBundle({
    required this.settings,
    required this.defaultsJson,
    this.overrideJson,
    this.overridePath,
  });

  bool get hasOverride => overrideJson != null;

  /// Contenu JSON à afficher pour expliquer la configuration effective.
  String get effectiveJson =>
      '${const JsonEncoder.withIndent('  ').convert(settings.toJson())}\n';
}

class NotificationSettingsStore {
  static const String assetPath = 'assets/data/notifications.json';
  static const String overrideFileName = 'notifications.json';

  /// Lit les réglages (défauts embarqués + surcharge locale).
  static Future<NotificationSettingsBundle> load({
    String? directoryPath,
  }) async {
    final defaultsJson = await _loadDefaultsJson();
    final overrideJson = await readRevisionDataFile(
      overrideFileName,
      directoryPath: directoryPath,
    );
    final overridePath = await revisionDataFilePath(
      overrideFileName,
      directoryPath: directoryPath,
    );

    final defaultsMap = _decode(defaultsJson);
    Map<String, dynamic>? overrideMap;
    if (overrideJson != null) {
      overrideMap = _decode(overrideJson);
    }

    final settings = NotificationSettings.fromJson(
      overrideMap,
      fallback: NotificationSettings.fromJson(defaultsMap),
    );

    return NotificationSettingsBundle(
      settings: settings,
      defaultsJson: defaultsJson,
      overrideJson: overrideJson,
      overridePath: overridePath,
    );
  }

  /// Écrit le fichier de surcharge s'il n'existe pas encore, et renvoie son
  /// chemin. L'utilisateur peut ensuite le modifier sans rebuild.
  static Future<String?> ensureOverrideFile({String? directoryPath}) async {
    final path = await revisionDataFilePath(
      overrideFileName,
      directoryPath: directoryPath,
    );
    if (path == null) return null;

    await writeRevisionDataFile(
      overrideFileName,
      await _loadDefaultsJson(),
      directoryPath: directoryPath,
      overwrite: false,
    );
    return path;
  }

  static Future<String> _loadDefaultsJson() async {
    try {
      return await loadAssetText(assetPath);
    } catch (_) {
      // Asset absent : on retombe sur les valeurs codées par défaut.
      return '${const JsonEncoder.withIndent('  ').convert(
        const NotificationSettings().toJson(),
      )}\n';
    }
  }

  static Map<String, dynamic>? _decode(String? jsonString) {
    if (jsonString == null || jsonString.trim().isEmpty) return null;
    try {
      final decoded = json.decode(jsonString);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {
      // JSON invalide : on ignore la surcharge.
    }
    return null;
  }
}
