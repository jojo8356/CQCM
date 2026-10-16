import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../models/revision_progress.dart';

Future<String?>? _cachedDefaultDirectory;

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

  _cachedDefaultDirectory ??= _resolveDefaultDirectory();
  return _cachedDefaultDirectory;
}

Future<String?> _resolveDefaultDirectory() async {
  try {
    final supportDirectory = await getApplicationSupportDirectory().timeout(
      const Duration(milliseconds: 500),
    );
    return '${supportDirectory.path}/cqcm-revision-data';
  } on MissingPluginException {
    return null;
  } on TimeoutException {
    return null;
  } catch (_) {
    // Plugin indisponible (tests, plateforme sans stockage persistant) :
    // la progression reste en mémoire pour la session en cours.
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
