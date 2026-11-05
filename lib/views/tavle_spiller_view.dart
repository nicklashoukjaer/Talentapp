// Auto-split (del af biblioteket padel_app)
// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
part of '../main.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Spillerens egen tavle
//
// Trænerens tavle er et værktøj: opsætning, låse, stjerner, ombytninger.
// Spilleren skal kun vide ét: hvilken bane, med hvem, mod hvem. Derfor en
// egen skærm frem for at give alle adgang til trænerens.
//
// Læseadgangen findes i forvejen — RLS på runder og pladser tillader alle
// indloggede at se dem.
//
// Træk ned for at hente igen. Appen bruger ikke realtime nogen steder, og
// det er et bevidst valg at lade være her også.
// ─────────────────────────────────────────────────────────────────────────────

class TavleSpillerSkaerm extends StatefulWidget {
  final Map<String, dynamic> training;
  const TavleSpillerSkaerm({super.key, required this.training});

  @override
  State<TavleSpillerSkaerm> createState() => _TavleSpillerSkaermState();
}

class _TavleSpillerSkaermState extends State<TavleSpillerSkaerm> {
  List<SpillerRunde> _runder = const [];
  bool _loading = true;
  String? _error;

  String get _uid => supabase.auth.currentUser?.id ?? '';

  @override
  void initState() {
    super.initState();
    _hent();
  }

  Future<void> _hent() async {
    if (!_loading) setState(() => _error = null);
    try {
      final r = await TavleService.hentSpillerRunder(widget.training, _uid);
      if (!mounted) return;
      setState(() {
        _runder = r;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final titel = widget.training['titel'] as String? ?? 'Træning';
    final pc = isDesktop(context);

    return Scaffold(
      appBar: AppBar(title: const Text('MIN BANE')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _ErrorView(error: _error!, onRetry: _hent)
              : RefreshIndicator(
                  onRefresh: _hent,
                  color: _neon,
                  backgroundColor: _surfaceDark,
                  child: ListView(
                    // Altid scrollbar, også når der er lidt indhold —
                    // ellers kan man ikke trække ned for at opdatere.
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: EdgeInsets.fromLTRB(16, 16, 16, pc ? 40 : 96),
                    children: [
                      Center(
                        child: ConstrainedBox(
                          constraints:
                              BoxConstraints(maxWidth: pc ? 720 : 560),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(titel.toUpperCase(),
                                  style: _cond(
                                      size: pc ? 24 : 20,
                                      weight: FontWeight.w800),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis),
                              const SizedBox(height: 14),
                              if (_runder.isEmpty)
                                _tomtKort()
                              else ...[
                                _nuKort(_runder.first, pc),
                                if (_runder.length > 1) ...[
                                  const SizedBox(height: 20),
                                  Padding(
                                    padding:
                                        const EdgeInsets.only(left: 4, bottom: 8),
                                    child: Text('TIDLIGERE RUNDER',
                                        style: _body(
                                            size: 11,
                                            weight: FontWeight.w700,
                                            spacing: 1,
                                            color: _textSecondary)),
                                  ),
                                  for (final r in _runder.skip(1))
                                    _tidligereLinje(r),
                                ],
                              ],
                              const SizedBox(height: 18),
                              Center(
                                child: Text('Træk ned for at opdatere',
                                    style: _body(
                                        size: 11.5, color: _textMuted)),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }

  Widget _tomtKort() => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _surfaceDark,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _borderSubtle),
        ),
        child: Row(children: [
          const Icon(Icons.schedule, size: 20, color: _textMuted),
          const SizedBox(width: 11),
          Expanded(
            child: Text(
                'Træneren har ikke sat banerne endnu. '
                'Træk ned når I er i gang.',
                style: _body(size: 12.5, color: _textSecondary)),
          ),
        ]),
      );

  /// Den store besked: hvor skal jeg hen lige nu.
  Widget _nuKort(SpillerRunde r, bool pc) {
    final over = r.sidderOver;
    final farve = over ? _gold : _neon;

    return Container(
      padding: EdgeInsets.all(pc ? 22 : 18),
      decoration: BoxDecoration(
        color: _surfaceDark,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: farve.withValues(alpha: 0.55)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Text('RUNDE ${r.nr}',
                style: _body(
                    size: 12,
                    weight: FontWeight.w800,
                    spacing: 1.2,
                    color: _textSecondary)),
            const Spacer(),
            if (r.slutterAt != null) _nedtaelling(r.slutterAt!),
          ]),
          const SizedBox(height: 10),
          Text(over ? 'DU SIDDER OVER' : 'BANE ${r.bane}',
              style: _cond(
                  size: pc ? 52 : 44, weight: FontWeight.w800, color: farve)),
          if (over) ...[
            const SizedBox(height: 6),
            Text('Du er med igen i næste runde',
                style: _body(size: 13, color: _textSecondary)),
          ] else ...[
            const SizedBox(height: 16),
            _holdLinje('MED', r.makker == null ? const [] : [r.makker!],
                _success),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.only(left: 2),
              child: Text('mod', style: _body(size: 12, color: _textMuted)),
            ),
            const SizedBox(height: 12),
            _holdLinje('MODSTANDERE', r.modstandere, _danger),
          ],
        ],
      ),
    );
  }

  Widget _holdLinje(String titel, List<TavleSpiller> folk, Color farve) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(titel,
              style: _body(
                  size: 10,
                  weight: FontWeight.w700,
                  spacing: 1.1,
                  color: _textMuted)),
          const SizedBox(height: 7),
          if (folk.isEmpty)
            Text('—', style: _body(size: 13, color: _textMuted))
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final s in folk)
                  Container(
                    padding:
                        const EdgeInsets.fromLTRB(6, 5, 12, 5),
                    decoration: BoxDecoration(
                      color: farve.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                      border:
                          Border.all(color: farve.withValues(alpha: 0.35)),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      _InitialAvatar(navn: s.navn, size: 26),
                      const SizedBox(width: 9),
                      Text(s.navn,
                          style:
                              _body(size: 14, weight: FontWeight.w700)),
                    ]),
                  ),
              ],
            ),
        ],
      );

  /// Ur der tæller ned. Tegnes kun når træneren kører med tid.
  Widget _nedtaelling(DateTime slut) {
    final rest = slut.difference(DateTime.now());
    if (rest.isNegative) {
      return Text('Tiden er gået',
          style: _body(size: 12, weight: FontWeight.w700, color: _gold));
    }
    final m = rest.inMinutes, sek = rest.inSeconds % 60;
    return Text('$m:${sek.toString().padLeft(2, '0')}',
        style: _cond(
            size: 20,
            weight: FontWeight.w800,
            color: rest.inMinutes < 2 ? _danger : _neon));
  }

  Widget _tidligereLinje(SpillerRunde r) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
          decoration: BoxDecoration(
            color: _surfaceDark,
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: _borderSubtle),
          ),
          child: Row(children: [
            SizedBox(
              width: 34,
              child: Text('${r.nr}',
                  style: _cond(
                      size: 19, weight: FontWeight.w800, color: _textMuted)),
            ),
            Expanded(
              child: Text(
                  r.sidderOver
                      ? 'Sad over'
                      : 'Bane ${r.bane}'
                          '${r.makker == null ? '' : ' · med ${r.makker!.navn}'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _body(size: 13, weight: FontWeight.w600)),
            ),
            if (!r.sidderOver && r.modstandere.isNotEmpty)
              Flexible(
                child: Text(
                    'mod ${r.modstandere.map((s) => s.navn).join(' & ')}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: _body(size: 11.5, color: _textMuted)),
              ),
          ]),
        ),
      );
}
