/// Résumé lisible de `flutter test`.
///
/// `flutter test` affiche les avertissements et les erreurs attendues (par
/// exemple le plugin de notifications, absent dans les tests) même quand tout
/// passe. Ce script relance la suite avec le rapport JSON de `package:test` et
/// n'affiche qu'une ligne par fichier :
///
/// * `OK` : tous les tests passent, sans le moindre message ;
/// * `OK (warning)` : tous les tests passent, des messages connus ont été
///   écrits (ils sont résumés, pas affichés) ;
/// * `OK (error)` : tous les tests passent, des erreurs attendues ont été
///   signalées puis traitées par le test ;
/// * `KO` : un échec — dans ce cas seulement, le détail est affiché.
///
/// Exemples :
///
/// ```bash
/// dart run bin/test_summary.dart                  # toute la suite
/// dart run bin/test_summary.dart test/app_flow_test.dart
/// dart run bin/test_summary.dart --details        # messages et erreurs connus
/// ```
library;

import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  final details = args.contains('--details') || args.contains('-d');
  final patterns = args
      .where((argument) => !argument.startsWith('-'))
      .toList(growable: false);

  final executable = Platform.isWindows ? 'flutter.bat' : 'flutter';
  final Process process;
  try {
    process = await Process.start(
      executable,
      ['test', '--reporter', 'json', ...patterns],
      runInShell: Platform.isWindows,
    );
  } on ProcessException catch (error) {
    stderr.writeln('Impossible de lancer « $executable test » : $error');
    exitCode = 2;
    return;
  }

  final report = _Report();
  final raw = <String>[];

  final stdoutSubscription = process.stdout
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen((line) => report.handle(line, raw));
  final stderrSubscription = process.stderr
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen(raw.add);

  final exitCode = await process.exitCode;
  await stdoutSubscription.cancel();
  await stderrSubscription.cancel();

  if (!report.hasData) {
    stdout.writeln(raw.join('\n'));
    stderr.writeln('Aucun rapport JSON reçu de « flutter test ».');
    exit(exitCode == 0 ? 1 : exitCode);
  }

  report.printSummary(details: details, raw: raw);
  exit(exitCode == 0 ? 0 : 1);
}

enum _Status {
  ok('OK'),
  warning('OK (warning)'),
  error('OK (error)'),
  failed('KO');

  const _Status(this.label);

  final String label;

  int get order {
    switch (this) {
      case _Status.failed:
        return 0;
      case _Status.error:
        return 1;
      case _Status.warning:
        return 2;
      case _Status.ok:
        return 3;
    }
  }
}

class _FileReport {
  _FileReport(this.path);

  final String path;

  int tests = 0;
  int skipped = 0;
  int failures = 0;
  int warnings = 0;
  int errors = 0;
  final List<String> details = [];

  _Status get status {
    if (failures > 0) return _Status.failed;
    if (errors > 0) return _Status.error;
    if (warnings > 0) return _Status.warning;
    return _Status.ok;
  }

  String get counts {
    final parts = <String>['$tests test(s)'];
    if (skipped > 0) parts.add('$skipped ignoré(s)');
    if (failures > 0) parts.add('$failures échec(s)');
    if (errors > 0) parts.add('$errors erreur(s) connue(s)');
    if (warnings > 0) parts.add('$warnings message(s) ignoré(s)');
    return parts.join(' · ');
  }
}

class _Report {
  final Map<int, String> _suitePaths = {};
  final Map<int, _FileReport> _files = {};
  final Map<int, _FileReport> _testFile = {};
  final Map<int, String> _testNames = {};
  final List<String> _failureDetails = [];

  bool hasData = false;

  void handle(String line, List<String> raw) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) return;

    final Map<String, dynamic> event;
    try {
      final decoded = json.decode(trimmed);
      if (decoded is! Map<String, dynamic> || decoded['type'] is! String) {
        raw.add(line);
        return;
      }
      event = decoded;
    } catch (_) {
      raw.add(line);
      return;
    }

    hasData = true;

    final type = event['type'] as String;

    if (type == 'suite') {
      final suite = event['suite'] as Map<String, dynamic>?;
      final id = suite?['id'];
      final path = suite?['path'];
      if (id is int && path is String) {
        _suitePaths[id] = path;
      }
      return;
    }

    if (type == 'testStart') {
      final test = event['test'] as Map<String, dynamic>?;
      if (test == null) return;
      final id = test['id'];
      if (id is! int) return;

      final path =
          _suitePaths[test['suiteID']] ??
          _pathFromUrl(test['url']) ??
          'suite inconnue';
      _testFile[id] = _files.putIfAbsent(path, () => _FileReport(path));
      final name = test['name'];
      if (name is String) _testNames[id] = name;
      return;
    }

    if (type == 'print') {
      final file = _testFile[event['testID']];
      final message = event['message'];
      if (file == null || message is! String) return;
      file.warnings++;
      file.details.add('  · $message');
      return;
    }

    if (type == 'error') {
      final file = _testFile[event['testID']];
      if (file == null) return;
      final message = '${event['error'] ?? ''}'.trim();
      if (event['isFailure'] == true) {
        final name = _testNames[event['testID']] ?? 'test inconnu';
        _failureDetails.add('── Échec : ${file.path} · « $name »\n$message');
      } else {
        file.errors++;
        file.details.add('  · $message');
      }
      return;
    }

    if (type == 'testDone') {
      final file = _testFile[event['testID']];
      if (file == null || event['hidden'] == true) return;
      file.tests++;
      if (event['skipped'] == true) file.skipped++;
      final result = event['result'];
      if (result != null && result != 'success') {
        file.failures++;
      }
    }
  }

  static String? _pathFromUrl(Object? url) {
    if (url is! String || url.isEmpty) return null;
    final uri = Uri.tryParse(url);
    if (uri == null) return url;
    if (uri.scheme == 'file') return uri.toFilePath();
    return url;
  }

  void printSummary({required bool details, required List<String> raw}) {
    final files = _files.values.toList()
      ..sort((a, b) {
        final byStatus = a.status.order.compareTo(b.status.order);
        return byStatus != 0 ? byStatus : a.path.compareTo(b.path);
      });

    final labelWidth = files.fold<int>(
      0,
      (width, file) => file.status.label.length > width
          ? file.status.label.length
          : width,
    );
    final pathWidth = files.fold<int>(
      0,
      (width, file) => _relative(file.path).length > width
          ? _relative(file.path).length
          : width,
    );

    stdout.writeln('CQCM · résumé des tests');
    stdout.writeln('─' * 72);

    var passed = 0;
    var failed = 0;
    var testCount = 0;

    for (final file in files) {
      final status = file.status;
      testCount += file.tests;
      if (status == _Status.failed) {
        failed++;
      } else {
        passed++;
      }

      stdout.writeln(
        '${status.label.padRight(labelWidth)}  '
        '${_relative(file.path).padRight(pathWidth)}  '
        '${file.counts}',
      );
    }

    stdout.writeln('─' * 72);
    stdout.writeln(
      '${files.length} fichier(s) · $testCount test(s) · $passed OK · $failed KO',
    );
    stdout.writeln(
      'OK = tout passe · OK (warning) = messages connus · '
      'OK (error) = erreurs attendues · KO = à corriger',
    );

    for (final detail in _failureDetails) {
      stdout.writeln();
      stdout.writeln(detail);
    }

    if (details) {
      stdout.writeln();
      stdout.writeln('Messages et erreurs connus :');
      for (final file in files) {
        if (file.details.isEmpty) continue;
        stdout.writeln('  ${_relative(file.path)}');
        for (final line in file.details) {
          stdout.writeln(line);
        }
      }
    }

    if (raw.isNotEmpty && failed > 0) {
      stdout.writeln();
      stdout.writeln('Sortie brute de flutter test :');
      stdout.writeln(raw.join('\n'));
    }
  }

  static String _relative(String path) {
    final normalized = path.replaceAll('\\', '/');
    final index = normalized.lastIndexOf('/test/');
    if (index < 0) return normalized;
    return 'test/${normalized.substring(index + '/test/'.length)}';
  }
}
