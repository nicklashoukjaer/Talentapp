// Letvægts lokal cache til "instant UI": vis cachede data med det samme ved
// opstart, mens der hentes friske data i baggrunden fra Supabase.
// Bruger platformStorage (localStorage på web/PWA — overlever genstart;
// in-memory på native). Ingen tomme loading-skærme ved opstart.
part of '../main.dart';

class CacheService {
  static void put(String key, Object? value) {
    if (value == null) return;
    try {
      platformStorageSet('cache_$key', jsonEncode(value));
    } catch (_) {}
  }

  /// Cachet objekt (fx brugerprofil).
  static Map<String, dynamic>? getMap(String key) {
    try {
      final raw = platformStorageGet('cache_$key');
      if (raw == null) return null;
      return (jsonDecode(raw) as Map).cast<String, dynamic>();
    } catch (_) {
      return null;
    }
  }

  /// Cachet liste af rækker (fx holdsaldo/leaderboard).
  static List<Map<String, dynamic>>? getList(String key) {
    try {
      final raw = platformStorageGet('cache_$key');
      if (raw == null) return null;
      return (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    } catch (_) {
      return null;
    }
  }
}
