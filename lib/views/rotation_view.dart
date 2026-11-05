// Auto-split (del af biblioteket padel_app)
// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
part of '../main.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Roteringstavlen
//
// Træneren fordeler de tilmeldte på baner, kører runder, og kan bytte om på
// spillerne undervejs. Alt gemmes, så en runde kan genfindes bagefter og
// tælles med i par-overblikket.
//
// Genbruger appens egne byggesten: _sideInfo/_sideBadge til banehalvdelen,
// _InitialAvatar til spillerne og _fieldGroup til opsætningen.
// ─────────────────────────────────────────────────────────────────────────────

class RotationScreen extends StatefulWidget {
  final Map<String, dynamic> training;

  /// De tilmeldte, som begivenhedsdetaljen allerede har hentet. Sendes med,
  /// så tavlen ikke henter dem igen — og så den viser præcis dem man kigger
  /// på i forvejen.
  final List<TavleSpiller> spillere;

  /// uid → holdnavn. Bruges i "Opdelt efter hold"-tilstanden.
  final Map<String, String> holdAf;

  const RotationScreen({
    super.key,
    required this.training,
    required this.spillere,
    required this.holdAf,
  });

  @override
  State<RotationScreen> createState() => _RotationScreenState();
}

class _RotationScreenState extends State<RotationScreen> {
  String _tilstand = 'mixet';   // mixet | opdelt
  String _afvikling = 'manuel'; // manuel | timer
  int _minutter = 15;
  int _baner = 2;

  bool _loading = true;
  bool _busy = false;
  String? _error;

  int _rundeNr = 0;
  String? _rundeId;

  /// Hele den aktuelle runde — baner, par og låse ét sted. Låsen lå før i
  /// et sideløbende sæt af 'bane-par'-nøgler, der kunne komme ud af trit
  /// med banerne når de blev nummereret om.
  Opstilling _op = const Opstilling.tom();

  /// Par der allerede har spillet sammen i DENNE træning — bruges til at
  /// undgå gentagelser når næste runde dannes.
  Set<String> _spilletSammen = {};

  /// Stjernemarkerede par. Hentes for hele klubben, så en markering fra en
  /// tidligere træning også vises.
  Set<String> _kemi = {};

  Timer? _ur;
  Duration _tilbage = Duration.zero;

  String get _tid => widget.training['id'] as String;

  TavleOpsaetning get _nuvaerendeOpsaetning => TavleOpsaetning(
      tilstand: _tilstand,
      afvikling: _afvikling,
      minutter: _minutter,
      baner: _baner);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _ur?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    // Stjernerne fra cachen først, så tavlen tegner uden spinner.
    _kemi = TavleService.kemiFraCache();
    try {
      final start = await TavleService.hentStart(_tid);
      final op = start.rundeId == null
          ? const Opstilling.tom()
          : await TavleService.hentRunde(start.rundeId!, widget.spillere);
      if (!mounted) return;
      setState(() {
        _tilstand = start.opsaetning.tilstand;
        _afvikling = start.opsaetning.afvikling;
        _minutter = start.opsaetning.minutter;
        _baner = start.opsaetning.baner;
        _kemi = start.kemi;
        _spilletSammen = start.spilletSammen;
        _rundeNr = start.rundeNr;
        _rundeId = start.rundeId;
        _op = op;
        _loading = false;
      });
      if (start.slutterAt != null) _startUr(start.slutterAt);
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = e.toString(); });
    }
  }

  // ── Generering ───────────────────────────────────────────────────────────
  //
  // Prioriteringen er: sæt venstre sammen med højre, undgå par der allerede
  // har spillet sammen i dag, og fordel jævnt over banerne. Stjernen bruges
  // IKKE her — den er trænerens notat, ikke et input til fordelingen.

  /// Fordeler spillerne. [bevarLaaste] holder de låste par på deres plads og
  /// blander kun resten — det er det "Bland ulåste" gør, og det næste runde
  /// gør, så en træner kan fastlåse fx seks spillere og lade appen tage de
  /// øvrige ti hver gang.
  List<TavleBane> _generer({bool bevarLaaste = true}) {
    final fastholdt = <int, Map<int, List<TavleSpiller>>>{};
    final bundne = <String>{};
    if (bevarLaaste) {
      for (final b in _op.baner) {
        for (final (i, p) in [b.par1, b.par2].indexed) {
          if (!p.laast || p.erTom) continue;
          (fastholdt[b.nr] ??= {})[i + 1] = [...p.spillere];
          bundne.addAll(p.spillere.map((s) => s.id));
        }
      }
    }
    final frie =
        widget.spillere.where((s) => !bundne.contains(s.id)).toList();
    return _fordel(frie, fastholdt);
  }

  List<TavleBane> _fordel(List<TavleSpiller> frie,
      Map<int, Map<int, List<TavleSpiller>>> fastholdt) {
    final puljer = <List<TavleSpiller>>[];
    if (_tilstand == 'opdelt') {
      final efterHold = <String, List<TavleSpiller>>{};
      for (final s in frie) {
        (efterHold[widget.holdAf[s.id] ?? 'Uden hold'] ??= []).add(s);
      }
      puljer.addAll(efterHold.values);
    } else {
      puljer.add([...frie]);
    }

    final ud = <TavleBane>[];
    var baneNr = 1;
    for (final pulje in puljer) {
      final rest = [...pulje]..shuffle();
      // Venstre- og højrespillere hver for sig, så de kan parres på tværs.
      final venstre = rest.where((s) => s.side == 'venstre').toList();
      final hoejre = rest.where((s) => s.side == 'hoejre').toList();
      final resten = rest
          .where((s) => s.side != 'venstre' && s.side != 'hoejre')
          .toList();

      final par = <List<TavleSpiller>>[];
      while (venstre.isNotEmpty && hoejre.isNotEmpty) {
        final v = venstre.removeAt(0);
        // Vælg den højrespiller man IKKE allerede har spillet med i dag.
        var idx = hoejre.indexWhere(
            (h) => !_spilletSammen.contains(parNoegle(v.id, h.id)));
        if (idx < 0) idx = 0;
        par.add([v, hoejre.removeAt(idx)]);
      }
      // Dem der er tilbage (kun ét fortrukket ben, eller "begge"/ukendt)
      // parres to og to.
      final tilovers = [...venstre, ...hoejre, ...resten];
      while (tilovers.length >= 2) {
        final a = tilovers.removeAt(0);
        var idx = tilovers.indexWhere(
            (b) => !_spilletSammen.contains(parNoegle(a.id, b.id)));
        if (idx < 0) idx = 0;
        par.add([a, tilovers.removeAt(idx)]);
      }
      if (tilovers.isNotEmpty) par.add([tilovers.removeAt(0)]);

      for (var i = 0; i < par.length; i += 2) {
        ud.add(TavleBane(
          baneNr++,
          TavlePar(par[i]),
          TavlePar(i + 1 < par.length ? par[i + 1] : []),
        ));
      }
    }

    if (fastholdt.isEmpty) return ud;

    // De låste par skal stå præcis hvor de stod. De nye par fylder de
    // pladser der er tilbage, i rækkefølge.
    final nye = <List<TavleSpiller>>[
      for (final b in ud) ...[b.par1.spillere, b.par2.spillere]
    ]..removeWhere((p) => p.isEmpty);

    final maxBane = [
      ...fastholdt.keys,
      if (ud.isNotEmpty) ud.length,
    ].fold<int>(1, (a, b) => a > b ? a : b);

    final samlet = <TavleBane>[];
    var k = 0;
    for (var bane = 1; bane <= maxBane || nye.length > k; bane++) {
      final pladser = <List<TavleSpiller>>[];
      for (var par = 1; par <= 2; par++) {
        final laast = fastholdt[bane]?[par];
        if (laast != null) {
          pladser.add(laast);
        } else {
          pladser.add(k < nye.length ? nye[k++] : <TavleSpiller>[]);
        }
      }
      if (pladser[0].isEmpty && pladser[1].isEmpty) continue;
      // Et fastholdt par bliver ved med at være låst i den nye runde.
      samlet.add(TavleBane(
        bane,
        TavlePar(pladser[0], laast: fastholdt[bane]?[1] != null),
        TavlePar(pladser[1], laast: fastholdt[bane]?[2] != null),
      ));
    }
    return samlet;
  }

  Future<void> _nyRunde() async {
    if (widget.spillere.length < 2) {
      _snack(context, 'Der skal mindst være 2 tilmeldte', _gold);
      return;
    }
    setState(() => _busy = true);
    final ny = Opstilling(baner: _generer());
    try {
      await TavleService.gemOpsaetning(_tid, _nuvaerendeOpsaetning);

      final nr = _rundeNr + 1;
      final slut = _afvikling == 'timer'
          ? DateTime.now().add(Duration(minutes: _minutter))
          : null;
      final rid = await TavleService.opretRunde(
        trainingId: _tid,
        nr: nr,
        opstilling: ny,
        slutterAt: slut,
      );

      // Husk parrene, så næste runde undgår dem.
      for (final par in ny.parrene) {
        final n = par.noegle;
        if (n != null) _spilletSammen.add(n);
      }

      if (!mounted) return;
      setState(() {
        _rundeNr = nr;
        _rundeId = rid;
        _op = ny;
        _busy = false;
      });
      _startUr(slut);
    } on PostgrestException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _snack(context, e.message, _danger);
    }
  }

  void _startUr(DateTime? slut) {
    _ur?.cancel();
    if (slut == null) {
      setState(() => _tilbage = Duration.zero);
      return;
    }
    void tik() {
      final rest = slut.difference(DateTime.now());
      if (!mounted) return;
      setState(() => _tilbage = rest.isNegative ? Duration.zero : rest);
      if (rest.isNegative) _ur?.cancel();
    }
    tik();
    _ur = Timer.periodic(const Duration(seconds: 1), (_) => tik());
  }

  // ── Bytte om på spillere ─────────────────────────────────────────────────

  TavleSpiller? _valgt;

  Future<void> _byt(TavleSpiller a, TavleSpiller b) async {
    setState(() {
      _op = _op.byt(a, b);
      _valgt = null;
    });
    await _skrivRunde();
  }

  /// Genblander KUN de ulåste. Bruges når træneren har sat et par fast og
  /// vil have appen til at tage resten.
  Future<void> _blandUlaaste() async {
    if (_rundeId == null) return;
    final laaste = _op.laastePar.length;
    if (laaste > 0 && _op.baner.every((b) => b.laast)) {
      _snack(context, 'Alt er låst — lås noget op først', _gold);
      return;
    }
    setState(() {
      _op = _op.medBaner(_generer());
      _valgt = null;
    });
    await _skrivRunde();
  }

  /// Skriver den aktuelle opstilling. Går gennem modellens egen
  /// serialisering, så der kun findes ÉN oversættelse til databasen.
  Future<void> _skrivRunde() async {
    if (_rundeId == null) return;
    try {
      await TavleService.skrivOpstilling(_rundeId!, _op);
    } on PostgrestException catch (e) {
      if (mounted) _snack(context, e.message, _danger);
    }
  }

  Future<void> _toggleLaasPar(int bane, int par) async {
    final nu = _op.baner
        .firstWhere((b) => b.nr == bane,
            orElse: () => const TavleBane(0, TavlePar.tom(), TavlePar.tom()));
    final laast = par == 1 ? nu.par1.laast : nu.par2.laast;
    setState(() => _op = _op.medLaas(bane, par, !laast));
    await _skrivRunde();
  }

  Future<void> _toggleLaasBane(TavleBane b) async {
    setState(() => _op = _op.medBaneLaas(b.nr, !b.laast));
    await _skrivRunde();
  }

  Future<void> _toggleKemi(TavlePar par) async {
    if (!par.erHelt) return;
    final a = par.spillere[0], b = par.spillere[1];
    if (a.erGaest || b.erGaest) {
      _snack(context, 'Afløsere uden profil kan ikke markeres', _gold);
      return;
    }
    final noegle = par.noegle!;
    final harNu = _kemi.contains(noegle);
    setState(() => harNu ? _kemi.remove(noegle) : _kemi.add(noegle));
    try {
      await TavleService.saetKemi(a.id, b.id, !harNu);
    } on PostgrestException catch (e) {
      if (!mounted) return;
      // Sæt tilbage — markeringen nåede aldrig databasen.
      setState(() => harNu ? _kemi.add(noegle) : _kemi.remove(noegle));
      _snack(context, e.message, _danger);
    }
  }

  // ── Visning ──────────────────────────────────────────────────────────────

  String _tidTekst(Duration d) {
    final m = d.inMinutes, sek = d.inSeconds % 60;
    return '$m:${sek.toString().padLeft(2, '0')}';
  }

  Widget _opsaetning() => _fieldGroup('OPSÆTNING', [
        Text('Tilstand', style: _body(size: 12.5, color: _textSecondary)),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: _valgKnap('🔀  Mixet', _tilstand == 'mixet',
              () => setState(() => _tilstand = 'mixet'))),
          const SizedBox(width: 8),
          Expanded(child: _valgKnap('🛡️  Opdelt', _tilstand == 'opdelt',
              () => setState(() => _tilstand = 'opdelt'))),
        ]),
        Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 16),
          child: Text(
              _tilstand == 'mixet'
                  ? 'Spillere blandes på tværs af begivenhedens hold'
                  : 'Der roteres kun internt på hvert hold',
              style: _body(size: 11.5, color: _textMuted)),
        ),
        Text('Afvikling', style: _body(size: 12.5, color: _textSecondary)),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: _valgKnap('Manuel', _afvikling == 'manuel',
              () => setState(() => _afvikling = 'manuel'))),
          const SizedBox(width: 8),
          Expanded(child: _valgKnap('Timer', _afvikling == 'timer',
              () => setState(() => _afvikling = 'timer'))),
        ]),
        if (_afvikling == 'timer') ...[
          const SizedBox(height: 12),
          Row(children: [
            Text('Rundelængde', style: _body(size: 12.5, color: _textSecondary)),
            const Spacer(),
            for (final m in [10, 15, 20, 25]) ...[
              const SizedBox(width: 6),
              _valgKnap('$m min', _minutter == m,
                  () => setState(() => _minutter = m), kompakt: true),
            ],
          ]),
        ],
      ]);

  Widget _valgKnap(String tekst, bool aktiv, VoidCallback onTap,
          {bool kompakt = false}) =>
      Material(
        color: aktiv ? _neon.withValues(alpha: 0.16) : _surfaceElevated,
        borderRadius: BorderRadius.circular(11),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(11),
          child: Container(
            padding: EdgeInsets.symmetric(
                horizontal: kompakt ? 11 : 14, vertical: kompakt ? 7 : 11),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: aktiv ? _neon : _borderSubtle),
            ),
            child: Text(tekst,
                style: _body(
                    size: kompakt ? 12 : 13.5,
                    weight: FontWeight.w700,
                    color: aktiv ? _neon : _textSecondary)),
          ),
        ),
      );

  /// Én spiller på banen. Tryk vælger; tryk på en anden bytter de to om.
  Widget _spillerBrik(TavleSpiller s) {
    final valgt = _valgt?.id == s.id;
    final info = _sideInfo(s.side);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: valgt ? _neon.withValues(alpha: 0.18) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: () {
            if (_valgt == null) {
              setState(() => _valgt = s);
            } else if (_valgt!.id == s.id) {
              setState(() => _valgt = null);
            } else {
              _byt(_valgt!, s);
            }
          },
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: valgt ? _neon : Colors.transparent),
            ),
            child: Row(children: [
              _InitialAvatar(navn: s.navn, size: 26),
              const SizedBox(width: 9),
              Expanded(
                child: Text(s.navn,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _body(size: 13, weight: FontWeight.w600)),
              ),
              Container(
                width: 19,
                height: 19,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: info.farve.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(info.kort,
                    style: _body(
                        size: 10.5,
                        weight: FontWeight.w800,
                        color: info.farve)),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _parBlok(TavleBane bane, int parNr, TavlePar par) {
    final kanMarkeres = par.spillere.length == 2 &&
        !par.spillere[0].erGaest && !par.spillere[1].erGaest;
    final markeret = kanMarkeres &&
        _kemi.contains(parNoegle(par.spillere[0].id, par.spillere[1].id));
    final laast = par.laast;
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 4, 4),
      decoration: BoxDecoration(
        color: laast ? _gold.withValues(alpha: 0.10) : _surfaceElevated,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: laast ? _gold.withValues(alpha: 0.55) : Colors.transparent),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final s in par.spillere) _spillerBrik(s),
          if (par.spillere.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text('—',
                  textAlign: TextAlign.center,
                  style: _body(size: 12, color: _textMuted)),
            ),
          // Lås og stjerne tegnes ALTID på et par med spillere, så det ikke
          // ligner at funktionerne mangler før de er taget i brug.
          if (par.spillere.isNotEmpty)
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              IconButton(
                onPressed: () => _toggleLaasPar(bane.nr, parNr),
                icon: Icon(laast ? Icons.lock : Icons.lock_open_outlined,
                    size: 18, color: laast ? _gold : _textMuted),
                visualDensity: VisualDensity.compact,
                tooltip: laast ? 'Lås parret op' : 'Lås parret fast',
              ),
              if (par.spillere.length == 2)
                IconButton(
                  onPressed: () => _toggleKemi(par),
                  icon: Icon(markeret ? Icons.star : Icons.star_border,
                      size: 19, color: markeret ? _gold : _textMuted),
                  visualDensity: VisualDensity.compact,
                  tooltip: markeret ? 'Fjern god kemi' : 'Markér god kemi',
                ),
            ]),
        ],
      ),
    );
  }

  Widget _baneKort(TavleBane b) => Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _surfaceDark,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _borderSubtle),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 10, left: 2),
              child: Row(children: [
                Expanded(
                  child: Text('BANE ${b.nr}',
                      style: _cond(size: 16, weight: FontWeight.w800)),
                ),
                TextButton.icon(
                  onPressed: () => _toggleLaasBane(b),
                  icon: Icon(
                      b.laast ? Icons.lock : Icons.lock_open_outlined,
                      size: 15),
                  label: Text(b.laast ? 'Banen er låst' : 'Lås banen'),
                  style: TextButton.styleFrom(
                    foregroundColor: b.laast ? _gold : _textMuted,
                    textStyle: _body(size: 12, weight: FontWeight.w700),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ]),
            ),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: _parBlok(b, 1, b.par1)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Text('mod',
                    style: _body(size: 11, color: _textMuted)),
              ),
              Expanded(child: _parBlok(b, 2, b.par2)),
            ]),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_rundeNr == 0 ? 'TAVLE' : 'RUNDE $_rundeNr'),
        actions: [
          if (_afvikling == 'timer' && _tilbage > Duration.zero)
            Padding(
              padding: const EdgeInsets.only(right: 14),
              child: Center(
                child: Text(_tidTekst(_tilbage),
                    style: _cond(
                        size: 20,
                        weight: FontWeight.w800,
                        color: _tilbage.inMinutes < 2 ? _danger : _neon)),
              ),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _ErrorView(error: _error!, onRetry: _load)
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                  children: [
                    Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 760),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (_rundeNr == 0) ...[
                              _opsaetning(),
                              const SizedBox(height: 18),
                              Text(
                                  '${widget.spillere.length} tilmeldte fordeles '
                                  'når du starter første runde',
                                  style: _body(
                                      size: 12.5, color: _textSecondary)),
                            ] else ...[
                              if (_valgt != null)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: Text(
                                      'Tryk på en anden spiller for at bytte '
                                      '${_valgt!.navn} om',
                                      style: _body(
                                          size: 12.5,
                                          weight: FontWeight.w600,
                                          color: _neon)),
                                ),
                              // Tegnes ALTID når en runde er i gang — også
                              // uden låse, hvor den bare blander alle.
                              Padding(
                                padding: const EdgeInsets.only(bottom: 14),
                                child: Row(children: [
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed:
                                          _busy ? null : _blandUlaaste,
                                      icon: const Icon(Icons.shuffle, size: 17),
                                      label: Text(_op.laastePar.isEmpty
                                          ? 'Bland alle'
                                          : 'Bland ulåste'),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: _neon,
                                        side: BorderSide(
                                            color: _neon.withValues(alpha: .5)),
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 12),
                                      ),
                                    ),
                                  ),
                                  if (_op.laastePar.isNotEmpty) ...[
                                    const SizedBox(width: 10),
                                    Row(children: [
                                      const Icon(Icons.lock,
                                          size: 14, color: _gold),
                                      const SizedBox(width: 5),
                                      Text('${_op.laastePar.length} låst',
                                          style: _body(
                                              size: 12,
                                              weight: FontWeight.w700,
                                              color: _gold)),
                                    ]),
                                  ],
                                ]),
                              ),
                              for (final b in _op.baner) _baneKort(b),
                              if (_op.baner.isEmpty)
                                Text('Ingen baner i denne runde',
                                    style: _body(
                                        size: 12.5, color: _textSecondary)),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
      floatingActionButton: _loading
          ? null
          : FloatingActionButton.extended(
              onPressed: _busy ? null : _nyRunde,
              backgroundColor: _neon,
              icon: Icon(_rundeNr == 0 ? Icons.play_arrow : Icons.skip_next),
              label: Text(_rundeNr == 0 ? 'Start runde 1' : 'Næste runde'),
            ),
    );
  }
}
