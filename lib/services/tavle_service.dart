// Auto-split (del af biblioteket padel_app)
part of '../main.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Tavlens databaseadgang
//
// Samlet her af to grunde. Dels lå de samme forespørgsler spredt ud over
// rotation_view og to næsten ens indgange i oversigt_view, hvor kun den ene
// tog gæster med — to veje til samme skærm der viste forskelligt. Dels skal
// skrivningerne kunne gøres atomare i fase 2 uden at skulle findes frem fra
// midten af en widget.
// ─────────────────────────────────────────────────────────────────────────────

/// Tavlens opsætning for én træning.
class TavleOpsaetning {
  /// `mixet` eller `opdelt` (efter hold).
  final String tilstand;

  /// `manuel` eller `timer`.
  final String afvikling;
  final int minutter;
  final int baner;

  /// Skal holdets faste par holdes sammen i denne træning? Gælder én
  /// træning, ikke holdet — derfor står den her og ikke på parret.
  final bool brugFastePar;

  const TavleOpsaetning({
    this.tilstand = 'mixet',
    this.afvikling = 'manuel',
    this.minutter = 15,
    this.baner = 2,
    this.brugFastePar = true,
  });

  factory TavleOpsaetning.fraRaekke(Map<String, dynamic>? m) => m == null
      ? const TavleOpsaetning()
      : TavleOpsaetning(
          tilstand: m['tilstand'] as String? ?? 'mixet',
          afvikling: m['afvikling'] as String? ?? 'manuel',
          minutter: (m['minutter'] as num?)?.toInt() ?? 15,
          baner: (m['baner'] as num?)?.toInt() ?? 2,
          brugFastePar: m['brug_faste_par'] as bool? ?? true,
        );
}

/// Alt tavlen skal bruge for at tegne sig selv første gang.
class TavleStart {
  final TavleOpsaetning opsaetning;
  final int rundeNr;
  final String? rundeId;
  final DateTime? slutterAt;

  /// Stjernemarkerede par, som sorterede nøgler.
  final Set<String> kemi;

  /// Par der allerede har spillet sammen i DENNE træning.
  final Set<String> spilletSammen;

  /// Faste par for begivenhedens hold. Bindende i fordelingen.
  final Set<String> fastePar;

  /// uid → [førstevalg, andetvalg] fra spillernes egne profiler.
  final Map<String, List<String>> favoritter;

  /// Par → gange de har spillet sammen før, på tværs af træninger.
  final Map<String, int> historik;

  /// uid → runder spillet i denne træning. Styrer hvem der sidder over.
  final Map<String, int> runderSpillet;

  /// Modstanderpar der allerede er mødtes i dag.
  final Set<String> modtFoer;

  /// Versionen af den aktuelle runde, til samtidighedstjek.
  final int version;

  /// Har træneren gemt en opsætning før? Er den ikke det, vælger tavlen
  /// et antal baner der passer til de tilmeldte — ellers ville to baner
  /// sætte halvdelen af en stor træning på bænken uden at nogen bad om
  /// det.
  final bool harOpsaetning;

  const TavleStart({
    required this.opsaetning,
    required this.rundeNr,
    required this.rundeId,
    required this.slutterAt,
    required this.kemi,
    required this.spilletSammen,
    this.fastePar = const {},
    this.favoritter = const {},
    this.historik = const {},
    this.runderSpillet = const {},
    this.modtFoer = const {},
    this.version = 1,
    this.harOpsaetning = false,
  });
}

/// Deltagerne til en træning, klar til tavlen.
class TavleDeltagere {
  final List<TavleSpiller> spillere;

  /// uid → holdnavn. Bruges af "Opdelt efter hold".
  final Map<String, String> holdAf;

  const TavleDeltagere(this.spillere, this.holdAf);
}

/// Én runde set fra én spillers stol.
class SpillerRunde {
  final int nr;

  /// Null når spilleren sad over i runden.
  final int? bane;
  final TavleSpiller? makker;
  final List<TavleSpiller> modstandere;

  /// Hvornår runden slutter, hvis træneren kører med ur.
  final DateTime? slutterAt;

  const SpillerRunde({
    required this.nr,
    this.bane,
    this.makker,
    this.modstandere = const [],
    this.slutterAt,
  });

  bool get sidderOver => bane == null;
}

class TavleService {
  static const _kemiNoegle = 'par_kemi';

  // ── Deltagere ──────────────────────────────────────────────────────────

  /// Henter tilmeldte og afløsere til en træning.
  ///
  /// Én indgang til tavlen. Før fandtes to: begivenhedsdetaljen sendte de
  /// deltagere den allerede havde (med gæster), mens dashboardet hentede
  /// sine egne (uden gæster). Samme skærm, to forskellige holdlister.
  ///
  /// [kendte] lader kalderen genbruge det den allerede har hentet, så
  /// begivenhedsdetaljen ikke spørger databasen om noget den ved.
  static Future<TavleDeltagere> hentDeltagere(
    Map<String, dynamic> training, {
    List<TavleSpiller>? kendte,
  }) async {
    final tid = training['id'] as String;
    final spillere = <TavleSpiller>[];

    if (kendte != null) {
      spillere.addAll(kendte);
    } else {
      final parts = List<Map<String, dynamic>>.from(await supabase
          .from('training_participants')
          .select('user_id, status')
          .eq('training_id', tid) as List);
      final tilmeldte = parts
          .where((p) => p['status'] != 'afmeldt')
          .map((p) => p['user_id'] as String)
          .toSet();

      if (tilmeldte.isNotEmpty) {
        final profiler = List<Map<String, dynamic>>.from(await supabase
            .from('profiles')
            .select('id, navn, spiller_side')
            .inFilter('id', tilmeldte.toList()) as List);
        spillere.addAll([
          for (final p in profiler)
            TavleSpiller(
              id: p['id'] as String,
              navn: p['navn'] as String? ?? '?',
              side: p['spiller_side'] as String?,
            )
        ]);
      }

      // Afløsere uden konto. De manglede helt i dashboard-indgangen.
      final gaester = List<Map<String, dynamic>>.from(await supabase
          .from('training_guests')
          .select('id, navn')
          .eq('training_id', tid) as List);
      spillere.addAll([
        for (final g in gaester)
          TavleSpiller(
            id: g['id'] as String,
            navn: g['navn'] as String? ?? 'Gæst',
            erGaest: true,
          )
      ]);
    }

    return TavleDeltagere(spillere, await hentHoldAf(training));
  }

  /// uid → holdnavn for de hold begivenheden hører til.
  static Future<Map<String, String>> hentHoldAf(
      Map<String, dynamic> training) async {
    final gids = _trainingGroupIds(training);
    if (gids.isEmpty) return const {};
    try {
      final rows = List<Map<String, dynamic>>.from(await supabase
          .from('group_members')
          .select('user_id, groups!inner(navn)')
          .inFilter('group_id', gids) as List);
      return {
        for (final r in rows)
          if (r['groups'] is Map)
            r['user_id'] as String:
                (r['groups'] as Map)['navn'] as String? ?? '?'
      };
    } catch (_) {
      // Holdnavne er pynt i "Opdelt efter hold". Tavlen skal kunne åbne
      // uden dem.
      return const {};
    }
  }

  // ── Opstart ────────────────────────────────────────────────────────────

  /// Stjernemarkeringerne fra cachen, så tavlen kan tegne uden spinner.
  static Set<String> kemiFraCache() {
    final raa = CacheService.getList(_kemiNoegle);
    if (raa == null) return {};
    return {
      for (final k in raa)
        if (k['spiller_lav'] != null && k['spiller_hoej'] != null)
          parNoegle(k['spiller_lav'] as String, k['spiller_hoej'] as String)
    };
  }

  /// Alt der skal til for at åbne tavlen.
  ///
  /// [gruppeIds] er begivenhedens hold — faste par hentes kun for dem.
  /// [deltagere] bruges til at hente favoritter og historik for netop de
  /// spillere der er med, frem for hele klubben.
  static Future<TavleStart> hentStart(
    String trainingId, {
    List<String> gruppeIds = const [],
    List<TavleSpiller> deltagere = const [],
  }) async {
    // Hver for sig: Future.wait over forskellige returtyper kan ikke udlede
    // en fælles type her.
    final board = await supabase
        .from('training_boards')
        .select()
        .eq('training_id', trainingId)
        .maybeSingle();

    final sidste = await supabase
        .from('training_rounds')
        .select('id, nr, slutter_at, version')
        .eq('training_id', trainingId)
        .order('nr', ascending: false)
        .limit(1)
        .maybeSingle();

    final kemiRaekker = List<Map<String, dynamic>>.from(await supabase
        .from('par_kemi')
        .select('spiller_lav, spiller_hoej') as List);
    CacheService.put(_kemiNoegle, kemiRaekker);

    return TavleStart(
      opsaetning: TavleOpsaetning.fraRaekke(board),
      rundeNr: (sidste?['nr'] as num?)?.toInt() ?? 0,
      rundeId: sidste?['id'] as String?,
      slutterAt: sidste?['slutter_at'] == null
          ? null
          : DateTime.parse(sidste!['slutter_at'] as String).toLocal(),
      kemi: {
        for (final k in kemiRaekker)
          parNoegle(k['spiller_lav'] as String, k['spiller_hoej'] as String)
      },
      spilletSammen: await hentSpilletSammen(trainingId),
      fastePar: await hentFastePar(gruppeIds),
      favoritter: await hentFavoritter(
          [for (final d in deltagere) if (!d.erGaest) d.id]),
      historik: await hentHistorik(),
      runderSpillet: await hentRunderSpillet(trainingId),
      modtFoer: await hentModtFoer(trainingId),
      version: (sidste?['version'] as num?)?.toInt() ?? 1,
      harOpsaetning: board != null,
    );
  }

  // ── Faste par ──────────────────────────────────────────────────────────

  /// Faste par for de angivne hold, som sorterede nøgler.
  static Future<Set<String>> hentFastePar(List<String> gruppeIds) async {
    if (gruppeIds.isEmpty) return {};
    final rows = List<Map<String, dynamic>>.from(await supabase
        .from('faste_par')
        .select('spiller_lav, spiller_hoej')
        .inFilter('group_id', gruppeIds)
        .eq('aktiv', true) as List);
    return {
      for (final r in rows)
        parNoegle(r['spiller_lav'] as String, r['spiller_hoej'] as String)
    };
  }

  /// Faste par med navne, til administrationen.
  static Future<List<Map<String, dynamic>>> hentFastePerHold(
      List<String> gruppeIds) async {
    if (gruppeIds.isEmpty) return const [];
    return List<Map<String, dynamic>>.from(await supabase
        .from('faste_par')
        .select('group_id, spiller_lav, spiller_hoej, navn, aktiv')
        .inFilter('group_id', gruppeIds) as List);
  }

  static Future<void> gemFastPar(
      String groupId, String a, String b, {String? navn}) async {
    await supabase.from('faste_par').upsert({
      'group_id': groupId,
      'spiller_lav': a.compareTo(b) < 0 ? a : b,
      'spiller_hoej': a.compareTo(b) < 0 ? b : a,
      if (navn != null && navn.trim().isNotEmpty) 'navn': navn.trim(),
      'aktiv': true,
      'oprettet_af': supabase.auth.currentUser?.id,
    });
  }

  static Future<void> sletFastPar(String groupId, String a, String b) async {
    await supabase
        .from('faste_par')
        .delete()
        .eq('group_id', groupId)
        .eq('spiller_lav', a.compareTo(b) < 0 ? a : b)
        .eq('spiller_hoej', a.compareTo(b) < 0 ? b : a);
  }

  // ── Øvrige signaler til fordelingen ────────────────────────────────────

  /// Spillernes egne makkervalg: uid → [førstevalg, andetvalg].
  static Future<Map<String, List<String>>> hentFavoritter(
      List<String> uids) async {
    if (uids.isEmpty) return const {};
    final rows = List<Map<String, dynamic>>.from(await supabase
        .from('profiles')
        .select('id, makker_prio_1, makker_prio_2')
        .inFilter('id', uids) as List);
    return {
      for (final r in rows)
        r['id'] as String: [
          if (r['makker_prio_1'] != null) r['makker_prio_1'] as String,
          if (r['makker_prio_2'] != null) r['makker_prio_2'] as String,
        ]
    };
  }

  /// Hvor mange gange hvert par har spillet sammen før, på tværs af
  /// træninger. Læses fra par_overblik, som allerede regner det ud.
  static Future<Map<String, int>> hentHistorik() async {
    try {
      final rows = List<Map<String, dynamic>>.from(await supabase
          .from('par_overblik')
          .select('spiller_lav, spiller_hoej, runder_sammen') as List);
      return {
        for (final r in rows)
          parNoegle(r['spiller_lav'] as String, r['spiller_hoej'] as String):
              (r['runder_sammen'] as num?)?.toInt() ?? 0
      };
    } catch (_) {
      // Historik er et blødt signal. Kan den ikke hentes, fordeles der
      // uden den frem for at tavlen ikke kan åbne.
      return const {};
    }
  }

  /// uid → runder spillet i denne træning. Bænken fordeles efter det.
  static Future<Map<String, int>> hentRunderSpillet(String trainingId) async {
    final rows = List<Map<String, dynamic>>.from(await supabase
        .from('training_round_slots')
        .select('user_id, guest_id, bane, training_rounds!inner(training_id)')
        .eq('training_rounds.training_id', trainingId) as List);
    final ud = <String, int>{};
    for (final r in rows) {
      if (r['bane'] == null) continue; // sad over — tæller ikke
      final id = (r['user_id'] ?? r['guest_id']) as String?;
      if (id != null) ud[id] = (ud[id] ?? 0) + 1;
    }
    return ud;
  }

  /// Hvilke par der allerede har mødt hinanden i dag.
  static Future<Set<String>> hentModtFoer(String trainingId) async {
    final rows = List<Map<String, dynamic>>.from(await supabase
        .from('training_round_slots')
        .select('round_id, bane, par, user_id, guest_id, '
            'training_rounds!inner(training_id)')
        .eq('training_rounds.training_id', trainingId) as List);

    // Saml spillerne pr. (runde, bane, par) og dan derefter mødepar.
    final grupper = <String, List<String>>{};
    for (final r in rows) {
      if (r['bane'] == null) continue;
      final id = (r['user_id'] ?? r['guest_id']) as String?;
      if (id == null) continue;
      (grupper['${r['round_id']}-${r['bane']}-${r['par']}'] ??= []).add(id);
    }

    final perBane = <String, List<String>>{};
    for (final e in grupper.entries) {
      if (e.value.length != 2) continue;
      final dele = e.key.split('-');
      final bane = '${dele[0]}-${dele[1]}';
      (perBane[bane] ??= []).add(parNoegle(e.value[0], e.value[1]));
    }

    return {
      for (final par in perBane.values)
        if (par.length == 2)
          par[0].compareTo(par[1]) < 0
              ? '${par[0]}#${par[1]}'
              : '${par[1]}#${par[0]}'
    };
  }

  /// Par der allerede har spillet sammen i denne træning.
  static Future<Set<String>> hentSpilletSammen(String trainingId) async {
    final rows = List<Map<String, dynamic>>.from(await supabase
        .from('training_round_slots')
        .select('round_id, bane, par, user_id, training_rounds!inner(training_id)')
        .eq('training_rounds.training_id', trainingId) as List);

    final grupper = <String, List<String>>{};
    for (final s in rows) {
      final uid = s['user_id'] as String?;
      if (uid == null || s['bane'] == null) continue;
      (grupper['${s['round_id']}-${s['bane']}-${s['par']}'] ??= []).add(uid);
    }

    final ud = <String>{};
    for (final g in grupper.values) {
      for (var i = 0; i < g.length; i++) {
        for (var j = i + 1; j < g.length; j++) {
          ud.add(parNoegle(g[i], g[j]));
        }
      }
    }
    return ud;
  }

  /// Opstillingen i en bestemt runde.
  static Future<Opstilling> hentRunde(
      String roundId, List<TavleSpiller> spillere) async {
    final rows = List<Map<String, dynamic>>.from(await supabase
        .from('training_round_slots')
        .select('bane, par, user_id, guest_id, laast')
        .eq('round_id', roundId)
        .order('bane', ascending: true) as List);
    return Opstilling.fraRaekker(rows, {for (final s in spillere) s.id: s});
  }

  // ── Spillerens egen visning ────────────────────────────────────────────

  /// Alle runder, set fra [uid]'s stol — nyeste først.
  ///
  /// Læseadgangen findes allerede: RLS på runder og pladser tillader alle
  /// indloggede at se dem. Spilleren skal bare have det vist uden at
  /// skulle åbne trænerens tavle.
  static Future<List<SpillerRunde>> hentSpillerRunder(
    Map<String, dynamic> training,
    String uid,
  ) async {
    final tid = training['id'] as String;
    final runder = List<Map<String, dynamic>>.from(await supabase
        .from('training_rounds')
        .select('id, nr, slutter_at')
        .eq('training_id', tid)
        .order('nr', ascending: false) as List);
    if (runder.isEmpty) return const [];

    final slots = List<Map<String, dynamic>>.from(await supabase
        .from('training_round_slots')
        .select('round_id, bane, par, user_id, guest_id')
        .inFilter('round_id', [for (final r in runder) r['id'] as String])
        as List);

    final navne = {
      for (final s in (await hentDeltagere(training)).spillere) s.id: s
    };

    final ud = <SpillerRunde>[];
    for (final r in runder) {
      final rid = r['id'] as String;
      final mine = slots.where((s) => s['round_id'] == rid).toList();
      final min = mine.firstWhere((s) => s['user_id'] == uid,
          orElse: () => const <String, dynamic>{});

      // Ikke med i runden overhovedet — hverken på bane eller bænk.
      if (min.isEmpty) continue;

      final bane = (min['bane'] as num?)?.toInt();
      final par = (min['par'] as num?)?.toInt();
      final nr = (r['nr'] as num).toInt();
      final slut = r['slutter_at'] == null
          ? null
          : DateTime.parse(r['slutter_at'] as String).toLocal();

      if (bane == null) {
        ud.add(SpillerRunde(nr: nr, slutterAt: slut));
        continue;
      }

      TavleSpiller? navnFor(Map<String, dynamic> s) =>
          navne[(s['user_id'] ?? s['guest_id']) as String? ?? ''];

      final paaBanen = mine.where((s) => s['bane'] == bane);
      ud.add(SpillerRunde(
        nr: nr,
        bane: bane,
        slutterAt: slut,
        makker: paaBanen
            .where((s) => s['par'] == par && s['user_id'] != uid)
            .map(navnFor)
            .firstWhere((x) => x != null, orElse: () => null),
        modstandere: [
          for (final s in paaBanen.where((s) => s['par'] != par))
            if (navnFor(s) != null) navnFor(s)!
        ],
      ));
    }
    return ud;
  }

  /// Er der en tavle i gang for træningen? Bruges af genvejen i Oversigt.
  static Future<Map<String, int>> hentAktiveTavler(
      List<String> trainingIds) async {
    if (trainingIds.isEmpty) return const {};
    try {
      final rows = List<Map<String, dynamic>>.from(await supabase
          .from('training_rounds')
          .select('training_id, nr')
          .inFilter('training_id', trainingIds) as List);
      final ud = <String, int>{};
      for (final r in rows) {
        final t = r['training_id'] as String;
        final nr = (r['nr'] as num).toInt();
        if (nr > (ud[t] ?? 0)) ud[t] = nr;
      }
      return ud;
    } catch (_) {
      return const {};
    }
  }

  // ── Skrivning ──────────────────────────────────────────────────────────

  static Future<void> gemOpsaetning(
      String trainingId, TavleOpsaetning o) async {
    await supabase.from('training_boards').upsert({
      'training_id': trainingId,
      'tilstand': o.tilstand,
      'afvikling': o.afvikling,
      'minutter': o.minutter,
      'baner': o.baner,
      'brug_faste_par': o.brugFastePar,
      'oprettet_af': supabase.auth.currentUser?.id,
    });
  }

  /// Opretter en runde og skriver opstillingen. Returnerer runde-id'et.
  static Future<String> opretRunde({
    required String trainingId,
    required int nr,
    required Opstilling opstilling,
    DateTime? slutterAt,
  }) async {
    final runde = await supabase.from('training_rounds').insert({
      'training_id': trainingId,
      'nr': nr,
      'startet_at': DateTime.now().toUtc().toIso8601String(),
      'slutter_at': slutterAt?.toUtc().toIso8601String(),
    }).select('id').single();

    final rid = runde['id'] as String;
    await skrivOpstilling(rid, opstilling);
    return rid;
  }

  /// Skriver en runde om. Det eneste sted slots ændres.
  ///
  /// Slet-og-indsæt frem for at flytte enkeltrækker: en ombytning rører to
  /// rækker der begge har unikke nøgler på (round_id, user_id), og en
  /// delvis opdatering ville bryde dem undervejs. Fase 2 lægger det ind i
  /// én transaktion med versionstjek, så to trænere ikke kan overskrive
  /// hinanden ubemærket.
  /// @returns Den nye version af runden.
  static Future<int> skrivOpstilling(
    String roundId,
    Opstilling opstilling, {
    int? version,
  }) async {
    final raekker = opstilling
        .tilRaekker(roundId)
        .map((r) => {
              'bane': r['bane'],
              'par': r['par'],
              'laast': r['laast'],
              'user_id': r['user_id'],
              'guest_id': r['guest_id'],
            })
        .toList();
    final ny = await supabase.rpc('gem_runde', params: {
      'p_round_id': roundId,
      'p_slots': raekker,
      'p_version': version,
    });
    return (ny as num?)?.toInt() ?? 1;
  }

  /// Slår en stjernemarkering til eller fra. Returnerer den nye tilstand.
  static Future<bool> saetKemi(String a, String b, bool paa) async {
    final lav = a.compareTo(b) < 0 ? a : b;
    final hoej = a.compareTo(b) < 0 ? b : a;
    if (paa) {
      await supabase.from('par_kemi').upsert({
        'spiller_lav': lav,
        'spiller_hoej': hoej,
        'markeret_af': supabase.auth.currentUser?.id,
      });
    } else {
      await supabase
          .from('par_kemi')
          .delete()
          .eq('spiller_lav', lav)
          .eq('spiller_hoej', hoej);
    }
    CacheService.glem(_kemiNoegle);
    return paa;
  }
}
