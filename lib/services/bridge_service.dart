// Auto-split (del af biblioteket padel_app)
// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
part of '../main.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Automations-broen
//
// Broen kører som et Node-program på den maskine hvor robotten bor, og
// lytter KUN på 127.0.0.1. Det betyder at den findes for den der har startet
// den — ikke på telefoner og ikke for de øvrige medlemmer.
//
// Derfor er alt herfra en TILFØJELSE: kan broen ikke nås, tegner appen
// præcis som før. Ingen fejlskærm, ingen spinner der hænger.
// ─────────────────────────────────────────────────────────────────────────────

/// Bane-status for én hjemmekamp, som broen melder den.
class BaneStatus {
  final String trainingId;
  final bool booket;
  final List<String> baner;
  const BaneStatus({
    required this.trainingId,
    required this.booket,
    this.baner = const [],
  });
}

/// Broens seneste banesvar, delt på tværs af skærme.
///
/// Banestatus vises tre steder — dashboardlinjen, feedkortet og
/// PC-tabellen — men kun dashboardet spørger broen. Uden et fælles sted
/// ville de to andre blive ved med at vise appens gamle afkrydsningsflag
/// og modsige Bookli.
///
/// Tom betyder "broen har ikke svaret", ALDRIG "ingen baner". De to må
/// ikke forveksles: det første skal falde tilbage til databasen, det
/// andet skal give en advarsel.
class BaneFacit {
  static final ValueNotifier<Map<String, BaneStatus>> _alle =
      ValueNotifier(const {});

  static ValueListenable<Map<String, BaneStatus>> get lytter => _alle;

  static void saet(Map<String, BaneStatus> m) => _alle.value = m;

  static BaneStatus? af(Object? trainingId) =>
      trainingId is String ? _alle.value[trainingId] : null;
}

class BridgeService {
  /// Adresse og nøgle er maskinspecifikke og gemmes derfor lokalt, ikke i
  /// databasen — en anden enhed har en anden bro, eller ingen.
  static String get adresse =>
      platformStorageGet('bro_adresse') ?? 'http://127.0.0.1:8787';
  static String get noegle => platformStorageGet('bro_noegle') ?? '';

  static void gem(String adresse, String noegle) {
    // Uden dette bliver en indsat adresse med skråstreg til sidst til
    // "…com//status", som broen ikke kender.
    final a = adresse.trim().replaceAll(RegExp(r'/+$'), '');
    platformStorageSet('bro_adresse', a);
    platformStorageSet('bro_noegle', noegle.trim());
    _sidstSvigtede = null;
  }

  static bool get erOpsat => noegle.isNotEmpty;

  /// Når broen ikke svarer, holder vi pause. Uden det ville hvert eneste
  /// build af Dashboardet sende et kald afsted der skal time ud.
  static DateTime? _sidstSvigtede;
  static bool get _iPause =>
      _sidstSvigtede != null &&
      DateTime.now().difference(_sidstSvigtede!) < const Duration(minutes: 2);

  static Future<Map<String, dynamic>?> _kald(
    String sti, {
    Map<String, dynamic>? krop,
  }) async {
    if (!erOpsat || _iPause) return null;
    try {
      final svar = await http
          .post(
            Uri.parse('$adresse$sti'),
            headers: {
              'content-type': 'application/json',
              'x-bridge-token': noegle,
            },
            body: jsonEncode(krop ?? const {}),
          )
          .timeout(const Duration(seconds: 90));
      if (svar.statusCode != 200) {
        _sidstSvigtede = DateTime.now();
        return null;
      }
      _sidstSvigtede = null;
      return jsonDecode(svar.body) as Map<String, dynamic>;
    } catch (_) {
      // Broen er slukket, eller browseren blokerede kaldet. Begge dele er
      // normale — appen skal bare ikke vise bane-status.
      _sidstSvigtede = DateTime.now();
      return null;
    }
  }

  /// Er broen i live?
  static Future<bool> tjek() async {
    final r = await _kald('/status');
    return r?['oppe'] == true;
  }

  /// Bane-status for de hjemmekampe der sendes med.
  ///
  /// Tom liste tilbage betyder "broen svarede ikke" — ikke "ingen baner".
  /// De to må ikke forveksles, og derfor er returtypen nullable.
  static Future<List<BaneStatus>?> validerBaner(
      List<Map<String, dynamic>> kampe) async {
    if (kampe.isEmpty) return const [];
    final r = await _kald('/bookli/valider', krop: {
      'kampe': [
        for (final k in kampe)
          {
            'id': k['id'],
            'titel': k['titel'],
            'start': k['start_tid'],
            'slut': k['slut_tid'],
          }
      ]
    });
    final liste = r?['resultat'];
    if (liste is! List) return null;
    return [
      for (final e in liste.whereType<Map>())
        BaneStatus(
          trainingId: (e['kamp']?['id'] ?? '') as String,
          booket: e['status'] == 'BOOKET',
          baner: ((e['baner'] as List?) ?? const [])
              .map((x) => x.toString())
              .toList(),
        )
    ];
  }

  /// Kampprogrammet fra RankedIn, holdnavn → kampe.
  ///
  /// Understøtter et vilkårligt antal hold: broen slår selv op hvilke hold
  /// der har et rankedin_url i databasen, så T3, Damer 2 og hvad der ellers
  /// måtte komme, følger med uden kodeændring.
  static Future<Map<String, List<Map<String, dynamic>>>?> hentKampe() async {
    final r = await _kald('/rankedin/kampe');
    final hold = r?['hold'];
    if (hold is! Map) return null;
    return {
      for (final e in hold.entries)
        e.key as String: [
          for (final k in (e.value as List? ?? const []).whereType<Map>())
            k.cast<String, dynamic>()
        ]
    };
  }
}
