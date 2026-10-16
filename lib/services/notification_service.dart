/// Rappels système : programme les notifications locales à partir du plan
/// JSON calculé pour le programme de révision.
///
/// Le plugin utilisé est `flutter_local_notifications` (voir
/// `docs/notifications.md` pour la configuration des plateformes). Tous les
/// appels sont protégés : si le plugin n'est pas disponible (plateforme non
/// gérée, permission refusée, test automatique), l'application continue de
/// fonctionner et l'erreur est exposée dans l'écran Rappels.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as timezone_data;
import 'package:timezone/timezone.dart' as tz;

import '../models/notification_settings.dart';
import '../models/revision.dart';
import 'notification_plan.dart';
import 'notification_settings_store.dart';
import 'revision_plan.dart';

/// Résultat d'une synchronisation, affiché dans l'écran Rappels.
class NotificationSyncResult {
  final NotificationSettingsBundle bundle;
  final NotificationPlan plan;
  final bool platformReady;
  final bool scheduled;
  final String? error;

  const NotificationSyncResult({
    required this.bundle,
    required this.plan,
    required this.platformReady,
    required this.scheduled,
    this.error,
  });

  String get summary {
    if (error != null) {
      return 'Rappels système indisponibles : $error';
    }
    if (!platformReady) {
      return 'Rappels système indisponibles sur cette plateforme.';
    }
    if (scheduled) return plan.status;
    return '${plan.status} (non programmés)';
  }
}

class ReminderNotifications {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static bool _initialized = false;
  static String? _lastError;
  static String? _lastPayload;

  static bool get isInitialized => _initialized;

  static String? get lastError => _lastError;

  /// Charge utile JSON de la dernière notification touchée.
  static String? get lastPayload => _lastPayload;

  /// Plateformes sur lesquelles le plugin sait afficher une notification.
  static bool get isSupportedPlatform {
    if (kIsWeb) return false;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
      case TargetPlatform.linux:
      case TargetPlatform.windows:
        return true;
      case TargetPlatform.fuchsia:
        return false;
    }
  }

  /// Linux ne fournit pas d'API de planification : seuls les affichages
  /// immédiats y sont possibles.
  static bool get supportsScheduling {
    if (!isSupportedPlatform) return false;
    return defaultTargetPlatform != TargetPlatform.linux;
  }

  /// Initialise le plugin et, si demandé, l'autorisation d'affichage.
  static Future<bool> initialize({
    NotificationSettings? settings,
    bool requestPermission = false,
  }) async {
    if (!isSupportedPlatform) {
      _lastError = 'rappels non gérés sur cette plateforme';
      _initialized = false;
      return false;
    }

    try {
      _configureTimeZone(settings?.timezone ?? '');

      final initializationSettings = InitializationSettings(
        // Icone dediee (drawable) : Android recommande de ne pas utiliser
        // l'icone de lancement pour les notifications.
        android: const AndroidInitializationSettings('cqcm_notification'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: requestPermission,
          requestBadgePermission: requestPermission,
          requestSoundPermission: requestPermission,
        ),
        macOS: DarwinInitializationSettings(
          requestAlertPermission: requestPermission,
          requestBadgePermission: requestPermission,
          requestSoundPermission: requestPermission,
        ),
        linux: const LinuxInitializationSettings(
          defaultActionName: 'Ouvrir CQCM',
        ),
        windows: const WindowsInitializationSettings(
          appName: 'CQCM',
          appUserModelId: 'com.cqcm.cqcm',
          guid: '1f0a4c62-58b0-4f0e-9a71-0d5cbb2e6a37',
        ),
      );

      await _plugin.initialize(
        initializationSettings,
        onDidReceiveNotificationResponse: _onResponse,
      );

      _initialized = true;
      _lastError = null;

      if (requestPermission && defaultTargetPlatform == TargetPlatform.android) {
        await _requestAndroidPermission(settings: settings);
      }
      return true;
    } catch (error) {
      _lastError = '$error';
      _initialized = false;
      return false;
    }
  }

  /// Demande l'autorisation d'afficher des notifications (Android 13+,
  /// iOS/macOS via les réglages Darwin).
  static Future<bool?> requestPermission({
    NotificationSettings? settings,
  }) async {
    if (!isSupportedPlatform) return null;

    try {
      if (!_initialized) {
        await initialize(settings: settings, requestPermission: true);
      }

      if (defaultTargetPlatform == TargetPlatform.android) {
        return _requestAndroidPermission(settings: settings);
      }

      if (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS) {
        // iOS/macOS ne redemandent pas si l'utilisateur a déjà refusé :
        // la ré-initialisation déclenche la demande au premier lancement.
        return initialize(settings: settings, requestPermission: true);
      }
      return null;
    } catch (error) {
      _lastError = '$error';
      return null;
    }
  }

  /// Charge les réglages JSON, calcule le plan et programme les rappels.
  ///
  /// Utilisée au démarrage de l'application et après chaque séance de
  /// révision : les échéances ont changé, les rappels sont reprogrammés.
  static Future<NotificationSyncResult> syncRevisionReminders({
    required RevisionPlan plan,
    required RevisionDeck deck,
    String? directoryPath,
  }) async {
    final bundle = await NotificationSettingsStore.load(
      directoryPath: directoryPath,
    );
    final settings = bundle.settings;

    final notificationPlan = NotificationPlan.build(
      deckId: deck.id,
      deckTitle: deck.title,
      items: plan.itemsOf(deck.id),
      progressFor: plan.progressFor,
      settings: settings,
      now: plan.now,
    );

    if (!notificationPlan.enabled) {
      await cancelAll();
      return NotificationSyncResult(
        bundle: bundle,
        plan: notificationPlan,
        platformReady: isSupportedPlatform,
        scheduled: false,
      );
    }

    final ready = _initialized ||
        await initialize(
          settings: settings,
          requestPermission: settings.requestPermissionOnStart,
        );

    if (!ready) {
      return NotificationSyncResult(
        bundle: bundle,
        plan: notificationPlan,
        platformReady: false,
        scheduled: false,
        error: _lastError,
      );
    }

    if (!supportsScheduling) {
      return NotificationSyncResult(
        bundle: bundle,
        plan: notificationPlan,
        platformReady: true,
        scheduled: false,
        error: 'cette plateforme ne programme pas de rappel différé',
      );
    }

    final error = await applyPlan(notificationPlan);
    return NotificationSyncResult(
      bundle: bundle,
      plan: notificationPlan,
      platformReady: true,
      scheduled: error == null,
      error: error,
    );
  }

  /// Programme les rappels du plan. Renvoie null si tout s'est bien passé.
  static Future<String?> applyPlan(NotificationPlan plan) async {
    if (!_initialized) {
      return _lastError ?? 'plugin non initialisé';
    }

    try {
      await _plugin.cancelAll();

      for (final reminder in plan.notifications) {
        await _plugin.zonedSchedule(
          reminder.id,
          reminder.title,
          reminder.body,
          tz.TZDateTime.from(reminder.fireAt, tz.local),
          NotificationDetails(
            android: AndroidNotificationDetails(
              plan.settings.channelId,
              plan.settings.channelName,
              channelDescription: plan.settings.channelDescription,
              importance: Importance.high,
              priority: Priority.high,
            ),
            iOS: const DarwinNotificationDetails(),
            macOS: const DarwinNotificationDetails(),
          ),
          androidScheduleMode: plan.settings.exact
              ? AndroidScheduleMode.exactAllowWhileIdle
              : AndroidScheduleMode.inexactAllowWhileIdle,
          payload: reminder.payload,
        );
      }

      _lastError = null;
      return null;
    } catch (error) {
      _lastError = '$error';
      return '$error';
    }
  }

  static Future<void> cancelAll() async {
    if (!_initialized) return;
    try {
      await _plugin.cancelAll();
    } catch (error) {
      _lastError = '$error';
    }
  }

  /// Affiche immédiatement une notification de test (vérification manuelle).
  static Future<String?> showTestNotification(NotificationSettings settings) async {
    final ready = _initialized ||
        await initialize(settings: settings, requestPermission: true);
    if (!ready) return _lastError ?? 'plugin non initialisé';

    try {
      await _plugin.show(
        99,
        'CQCM – test de rappel',
        'Les notifications fonctionnent. Rendez-vous ${settings.timeLabel}.',
        NotificationDetails(
          android: AndroidNotificationDetails(
            settings.channelId,
            settings.channelName,
            channelDescription: settings.channelDescription,
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: const DarwinNotificationDetails(),
          macOS: const DarwinNotificationDetails(),
        ),
        payload: '{"test":true}',
      );
      return null;
    } catch (error) {
      _lastError = '$error';
      return '$error';
    }
  }

  /// Rappels réellement enregistrés dans le système.
  static Future<List<String>> pendingSummary() async {
    if (!_initialized) return const [];
    try {
      final pending = await _plugin.pendingNotificationRequests();
      final lines = <String>[
        for (final request in pending)
          '#${request.id} · ${request.title ?? ''} · ${request.body ?? ''}',
      ];
      _lastError = null;
      return lines;
    } catch (error) {
      _lastError = '$error';
      return const [];
    }
  }

  static Future<bool?> _requestAndroidPermission({
    NotificationSettings? settings,
  }) async {
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android == null) return null;

    final granted = await android.requestNotificationsPermission();
    if (settings?.exact == true) {
      try {
        await android.requestExactAlarmsPermission();
      } catch (_) {
        // Permission exacte refusée : les rappels restent approximatifs.
      }
    }
    return granted;
  }

  /// Charge la base de fuseaux et applique celui du JSON s'il est renseigné.
  static void _configureTimeZone(String timeZoneName) {
    timezone_data.initializeTimeZones();
    if (timeZoneName.trim().isEmpty) return;
    try {
      tz.setLocalLocation(tz.getLocation(timeZoneName.trim()));
    } catch (_) {
      // Fuseau inconnu : on garde le fuseau par défaut.
    }
  }

  static void _onResponse(NotificationResponse response) {
    _lastPayload = response.payload;
  }
}
