# Règles R8 / ProGuard du projet.
#
# Ce fichier est lu automatiquement par le plugin Gradle de Flutter quand le
# rétrécissement est actif — c'est le cas par défaut en release (`shrink=true`,
# jamais désactivé dans `android/gradle.properties`).
#
# Pourquoi ce fichier existe : `flutter_local_notifications` (dé)sérialise ses
# rappels programmés avec Gson, par réflexion sur les noms de champs (voir
# `FlutterLocalNotificationsPlugin.buildGson()` et `loadScheduledNotifications`).
# R8 renomme les champs par défaut : les rappels relus depuis les
# SharedPreferences après une mise à jour du binaire deviennent illisibles et
# disparaissent sans message d'erreur. Les règles ci-dessous figent ces noms —
# le rétrécissement et les optimisations restent actifs, seul le renommage est
# bloqué là où c'est nécessaire (coût : quelques kilo-octets de noms).

# Gson s'appuie sur les signatures génériques (`TypeToken`) et les annotations.
-keepattributes Signature
-keepattributes *Annotation*
-keep class com.google.gson.reflect.TypeToken { *; }
-keep class * extends com.google.gson.reflect.TypeToken
-keepclassmembers,allowobfuscation,allowshrinking class * {
    @com.google.gson.annotations.SerializedName <fields>;
}

# Modèles du plugin : noms de classes et de champs utilisés comme clés JSON.
-keepnames class com.dexterous.flutterlocalnotifications.** { *; }

# Gson charge `sun.misc.Unsafe` par réflexion quand il est disponible : son
# absence sur Android n'est pas une erreur.
-dontwarn sun.misc.**
