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

  const TavleOpsaetning({
    this.tilstand = 'mixet',
    this.afvikling = 'manuel',
    this.minutter = 15,
    this.baner = 2,
  });

  factory TavleOpsaetning.fraRaekke(Map<String, dynamic>? m) => m == null
      ? const TavleOpsaetning()
      : TavleOpsaetning(
          tilstand: m['tilstand'] as String? ?? 'mixet',
          afvikling: m['afvikling'] as String? ?? 'manuel',
          minutter: (m['minutter'] as num?)?.toInt() ?? 15,
          baner: (m['baner'] as num?)?.toInt() ?? 2,
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

  const TavleStart({
    required this.opsaetning,
    required this.rundeNr,
    required this.rundeId,
    required this.slutterAt,
    required this.kemi,
    required this.spilletSammen,
  });
}

/// Deltagerne til en træning, klar til tavlen.
class TavleDeltagere {
  final List<TavleSpiller> spillere;

  /// uid → holdnavn. Bruges af "Opdelt efter hold".
  final Map<String, String> holdAf;

  const TavleDeltagere(this.spillere, this.holdAf);
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
  static Future<TavleStart> hentStart(String trainingId) async {
    // Hver for sig: Future.wait over forskellige returtyper kan ikke udlede
    // en fælles type her.
    final board = await supabase
        .from('training_boards')
        .select()
        .eq('training_id', trainingId)
        .maybeSingle();

    final sidste = await supabase
        .from('training_rounds')
        .select('id, nr, slutter_at')
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
    );
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

  // ── Skrivning ──────────────────────────────────────────────────────────

  static Future<void> gemOpsaetning(
      String trainingId, TavleOpsaetning o) async {
    await supabase.from('training_boards').upsert({
      'training_id': trainingId,
      'tilstand': o.tilstand,
      'afvikling': o.afvikling,
      'minutter': o.minutter,
      'baner': o.baner,
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
  static Future<void> skrivOpstilling(
      String roundId, Opstilling opstilling) async {
    await supabase
        .from('training_round_slots')
        .delete()
        .eq('round_id', roundId);
    final raekker = opstilling.tilRaekker(roundId);
    if (raekker.isEmpty) return;
    await supabase.from('training_round_slots').insert(raekker);
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
