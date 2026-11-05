// Auto-split (del af biblioteket padel_app)
part of '../main.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Tavlens datamodel
//
// Én opstilling, én sandhed. Før lå baner og par som private klasser inde i
// skærmen, og hver handling — byt, lås, ny runde — skrev selv sine rækker til
// databasen ud fra den tilstand den tilfældigvis kendte. Det var dér
// synkroniseringsfejlene opstod: to veje til den samme skrivning kunne nå at
// være uenige.
//
// Her ejer [Opstilling] hele billedet, og ALLE skrivninger går gennem
// [Opstilling.tilRaekker]. Modellen er uforanderlig: hver handling giver en ny
// opstilling frem for at rette i den gamle. Så kan en halvfærdig ændring ikke
// blive stående, og UI'et kan ikke komme til at tegne noget andet end det der
// bliver gemt.
// ─────────────────────────────────────────────────────────────────────────────

/// En spiller på tavlen.
///
/// Afløsere uden profil har [erGaest]. De kan hverken stjernemarkeres eller
/// tælles med i par-overblikket — der er ingen bruger at knytte det til.
class TavleSpiller {
  final String id;
  final String navn;

  /// Foretrukken banehalvdel: `venstre`, `hoejre`, `begge` eller null.
  final String? side;
  final bool erGaest;

  const TavleSpiller({
    required this.id,
    required this.navn,
    this.side,
    this.erGaest = false,
  });

  @override
  bool operator ==(Object other) => other is TavleSpiller && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// Et par på en bane. Står med én spiller hvis antallet ikke går op.
///
/// [laast] betyder at parret bliver stående når resten blandes. Låsen hører
/// til parret, ikke til en sideløbende liste over koordinater — det var den
/// gamle `Set<String> _laaste`, og den kunne komme ud af trit med banerne når
/// de blev nummereret om.
class TavlePar {
  final List<TavleSpiller> spillere;
  final bool laast;

  const TavlePar(this.spillere, {this.laast = false});

  const TavlePar.tom() : spillere = const [], laast = false;

  bool get erTom => spillere.isEmpty;
  bool get erHelt => spillere.length == 2;

  TavlePar medLaas(bool v) => TavlePar(spillere, laast: v);

  /// Nøglen til par-historik og stjerner. Sorteret, så (A,B) og (B,A) er
  /// samme par — præcis som `par_kemi` gemmer dem i databasen.
  String? get noegle => erHelt
      ? parNoegle(spillere[0].id, spillere[1].id)
      : null;
}

/// En bane med to par der spiller mod hinanden.
class TavleBane {
  final int nr;
  final TavlePar par1;
  final TavlePar par2;

  const TavleBane(this.nr, this.par1, this.par2);

  Iterable<TavleSpiller> get alle => [...par1.spillere, ...par2.spillere];

  bool get erTom => par1.erTom && par2.erTom;

  /// Hele banen er låst når begge par er det.
  bool get laast => par1.laast && par2.laast;

  TavleBane medPar(int nr, TavlePar p) =>
      TavleBane(this.nr, nr == 1 ? p : par1, nr == 2 ? p : par2);
}

/// Hele runden: banerne og dem der sidder over.
///
/// Bænken er med i modellen fra nu af, men fyldes først når baner og par må
/// være tomme i databasen (fase 2). Indtil da er den altid tom, og
/// [tilRaekker] skriver derfor ingen bænkrækker.
class Opstilling {
  final List<TavleBane> baner;
  final List<TavleSpiller> baenk;

  const Opstilling({this.baner = const [], this.baenk = const []});

  const Opstilling.tom() : baner = const [], baenk = const [];

  bool get erTom => baner.isEmpty && baenk.isEmpty;

  Iterable<TavleSpiller> get alle =>
      [for (final b in baner) ...b.alle, ...baenk];

  Iterable<TavlePar> get parrene =>
      [for (final b in baner) ...[b.par1, b.par2]].where((p) => !p.erTom);

  /// Alle par der er låst, som spiller-lister. Bruges når næste runde dannes.
  List<List<TavleSpiller>> get laastePar =>
      [for (final p in parrene) if (p.laast) p.spillere];

  Opstilling medBaner(List<TavleBane> nye) =>
      Opstilling(baner: nye, baenk: baenk);

  /// Bytter to spillere om, uanset hvor de står — også hvis den ene sidder
  /// over. Hele opstillingen bygges om, så der ikke kan blive en halv
  /// ombytning tilbage nogen steder.
  Opstilling byt(TavleSpiller a, TavleSpiller b) {
    if (a.id == b.id) return this;
    TavleSpiller skift(TavleSpiller s) =>
        s.id == a.id ? b : (s.id == b.id ? a : s);
    TavlePar skiftPar(TavlePar p) =>
        TavlePar([for (final s in p.spillere) skift(s)], laast: p.laast);
    return Opstilling(
      baner: [
        for (final bane in baner)
          TavleBane(bane.nr, skiftPar(bane.par1), skiftPar(bane.par2))
      ],
      baenk: [for (final s in baenk) skift(s)],
    );
  }

  /// Slår låsen til eller fra på ét par.
  Opstilling medLaas(int baneNr, int parNr, bool laast) => Opstilling(
        baner: [
          for (final b in baner)
            if (b.nr != baneNr)
              b
            else
              b.medPar(parNr,
                  (parNr == 1 ? b.par1 : b.par2).medLaas(laast))
        ],
        baenk: baenk,
      );

  /// Slår låsen til eller fra på begge par på en bane.
  Opstilling medBaneLaas(int baneNr, bool laast) => Opstilling(
        baner: [
          for (final b in baner)
            if (b.nr != baneNr)
              b
            else
              TavleBane(b.nr, b.par1.medLaas(laast), b.par2.medLaas(laast))
        ],
        baenk: baenk,
      );

  /// Rækkerne til `training_round_slots`. Det ENESTE sted opstillingen
  /// oversættes til database — alle skrivninger går herigennem.
  List<Map<String, dynamic>> tilRaekker(String roundId) {
    Map<String, dynamic> raekke(TavleSpiller s,
            {int? bane, int? par, bool laast = false}) =>
        {
          'round_id': roundId,
          'bane': bane,
          'par': par,
          'laast': laast,
          if (s.erGaest) 'guest_id': s.id else 'user_id': s.id,
        };

    return [
      for (final b in baner)
        for (final (i, p) in [b.par1, b.par2].indexed)
          for (final s in p.spillere)
            raekke(s, bane: b.nr, par: i + 1, laast: p.laast),
      // Bænken får bane og par som null. Databasen tillader det først fra
      // fase 2, og indtil da er listen altid tom.
      for (final s in baenk) raekke(s),
    ];
  }

  /// Bygger en opstilling fra databasens rækker.
  ///
  /// [kendte] er spillerne skærmen allerede har. Rækker der peger på nogen
  /// der ikke er med — en afmeldt spiller fra en tidligere runde — springes
  /// over frem for at tegne et tomt navn.
  static Opstilling fraRaekker(
    List<Map<String, dynamic>> rows,
    Map<String, TavleSpiller> kendte,
  ) {
    final baner = <int, Map<int, List<TavleSpiller>>>{};
    final laast = <String, bool>{};
    final baenk = <TavleSpiller>[];

    for (final r in rows) {
      final id = (r['user_id'] ?? r['guest_id']) as String?;
      final sp = id == null ? null : kendte[id];
      if (sp == null) continue;

      final b = (r['bane'] as num?)?.toInt();
      final p = (r['par'] as num?)?.toInt();
      if (b == null || p == null) {
        baenk.add(sp);
        continue;
      }
      ((baner[b] ??= {})[p] ??= []).add(sp);
      if (r['laast'] == true) laast['$b-$p'] = true;
    }

    return Opstilling(
      baner: [
        for (final nr in baner.keys.toList()..sort())
          TavleBane(
            nr,
            TavlePar(baner[nr]?[1] ?? const [],
                laast: laast['$nr-1'] ?? false),
            TavlePar(baner[nr]?[2] ?? const [],
                laast: laast['$nr-2'] ?? false),
          )
      ],
      baenk: baenk,
    );
  }
}

/// Sorteret nøgle for et par. Samme regel som `par_kemi` og `par_overblik`
/// bruger i databasen: den laveste id først, så (A,B) og (B,A) er ét par.
String parNoegle(String a, String b) =>
    a.compareTo(b) < 0 ? '$a|$b' : '$b|$a';
