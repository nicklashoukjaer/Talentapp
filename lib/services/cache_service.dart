// Letvægts lokal cache til "instant UI": vis cachede data med det samme ved
// opstart, mens der hentes friske data i baggrunden fra Supabase.
// Bruger platformStorage (localStorage på web/PWA — overlever genstart;
// in-memory på native). Ingen tomme loading-skærme ved opstart.
part of '../main.dart';

class CacheService {
  /// Første lag: rå objekter i hukommelsen. Et opslag her koster ingenting,
  /// hvor localStorage både skal læses og JSON-afkodes — og det sidste bliver
  /// mærkbart når feedet fylder.
  ///
  /// Andet lag er fortsat localStorage, så data også overlever at appen
  /// lukkes helt. Hukommelsen fyldes fra det ved første opslag.
  static final Map<String, Object?> _hukommelse = {};

  static void put(String key, Object? value) {
    if (value == null) return;
    _hukommelse[key] = value;
    try {
      platformStorageSet('cache_$key', jsonEncode(value));
    } catch (_) {}
  }

  /// Fjerner en nøgle begge steder. Bruges når data er blevet ugyldige.
  static void glem(String key) {
    _hukommelse.remove(key);
    try {
      platformStorageSet('cache_$key', '');
    } catch (_) {}
  }

  static Object? _raa(String key) {
    if (_hukommelse.containsKey(key)) return _hukommelse[key];
    try {
      final raw = platformStorageGet('cache_$key');
      if (raw == null || raw.isEmpty) return null;
      final v = jsonDecode(raw);
      _hukommelse[key] = v;
      return v;
    } catch (_) {
      return null;
    }
  }

  /// Cachet objekt (fx brugerprofil).
  static Map<String, dynamic>? getMap(String key) {
    try {
      final v = _raa(key);
      if (v == null) return null;
      return (v as Map).cast<String, dynamic>();
    } catch (_) {
      return null;
    }
  }

  /// Cachet liste af rækker (fx holdsaldo/leaderboard).
  static List<Map<String, dynamic>>? getList(String key) {
    try {
      final v = _raa(key);
      if (v == null) return null;
      return (v as List).cast<Map<String, dynamic>>();
    } catch (_) {
      return null;
    }
  }
}
