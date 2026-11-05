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

  /// Alle runder på tavlen, i rækkefølge. Træneren kan forberede flere
  /// før træningen og klikke frem og tilbage mellem dem.
  List<TavleRunde> _runder = [];

  /// Hvilken runde man KIGGER på i tavlen.
  int _valgt = 0;

  /// Hvilken runde der AFVIKLES — den spillerne ser. Ikke nødvendigvis
  /// den man kigger på: træneren kan forberede runde 3 mens holdet
  /// stadig spiller runde 1.
  int _aktivNr = 0;

  /// Hvor mange runder "Generér alle runder" laver.
  int _antalRunder = 2;

  TavleRunde? get _runde =>
      (_valgt >= 0 && _valgt < _runder.length) ? _runder[_valgt] : null;

  int get _rundeNr => _runde?.nr ?? 0;
  String? get _rundeId => _runde?.id;

  /// Opstillingen for den runde man kigger på.
  Opstilling get _op => _runde?.opstilling ?? const Opstilling.tom();

  set _op(Opstilling v) {
    final r = _runde;
    if (r == null) return;
    _runder[_valgt] = r.medOpstilling(v);
  }

  /// Par der allerede har spillet sammen i DENNE træning — bruges til at
  /// undgå gentagelser når næste runde dannes.
  Set<String> _spilletSammen = {};

  /// Stjernemarkerede par. Hentes for hele klubben, så en markering fra en
  /// tidligere træning også vises.
  Set<String> _kemi = {};

  /// Faste par for begivenhedens hold. Bindende — kan ikke splittes.
  Set<String> _fastePar = {};

  /// Skal de faste par bruges i dag? Gemmes på tavlen, så valget
  /// overlever at skærmen lukkes midt i en træning.
  bool _brugFastePar = true;

  /// Spillernes egne makkervalg.
  Map<String, List<String>> _favoritter = const {};

  /// Hvor ofte par har spillet sammen tidligere.
  Map<String, int> _historik = const {};

  /// Runder spillet i denne træning. Styrer hvem der sidder over.
  Map<String, int> _runderSpillet = const {};

  /// Modstanderpar der allerede er mødtes i dag.
  Set<String> _modtFoer = {};


  Timer? _ur;
  Duration _tilbage = Duration.zero;

  String get _tid => widget.training['id'] as String;

  /// Hvor mange der faktisk kommer på banen. Samme regnestykke som
  /// fordelingen: fire pr. bane, rundet NED til hele baner — elleve
  /// spillere på tre baner giver otte på banen, ikke elleve.
  int get _paaBaneNu {
    final plads = _baner * 4;
    final hele = (widget.spillere.length ~/ 4) * 4;
    return plads < hele ? plads : hele;
  }

  int get _overNu => widget.spillere.length - _paaBaneNu;

  String get _fordelingsTekst => _overNu > 0
      ? '$_paaBaneNu på banen · $_overNu sidder over pr. runde'
      : '$_paaBaneNu på banen · alle er med';

  TavleOpsaetning get _nuvaerendeOpsaetning => TavleOpsaetning(
      tilstand: _tilstand,
      afvikling: _afvikling,
      minutter: _minutter,
      baner: _baner,
      brugFastePar: _brugFastePar);

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
      final start = await TavleService.hentStart(
        _tid,
        gruppeIds: _trainingGroupIds(widget.training),
        deltagere: widget.spillere,
      );
      final runder =
          await TavleService.hentAlleRunder(_tid, widget.spillere);
      if (!mounted) return;

      // Hvilken runde afvikles? Gemt valg, ellers den højeste — som før.
      final aktiv = start.opsaetning.aktivRunde ??
          (runder.isEmpty ? 0 : runder.last.nr);
      var valgt = runder.indexWhere((r) => r.nr == aktiv);
      if (valgt < 0) valgt = runder.isEmpty ? 0 : runder.length - 1;

      setState(() {
        _tilstand = start.opsaetning.tilstand;
        _afvikling = start.opsaetning.afvikling;
        _minutter = start.opsaetning.minutter;
        // Uden en gemt opsætning gættes antallet ud fra de tilmeldte, så
        // ingen havner på bænken bare fordi standarden var to baner.
        _baner = start.harOpsaetning
            ? start.opsaetning.baner
            : ((widget.spillere.length + 3) ~/ 4).clamp(1, 6);
        _kemi = start.kemi;
        _spilletSammen = start.spilletSammen;
        _fastePar = start.fastePar;
        _brugFastePar = start.opsaetning.brugFastePar;
        _favoritter = start.favoritter;
        _historik = start.historik;
        _runderSpillet = start.runderSpillet;
        _modtFoer = start.modtFoer;
        _runder = runder;
        _valgt = valgt;
        _aktivNr = aktiv;
        _loading = false;
      });
      final r = _runde;
      if (r?.slutterAt != null && r!.nr == _aktivNr) _startUr(r.slutterAt);
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = e.toString(); });
    }
  }

  // ── Generering ───────────────────────────────────────────────────────────
  //
  // Selve fordelingen ligger i tavle_fordeling.dart. Den kender hverken
  // database eller skærm og kan derfor prøves af for sig.

  /// Henter de faste par forfra fra databasen.
  ///
  /// Kaldes lige inden en runde dannes. Træneren kan have oprettet eller
  /// fjernet en konstellation fra en anden skærm — eller slået kontakten
  /// til igen midt i træningen — og så skal den næste runde bruge det der
  /// står NU, ikke det der stod da tavlen blev åbnet.
  Future<void> _genhentFastePar() async {
    final gids = _trainingGroupIds(widget.training);
    if (gids.isEmpty) return;
    try {
      final friske = await TavleService.hentFastePar(gids);
      if (!mounted) return;
      setState(() => _fastePar = friske);
    } catch (_) {
      // Et mislykket opslag må ikke spærre for at køre videre; så
      // bruges de par tavlen allerede kender.
    }
  }

  /// Danner en ny opstilling. [bevarLaaste] holder de låste par på plads
  /// og fordeler kun resten.
  /// Grundlaget for fordelingen. Ét sted, så en enkelt runde og en hel
  /// serie bygger på præcis de samme forudsætninger.
  FordelingsInput _fordelingsInput({bool bevarLaaste = true}) =>
      FordelingsInput(
          spillere: widget.spillere,
          baner: _baner,
          tilstand: _tilstand,
          holdAf: widget.holdAf,
          fastePar: _brugFastePar ? _fastePar : const {},
          kemi: _kemi,
          favoritter: _favoritter,
          sammenIDag: _spilletSammen,
          historik: _historik,
          runderSpillet: _runderSpillet,
          laaste: bevarLaaste ? _op.laastePar : const [],
        modtFoer: _modtFoer,
      );

  Opstilling _genererOpstilling({bool bevarLaaste = true}) =>
      fordel(_fordelingsInput(bevarLaaste: bevarLaaste));

  /// Genererer [antal] runder på én gang og gemmer dem.
  ///
  /// Hele pointen med at gøre det samlet: runde 2 kender runde 1. Lavede
  /// man dem enkeltvis på forhånd, ville de alle tage udgangspunkt i en
  /// tom dag og kunne finde på det samme hver gang.
  Future<void> _genererRunder(int antal) async {
    if (widget.spillere.length < 4) {
      _snack(context, 'Der skal mindst være 4 tilmeldte', _gold);
      return;
    }
    setState(() => _busy = true);
    if (_brugFastePar) await _genhentFastePar();
    if (!mounted) return;

    final opstillinger = fordelFlere(_fordelingsInput(), antal);
    try {
      await TavleService.gemOpsaetning(_tid, _nuvaerendeOpsaetning);
      final foerste = _runder.isEmpty ? 1 : _runder.last.nr + 1;
      final nye = await TavleService.opretFlereRunder(
        trainingId: _tid,
        foersteNr: foerste,
        opstillinger: opstillinger,
      );
      if (nye.isEmpty) {
        if (mounted) setState(() => _busy = false);
        return;
      }

      // Første gang sættes uret og tavlen peger på runde 1. Tilføjer man
      // flere runder senere, rører vi IKKE den der spilles lige nu.
      final foerstegang = _runder.isEmpty;
      DateTime? slut;
      if (foerstegang) {
        slut = await TavleService.startRunde(
            nye.first.id, _afvikling == 'timer' ? _minutter : null);
        await TavleService.saetAktivRunde(_tid, nye.first.nr);
      }
      if (!mounted) return;
      setState(() {
        _runder = [..._runder, ...nye];
        if (foerstegang) {
          _valgt = 0;
          _aktivNr = nye.first.nr;
        }
        _busy = false;
      });
      _opdaterEfterRunder(opstillinger);
      if (slut != null) _startUr(slut);
    } on PostgrestException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _snack(context, e.message, _danger);
    }
  }

  /// Fører straf og bænk-rotation videre efter at runder er dannet.
  void _opdaterEfterRunder(List<Opstilling> nye) {
    for (final op in nye) {
      for (final par in op.parrene) {
        final n = par.noegle;
        if (n != null) _spilletSammen.add(n);
      }
      for (final b in op.baner) {
        final n1 = b.par1.noegle, n2 = b.par2.noegle;
        if (n1 != null && n2 != null) {
          _modtFoer.add(n1.compareTo(n2) < 0 ? '$n1#$n2' : '$n2#$n1');
        }
        for (final sp in b.alle) {
          _runderSpillet[sp.id] = (_runderSpillet[sp.id] ?? 0) + 1;
        }
      }
    }
  }

  /// Skifter til en runde. Er den allerede forberedt, SLETTES intet — der
  /// skiftes bare visning, og spillerne følger med.
  Future<void> _skiftTil(int idx, {bool goerAktiv = false}) async {
    if (idx < 0 || idx >= _runder.length) return;
    setState(() {
      _valgt = idx;
      _valgtSpiller = null;
    });
    if (!goerAktiv) return;

    final r = _runder[idx];
    setState(() => _aktivNr = r.nr);
    try {
      await TavleService.saetAktivRunde(_tid, r.nr);
      final slut = await TavleService.startRunde(
          r.id, _afvikling == 'timer' ? _minutter : null);
      if (mounted) _startUr(slut);
    } on PostgrestException catch (e) {
      if (mounted) _snack(context, e.message, _danger);
    }
  }

  /// "Næste runde": skift til den næste forberedte, eller lav én mere.
  Future<void> _naesteRunde() async {
    if (_runder.isEmpty) {
      await _genererRunder(_antalRunder);
      return;
    }
    final naeste = _runder.indexWhere((r) => r.nr > _aktivNr);
    if (naeste >= 0) {
      await _skiftTil(naeste, goerAktiv: true);
      return;
    }
    // Ingen forberedt runde tilbage — lav én.
    await _genererRunder(1);
    if (mounted && _runder.isNotEmpty) {
      await _skiftTil(_runder.length - 1, goerAktiv: true);
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

  TavleSpiller? _valgtSpiller;

  Future<void> _byt(TavleSpiller a, TavleSpiller b) async {
    setState(() {
      _op = _op.byt(a, b);
      _valgtSpiller = null;
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
    if (_brugFastePar) await _genhentFastePar();
    if (!mounted) return;
    setState(() {
      _op = _genererOpstilling();
      _valgtSpiller = null;
    });
    await _skrivRunde();
  }

  /// Skriver den aktuelle opstilling. Går gennem modellens egen
  /// serialisering, så der kun findes ÉN oversættelse til databasen.
  Future<void> _skrivRunde() async {
    final r = _runde;
    if (r == null) return;
    try {
      // Hver runde har sin egen version, så en rettelse i runde 1 ikke
      // kan forveksles med en rettelse i runde 2.
      final ny = await TavleService.skrivOpstilling(r.id, r.opstilling,
          version: r.version);
      if (mounted) {
        setState(() => _runder[_valgt] = r.medOpstilling(r.opstilling,
            version: ny));
      }
    } on PostgrestException catch (e) {
      if (!mounted) return;
      // 40001 = en anden har ændret tavlen imens. Hent forfra frem for at
      // lade skærmen vise noget andet end databasen.
      if (e.code == '40001') {
        _snack(context, 'Tavlen blev ændret af en anden — henter forfra',
            _gold);
        await _load();
      } else {
        _snack(context, e.message, _danger);
      }
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
        Text('Antal baner', style: _body(size: 12.5, color: _textSecondary)),
        const SizedBox(height: 8),
        Row(children: [
          for (final n in [1, 2, 3, 4, 5]) ...[
            if (n > 1) const SizedBox(width: 6),
            Expanded(
              child: _valgKnap('$n', _baner == n,
                  () => setState(() => _baner = n), kompakt: true),
            ),
          ],
        ]),
        Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 16),
          child: Text(_fordelingsTekst,
              style: _body(size: 11.5, color: _textMuted)),
        ),
        Text('Runder der forberedes',
            style: _body(size: 12.5, color: _textSecondary)),
        const SizedBox(height: 8),
        Row(children: [
          for (final n in [1, 2, 3, 4]) ...[
            if (n > 1) const SizedBox(width: 6),
            Expanded(
              child: _valgKnap('$n', _antalRunder == n,
                  () => setState(() => _antalRunder = n), kompakt: true),
            ),
          ],
        ]),
        Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 16),
          child: Text(
              _antalRunder == 1
                  ? 'Én runde dannes nu. Du kan altid tilføje flere.'
                  : 'Alle $_antalRunder runder dannes på én gang. Runde 2 '
                      'kender runde 1, så ingen får samme makker to gange '
                      'i træk.',
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

  /// Gemmer opsætningen med det samme når en kontakt skiftes.
  ///
  /// Den ændrer IKKE den runde der kører — det ville flytte folk midt i
  /// et spil. Valget slår igennem ved næste "Bland" eller "Næste runde".
  Future<void> _gemOpsaetning() async {
    try {
      await TavleService.gemOpsaetning(_tid, _nuvaerendeOpsaetning);
    } on PostgrestException catch (e) {
      if (mounted) _snack(context, e.message, _danger);
    }
  }

  /// Rundevælgeren. Ét tryk pr. runde — træneren kan klikke frem og
  /// tilbage og rette i hver enkelt uden at noget slettes.
  ///
  /// Den runde der AFVIKLES er markeret med en prik; den man KIGGER på
  /// er fyldt. De to er ikke nødvendigvis den samme: man kan forberede
  /// runde 3 mens holdet spiller runde 1.
  Widget _rundeVaelger() {
    if (_runder.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          for (final (i, r) in _runder.indexed) ...[
            if (i > 0) const SizedBox(width: 8),
            GestureDetector(
              onTap: _busy ? null : () => _skiftTil(i),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 15, vertical: 9),
                decoration: BoxDecoration(
                  color: i == _valgt
                      ? _neon.withValues(alpha: 0.18)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                      color: i == _valgt ? _neon : _borderSubtle),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (r.nr == _aktivNr) ...[
                    Container(
                      width: 7,
                      height: 7,
                      decoration: const BoxDecoration(
                          color: _success, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 7),
                  ],
                  Text('Runde ${r.nr}',
                      style: _body(
                          size: 13,
                          weight: FontWeight.w700,
                          color: i == _valgt ? _textPrimary : _textSecondary)),
                ]),
              ),
            ),
          ],
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _busy ? null : () => _genererRunder(1),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: _borderSubtle),
              ),
              child: const Icon(Icons.add, size: 17, color: _textMuted),
            ),
          ),
        ]),
      ),
    );
  }

  /// Linjen der fortæller hvad man kigger på, når det ikke er den runde
  /// holdet spiller. Uden den kunne man komme til at rette i runde 3 og
  /// undre sig over at der ikke skete noget på banen.
  Widget _forberedtBesked() {
    final r = _runde;
    if (r == null || r.nr == _aktivNr) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: _gold.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _gold.withValues(alpha: 0.45)),
        ),
        child: Row(children: [
          const Icon(Icons.edit_calendar_outlined, size: 16, color: _gold),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
                r.nr > _aktivNr
                    ? 'Forberedt runde — holdet spiller runde $_aktivNr'
                    : 'Tidligere runde — holdet spiller runde $_aktivNr',
                style: _body(size: 12, weight: FontWeight.w600, color: _gold)),
          ),
          TextButton(
            onPressed: _busy ? null : () => _skiftTil(_valgt, goerAktiv: true),
            style: TextButton.styleFrom(
              foregroundColor: _gold,
              textStyle: _body(size: 12, weight: FontWeight.w700),
              visualDensity: VisualDensity.compact,
            ),
            child: const Text('Kør denne nu'),
          ),
        ]),
      ),
    );
  }

  /// Tilstandsknapperne mens en runde kører.
  ///
  /// Hele opsætningen blev før gemt væk så snart første runde var sat i
  /// gang, og så kunne man ikke skifte mellem mixet og opdelt uden at
  /// lukke tavlen. Her står det der hele vejen — kompakt, men fuldt
  /// betjenbart.
  Widget _kontrolStribe() {
    final harFaste = _fastePar.isNotEmpty;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 12),
      decoration: BoxDecoration(
        color: _surfaceDark,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Expanded(
              child: _valgKnap('🔀  Mixet', _tilstand == 'mixet', () {
                setState(() => _tilstand = 'mixet');
                unawaited(_gemOpsaetning());
              }, kompakt: true),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _valgKnap('🛡️  Opdelt', _tilstand == 'opdelt', () {
                setState(() => _tilstand = 'opdelt');
                unawaited(_gemOpsaetning());
              }, kompakt: true),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _valgKnap(
                  harFaste ? 'Faste par' : 'Ingen faste',
                  harFaste && _brugFastePar,
                  harFaste
                      ? () {
                          setState(() => _brugFastePar = !_brugFastePar);
                          unawaited(_gemOpsaetning());
                        }
                      : () => _snack(
                          context,
                          'Holdet har ingen faste par endnu — opret dem '
                          'før første runde',
                          _gold),
                  kompakt: true),
            ),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Text('Baner', style: _body(size: 11.5, color: _textMuted)),
            const SizedBox(width: 10),
            for (final n in [1, 2, 3, 4, 5]) ...[
              if (n > 1) const SizedBox(width: 6),
              Expanded(
                child: _valgKnap('$n', _baner == n, () {
                  setState(() => _baner = n);
                  unawaited(_gemOpsaetning());
                }, kompakt: true),
              ),
            ],
          ]),
          const SizedBox(height: 8),
          Text(
              '$_fordelingsTekst · '
              '${_tilstand == 'opdelt'
                  ? 'kun internt på hvert hold'
                  : 'blandet på tværs af holdene'}'
              ' · slår igennem ved næste runde',
              style: _body(size: 11, color: _textMuted)),
        ],
      ),
    );
  }

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
    final valgt = _valgtSpiller?.id == s.id;
    final info = _sideInfo(s.side);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: valgt ? _neon.withValues(alpha: 0.18) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: () {
            if (_valgtSpiller == null) {
              setState(() => _valgtSpiller = s);
            } else if (_valgtSpiller!.id == s.id) {
              setState(() => _valgtSpiller = null);
            } else {
              _byt(_valgtSpiller!, s);
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

  // ── Faste par ────────────────────────────────────────────────────────

  /// Navnet på et fast par, ud fra de tilmeldte.
  String _parTekst(String noegle) {
    final dele = noegle.split('|');
    String navn(String id) => widget.spillere
        .firstWhere((s) => s.id == id,
            orElse: () => TavleSpiller(id: id, navn: 'Ikke tilmeldt'))
        .navn;
    return '${navn(dele[0])} & ${navn(dele[1])}';
  }

  /// Er begge halvdele af parret tilmeldt i dag?
  bool _parErKlar(String noegle) {
    final ids = widget.spillere.map((s) => s.id).toSet();
    return noegle.split('|').every(ids.contains);
  }

  Widget _fastePartKort() {
    final gids = _trainingGroupIds(widget.training);
    return _fieldGroup('FASTE PAR', [
      Text(
          gids.isEmpty
              ? 'Begivenheden er ikke knyttet til et hold, så der kan '
                  'ikke sættes faste par op.'
              : 'Faste par holdes sammen når runderne dannes. Modstanderne '
                  'roteres frit. Er kun den ene tilmeldt, springes parret '
                  'over.',
          style: _body(size: 11.5, color: _textMuted)),
      if (gids.isNotEmpty) ...[
        if (_fastePar.isNotEmpty) ...[
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: Text('Brug dem i denne træning',
                  style: _body(size: 12.5, weight: FontWeight.w600)),
            ),
            Switch(
              value: _brugFastePar,
              activeThumbColor: _neon,
              onChanged: (v) {
                setState(() => _brugFastePar = v);
                unawaited(_gemOpsaetning());
              },
            ),
          ]),
        ],
        const SizedBox(height: 10),
        if (_fastePar.isEmpty)
          Text('Ingen faste par på holdet endnu',
              style: _body(size: 12.5, color: _textSecondary)),
        for (final n in _fastePar)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(children: [
              Icon(Icons.link,
                  size: 16, color: _parErKlar(n) ? _neon : _textMuted),
              const SizedBox(width: 9),
              Expanded(
                child: Text(_parTekst(n),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _body(
                        size: 13,
                        weight: FontWeight.w600,
                        color: _parErKlar(n) ? _textPrimary : _textMuted)),
              ),
              if (!_parErKlar(n))
                Text('springes over',
                    style: _body(size: 10.5, color: _textMuted)),
              IconButton(
                onPressed: () => _fjernFastPar(n),
                icon: const Icon(Icons.close, size: 17, color: _textMuted),
                visualDensity: VisualDensity.compact,
                tooltip: 'Fjern det faste par',
              ),
            ]),
          ),
        const SizedBox(height: 6),
        OutlinedButton.icon(
          onPressed: _busy ? null : _opretFastPar,
          icon: const Icon(Icons.add_link, size: 17),
          label: const Text('Opret fast par'),
          style: OutlinedButton.styleFrom(
            foregroundColor: _neon,
            side: BorderSide(color: _neon.withValues(alpha: .5)),
            padding: const EdgeInsets.symmetric(vertical: 12),
          ),
        ),
      ],
    ]);
  }

  Future<void> _opretFastPar() async {
    final gids = _trainingGroupIds(widget.training);
    if (gids.isEmpty) return;

    final a = await _vaelgSpiller('Vælg første spiller', const {});
    if (a == null || !mounted) return;
    final b = await _vaelgSpiller('Vælg makker', {a.id});
    if (b == null || !mounted) return;

    try {
      await TavleService.gemFastPar(gids.first, a.id, b.id);
      if (!mounted) return;
      setState(() => _fastePar = {..._fastePar, parNoegle(a.id, b.id)});
      _snack(context, '${a.navn} & ${b.navn} er nu et fast par', _success);
    } on PostgrestException catch (e) {
      if (mounted) _snack(context, e.message, _danger);
    }
  }

  Future<void> _fjernFastPar(String noegle) async {
    final gids = _trainingGroupIds(widget.training);
    if (gids.isEmpty) return;
    final dele = noegle.split('|');
    try {
      await TavleService.sletFastPar(gids.first, dele[0], dele[1]);
      if (!mounted) return;
      setState(() => _fastePar = {..._fastePar}..remove(noegle));
    } on PostgrestException catch (e) {
      if (mounted) _snack(context, e.message, _danger);
    }
  }

  /// Vælger blandt de tilmeldte. Afløsere uden profil kan ikke indgå i et
  /// fast par — der er ingen bruger at knytte det til.
  Future<TavleSpiller?> _vaelgSpiller(String titel, Set<String> undtagen) {
    final valg = widget.spillere
        .where((s) => !s.erGaest && !undtagen.contains(s.id))
        .toList()
      ..sort((x, y) => x.navn.compareTo(y.navn));
    return showModalBottomSheet<TavleSpiller>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => SafeArea(
        top: false,
        child: Container(
          margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          decoration: BoxDecoration(
            color: _surfaceDark,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _borderSubtle),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(titel.toUpperCase(),
                  style: _cond(size: 19, weight: FontWeight.w800)),
              const SizedBox(height: 10),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final s in valg)
                      ListTile(
                        onTap: () => Navigator.pop(ctx, s),
                        leading: _InitialAvatar(navn: s.navn, size: 30),
                        title: Text(s.navn,
                            style: _body(size: 14, weight: FontWeight.w600)),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
            ],
          ),
        ),
      ),
    );
  }

  /// Dem der sidder over i runden.
  ///
  /// De står på tavlen som alle andre — man kan bytte dem ind ved at
  /// trykke på en der spiller. Før endte den overskydende i et par med
  /// én mand, og så lignede det en fejl frem for en pause.
  Widget _baenkKort() => Container(
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
                const Icon(Icons.airline_seat_recline_normal,
                    size: 16, color: _textMuted),
                const SizedBox(width: 7),
                Text('SIDDER OVER',
                    style: _cond(
                        size: 16, weight: FontWeight.w800, color: _textMuted)),
                const Spacer(),
                Text('${_op.baenk.length}',
                    style: _cond(
                        size: 16, weight: FontWeight.w800, color: _textMuted)),
              ]),
            ),
            for (final sp in _op.baenk) _spillerBrik(sp),
          ],
        ),
      );

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
                              const SizedBox(height: 14),
                              _fastePartKort(),
                              const SizedBox(height: 18),
                              Text(
                                  '${widget.spillere.length} tilmeldte fordeles '
                                  'når du starter første runde',
                                  style: _body(
                                      size: 12.5, color: _textSecondary)),
                            ] else ...[
                              if (_valgtSpiller != null)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: Text(
                                      'Tryk på en anden spiller for at bytte '
                                      '${_valgtSpiller!.navn} om',
                                      style: _body(
                                          size: 12.5,
                                          weight: FontWeight.w600,
                                          color: _neon)),
                                ),
                              _rundeVaelger(),
                              _forberedtBesked(),
                              _kontrolStribe(),
                              // Faste par kan også oprettes og fjernes
                              // midt i en træning — ellers skulle man
                              // lukke tavlen for at rette en
                              // konstellation.
                              _fastePartKort(),
                              const SizedBox(height: 14),
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
                              if (_op.baenk.isNotEmpty) _baenkKort(),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
      floatingActionButton: _loading
          ? null
          : Builder(builder: (_) {
              final tom = _runder.isEmpty;
              // Er der en forberedt runde forude, SKIFTER knappen bare
              // til den. Først når der ikke er flere, laves en ny.
              final harForberedt = _runder.any((r) => r.nr > _aktivNr);
              return FloatingActionButton.extended(
                onPressed: _busy ? null : _naesteRunde,
                backgroundColor: _neon,
                icon: Icon(tom ? Icons.play_arrow : Icons.skip_next),
                label: Text(tom
                    ? 'Generér $_antalRunder runder'
                    : harForberedt
                        ? 'Kør næste runde'
                        : 'Ny runde'),
              );
            }),
    );
  }
}
