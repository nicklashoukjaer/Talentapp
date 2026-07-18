// Auto-split (del af biblioteket padel_app)
// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
part of '../main.dart';

class _PollDateRow {
  final String id;
  DateTime? value;
  _PollDateRow(this.id, this.value);
}

class CreatePollDialog extends StatefulWidget {
  const CreatePollDialog({super.key});
  @override
  State<CreatePollDialog> createState() => _CreatePollDialogState();
}

class _CreatePollDialogState extends State<CreatePollDialog> {
  final _formKey = GlobalKey<FormState>();
  final _titel   = TextEditingController();
  final _beskr   = TextEditingController();
  final List<_PollDateRow> _dates = [];
  int _idCounter = 0;
  bool _saving = false;
  DateTime? _frist; // stemmefrist — afstemningen lukker automatisk her
  List<Map<String, dynamic>> _groups = const [];
  String? _groupId; // null = klub-bred (alle kan stemme)

  @override
  void initState() {
    super.initState();
    _addDate();
    _loadGroups();
  }

  Future<void> _loadGroups() async {
    try {
      final userId = supabase.auth.currentUser!.id;
      final results = await Future.wait([
        supabase.from('groups').select('id, navn, type, farve, sort').order('sort'),
        supabase.from('group_members').select('group_id').eq('user_id', userId),
      ]);
      if (!mounted) return;
      final groups = List<Map<String, dynamic>>.from(results[0] as List);
      final myIds = List<Map<String, dynamic>>.from(results[1] as List)
          .map((r) => r['group_id'] as String)
          .toSet();
      setState(() {
        _groups = groups;
        // Forudvælg trænerens hold hvis de kun er på ét (kan stadig ændres).
        if (_groupId == null && myIds.length == 1) {
          final only = myIds.first;
          if (groups.any((g) => g['id'] == only)) _groupId = only;
        }
      });
    } catch (_) {}
  }

  Widget _groupChip(String label, String? id) {
    final active = _groupId == id;
    return GestureDetector(
      onTap: () => setState(() => _groupId = id),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: active ? _neon : _surfaceElevated,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: active ? _neon : _borderSubtle),
        ),
        child: Text(label,
            style: _body(
                size: 13,
                weight: FontWeight.w600,
                color: active ? Colors.white : _textPrimary)),
      ),
    );
  }

  @override
  void dispose() {
    _titel.dispose();
    _beskr.dispose();
    super.dispose();
  }

  void _addDate() {
    setState(() => _dates.add(_PollDateRow('row_${_idCounter++}', null)));
  }

  void _removeDate(String id) {
    setState(() => _dates.removeWhere((d) => d.id == id));
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final validDates = _dates.where((d) => d.value != null).map((d) => d.value!).toList();
    if (validDates.isEmpty) {
      _snack(context, 'Tilføj mindst én dato/tid', Colors.orange);
      return;
    }

    setState(() => _saving = true);
    try {
      final pollResp = await supabase.from('polls').insert({
        'titel':       _titel.text.trim(),
        'beskrivelse': _beskr.text.trim().isEmpty ? null : _beskr.text.trim(),
        'created_by':  supabase.auth.currentUser!.id,
        'group_id':    _groupId,
        if (_frist != null) 'lukket_at': _frist!.toUtc().toIso8601String(),
      }).select('id').single();

      final pollId = pollResp['id'];
      await supabase.from('poll_options').insert(
        validDates.map((d) => {
          'poll_id':    pollId,
          'option_tid': d.toUtc().toIso8601String(),
        }).toList(),
      );

      if (!mounted) return;
      _snack(context, 'Afstemning oprettet med ${validDates.length} datoer', Colors.green);
      Navigator.of(context).pop(true);
    } on PostgrestException catch (e) {
      if (mounted) _snack(context, e.message, Colors.red);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.92),
        decoration: const BoxDecoration(
          color: _surfaceDark,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          border: Border(top: BorderSide(color: _borderSubtle)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40, height: 4,
              margin: const EdgeInsets.only(top: 10, bottom: 6),
              decoration: BoxDecoration(
                color: _borderSubtle, borderRadius: BorderRadius.circular(999)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 10, 6),
              child: Row(children: [
                Expanded(child: Text('OPRET AFSTEMNING',
                    style: theme.textTheme.titleLarge)),
                IconButton(
                  onPressed: _saving ? null : () => Navigator.of(context).pop(false),
                  icon: const Icon(Icons.close),
                  color: _textSecondary,
                ),
              ]),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                if (_groups.isNotEmpty) ...[
                  Text('Hvem kan stemme?',
                      style: _body(
                          size: 13, weight: FontWeight.w600, color: _textSecondary)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8, runSpacing: 8,
                    children: [
                      _groupChip('Alle', null),
                      for (final g in _groups)
                        _groupChip(g['navn'] as String, g['id'] as String),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],
                TextFormField(
                  controller: _titel,
                  autofocus: true,
                  textInputAction: TextInputAction.next,
                  onFieldSubmitted: (_) => FocusScope.of(context).nextFocus(),
                  decoration: const InputDecoration(
                    labelText: 'Titel',
                    hintText: 'F.eks. "Kampafstemning mod nabolandsklubben"',
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Påkrævet' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _beskr,
                  textInputAction: TextInputAction.next,
                  onFieldSubmitted: (_) => FocusScope.of(context).nextFocus(),
                  decoration: const InputDecoration(
                    labelText: 'Beskrivelse',
                    helperText: 'Valgfri — kontekst til medlemmerne',
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 20),
                _fieldGroup('STEMMEFRIST · valgfri', [
                  _QuickDateTimeField(
                    label: 'Dato',
                    value: _frist,
                    onChanged: (v) => setState(() => _frist = v),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 6, left: 2),
                    child: Text(
                      _frist == null
                          ? 'Tom = åben indtil du selv lukker den'
                          : 'Afstemningen lukker automatisk — ingen kan stemme efter',
                      style: const TextStyle(color: _textMuted, fontSize: 11),
                    ),
                  ),
                ]),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Icon(Icons.event, color: theme.colorScheme.primary),
                    const SizedBox(width: 8),
                    Text('Dato-muligheder',
                        style: theme.textTheme.titleMedium),
                    const Spacer(),
                    Text('${_dates.where((d) => d.value != null).length} valgt',
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant)),
                  ],
                ),
                const SizedBox(height: 12),
                ..._dates.map((d) => Padding(
                  key: ValueKey(d.id),
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: _QuickDateTimeField(
                          key: ValueKey('field_${d.id}'),
                          label: 'Dato/tid',
                          value: d.value,
                          onChanged: (v) => setState(() => d.value = v),
                        ),
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        onPressed: _dates.length > 1
                            ? () => _removeDate(d.id)
                            : null,
                        icon: const Icon(Icons.remove_circle_outline),
                        color: Colors.red.shade400,
                        tooltip: 'Fjern',
                      ),
                    ],
                  ),
                )),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _addDate,
                    icon: const Icon(Icons.add),
                    label: const Text('Tilføj endnu en dato'),
                  ),
                ),
                    ],
                  ),
                ),
              ),
            ),
            // Sticky footer
            Container(
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: _borderSubtle)),
              ),
              padding: EdgeInsets.fromLTRB(
                  16, 12, 16, 12 + MediaQuery.of(context).padding.bottom),
              child: Row(children: [
                Expanded(
                  child: TextButton(
                    onPressed: _saving ? null : () => Navigator.of(context).pop(false),
                    style: TextButton.styleFrom(
                      foregroundColor: _textSecondary,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text('Annullér'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(width: 18, height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('Opret afstemning'),
                  ),
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Favorit-par pr. dato (7a/8a/8b) — overblik over mulige makker-par
// ─────────────────────────────────────────────────────────────────────────────
class _FavPair {
  final String aId, bId, aName, bName;
  final bool mutual;
  _FavPair(this.aId, this.bId, this.aName, this.bName, this.mutual);
}

class FavoritePairsScreen extends StatefulWidget {
  final Map<String, dynamic> poll;
  const FavoritePairsScreen({super.key, required this.poll});
  @override
  State<FavoritePairsScreen> createState() => _FavoritePairsScreenState();
}

class _FavoritePairsScreenState extends State<FavoritePairsScreen> {
  List<Map<String, dynamic>> _options = const [];
  Map<String, Set<String>> _votersByOption = {}; // option_id → "kan"-stemmere
  Map<String, Set<String>> _favorites = {};       // user_id → favorit user_ids
  Map<String, String> _names = {};                // user_id → navn
  bool _loading = true;
  String? _error;
  bool _isStaff = false;
  bool _onlyMutual = true; // 8a/8b-toggle (kun for staff)

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final uid = supabase.auth.currentUser!.id;
      final options = await supabase
          .from('poll_options')
          .select('id, option_tid, beskrivelse')
          .eq('poll_id', widget.poll['id'])
          .order('option_tid');
      final optList = List<Map<String, dynamic>>.from(options as List);
      final optIds = optList.map((o) => o['id'] as String).toList();

      final results = await Future.wait([
        optIds.isEmpty
            ? Future.value(const <Map<String, dynamic>>[])
            : supabase
                .from('poll_responses')
                .select('poll_option_id, user_id, svar')
                .inFilter('poll_option_id', optIds),
        supabase
            .from('profiles')
            .select('id, navn, rolle, makker_prio_1, makker_prio_2'),
      ]);
      final responses = List<Map<String, dynamic>>.from(results[0] as List);
      final profiles = List<Map<String, dynamic>>.from(results[1] as List);

      final voters = <String, Set<String>>{for (final id in optIds) id: <String>{}};
      for (final r in responses) {
        if (r['svar'] == true) {
          voters[r['poll_option_id'] as String]?.add(r['user_id'] as String);
        }
      }
      final favs = <String, Set<String>>{};
      final names = <String, String>{};
      var staff = false;
      for (final p in profiles) {
        final id = p['id'] as String;
        names[id] = p['navn'] as String? ?? '(ukendt)';
        final s = <String>{};
        if (p['makker_prio_1'] != null) s.add(p['makker_prio_1'] as String);
        if (p['makker_prio_2'] != null) s.add(p['makker_prio_2'] as String);
        favs[id] = s;
        if (id == uid) {
          final rolle = p['rolle'] as String?;
          staff = rolle == 'admin' || rolle == 'træner';
        }
      }
      if (!mounted) return;
      setState(() {
        _options = optList;
        _votersByOption = voters;
        _favorites = favs;
        _names = names;
        _isStaff = staff;
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = e.toString(); });
    }
  }

  /// Beregn disjunkte favorit-par blandt "kan"-stemmerne for én dato.
  ({List<_FavPair> pairs, int withoutPartner}) _pairsFor(Set<String> voters) {
    final list = voters.toList();
    final cands = <_FavPair>[];
    for (var i = 0; i < list.length; i++) {
      for (var j = i + 1; j < list.length; j++) {
        final a = list[i], b = list[j];
        final aFavB = (_favorites[a] ?? const {}).contains(b);
        final bFavA = (_favorites[b] ?? const {}).contains(a);
        final mutual = aFavB && bFavA;
        final oneWay = aFavB || bFavA;
        if (mutual || (!_onlyMutual && oneWay)) {
          cands.add(_FavPair(a, b, _names[a] ?? '?', _names[b] ?? '?', mutual));
        }
      }
    }
    // Gensidige først, så vi vælger de sikreste par.
    cands.sort((x, y) => (y.mutual ? 1 : 0) - (x.mutual ? 1 : 0));
    final used = <String>{};
    final selected = <_FavPair>[];
    for (final c in cands) {
      if (used.contains(c.aId) || used.contains(c.bId)) continue;
      used..add(c.aId)..add(c.bId);
      selected.add(c);
    }
    return (pairs: selected, withoutPartner: voters.length - used.length);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('SPILLE DAGE'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _ErrorView(error: _error!, onRetry: _load)
              : _buildBody(theme),
    );
  }

  Widget _buildBody(ThemeData theme) {
    // Beregn resultater pr. dato
    final results = _options.map((o) {
      final id = o['id'] as String;
      final voters = _votersByOption[id] ?? const <String>{};
      final r = _pairsFor(voters);
      return (option: o, can: voters.length, pairs: r.pairs, without: r.withoutPartner);
    }).toList();

    // Stærkeste dato = flest par
    final strongest = results.isEmpty
        ? null
        : results.reduce((a, b) => b.pairs.length > a.pairs.length ? b : a);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 700),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Toggle (kun staff)
                if (_isStaff) ...[
                  _MutualToggle(
                    onlyMutual: _onlyMutual,
                    onChanged: (v) => setState(() => _onlyMutual = v),
                  ),
                  const SizedBox(height: 14),
                ],
                // Stærkeste dato
                if (strongest != null && strongest.pairs.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(bottom: 14),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: _success.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: _success.withValues(alpha: 0.4)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          const Text('🏆', style: TextStyle(fontSize: 16)),
                          const SizedBox(width: 8),
                          Text('Stærkeste dato',
                              style: _cond(size: 17, weight: FontWeight.w800, color: _success)),
                        ]),
                        const SizedBox(height: 6),
                        Text(
                          '${_fmtDate(DateTime.parse(strongest.option['option_tid'] as String).toLocal())} '
                          'giver flest favorit-par — I kan stille '
                          '${strongest.pairs.length} par der alle har deres favorit-makker.',
                          style: _body(size: 13, color: _textPrimary),
                        ),
                      ],
                    ),
                  ),
                Row(children: [
                  const Icon(Icons.info_outline, size: 14, color: _textMuted),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text('Bygger på favorit-makkere fra profilerne',
                        style: _body(size: 12, color: _textMuted)),
                  ),
                ]),
                const SizedBox(height: 12),
                for (final r in results) _dateCard(theme, r),
                const SizedBox(height: 12),
                Text('Kun et overblik — du sætter den endelige opstilling til '
                    'kampen selv.',
                    textAlign: TextAlign.center,
                    style: _body(size: 12, color: _textMuted)),
                const SizedBox(height: 10),
                // Legende
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 16, runSpacing: 6,
                  children: [
                    _legend(true, 'Gensidig'),
                    if (_isStaff && !_onlyMutual) _legend(false, 'Én-vejs'),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _legend(bool mutual, String label) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(mutual ? Icons.favorite : Icons.favorite_border,
              size: 14, color: mutual ? _danger : _gold),
          const SizedBox(width: 6),
          Text(label, style: _body(size: 12, color: _textSecondary)),
        ],
      );

  Widget _dateCard(ThemeData theme,
      ({Map<String, dynamic> option, int can, List<_FavPair> pairs, int without}) r) {
    final tid = DateTime.parse(r.option['option_tid'] as String).toLocal();
    final n = r.pairs.length;
    final allMutual = r.pairs.every((p) => p.mutual);
    final badgeColor = n == 0 ? _textMuted : (allMutual ? _success : _gold);
    final badgeText = n == 0
        ? 'Ingen par'
        : (_onlyMutual
            ? '$n gensidig${n == 1 ? '' : 'e'}'
            : '$n ${allMutual ? 'gensidige' : 'mulige'}');
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_fmtDateTime(tid),
                        style: _cond(size: 17, weight: FontWeight.w800)),
                    Text('${r.can} kan spille',
                        style: _body(size: 12, color: _textSecondary)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: badgeColor.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(badgeText,
                    style: _body(size: 12, weight: FontWeight.w700, color: badgeColor)),
              ),
            ]),
            if (r.pairs.isNotEmpty) ...[
              const SizedBox(height: 10),
              for (final p in r.pairs) _pairRow(p),
            ],
            if (r.without > 0) ...[
              const SizedBox(height: 6),
              Text('${r.without} uden makker',
                  style: _body(size: 12, color: _textMuted)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _pairRow(_FavPair p) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        _InitialAvatar(navn: p.aName, size: 26),
        const SizedBox(width: 2),
        _InitialAvatar(navn: p.bName, size: 26),
        const SizedBox(width: 10),
        Expanded(
          child: Text('${p.aName} & ${p.bName}',
              style: _body(size: 14, weight: FontWeight.w600),
              maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
        if (!p.mutual)
          Text('én-vejs', style: _body(size: 11, color: _gold)),
        const SizedBox(width: 6),
        Icon(p.mutual ? Icons.favorite : Icons.favorite_border,
            size: 16, color: p.mutual ? _danger : _gold),
      ]),
    );
  }
}

class _MutualToggle extends StatelessWidget {
  final bool onlyMutual;
  final ValueChanged<bool> onChanged;
  const _MutualToggle({required this.onlyMutual, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    Widget seg(String label, bool mutual) {
      final active = onlyMutual == mutual;
      return Expanded(
        child: GestureDetector(
          onTap: () => onChanged(mutual),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: active ? _neon : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(label,
                style: _body(
                    size: 13,
                    weight: FontWeight.w700,
                    color: active ? Colors.white : _textSecondary)),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: _surfaceDark,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _borderSubtle),
      ),
      child: Row(children: [
        seg('Kun gensidige', true),
        seg('Alle favoritter', false),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Synergy report screen (Fase 3)
// ─────────────────────────────────────────────────────────────────────────────

class _SynergyOption {
  final String id;
  final DateTime tid;
  final String? label;
  final int yesCount;
  final int pairCount;
  final int totalScore;
  final List<_SynergyPair> pairs;
  _SynergyOption({
    required this.id, required this.tid, required this.label,
    required this.yesCount, required this.pairCount,
    required this.totalScore, required this.pairs,
  });
}

class _SynergyPair {
  final String lowName, highName, label;
  final int score;
  _SynergyPair(this.lowName, this.highName, this.label, this.score);
}

class SynergyReportScreen extends StatefulWidget {
  final Map<String, dynamic> poll;
  const SynergyReportScreen({super.key, required this.poll});
  @override
  State<SynergyReportScreen> createState() => _SynergyReportScreenState();
}

class _SynergyReportScreenState extends State<SynergyReportScreen> {
  List<_SynergyOption> _options = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final rows = await supabase.rpc('get_poll_synergy_report',
          params: {'p_poll_id': widget.poll['id']});

      final list = (rows as List).map((r) {
        final m = r as Map<String, dynamic>;
        final rawPairs = (m['pairs'] as List?) ?? const [];
        final pairs = rawPairs.map((p) {
          final pm = p as Map<String, dynamic>;
          return _SynergyPair(
            pm['player_low_navn']  as String,
            pm['player_high_navn'] as String,
            pm['label']            as String,
            pm['score']            as int,
          );
        }).toList();
        return _SynergyOption(
          id:         m['option_id']    as String,
          tid:        DateTime.parse(m['option_tid'] as String),
          label:      m['option_label'] as String?,
          yesCount:   m['yes_count']    as int,
          pairCount:  m['pair_count']   as int,
          totalScore: m['total_score']  as int,
          pairs:      pairs,
        );
      }).toList();

      list.sort((a, b) {
        final cmp = b.totalScore.compareTo(a.totalScore);
        if (cmp != 0) return cmp;
        return b.yesCount.compareTo(a.yesCount);
      });

      setState(() {
        _options = list;
        _loading = false;
      });
    } catch (e) {
      setState(() { _loading = false; _error = e.toString(); });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.poll['titel'] as String),
        actions: [
          IconButton(
            onPressed: _load,
            icon: const Icon(Icons.refresh),
            tooltip: 'Genberegn',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _ErrorView(error: _error!, onRetry: _load)
              : _options.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.bar_chart,
                                size: 64, color: Colors.grey.shade400),
                            const SizedBox(height: 16),
                            const Text('Ingen data — vent på at spillerne svarer'),
                          ],
                        ),
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 720),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 4),
                                  child: Text(
                                    'Sorteret efter samlet synergi-score — '
                                    'bedste dato øverst',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                        color: theme.colorScheme.onSurfaceVariant,
                                        fontStyle: FontStyle.italic),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                ..._options.map((o) => _SynergyCard(option: o)),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
    );
  }
}

class _SynergyCard extends StatelessWidget {
  final _SynergyOption option;
  const _SynergyCard({required this.option});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scoreColor = _scoreBadgeColor(option.totalScore, option.pairCount);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        initiallyExpanded: option.pairs.isNotEmpty,
        leading: Container(
          width: 48, height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: scoreColor, shape: BoxShape.circle),
          child: Text('${option.totalScore}',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold)),
        ),
        title: Text(_fmtDateTime(option.tid.toLocal()),
            style: theme.textTheme.titleMedium),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Wrap(
            spacing: 6,
            children: [
              _Pill(label: '${option.yesCount} JA',
                  bg: Colors.green.shade50, fg: Colors.green.shade800),
              _Pill(label: '${option.pairCount} par',
                  bg: theme.colorScheme.primaryContainer,
                  fg: theme.colorScheme.onPrimaryContainer),
              if (option.label != null && option.label!.isNotEmpty)
                _Pill(label: option.label!,
                    bg: theme.colorScheme.surfaceContainerHighest,
                    fg: theme.colorScheme.onSurface),
            ],
          ),
        ),
        children: option.pairs.isEmpty
            ? const [Padding(
                padding: EdgeInsets.all(16),
                child: Text('Ingen kemi-par tilgængelige denne dag',
                    style: TextStyle(color: Colors.grey)),
              )]
            : option.pairs.map((p) => ListTile(
                dense: true,
                leading: Container(
                  width: 32, height: 32,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _synergyColor(p.score),
                    shape: BoxShape.circle,
                  ),
                  child: Text('${p.score}',
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold)),
                ),
                title: Text('${p.lowName}  ⇄  ${p.highName}'),
                subtitle: Text(p.label),
              )).toList(),
      ),
    );
  }

  Color _scoreBadgeColor(int total, int pairCount) {
    if (total >= 10) return Colors.green.shade700;
    if (total >= 5)  return Colors.lightGreen.shade600;
    if (total >= 2)  return Colors.amber.shade700;
    if (pairCount > 0) return Colors.orange.shade700;
    return Colors.grey.shade500;
  }
}

class _Pill extends StatelessWidget {
  final String label;
  final Color bg;
  final Color fg;
  const _Pill({required this.label, required this.bg, required this.fg});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(label, style: TextStyle(
          color: fg, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}

Color _synergyColor(int score) => switch (score) {
  5 => Colors.green.shade700,
  4 => Colors.lightGreen.shade600,
  3 => Colors.amber.shade700,
  2 => Colors.orange.shade700,
  _ => Colors.grey.shade500,
};

// ─────────────────────────────────────────────────────────────────────────────
// QuickDateTimeField — 1 klik på dato, 4 cifre til tid (auto-formateret HH:MM)
// ─────────────────────────────────────────────────────────────────────────────

