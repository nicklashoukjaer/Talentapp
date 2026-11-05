// Auto-split (del af biblioteket padel_app)
part of '../main.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Fordelingen
//
// Den gamle fordeling var grådig og kendte kun ét signal: sæt en venstre-
// spiller sammen med en højrespiller. Stjernen og spillernes egne
// makkervalg blev indsamlet og vist, men indgik aldrig i beslutningen.
//
// Her gives hvert muligt par en karakter, og de bedste par vælges først.
// Så kan flere hensyn veje mod hinanden i stedet for at det første hensyn
// afgør alt. Vægtene står samlet i [Vaegte] og kan justeres uden at røre
// logikken.
//
// Faste par er ikke en vægt men en binding: de dannes før alt andet og
// kan ikke brydes.
// ─────────────────────────────────────────────────────────────────────────────

/// Vægtene i fordelingen. Ét sted, så de kan skrues på uden at lede.
class Vaegte {
  /// Træneren har stjernemarkeret parret.
  static const kemi = 40;

  /// Spilleren har selv valgt den anden som første eller anden makker.
  static const favorit1 = 30;
  static const favorit2 = 20;

  /// Begge har valgt hinanden. Lægges oven i den bedste af de to
  /// ovenstående — ikke oven i begge, ellers ville et gensidigt
  /// førstevalg alene veje tungere end alt andet tilsammen.
  static const gensidig = 15;

  /// Én venstre- og én højrespiller.
  static const sidePasser = 25;

  /// To der begge vil stå i samme side.
  static const sideKolliderer = -20;

  /// Har allerede spillet sammen i DAG. Vejer tungere end stjernen, så et
  /// stjernepar ikke får hinanden to runder i træk.
  static const sammenIDag = -60;

  /// Har spillet sammen før, pr. gang — med et loft, så en gammel makker
  /// ikke bliver umulig for evigt.
  static const sammenFoer = -5;
  static const sammenFoerLoft = -25;
}

/// Alt fordelingen skal vide. Samlet i ét objekt, så funktionen kan prøves
/// af uden en database og uden en skærm.
class FordelingsInput {
  final List<TavleSpiller> spillere;

  /// Antal baner der er til rådighed. Styrer hvor mange der kan spille —
  /// resten sidder over. Feltet fandtes før, men blev ikke brugt.
  final int baner;

  /// `mixet` eller `opdelt` (hold for sig).
  final String tilstand;
  final Map<String, String> holdAf;

  /// Faste par som sorterede nøgler. Bindende.
  final Set<String> fastePar;

  /// Stjernemarkerede par.
  final Set<String> kemi;

  /// uid → [førstevalg, andetvalg]. Tomme pladser udelades.
  final Map<String, List<String>> favoritter;

  /// Par der allerede har spillet sammen i dag.
  final Set<String> sammenIDag;

  /// Par → antal gange de har spillet sammen tidligere.
  final Map<String, int> historik;

  /// uid → runder spillet i denne træning. Styrer hvem der sidder over.
  final Map<String, int> runderSpillet;

  /// Par der skal blive stående præcis hvor de er.
  final List<List<TavleSpiller>> laaste;

  /// Modstanderpar man allerede har mødt i dag, som "parnøgle vs parnøgle".
  final Set<String> modtFoer;

  const FordelingsInput({
    required this.spillere,
    this.baner = 2,
    this.tilstand = 'mixet',
    this.holdAf = const {},
    this.fastePar = const {},
    this.kemi = const {},
    this.favoritter = const {},
    this.sammenIDag = const {},
    this.historik = const {},
    this.runderSpillet = const {},
    this.laaste = const [],
    this.modtFoer = const {},
  });
}

/// Resultatet: banerne og dem der sidder over.
Opstilling fordel(FordelingsInput ind) {
  final laasteIds = {
    for (final p in ind.laaste)
      for (final s in p) s.id
  };

  // ── 1. Hvem spiller, og hvem sidder over ──────────────────────────────
  //
  // Der er plads til fire pr. bane. Er der flere tilmeldte, prioriteres de
  // der har spillet færrest runder — så siddetiden fordeler sig af sig
  // selv over en træning.
  final plads = ind.baner * 4;
  final kandidater = ind.spillere.where((s) => !laasteIds.contains(s.id)).toList()
    ..shuffle()
    ..sort((a, b) => (ind.runderSpillet[a.id] ?? 0)
        .compareTo(ind.runderSpillet[b.id] ?? 0));

  final tilbage = plads - laasteIds.length;
  var spiller = kandidater.take(tilbage < 0 ? 0 : tilbage).toList();
  var baenk = kandidater.skip(spiller.length).toList();

  // Et fast par må ikke splittes af bænken: er den ene med og den anden
  // ikke, byttes der så de følges ad.
  (spiller, baenk) = _holdFastePraSamlet(spiller, baenk, ind.fastePar);

  // ── 2. Dan parrene ────────────────────────────────────────────────────
  final par = <List<TavleSpiller>>[...ind.laaste];
  final laasteSaet = {for (final p in ind.laaste) if (p.length == 2) _n(p)};

  for (final pulje in _puljer(spiller, ind)) {
    par.addAll(_parDan(pulje, ind, laasteSaet));
  }

  // ── 3. Fordel parrene på baner ────────────────────────────────────────
  return Opstilling(baner: _paaBaner(par, ind), baenk: baenk);
}

String _n(List<TavleSpiller> p) => parNoegle(p[0].id, p[1].id);

/// Sikrer at begge halvdele af et fast par enten spiller eller sidder over.
(List<TavleSpiller>, List<TavleSpiller>) _holdFastePraSamlet(
  List<TavleSpiller> spiller,
  List<TavleSpiller> baenk,
  Set<String> fastePar,
) {
  if (fastePar.isEmpty || baenk.isEmpty) return (spiller, baenk);

  final paaBane = {for (final s in spiller) s.id: s};
  final paaBaenk = {for (final s in baenk) s.id: s};

  for (final noegle in fastePar) {
    final dele = noegle.split('|');
    final a = dele[0], b = dele[1];
    final aInde = paaBane.containsKey(a), bInde = paaBane.containsKey(b);
    if (aInde == bInde) continue;

    final ude = aInde ? b : a;
    if (!paaBaenk.containsKey(ude)) continue; // slet ikke tilmeldt

    // Byt den splittede makker ind, og send en uparret spiller ud.
    final offer = paaBane.values.firstWhere(
      (s) => s.id != a && s.id != b && !_iFastPar(s.id, fastePar),
      orElse: () => const TavleSpiller(id: '', navn: ''),
    );
    if (offer.id.isEmpty) continue;

    paaBane.remove(offer.id);
    paaBane[ude] = paaBaenk.remove(ude)!;
    paaBaenk[offer.id] = offer;
  }
  return (paaBane.values.toList(), paaBaenk.values.toList());
}

bool _iFastPar(String id, Set<String> fastePar) =>
    fastePar.any((n) => n.split('|').contains(id));

/// Mixet = én pulje. Opdelt = én pulje pr. hold.
List<List<TavleSpiller>> _puljer(
    List<TavleSpiller> spillere, FordelingsInput ind) {
  if (ind.tilstand != 'opdelt') return [spillere];
  final efterHold = <String, List<TavleSpiller>>{};
  for (final s in spillere) {
    (efterHold[ind.holdAf[s.id] ?? 'Uden hold'] ??= []).add(s);
  }
  return efterHold.values.toList();
}

/// Karakteren for at sætte [a] og [b] sammen. Højere er bedre.
int parPoint(TavleSpiller a, TavleSpiller b, FordelingsInput ind) {
  final n = parNoegle(a.id, b.id);
  var p = 0;

  if (ind.kemi.contains(n)) p += Vaegte.kemi;

  // Favoritter: den bedste af de to retninger tæller, og et gensidigt
  // valg lægger et tillæg oveni.
  int favor(TavleSpiller x, TavleSpiller y) {
    final v = ind.favoritter[x.id] ?? const [];
    if (v.isNotEmpty && v[0] == y.id) return Vaegte.favorit1;
    if (v.length > 1 && v[1] == y.id) return Vaegte.favorit2;
    return 0;
  }

  final fa = favor(a, b), fb = favor(b, a);
  p += fa > fb ? fa : fb;
  if (fa > 0 && fb > 0) p += Vaegte.gensidig;

  // Banehalvdel. "begge" og ukendt kolliderer aldrig — de kan stå hvor
  // som helst, og skal ikke straffes for at være fleksible.
  const faste = {'venstre', 'hoejre'};
  if (faste.contains(a.side) && faste.contains(b.side)) {
    p += a.side == b.side ? Vaegte.sideKolliderer : Vaegte.sidePasser;
  }

  if (ind.sammenIDag.contains(n)) p += Vaegte.sammenIDag;

  final foer = (ind.historik[n] ?? 0) * Vaegte.sammenFoer;
  p += foer < Vaegte.sammenFoerLoft ? Vaegte.sammenFoerLoft : foer;

  return p;
}

/// Danner par i én pulje: bedste karakter først, derefter et forsøg på at
/// bytte sig til en bedre samlet sum.
List<List<TavleSpiller>> _parDan(
  List<TavleSpiller> pulje,
  FordelingsInput ind,
  Set<String> alleredeLaast,
) {
  final rest = [...pulje];
  final par = <List<TavleSpiller>>[];

  // Faste par først. De er bindende og skal ikke konkurrere på point.
  for (final noegle in ind.fastePar) {
    if (alleredeLaast.contains(noegle)) continue;
    final dele = noegle.split('|');
    final a = rest.indexWhere((s) => s.id == dele[0]);
    if (a < 0) continue;
    final b = rest.indexWhere((s) => s.id == dele[1]);
    // Kun hvis BEGGE er med. Er den ene ikke tilmeldt, indgår den anden
    // helt normalt i puljen — det var aftalen.
    if (b < 0) continue;
    final sa = rest[a], sb = rest[b];
    rest.removeWhere((s) => s.id == sa.id || s.id == sb.id);
    par.add([sa, sb]);
  }

  // Alle mulige par, bedste først.
  final muligheder = <({int point, TavleSpiller a, TavleSpiller b})>[];
  for (var i = 0; i < rest.length; i++) {
    for (var j = i + 1; j < rest.length; j++) {
      muligheder.add((
        point: parPoint(rest[i], rest[j], ind),
        a: rest[i],
        b: rest[j]
      ));
    }
  }
  muligheder.sort((x, y) => y.point.compareTo(x.point));

  final brugt = <String>{};
  final dannet = <List<TavleSpiller>>[];
  for (final m in muligheder) {
    if (brugt.contains(m.a.id) || brugt.contains(m.b.id)) continue;
    brugt..add(m.a.id)..add(m.b.id);
    dannet.add([m.a, m.b]);
  }

  // Grådigt er ikke altid bedst: to middelgode par kan slå ét glimrende
  // og ét dårligt. Prøv at bytte makkere to og to så længe det hæver
  // summen. Få spillere, få runder — det koster ingenting.
  _forbedr(dannet, ind);

  par.addAll(dannet);

  // Den sidste uden makker, hvis antallet er ulige.
  final alene = rest.where((s) => !brugt.contains(s.id)).toList();
  for (final s in alene) {
    par.add([s]);
  }
  return par;
}

/// Bytter makkere to par ad gangen så længe det giver flere point.
void _forbedr(List<List<TavleSpiller>> par, FordelingsInput ind) {
  var bedret = true;
  var runder = 0;
  while (bedret && runder++ < 4) {
    bedret = false;
    for (var i = 0; i < par.length; i++) {
      for (var j = i + 1; j < par.length; j++) {
        if (par[i].length != 2 || par[j].length != 2) continue;
        final (a, b) = (par[i][0], par[i][1]);
        final (c, d) = (par[j][0], par[j][1]);
        final nu = parPoint(a, b, ind) + parPoint(c, d, ind);
        final v1 = parPoint(a, c, ind) + parPoint(b, d, ind);
        final v2 = parPoint(a, d, ind) + parPoint(b, c, ind);
        if (v1 > nu && v1 >= v2) {
          par[i] = [a, c];
          par[j] = [b, d];
          bedret = true;
        } else if (v2 > nu) {
          par[i] = [a, d];
          par[j] = [b, c];
          bedret = true;
        }
      }
    }
  }
}

/// Sætter parrene på baner, to ad gangen, og undgår at samme to par
/// mødes igen hvis det kan lade sig gøre.
List<TavleBane> _paaBaner(
    List<List<TavleSpiller>> par, FordelingsInput ind) {
  final rest = [...par];
  final ud = <TavleBane>[];
  final laasteSaet = {for (final p in ind.laaste) if (p.length == 2) _n(p)};

  var nr = 1;
  while (rest.isNotEmpty && nr <= ind.baner) {
    final a = rest.removeAt(0);
    if (rest.isEmpty) {
      ud.add(TavleBane(nr, TavlePar(a, laast: _erLaastPar(a, laasteSaet)),
          const TavlePar.tom()));
      break;
    }
    // Find en modstander man ikke lige har mødt.
    var idx = rest.indexWhere((b) =>
        a.length == 2 && b.length == 2 && !ind.modtFoer.contains(_vs(a, b)));
    if (idx < 0) idx = 0;
    final b = rest.removeAt(idx);
    ud.add(TavleBane(
      nr,
      TavlePar(a, laast: _erLaastPar(a, laasteSaet)),
      TavlePar(b, laast: _erLaastPar(b, laasteSaet)),
    ));
    nr++;
  }
  return ud;
}

bool _erLaastPar(List<TavleSpiller> p, Set<String> laaste) =>
    p.length == 2 && laaste.contains(_n(p));

/// Nøgle for "disse to par mødtes". Sorteret, så rækkefølgen er ligegyldig.
String _vs(List<TavleSpiller> a, List<TavleSpiller> b) {
  final na = _n(a), nb = _n(b);
  return na.compareTo(nb) < 0 ? '$na#$nb' : '$nb#$na';
}
