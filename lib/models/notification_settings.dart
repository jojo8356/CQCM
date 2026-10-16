/// Réglages des rappels de révision, lus depuis un fichier JSON.
///
/// Fichiers pris en compte, dans l'ordre :
///
/// 1. `assets/data/notifications.json` : valeurs par défaut, versionnées ;
/// 2. `<dossier de données>/notifications.json` : surcharge locale, sans
///    rebuild (mêmes clés, partielle acceptée).
///
/// Toute la configuration passe par du JSON : aucun écran de réglages.
library;

class NotificationSettings {
  /// Active ou coupe les rappels système.
  final bool enabled;

  /// Heure du rappel (0-23) et minutes (0-59).
  final int hour;
  final int minute;

  /// Nom de fuseau IANA (ex. `Europe/Paris`). Vide : fuseau du système.
  final String timezone;

  /// `true` : alarme exacte (permission Android supplémentaire),
  /// `false` : rappel approximatif, économe en batterie.
  final bool exact;

  /// Nombre de rappels à programmer à l'avance.
  final int maxNotifications;

  /// Demande l'autorisation d'afficher des notifications au démarrage.
  final bool requestPermissionOnStart;

  final String channelId;
  final String channelName;
  final String channelDescription;

  /// Gabarit du titre, avec `{count}`, `{deck}`, `{date}`.
  final String titleTemplate;

  /// Gabarit du corps, avec `{count}`, `{prompt}`, `{deck}`, `{date}`.
  final String bodyTemplate;

  const NotificationSettings({
    this.enabled = true,
    this.hour = 9,
    this.minute = 0,
    this.timezone = '',
    this.exact = false,
    this.maxNotifications = 8,
    this.requestPermissionOnStart = true,
    this.channelId = 'cqcm-revision',
    this.channelName = 'Révisions CQCM',
    this.channelDescription = 'Rappels de révision espacée du programme GP',
    this.titleTemplate = 'GP – {count} phrase(s) à réviser',
    this.bodyTemplate = 'Commence par : {prompt}',
  });

  /// Fusionne un JSON partiel avec une configuration existante.
  factory NotificationSettings.fromJson(
    Map<String, dynamic>? json, {
    NotificationSettings? fallback,
  }) {
    final base = fallback ?? const NotificationSettings();
    if (json == null) return base;

    return NotificationSettings(
      enabled: json['enabled'] as bool? ?? base.enabled,
      hour: _clampInt(json['hour'], base.hour, 0, 23),
      minute: _clampInt(json['minute'], base.minute, 0, 59),
      timezone: (json['timezone'] as String?)?.trim() ?? base.timezone,
      exact: json['exact'] as bool? ?? base.exact,
      maxNotifications: _clampInt(
        json['maxNotifications'],
        base.maxNotifications,
        1,
        32,
      ),
      requestPermissionOnStart:
          json['requestPermissionOnStart'] as bool? ??
          base.requestPermissionOnStart,
      channelId: (json['channelId'] as String?) ?? base.channelId,
      channelName: (json['channelName'] as String?) ?? base.channelName,
      channelDescription:
          (json['channelDescription'] as String?) ?? base.channelDescription,
      titleTemplate: (json['titleTemplate'] as String?) ?? base.titleTemplate,
      bodyTemplate: (json['bodyTemplate'] as String?) ?? base.bodyTemplate,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'enabled': enabled,
      'hour': hour,
      'minute': minute,
      'timezone': timezone,
      'exact': exact,
      'maxNotifications': maxNotifications,
      'requestPermissionOnStart': requestPermissionOnStart,
      'channelId': channelId,
      'channelName': channelName,
      'channelDescription': channelDescription,
      'titleTemplate': titleTemplate,
      'bodyTemplate': bodyTemplate,
    };
  }

  /// Heure du rappel au format `09:00`.
  String get timeLabel {
    final hourLabel = hour.toString().padLeft(2, '0');
    final minuteLabel = minute.toString().padLeft(2, '0');
    return '$hourLabel:$minuteLabel';
  }

  NotificationSettings copyWith({
    bool? enabled,
    int? hour,
    int? minute,
    String? timezone,
    bool? exact,
    int? maxNotifications,
    bool? requestPermissionOnStart,
  }) {
    return NotificationSettings(
      enabled: enabled ?? this.enabled,
      hour: hour ?? this.hour,
      minute: minute ?? this.minute,
      timezone: timezone ?? this.timezone,
      exact: exact ?? this.exact,
      maxNotifications: maxNotifications ?? this.maxNotifications,
      requestPermissionOnStart:
          requestPermissionOnStart ?? this.requestPermissionOnStart,
      channelId: channelId,
      channelName: channelName,
      channelDescription: channelDescription,
      titleTemplate: titleTemplate,
      bodyTemplate: bodyTemplate,
    );
  }

  static int _clampInt(Object? value, int fallback, int min, int max) {
    final parsed = value is num ? value.toInt() : null;
    if (parsed == null) return fallback;
    if (parsed < min) return min;
    if (parsed > max) return max;
    return parsed;
  }
}
