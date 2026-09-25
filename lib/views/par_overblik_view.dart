// Auto-split (del af biblioteket padel_app)
// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
part of '../main.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Par-overblik
//
// Hvem har spillet sammen, hvor ofte, hvilke sider dækker de — og har
// træneren markeret dem med en stjerne.
//
// Bemærk forskellen til FavoritePairsScreen: den viser hvad spillerne ØNSKER
// (makker_prio_1/2). Denne viser hvad der faktisk er sket på banen. De to
// supplerer hinanden, og ønsket vises derfor med her når det findes.
// ─────────────────────────────────────────────────────────────────────────────

class ParOverblikScreen extends StatefulWidget {
  const ParOverblikScreen({super.key});
  @override
  State<ParOverblikScreen> createState() => _ParOverblikScreenState();
}

class _ParOverblikScreenState extends State<ParOverblikScreen> {
  bool _loading = true;
  String? _error;

  List<Map<String, dynamic>> _par = const [];
  Map<String, Map<String, dynamic>> _profiler = {};
  Map<String, Set<String>> _holdAf = {};
  List<Map<String, dynamic>> _grupper = const [];

  String? _filterHold;        // null = alle hold
  bool _kunKemi = false;      // vis kun stjernemarkerede

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final par = List<Map<String, dynamic>>.from(
          await supabase.from('par_overblik').select() as List);
      final profiler = List<Map<String, dynamic>>.from(
          await supabase.from('profiles')
              .select('id, navn, spiller_side, makker_prio_1, makker_prio_2')
              .order('navn', ascending: true) as List);
      final gm = List<Map<String, dynamic>>.from(
          await supabase.from('group_members').select('group_id, user_id') as List);
      final grupper = List<Map<String, dynamic>>.from(
          await supabase.from('groups')
              .select('id, navn, farve, sort')
              .order('sort', ascending: true) as List);

      final holdAf = <String, Set<String>>{};
      for (final r in gm) {
        (holdAf[r['user_id'] as String] ??= {}).add(r['group_id'] as String);
      }

      if (!mounted) return;
      setState(() {
        _par = par;
        _profiler = {for (final p in profiler) p['id'] as String: p};
        _holdAf = holdAf;
        _grupper = grupper;
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = e.toString(); });
    }
  }

  /// Ønsker de hinanden som makker? Vises ved siden af det faktisk spillede.
  bool _ensker(String a, String b) {
    final pa = _profiler[a], pb = _profiler[b];
    return pa?['makker_prio_1'] == b || pa?['makker_prio_2'] == b ||
           pb?['makker_prio_1'] == a || pb?['makker_prio_2'] == a;
  }

  List<Map<String, dynamic>> get _synlige {
    var liste = _par.where((p) {
      if (_kunKemi && p['god_kemi'] != true) return false;
      if (_filterHold == null) return true;
      final a = _holdAf[p['spiller_lav'] as String] ?? const <String>{};
      final b = _holdAf[p['spiller_hoej'] as String] ?? const <String>{};
      return a.contains(_filterHold) && b.contains(_filterHold);
    }).toList();
    liste.sort((x, y) {
      // Stjernemarkerede øverst, derefter flest runder sammen.
      final k = (y['god_kemi'] == true ? 1 : 0) - (x['god_kemi'] == true ? 1 : 0);
      if (k != 0) return k;
      return ((y['runder_sammen'] as num?) ?? 0)
          .compareTo((x['runder_sammen'] as num?) ?? 0);
    });
    return liste;
  }

  Widget _sideMaerke(String? side) {
    final info = _sideInfo(side);
    return Container(
      width: 19,
      height: 19,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: info.farve.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(info.kort,
          style: _body(size: 10.5, weight: FontWeight.w800, color: info.farve)),
    );
  }

  Widget _parRaekke(Map<String, dynamic> p, bool foerste) {
    final a = _profiler[p['spiller_lav'] as String];
    final b = _profiler[p['spiller_hoej'] as String];
    if (a == null || b == null) return const SizedBox.shrink();
    final runder = ((p['runder_sammen'] as num?) ?? 0).toInt();
    final kemi = p['god_kemi'] == true;
    final oenske = _ensker(a['id'] as String, b['id'] as String);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 4),
      decoration: BoxDecoration(
        border: foerste
            ? null
            : const Border(top: BorderSide(color: _borderSubtle)),
      ),
      child: Row(children: [
        Icon(kemi ? Icons.star : Icons.star_border,
            size: 18, color: kemi ? _gold : _textMuted),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(children: [
                Flexible(
                  child: Text(
                      '${a['navn']} + ${b['navn']}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _body(size: 13.5, weight: FontWeight.w600)),
                ),
                const SizedBox(width: 8),
                _sideMaerke(a['spiller_side'] as String?),
                const SizedBox(width: 4),
                _sideMaerke(b['spiller_side'] as String?),
              ]),
              if (oenske)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Row(children: [
                    const Icon(Icons.favorite_border, size: 11, color: _info),
                    const SizedBox(width: 4),
                    Text('Har valgt hinanden som makker',
                        style: _body(size: 11, color: _info)),
                  ]),
                ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('$runder',
                style: _cond(
                    size: 18,
                    weight: FontWeight.w800,
                    color: runder > 0 ? _textPrimary : _textMuted)),
            Text(runder == 1 ? 'runde' : 'runder',
                style: _body(size: 10.5, color: _textMuted)),
          ],
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final liste = _synlige;
    return Scaffold(
      appBar: AppBar(title: const Text('PAR-OVERBLIK')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _ErrorView(error: _error!, onRetry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
                    children: [
                      Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 760),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Wrap(spacing: 8, runSpacing: 8, children: [
                                _filterChip('Alle hold', _filterHold == null,
                                    () => setState(() => _filterHold = null)),
                                for (final g in _grupper)
                                  _filterChip(
                                      g['navn'] as String,
                                      _filterHold == g['id'],
                                      () => setState(
                                          () => _filterHold = g['id'] as String)),
                                _filterChip('⭐ Kun god kemi', _kunKemi,
                                    () => setState(() => _kunKemi = !_kunKemi)),
                              ]),
                              const SizedBox(height: 16),
                              // Tegnes ALTID — også tom — så det ikke ligner
                              // at overblikket mangler.
                              Container(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 12),
                                decoration: BoxDecoration(
                                  color: _surfaceDark,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: _borderSubtle),
                                ),
                                child: liste.isEmpty
                                    ? Padding(
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 26),
                                        child: Column(children: [
                                          const Icon(Icons.groups_outlined,
                                              size: 34, color: _textMuted),
                                          const SizedBox(height: 10),
                                          Text(
                                              _kunKemi
                                                  ? 'Ingen par er markeret med god kemi endnu'
                                                  : 'Ingen par har spillet sammen endnu',
                                              textAlign: TextAlign.center,
                                              style: _body(
                                                  size: 13,
                                                  color: _textSecondary)),
                                          const SizedBox(height: 4),
                                          Text(
                                              'Kør en runde på en trænings tavle, '
                                              'så fyldes listen',
                                              textAlign: TextAlign.center,
                                              style: _body(
                                                  size: 11.5,
                                                  color: _textMuted)),
                                        ]),
                                      )
                                    : Column(
                                        children: [
                                          for (final (i, p) in liste.indexed)
                                            _parRaekke(p, i == 0),
                                        ],
                                      ),
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

  Widget _filterChip(String label, bool aktiv, VoidCallback onTap) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: aktiv ? _neon : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: aktiv ? _neon : _borderSubtle),
          ),
          child: Text(label,
              style: _body(
                  size: 12.5,
                  weight: FontWeight.w700,
                  color: aktiv ? Colors.white : _textSecondary)),
        ),
      );
}
