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

/// En spiller på tavlen. Afløsere uden profil har [erGaest] og kan hverken
/// stjernemarkeres eller tælles med i par-overblikket — der er ingen bruger
/// at knytte det til.
class _TavleSpiller {
  final String id;
  final String navn;
  final String? side;
  final bool erGaest;
  const _TavleSpiller({
    required this.id,
    required this.navn,
    this.side,
    this.erGaest = false,
  });
}

/// Et par på en bane. Kan stå med én spiller hvis antallet ikke går op.
class _TavlePar {
  final List<_TavleSpiller> spillere;
  _TavlePar(this.spillere);
}

/// En bane med to par.
class _TavleBane {
  final int nr;
  final _TavlePar par1;
  final _TavlePar par2;
  _TavleBane(this.nr, this.par1, this.par2);

  Iterable<_TavleSpiller> get alle => [...par1.spillere, ...par2.spillere];
}

class RotationScreen extends StatefulWidget {
  final Map<String, dynamic> training;

  /// De tilmeldte, som begivenhedsdetaljen allerede har hentet. Sendes med,
  /// så tavlen ikke henter dem igen — og så den viser præcis dem man kigger
  /// på i forvejen.
  final List<_TavleSpiller> spillere;

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
  List<_TavleBane> _baneListe = [];

  /// Par der allerede har spillet sammen i DENNE træning — bruges til at
  /// undgå gentagelser når næste runde dannes.
  final Set<String> _spilletSammen = {};

  /// Låste pladser i den aktuelle runde — nøgle 'bane-par'. Låste spillere
  /// bliver stående når resten blandes, og føres med over i næste runde.
  final Set<String> _laaste = {};

  /// Stjernemarkerede par (nøgle som _parNoegle). Hentes for hele klubben,
  /// så en markering fra en tidligere træning også vises.
  Set<String> _kemi = {};

  Timer? _ur;
  Duration _tilbage = Duration.zero;

  String get _tid => widget.training['id'] as String;

  static String _parNoegle(String a, String b) =>
      a.compareTo(b) < 0 ? '$a|$b' : '$b|$a';

  static String _laasNoegle(int bane, int par) => '$bane-$par';

  bool _erLaast(int bane, int par) =>
      _laaste.contains(_laasNoegle(bane, par));

  /// Er hele banen låst — altså begge par?
  bool _baneLaast(_TavleBane b) => _erLaast(b.nr, 1) && _erLaast(b.nr, 2);

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
    try {
      // Hentes hver for sig: Future.wait over forskellige returtyper kan
      // ikke udlede en fælles type her.
      final board = await supabase
          .from('training_boards').select().eq('training_id', _tid).maybeSingle();
      final sidste = await supabase
          .from('training_rounds').select('id, nr').eq('training_id', _tid)
          .order('nr', ascending: false).limit(1).maybeSingle();
      final kemi = List<Map<String, dynamic>>.from(
          await supabase.from('par_kemi').select('spiller_lav, spiller_hoej')
              as List);

      if (board != null) {
        _tilstand = board['tilstand'] as String? ?? 'mixet';
        _afvikling = board['afvikling'] as String? ?? 'manuel';
        _minutter = (board['minutter'] as num?)?.toInt() ?? 15;
        _baner = (board['baner'] as num?)?.toInt() ?? 2;
      }

      // Hvem har allerede spillet sammen i denne træning?
      final tidligere = await supabase
          .from('training_round_slots')
          .select('round_id, bane, par, user_id, '
              'training_rounds!inner(training_id)')
          .eq('training_rounds.training_id', _tid);
      final slots = List<Map<String, dynamic>>.from(tidligere as List);
      final grupper = <String, List<String>>{};
      for (final s in slots) {
        final uid = s['user_id'] as String?;
        if (uid == null) continue;
        (grupper['${s['round_id']}-${s['bane']}-${s['par']}'] ??= []).add(uid);
      }
      for (final g in grupper.values) {
        for (var i = 0; i < g.length; i++) {
          for (var j = i + 1; j < g.length; j++) {
            _spilletSammen.add(_parNoegle(g[i], g[j]));
          }
        }
      }

      if (!mounted) return;
      setState(() {
        _kemi = {
          for (final k in kemi)
            _parNoegle(k['spiller_lav'] as String, k['spiller_hoej'] as String)
        };
        _rundeNr = (sidste?['nr'] as num?)?.toInt() ?? 0;
        _rundeId = sidste?['id'] as String?;
        _loading = false;
      });
      if (_rundeId != null) await _hentRunde(_rundeId!);
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = e.toString(); });
    }
  }

  Future<void> _hentRunde(String id) async {
    try {
      final rows = await supabase
          .from('training_round_slots')
          .select('bane, par, user_id, guest_id, laast')
          .eq('round_id', id)
          .order('bane', ascending: true);
      final slots = List<Map<String, dynamic>>.from(rows as List);
      final byId = {for (final s in widget.spillere) s.id: s};

      final baner = <int, Map<int, List<_TavleSpiller>>>{};
      for (final s in slots) {
        final uid = (s['user_id'] ?? s['guest_id']) as String?;
        final sp = uid == null ? null : byId[uid];
        if (sp == null) continue;
        final b = (s['bane'] as num).toInt();
        final p = (s['par'] as num).toInt();
        ((baner[b] ??= {})[p] ??= []).add(sp);
        if (s['laast'] == true) _laaste.add(_laasNoegle(b, p));
      }
      if (!mounted) return;
      setState(() {
        _baneListe = [
          for (final b in baner.keys.toList()..sort())
            _TavleBane(b, _TavlePar(baner[b]?[1] ?? []), _TavlePar(baner[b]?[2] ?? []))
        ];
      });
    } catch (_) {}
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
  List<_TavleBane> _generer({bool bevarLaaste = true}) {
    final fastholdt = <int, Map<int, List<_TavleSpiller>>>{};
    final bundne = <String>{};
    if (bevarLaaste) {
      for (final b in _baneListe) {
        for (final (i, p) in [b.par1, b.par2].indexed) {
          if (!_erLaast(b.nr, i + 1) || p.spillere.isEmpty) continue;
          (fastholdt[b.nr] ??= {})[i + 1] = [...p.spillere];
          bundne.addAll(p.spillere.map((s) => s.id));
        }
      }
    }
    final frie =
        widget.spillere.where((s) => !bundne.contains(s.id)).toList();
    return _fordel(frie, fastholdt);
  }

  List<_TavleBane> _fordel(List<_TavleSpiller> frie,
      Map<int, Map<int, List<_TavleSpiller>>> fastholdt) {
    final puljer = <List<_TavleSpiller>>[];
    if (_tilstand == 'opdelt') {
      final efterHold = <String, List<_TavleSpiller>>{};
      for (final s in frie) {
        (efterHold[widget.holdAf[s.id] ?? 'Uden hold'] ??= []).add(s);
      }
      puljer.addAll(efterHold.values);
    } else {
      puljer.add([...frie]);
    }

    final ud = <_TavleBane>[];
    var baneNr = 1;
    for (final pulje in puljer) {
      final rest = [...pulje]..shuffle();
      // Venstre- og højrespillere hver for sig, så de kan parres på tværs.
      final venstre = rest.where((s) => s.side == 'venstre').toList();
      final hoejre = rest.where((s) => s.side == 'hoejre').toList();
      final resten = rest
          .where((s) => s.side != 'venstre' && s.side != 'hoejre')
          .toList();

      final par = <List<_TavleSpiller>>[];
      while (venstre.isNotEmpty && hoejre.isNotEmpty) {
        final v = venstre.removeAt(0);
        // Vælg den højrespiller man IKKE allerede har spillet med i dag.
        var idx = hoejre.indexWhere(
            (h) => !_spilletSammen.contains(_parNoegle(v.id, h.id)));
        if (idx < 0) idx = 0;
        par.add([v, hoejre.removeAt(idx)]);
      }
      // Dem der er tilbage (kun ét fortrukket ben, eller "begge"/ukendt)
      // parres to og to.
      final tilovers = [...venstre, ...hoejre, ...resten];
      while (tilovers.length >= 2) {
        final a = tilovers.removeAt(0);
        var idx = tilovers.indexWhere(
            (b) => !_spilletSammen.contains(_parNoegle(a.id, b.id)));
        if (idx < 0) idx = 0;
        par.add([a, tilovers.removeAt(idx)]);
      }
      if (tilovers.isNotEmpty) par.add([tilovers.removeAt(0)]);

      for (var i = 0; i < par.length; i += 2) {
        ud.add(_TavleBane(
          baneNr++,
          _TavlePar(par[i]),
          _TavlePar(i + 1 < par.length ? par[i + 1] : []),
        ));
      }
    }

    if (fastholdt.isEmpty) return ud;

    // De låste par skal stå præcis hvor de stod. De nye par fylder de
    // pladser der er tilbage, i rækkefølge.
    final nye = <List<_TavleSpiller>>[
      for (final b in ud) ...[b.par1.spillere, b.par2.spillere]
    ]..removeWhere((p) => p.isEmpty);

    final maxBane = [
      ...fastholdt.keys,
      if (ud.isNotEmpty) ud.length,
    ].fold<int>(1, (a, b) => a > b ? a : b);

    final samlet = <_TavleBane>[];
    var k = 0;
    for (var bane = 1; bane <= maxBane || nye.length > k; bane++) {
      final pladser = <List<_TavleSpiller>>[];
      for (var par = 1; par <= 2; par++) {
        final laast = fastholdt[bane]?[par];
        if (laast != null) {
          pladser.add(laast);
        } else {
          pladser.add(k < nye.length ? nye[k++] : <_TavleSpiller>[]);
        }
      }
      if (pladser[0].isEmpty && pladser[1].isEmpty) continue;
      samlet.add(_TavleBane(bane, _TavlePar(pladser[0]), _TavlePar(pladser[1])));
    }
    return samlet;
  }

  Future<void> _nyRunde() async {
    if (widget.spillere.length < 2) {
      _snack(context, 'Der skal mindst være 2 tilmeldte', _gold);
      return;
    }
    setState(() => _busy = true);
    final baner = _generer();
    try {
      await supabase.from('training_boards').upsert({
        'training_id': _tid,
        'tilstand': _tilstand,
        'afvikling': _afvikling,
        'minutter': _minutter,
        'baner': _baner,
        'oprettet_af': supabase.auth.currentUser?.id,
      });

      final nr = _rundeNr + 1;
      final slut = _afvikling == 'timer'
          ? DateTime.now().add(Duration(minutes: _minutter)).toUtc()
          : null;
      final runde = await supabase.from('training_rounds').insert({
        'training_id': _tid,
        'nr': nr,
        'startet_at': DateTime.now().toUtc().toIso8601String(),
        'slutter_at': slut?.toIso8601String(),
      }).select('id').single();
      final rid = runde['id'] as String;

      final raekker = <Map<String, dynamic>>[];
      for (final b in baner) {
        for (final (i, p) in [b.par1, b.par2].indexed) {
          for (final s in p.spillere) {
            raekker.add({
              'round_id': rid,
              'bane': b.nr,
              'par': i + 1,
              'laast': _erLaast(b.nr, i + 1),
              if (s.erGaest) 'guest_id': s.id else 'user_id': s.id,
            });
          }
        }
      }
      if (raekker.isNotEmpty) {
        await supabase.from('training_round_slots').insert(raekker);
      }

      // Husk parrene, så næste runde undgår dem.
      for (final b in baner) {
        for (final p in [b.par1, b.par2]) {
          if (p.spillere.length == 2) {
            _spilletSammen.add(
                _parNoegle(p.spillere[0].id, p.spillere[1].id));
          }
        }
      }

      if (!mounted) return;
      setState(() {
        _rundeNr = nr;
        _rundeId = rid;
        _baneListe = baner;
        _busy = false;
      });
      _startUr(slut?.toLocal());
    } on PostgrestException catch (e) {
      if (mounted) setState(() => _busy = false);
      if (mounted) _snack(context, e.message, _danger);
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

  _TavleSpiller? _valgt;

  Future<void> _byt(_TavleSpiller a, _TavleSpiller b) async {
    // Find og ombyt i den lokale opstilling.
    setState(() {
      for (final bane in _baneListe) {
        for (final p in [bane.par1, bane.par2]) {
          for (var i = 0; i < p.spillere.length; i++) {
            if (p.spillere[i].id == a.id) {
              p.spillere[i] = b;
            } else if (p.spillere[i].id == b.id) {
              p.spillere[i] = a;
            }
          }
        }
      }
      _valgt = null;
    });
    if (_rundeId == null) return;
    // Skriv hele runden om — færre kanter end at flytte enkeltrækker.
    try {
      await supabase.from('training_round_slots').delete().eq('round_id', _rundeId!);
      final raekker = <Map<String, dynamic>>[];
      for (final bane in _baneListe) {
        for (final (i, p) in [bane.par1, bane.par2].indexed) {
          for (final s in p.spillere) {
            raekker.add({
              'round_id': _rundeId,
              'bane': bane.nr,
              'par': i + 1,
              'laast': _erLaast(bane.nr, i + 1),
              if (s.erGaest) 'guest_id': s.id else 'user_id': s.id,
            });
          }
        }
      }
      if (raekker.isNotEmpty) {
        await supabase.from('training_round_slots').insert(raekker);
      }
    } on PostgrestException catch (e) {
      if (mounted) _snack(context, e.message, _danger);
    }
  }

  /// Genblander KUN de ulåste. Bruges når træneren har sat et par fast og
  /// vil have appen til at tage resten.
  Future<void> _blandUlaaste() async {
    if (_rundeId == null) return;
    final laastAntal = _laaste.length;
    if (laastAntal > 0 && _baneListe.every((b) => _baneLaast(b))) {
      _snack(context, 'Alt er låst — lås noget op først', _gold);
      return;
    }
    setState(() {
      _baneListe = _generer();
      _valgt = null;
    });
    await _skrivRunde();
  }

  /// Skriver den aktuelle opstilling. Hele runden skrives om frem for at
  /// flytte enkeltrækker — færre kanter at tage fejl af.
  Future<void> _skrivRunde() async {
    if (_rundeId == null) return;
    try {
      await supabase
          .from('training_round_slots')
          .delete()
          .eq('round_id', _rundeId!);
      final raekker = <Map<String, dynamic>>[];
      for (final bane in _baneListe) {
        for (final (i, p) in [bane.par1, bane.par2].indexed) {
          for (final s in p.spillere) {
            raekker.add({
              'round_id': _rundeId,
              'bane': bane.nr,
              'par': i + 1,
              'laast': _erLaast(bane.nr, i + 1),
              if (s.erGaest) 'guest_id': s.id else 'user_id': s.id,
            });
          }
        }
      }
      if (raekker.isNotEmpty) {
        await supabase.from('training_round_slots').insert(raekker);
      }
    } on PostgrestException catch (e) {
      if (mounted) _snack(context, e.message, _danger);
    }
  }

  Future<void> _toggleLaasPar(int bane, int par) async {
    setState(() {
      final n = _laasNoegle(bane, par);
      _laaste.contains(n) ? _laaste.remove(n) : _laaste.add(n);
    });
    await _skrivRunde();
  }

  Future<void> _toggleLaasBane(_TavleBane b) async {
    final laas = !_baneLaast(b);
    setState(() {
      for (var par = 1; par <= 2; par++) {
        final n = _laasNoegle(b.nr, par);
        laas ? _laaste.add(n) : _laaste.remove(n);
      }
    });
    await _skrivRunde();
  }

  Future<void> _toggleKemi(_TavlePar par) async {
    if (par.spillere.length != 2) return;
    final a = par.spillere[0], b = par.spillere[1];
    if (a.erGaest || b.erGaest) {
      _snack(context, 'Afløsere uden profil kan ikke markeres', _gold);
      return;
    }
    final lav = a.id.compareTo(b.id) < 0 ? a.id : b.id;
    final hoej = a.id.compareTo(b.id) < 0 ? b.id : a.id;
    final noegle = _parNoegle(a.id, b.id);
    final harNu = _kemi.contains(noegle);
    setState(() {
      harNu ? _kemi.remove(noegle) : _kemi.add(noegle);
    });
    try {
      if (harNu) {
        await supabase.from('par_kemi').delete()
            .eq('spiller_lav', lav).eq('spiller_hoej', hoej);
      } else {
        await supabase.from('par_kemi').insert({
          'spiller_lav': lav,
          'spiller_hoej': hoej,
          'markeret_af': supabase.auth.currentUser?.id,
        });
      }
    } on PostgrestException catch (e) {
      if (!mounted) return;
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
  Widget _spillerBrik(_TavleSpiller s) {
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

  Widget _parBlok(_TavleBane bane, int parNr, _TavlePar par) {
    final kanMarkeres = par.spillere.length == 2 &&
        !par.spillere[0].erGaest && !par.spillere[1].erGaest;
    final markeret = kanMarkeres &&
        _kemi.contains(_parNoegle(par.spillere[0].id, par.spillere[1].id));
    final laast = _erLaast(bane.nr, parNr);
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

  Widget _baneKort(_TavleBane b) => Container(
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
                      _baneLaast(b) ? Icons.lock : Icons.lock_open_outlined,
                      size: 15),
                  label: Text(_baneLaast(b) ? 'Banen er låst' : 'Lås banen'),
                  style: TextButton.styleFrom(
                    foregroundColor: _baneLaast(b) ? _gold : _textMuted,
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
                                      label: Text(_laaste.isEmpty
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
                                  if (_laaste.isNotEmpty) ...[
                                    const SizedBox(width: 10),
                                    Row(children: [
                                      const Icon(Icons.lock,
                                          size: 14, color: _gold),
                                      const SizedBox(width: 5),
                                      Text('${_laaste.length} låst',
                                          style: _body(
                                              size: 12,
                                              weight: FontWeight.w700,
                                              color: _gold)),
                                    ]),
                                  ],
                                ]),
                              ),
                              for (final b in _baneListe) _baneKort(b),
                              if (_baneListe.isEmpty)
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
