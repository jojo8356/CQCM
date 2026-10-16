import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../models/revision_progress.dart';

/// Dossier résolu, gardé en **valeur** (jamais un `Future`) : un `Future`
/// mémorisé dans un contexte puis attendu dans un autre ne se termine plus
/// (cas typique des tests de widgets, où chaque test a sa propre zone).
String? _resolvedDefaultDirectory;
bool _defaultDirectoryResolved = false;

/// Dossier de données de révision. Surchargeable par la variable
/// d'environnement `CQCM_REVISION_DIR` (desktop, CLI, tests).
String? defaultRevisionDataDirectory() {
  final configured = Platform.environment['CQCM_REVISION_DIR'];
  if (configured == null || configured.trim().isEmpty) {
    return null;
  }
  return configured;
}

Future<String?> resolveRevisionDataDirectory(String? directoryPath) async {
  if (directoryPath != null && directoryPath.trim().isNotEmpty) {
    return directoryPath;
  }

  final configured = defaultRevisionDataDirectory();
  if (configured != null) {
    return configured;
  }

  if (_defaultDirectoryResolved) {
    return _resolvedDefaultDirectory;
  }

  final resolved = await _resolveDefaultDirectory();
  if (resolved != null) {
    _resolvedDefaultDirectory = resolved;
    _defaultDirectoryResolved = true;
  }
  return resolved;
}

Future<String?> _resolveDefaultDirectory() async {
  try {
    final supportDirectory = await getApplicationSupportDirectory().timeout(
      const Duration(milliseconds: 500),
    );
    return '${supportDirectory.path}/cqcm-revision-data';
  } on MissingPluginException {
    // Plugin absent (tests, plateforme sans stockage) : réponse définitive,
    // la progression reste en mémoire pour la session en cours.
    _resolvedDefaultDirectory = null;
    _defaultDirectoryResolved = true;
    return null;
  } on TimeoutException {
    // Réponse indéterminée : on retentera au prochain appel.
    return null;
  } catch (_) {
    return null;
  }
}

Future<String?> revisionProgressFilePath(String? directoryPath) async {
  final directory = await resolveRevisionDataDirectory(directoryPath);
  if (directory == null || directory.trim().isEmpty) {
    return null;
  }
  return '$directory/progress.json';
}

/// Chemin d'un fichier du dossier de données de révision (null si aucun
/// dossier n'est disponible).
Future<String?> revisionDataFilePath(
  String fileName, {
  String? directoryPath,
}) async {
  final directory = await resolveRevisionDataDirectory(directoryPath);
  if (directory == null || directory.trim().isEmpty) {
    return null;
  }
  return '$directory/$fileName';
}

/// Lit un fichier JSON du dossier de données (surcharge de configuration).
Future<String?> readRevisionDataFile(
  String fileName, {
  String? directoryPath,
}) async {
  final path = await revisionDataFilePath(fileName, directoryPath: directoryPath);
  if (path == null) {
    return null;
  }
  final file = File(path);
  if (!await file.exists()) {
    return null;
  }
  try {
    return await file.readAsString();
  } catch (_) {
    return null;
  }
}

/// Écrit un fichier JSON dans le dossier de données (sans écraser un fichier
/// existant quand [overwrite] vaut false).
Future<bool> writeRevisionDataFile(
  String fileName,
  String contents, {
  String? directoryPath,
  bool overwrite = true,
}) async {
  final path = await revisionDataFilePath(fileName, directoryPath: directoryPath);
  if (path == null) {
    return false;
  }
  final file = File(path);
  if (!overwrite && await file.exists()) {
    return false;
  }
  try {
    await file.parent.create(recursive: true);
    await file.writeAsString(contents);
    return true;
  } catch (_) {
    return false;
  }
}

Future<Map<String, RevisionProgress>> loadRevisionProgress({
  String? directoryPath,
}) async {
  final path = await revisionProgressFilePath(directoryPath);
  if (path == null) {
    return {};
  }

  final file = File(path);
  if (!await file.exists()) {
    return {};
  }

  try {
    final decoded = json.decode(await file.readAsString());
    if (decoded is! Map<String, dynamic>) {
      return {};
    }
    final entries = decoded['progress'];
    if (entries is! List) {
      return {};
    }

    final result = <String, RevisionProgress>{};
    for (final entry in entries) {
      if (entry is! Map<String, dynamic>) {
        continue;
      }
      final progress = RevisionProgress.fromJson(entry);
      result[progress.itemId] = progress;
    }
    return result;
  } catch (_) {
    // Fichier illisible ou corrompu : on repart d'un historique vide.
    return {};
  }
}

Future<void> saveRevisionProgress(
  Map<String, RevisionProgress> progress, {
  String? directoryPath,
}) async {
  final path = await revisionProgressFilePath(directoryPath);
  if (path == null) {
    return;
  }

  final file = File(path);
  await file.parent.create(recursive: true);
  await file.writeAsString(
    '${const JsonEncoder.withIndent('  ').convert({
      'version': 1,
      'updatedAt': DateTime.now().toIso8601String(),
      'progress': progress.values
          .map((entry) => entry.toJson())
          .toList(),
    })}\n',
  );
}
