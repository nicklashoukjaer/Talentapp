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

/// Et stykke af en kamp der ikke er bane til.
class BaneHul {
  final DateTime fra;
  final DateTime til;
  const BaneHul(this.fra, this.til);
}

/// Bane-status for én hjemmekamp, som broen melder den.
///
/// Tre tilstande, ikke to. En booking der kun dækker en del af kampen
/// er hverken i orden eller fraværende, og at putte den i en af de to
/// kasser var netop fejlen: den 13. november lå to kampe oven på én
/// booking og blev begge meldt booket.
class BaneStatus {
  final String trainingId;

  /// Broens ord: `BOOKET`, `DELVIS_BOOKET` eller `MANGLER_BANE`.
  final String status;
  final List<String> baner;

  /// De stykker af kampen der ikke er dækket. Tom ved `BOOKET`.
  final List<BaneHul> mangler;

  /// Hvornår banerne står reserveret i Bookli. Null når ingen fandtes,
  /// og `til` kan være null hvis Bookli ikke oplyste en sluttid.
  final DateTime? banetidFra;
  final DateTime? banetidTil;

  /// Kampens eget tidsrum, som det står i appen. Det er forskellen
  /// mellem de to par der skal forklares — ikke bare at noget mangler.
  final DateTime? kamptidFra;
  final DateTime? kamptidTil;

  const BaneStatus({
    required this.trainingId,
    required this.status,
    this.baner = const [],
    this.mangler = const [],
    this.banetidFra,
    this.banetidTil,
    this.kamptidFra,
    this.kamptidTil,
  });

  bool get booket => status == 'BOOKET';
  bool get delvis => status == 'DELVIS_BOOKET';
  bool get iOrden => booket;
}

/// En bane i Bookli, som broen melder den.
class BookliBane {
  final String navn;   // "D10"
  final String hal;    // "Home Arena, Bane D8-D12"
  const BookliBane({required this.navn, required this.hal});
}

/// Svar på "kan vi få den her bane i det tidsrum".
class BaneLedig {
  final String bane;
  final bool ledig;

  /// Sandt når vi allerede holder banen i tidsrummet. Så skal der ikke
  /// bookes noget — og "ledig" er sandt netop fordi den er vores.
  final bool viHarSelv;
  final String? grund;
  const BaneLedig({
    required this.bane,
    required this.ledig,
    this.viHarSelv = false,
    this.grund,
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
          // Ukendt ord fra en nyere bro må ikke blive til falsk grønt.
          status: switch (e['status']) {
            'BOOKET' => 'BOOKET',
            'DELVIS_BOOKET' => 'DELVIS_BOOKET',
            _ => 'MANGLER_BANE',
          },
          baner: ((e['baner'] as List?) ?? const [])
              .map((x) => x.toString())
              .toList(),
          mangler: [
            for (final m in (e['mangler'] as List?) ?? const [])
              if (m is Map &&
                  m['fra'] is String &&
                  m['til'] is String)
                BaneHul(DateTime.parse(m['fra'] as String).toLocal(),
                    DateTime.parse(m['til'] as String).toLocal()),
          ],
          banetidFra: _tid(e['banetid'], 'fra'),
          banetidTil: _tid(e['banetid'], 'til'),
          kamptidFra: _tid(e['kamptid'], 'fra'),
          kamptidTil: _tid(e['kamptid'], 'til'),
        )
    ];
  }

  /// Banerne Bookli kender, fx D10 i "Home Arena, Bane D8-D12".
  ///
  /// Null betyder "broen svarede ikke" — ikke "ingen baner". Bane-vælgeren
  /// falder da tilbage på klubbens faste liste, så man stadig kan vælge
  /// uden at broen kører.
  static Future<List<BookliBane>?> hentBaner() async {
    final r = await _kald('/bookli/baner');
    final liste = r?['baner'];
    if (liste is! List) return null;
    return [
      for (final e in liste.whereType<Map>())
        BookliBane(
          navn: (e['navn'] ?? '').toString(),
          hal: (e['hal'] ?? '').toString(),
        )
    ];
  }

  /// Kan vi få banerne i tidsrummet? Vores egne bookinger trækkes fra,
  /// så en flytning ikke blokeres af den booking der skal flyttes.
  static Future<List<BaneLedig>?> tjekLedighed({
    required List<String> baner,
    required DateTime start,
    required DateTime slut,
  }) async {
    if (baner.isEmpty) return const [];
    final r = await _kald('/bookli/ledig', krop: {
      'baner': baner,
      'start': start.toUtc().toIso8601String(),
      'slut': slut.toUtc().toIso8601String(),
    });
    final liste = r?['ledighed'];
    if (liste is! List) return null;
    return [
      for (final e in liste.whereType<Map>())
        BaneLedig(
          bane: (e['bane'] ?? '').toString(),
          ledig: e['ledig'] == true,
          viHarSelv: (e['egne'] as List?)?.isNotEmpty ?? false,
          grund: e['optagetAf']?.toString(),
        )
    ];
  }

  /// Plukker et tidsstempel ud af broens svar. Alt kan mangle — en
  /// ældre bro kender ikke felterne — og så skal visningen bare klare
  /// sig uden.
  static DateTime? _tid(Object? blok, String felt) {
    if (blok is! Map) return null;
    final v = blok[felt];
    return v is String ? DateTime.tryParse(v)?.toLocal() : null;
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
