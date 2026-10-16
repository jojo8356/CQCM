import '../models/revision_progress.dart';

String? defaultRevisionDataDirectory() => null;

Future<String?> resolveRevisionDataDirectory(String? directoryPath) async {
  return directoryPath;
}

Future<String?> revisionProgressFilePath(String? directoryPath) async {
  return null;
}

/// Plateformes sans `dart:io` : la progression reste en mémoire pour la
/// session en cours.
Future<Map<String, RevisionProgress>> loadRevisionProgress({
  String? directoryPath,
}) async {
  return Map<String, RevisionProgress>.from(_memoryStore);
}

Future<void> saveRevisionProgress(
  Map<String, RevisionProgress> progress, {
  String? directoryPath,
}) async {
  _memoryStore = Map<String, RevisionProgress>.from(progress);
}

Map<String, RevisionProgress> _memoryStore = {};
