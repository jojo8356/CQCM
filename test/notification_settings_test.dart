import 'dart:io';

import 'package:cqcm/models/notification_settings.dart';
import 'package:cqcm/services/notification_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('cqcm-notif-test-');
  });

  tearDown(() async {
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  });

  File overrideFile() =>
      File('${directory.path}/${NotificationSettingsStore.overrideFileName}');

  group('valeurs par defaut', () {
    test('viennent de assets/data/notifications.json', () async {
      final bundle = await NotificationSettingsStore.load(
        directoryPath: directory.path,
      );

      expect(bundle.settings.enabled, isTrue);
      expect(bundle.settings.hour, 9);
      expect(bundle.settings.minute, 0);
      expect(bundle.settings.timezone, 'Europe/Paris');
      expect(bundle.settings.exact, isFalse);
      expect(bundle.settings.maxNotifications, 8);
      expect(bundle.settings.channelId, 'cqcm-revision');
      expect(bundle.settings.timeLabel, '09:00');
      expect(bundle.hasOverride, isFalse);
      expect(bundle.overrideJson, isNull);
      expect(bundle.defaultsJson, contains('"titleTemplate"'));
      expect(bundle.effectiveJson, contains('"enabled": true'));
    });

    test('sans fichier, les valeurs codees servent de repli', () {
      final settings = NotificationSettings.fromJson(null);

      expect(settings.enabled, isTrue);
      expect(settings.hour, 9);
      expect(settings.maxNotifications, 8);
      expect(settings.titleTemplate, contains('{count}'));
    });
  });

  group('surcharge locale', () {
    test('fusion partielle au-dessus des defauts', () async {
      await overrideFile().writeAsString(
        '{"hour": 18, "minute": 30, "timezone": "Europe/Berlin"}',
      );

      final bundle = await NotificationSettingsStore.load(
        directoryPath: directory.path,
      );

      expect(bundle.hasOverride, isTrue);
      expect(bundle.overrideJson, contains('Europe/Berlin'));
      expect(bundle.settings.hour, 18);
      expect(bundle.settings.minute, 30);
      expect(bundle.settings.timeLabel, '18:30');
      expect(bundle.settings.timezone, 'Europe/Berlin');
      // Clés absentes : les defauts embarqués restent appliqués.
      expect(bundle.settings.enabled, isTrue);
      expect(bundle.settings.maxNotifications, 8);
      expect(bundle.settings.channelId, 'cqcm-revision');
      expect(bundle.settings.titleTemplate, contains('{count}'));
    });

    test('bornes appliquees aux valeurs aberrantes', () async {
      await overrideFile().writeAsString(
        '{"hour": 99, "minute": -4, "maxNotifications": 500}',
      );

      final bundle = await NotificationSettingsStore.load(
        directoryPath: directory.path,
      );

      expect(bundle.settings.hour, 23);
      expect(bundle.settings.minute, 0);
      expect(bundle.settings.maxNotifications, 32);
    });

    test('JSON invalide ignore, defauts conserves', () async {
      await overrideFile().writeAsString('{ hour: 18');

      final bundle = await NotificationSettingsStore.load(
        directoryPath: directory.path,
      );

      expect(bundle.settings.hour, 9);
      expect(bundle.settings.enabled, isTrue);
    });

    test('un JSON non objet est ignore', () async {
      await overrideFile().writeAsString('[1, 2, 3]');

      final bundle = await NotificationSettingsStore.load(
        directoryPath: directory.path,
      );

      expect(bundle.settings.hour, 9);
    });
  });

  group('ensureOverrideFile', () {
    test('ecrit les defauts une seule fois', () async {
      final path = await NotificationSettingsStore.ensureOverrideFile(
        directoryPath: directory.path,
      );

      expect(path, isNotNull);
      expect(path, endsWith('notifications.json'));
      expect(await overrideFile().exists(), isTrue);
      expect(await overrideFile().readAsString(), contains('"hour": 9'));

      // L utilisateur modifie le fichier : il ne doit pas etre ecrase.
      await overrideFile().writeAsString('{"hour": 7}');
      await NotificationSettingsStore.ensureOverrideFile(
        directoryPath: directory.path,
      );

      expect(await overrideFile().readAsString(), '{"hour": 7}');
    });

    test('la surcharge ecrite est relue au chargement suivant', () async {
      await NotificationSettingsStore.ensureOverrideFile(
        directoryPath: directory.path,
      );
      await overrideFile().writeAsString('{"enabled": false, "hour": 7}');

      final bundle = await NotificationSettingsStore.load(
        directoryPath: directory.path,
      );

      expect(bundle.settings.enabled, isFalse);
      expect(bundle.settings.hour, 7);
      expect(bundle.settings.minute, 0);
    });
  });

  group('NotificationSettings', () {
    test('copyWith ne touche que les cles visees', () {
      const settings = NotificationSettings();
      final updated = settings.copyWith(
        hour: 6,
        minute: 45,
        exact: true,
        maxNotifications: 3,
      );

      expect(updated.hour, 6);
      expect(updated.timeLabel, '06:45');
      expect(updated.exact, isTrue);
      expect(updated.maxNotifications, 3);
      expect(updated.channelId, settings.channelId);
      expect(updated.titleTemplate, settings.titleTemplate);
    });

    test('toJson puis fromJson conservent la configuration', () {
      const settings = NotificationSettings(
        enabled: false,
        hour: 21,
        minute: 5,
        timezone: 'Europe/Paris',
        exact: true,
        maxNotifications: 4,
        requestPermissionOnStart: false,
        channelId: 'canal',
        channelName: 'Canal',
        channelDescription: 'Description',
        titleTemplate: 'T {count}',
        bodyTemplate: 'B {prompt}',
      );

      final restored = NotificationSettings.fromJson(settings.toJson());

      expect(restored.enabled, isFalse);
      expect(restored.hour, 21);
      expect(restored.minute, 5);
      expect(restored.timezone, 'Europe/Paris');
      expect(restored.exact, isTrue);
      expect(restored.maxNotifications, 4);
      expect(restored.requestPermissionOnStart, isFalse);
      expect(restored.channelId, 'canal');
      expect(restored.titleTemplate, 'T {count}');
      expect(restored.bodyTemplate, 'B {prompt}');
    });

    test('un fuseau vide reste vide (fuseau de l appareil)', () {
      final settings = NotificationSettings.fromJson({'timezone': '   '});

      expect(settings.timezone, isEmpty);
    });
  });
}
