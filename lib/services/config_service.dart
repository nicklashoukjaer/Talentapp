// Klub-konfiguration gemt i Supabase-tabellen `club_config` (én række, id=1).
// Indeholder bl.a. det aktive MobilePay Box-ID/-link, som ADMINS kan ændre fra
// Dashboard. Caches lokalt (instant) så betalingsknappen virker hurtigt.
part of '../main.dart';

/// Hvor et nulstil-kodeord-link skal sende brugeren hen — appens egen adresse.
/// Bruger den aktuelle web-origin (virker på både vercel-URL og evt. eget
/// domæne); falder tilbage til den kendte produktions-URL uden for web.
String get _passwordResetRedirect {
  try {
    final o = Uri.base.origin;
    if (o.startsWith('http')) return o;
  } catch (_) {}
  return 'https://de-talentlose.vercel.app';
}

class ClubConfig {
  static const _table = 'club_config';
  static const _rowId = 1;
  static String? _cachedBox;

  /// Sidst kendte Box-ID/-link (fra cache/DB) — null hvis ikke hentet endnu.
  static String? get cachedBox => _cachedBox;

  /// Henter det gemte MobilePay Box-ID/-link fra Supabase (cache-fallback).
  static Future<String?> fetchMobilePayBox() async {
    final cached = CacheService.getMap('club_config');
    if (cached != null) _cachedBox = cached['mobilepay_box_id'] as String?;
    try {
      final row = await supabase
          .from(_table)
          .select('mobilepay_box_id')
          .eq('id', _rowId)
          .maybeSingle();
      _cachedBox = row?['mobilepay_box_id'] as String?;
      CacheService.put('club_config', {'mobilepay_box_id': _cachedBox});
    } catch (_) {
      // Behold cache ved netværks-/RLS-fejl.
    }
    return _cachedBox;
  }

  /// Opdaterer Box-ID/-link. KUN admins kan dette — håndhæves af RLS i Supabase
  /// (kald fejler for ikke-admins). UI'et vises også kun for admins.
  static Future<void> updateMobilePayBox(String value) async {
    final v = value.trim();
    // .update() på den faste række (id=1) — kræver kun UPDATE-politikken i RLS
    // (rækken oprettes i SQL). Undgår INSERT-check som .upsert() ellers udløser.
    await supabase.from(_table).update({'mobilepay_box_id': v}).eq('id', _rowId);
    _cachedBox = v;
    CacheService.put('club_config', {'mobilepay_box_id': v});
  }

  /// Henter udeblivelses-bøde-konfigurationen: hvilken bødetype (+ beløb/titel)
  /// der bruges, og om automatisk opkrævning ved sent afbud er slået til.
  static Future<
      ({String? fineTypeId, int? belobOere, String? titel, bool autoEnabled})>
      fetchNoShowConfig() async {
    try {
      final row = await supabase
          .from(_table)
          .select(
              'noshow_fine_type_id, noshow_auto_enabled, fine_types(id, titel, belob_oere)')
          .eq('id', _rowId)
          .maybeSingle();
      final ft = row?['fine_types'] as Map<String, dynamic>?;
      return (
        fineTypeId: row?['noshow_fine_type_id'] as String?,
        belobOere: (ft?['belob_oere'] as num?)?.toInt(),
        titel: ft?['titel'] as String?,
        autoEnabled: (row?['noshow_auto_enabled'] as bool?) ?? false,
      );
    } catch (_) {
      return (fineTypeId: null, belobOere: null, titel: null, autoEnabled: false);
    }
  }

  /// Opdaterer udeblivelses-bøde-konfigurationen. KUN admin (RLS + UI).
  static Future<void> updateNoShowConfig({
    required String? fineTypeId,
    required bool autoEnabled,
  }) async {
    await supabase.from(_table).update({
      'noshow_fine_type_id': fineTypeId,
      'noshow_auto_enabled': autoEnabled,
    }).eq('id', _rowId);
  }

  /// Henter de hold (navn + box) som [userId] er medlem af, og som har et eget
  /// MobilePay Box-ID sat. Bruges af bødekassen til at sende betalingen til det
  /// rigtige holds boks. Hold uden egen boks udelades (de bruger fælles-boksen).
  static Future<List<({String navn, String box})>> teamBoxesForUser(
      String userId) async {
    try {
      final rows = await supabase
          .from('group_members')
          .select('groups(navn, mobilepay_box_id)')
          .eq('user_id', userId);
      final out = <({String navn, String box})>[];
      for (final r in (rows as List)) {
        final g = r['groups'] as Map<String, dynamic>?;
        final box = (g?['mobilepay_box_id'] as String?)?.trim();
        if (g != null && box != null && box.isNotEmpty) {
          out.add((navn: g['navn'] as String? ?? 'Hold', box: box));
        }
      }
      return out;
    } catch (_) {
      return const [];
    }
  }
}

/// Bygger det officielle MobilePay-link ud fra [box] og beløbet [oere].
/// MobilePay Box "pay-in" forventer beløbet i ØRE (fx 20 kr = 2000 øre),
/// så vi sender [oere] direkte (= kroner ganget med 100).
/// [box] kan være enten et rent Box-ID eller et fuldt URL (admin-valg).
String mobilePayLinkFor(String box, int oere) {
  final b = box.trim();
  if (b.startsWith('http')) {
    if (b.contains('amount=')) return b; // admin har allerede sat beløb/parametre
    final sep = b.contains('?') ? '&' : '?';
    return '$b${sep}amount=$oere';
  }
  // Rent Box-ID → officielt Vipps/MobilePay Box-link (beløb i øre).
  return 'https://qr.mobilepay.dk/box/$b/pay-in?amount=$oere';
}
