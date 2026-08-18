// Auto-split (del af biblioteket padel_app)
// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
part of '../main.dart';

class AfstemningerTab extends StatefulWidget {
  final bool isStaff; // admin/træner → må slette afstemninger
  final bool isAdmin; // fuld admin → ser ALLE holds afstemninger
  const AfstemningerTab({super.key, this.isStaff = false, this.isAdmin = false});
  @override
  State<AfstemningerTab> createState() => _AfstemningerTabState();
}

class _AfstemningerTabState extends State<AfstemningerTab> {
  List<Map<String, dynamic>> _polls = const [];
  Set<String> _myCaptainGroupIds = {};
  List<Map<String, dynamic>> _groups = const []; // alle hold (til filteret)
  Set<String> _myGroupIds = {};
  String? _filterGroupId; // valgt hold i tragt-filteret (null = ingen)

  /// Må den aktuelle bruger slette denne afstemning? (staff, opretter eller
  /// kaptajn for afstemningens hold)
  bool _canManagePoll(Map<String, dynamic> p) {
    if (widget.isStaff) return true;
    if (p['created_by'] == supabase.auth.currentUser?.id) return true;
    // Kaptajn for mindst ét af afstemningens hold.
    return _pollGroupIds(p).any(_myCaptainGroupIds.contains);
  }
  bool _loading = true;
  String? _error;
  int _tab = 0; // 0 = Åbne, 1 = Afsluttede

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Offentligt genindlæs — kaldes fx efter en ny afstemning er oprettet via FAB.
  void reload() => _load();

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final userId = supabase.auth.currentUser!.id;
      final results = await Future.wait([
        supabase.from('polls')
            .select('id, titel, beskrivelse, lukket_at, created_at, group_id, group_ids, created_by, type')
            .order('created_at', ascending: false),
        supabase.from('group_members').select('group_id, is_captain').eq('user_id', userId),
        supabase.from('groups').select('id, navn, farve, sort').order('sort'),
      ]);
      final allPolls = List<Map<String, dynamic>>.from(results[0] as List);
      final myGm = List<Map<String, dynamic>>.from(results[1] as List);
      final groups = List<Map<String, dynamic>>.from(results[2] as List);
      final myIds = myGm.map((r) => r['group_id'] as String).toSet();
      final myCaptainIds = myGm
          .where((r) => r['is_captain'] == true)
          .map((r) => r['group_id'] as String)
          .toSet();
      // Spillere/trænere ser klub-brede (null) + deres egne holds afstemninger.
      // Fuld admin ser alt.
      final visible = widget.isAdmin
          ? allPolls
          : allPolls.where((p) {
              final gids = _pollGroupIds(p);
              return gids.isEmpty || gids.any(myIds.contains);
            }).toList();
      if (!mounted) return;
      setState(() {
        _polls = visible;
        _groups = groups;
        _myGroupIds = myIds;
        _myCaptainGroupIds = myCaptainIds;
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = e.toString(); });
    }
  }

  /// Er der et aktivt hold-filter? (styrer tragt-badgen i app-headeren)
  bool get holdFilterActive => _filterGroupId != null;

  /// Navnene på de hold en afstemning gælder (tom = klub-bred).
  List<String> _groupNamesOf(Map<String, dynamic> p) => _pollGroupIds(p)
      .map((id) {
        final g = _groups.firstWhere((e) => e['id'] == id,
            orElse: () => const <String, dynamic>{});
        return g['navn'] as String?;
      })
      .whereType<String>()
      .toList();

  /// Afstemninger efter hold-filteret. Uden filter vises alt brugeren må se.
  List<Map<String, dynamic>> get _visiblePolls => _filterGroupId == null
      ? _polls
      : _polls
          .where((p) => _pollGroupIds(p).contains(_filterGroupId))
          .toList();

  /// Hold-filter som bundsheet — kaldes af tragt-ikonet i app-headeren.
  /// Admin kan vælge hvilket som helst hold; øvrige kun deres egne.
  Future<void> showHoldFilterSheet() async {
    final selectable = widget.isAdmin
        ? _groups
        : _groups.where((g) => _myGroupIds.contains(g['id'] as String)).toList();
    if (selectable.isEmpty) {
      _snack(context, 'Ingen hold at filtrere på', _textSecondary);
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        Color hex(String? h) {
          if (h == null || h.isEmpty) return _textSecondary;
          return Color(int.parse(h.replaceFirst('#', ''), radix: 16) | 0xFF000000);
        }

        Widget option(String? id, String label, Color dot) {
          final selected = _filterGroupId == id;
          return InkWell(
            onTap: () {
              setState(() => _filterGroupId = id);
              Navigator.of(ctx).pop();
            },
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: selected ? _neon.withValues(alpha: 0.14) : _surfaceElevated,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: selected ? _neon : _borderSubtle),
              ),
              child: Row(children: [
                Container(
                  width: 11, height: 11,
                  decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Text(label,
                      style: _body(
                          size: 14,
                          weight: FontWeight.w600,
                          color: selected ? _neon : _textPrimary)),
                ),
                if (selected) const Icon(Icons.check, size: 18, color: _neon),
              ]),
            ),
          );
        }

        return SafeArea(
          top: false,
          child: Container(
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            constraints:
                BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.8),
            decoration: BoxDecoration(
              color: _surfaceDark,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _borderSubtle),
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('VÆLG HOLD',
                      style: _cond(size: 20, weight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Text('Filtrér afstemningerne til ét hold.',
                      style: _body(size: 12.5, color: _textSecondary)),
                  const SizedBox(height: 14),
                  option(null, 'Alle afstemninger', _neon),
                  for (final g in selectable)
                    option(g['id'] as String, g['navn'] as String,
                        hex(g['farve'] as String?)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _open(Map<String, dynamic> poll) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PollDetailScreen(poll: poll),
    )).then((_) => _load());
  }

  Future<void> _editPoll(Map<String, dynamic> poll) async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EditPollSheet(poll: poll),
    );
    if (changed == true) _load();
  }

  Future<void> _deletePoll(Map<String, dynamic> poll) async {
    final id = poll['id'] as String;
    final titel = poll['titel'] as String? ?? 'afstemning';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Slet afstemning?'),
        content: Text('"$titel" og alle stemmer fjernes permanent.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annullér')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: _danger),
            child: const Text('Slet'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final opts =
          await supabase.from('poll_options').select('id').eq('poll_id', id);
      final optIds = (opts as List).map((o) => o['id'] as String).toList();
      if (optIds.isNotEmpty) {
        await supabase
            .from('poll_responses')
            .delete()
            .inFilter('poll_option_id', optIds);
      }
      await supabase.from('poll_options').delete().eq('poll_id', id);
      final deleted =
          await supabase.from('polls').delete().eq('id', id).select();
      if (!mounted) return;
      _snack(
        context,
        (deleted as List).isEmpty
            ? 'Kunne ikke slette — mangler du rettigheder?'
            : 'Afstemning slettet',
        (deleted).isEmpty ? _danger : _textSecondary,
      );
      _load();
    } on PostgrestException catch (e) {
      if (mounted) _snack(context, e.message, _danger);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return _loadingSkeleton();
    if (_error != null) return _ErrorView(error: _error!, onRetry: _load);
    if (_polls.isEmpty) {
      return const Center(
        child: _EmptyState(
          icon: Icons.how_to_vote_outlined,
          title: 'Ingen afstemninger endnu',
          subtitle: 'Tryk + for at oprette en afstemning',
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 700),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Åbne / Afsluttede — kompakt pille-toggle (som prototypen)
                  Builder(builder: (context) {
                    bool erLukket(Map<String, dynamic> p) =>
                        p['lukket_at'] != null &&
                        DateTime.parse(p['lukket_at'] as String)
                            .isBefore(DateTime.now());
                    final aabne = _visiblePolls.where((p) => !erLukket(p)).length;
                    final lukkede = _visiblePolls.where(erLukket).length;
                    Widget seg(String label, int i) {
                      final active = _tab == i;
                      return GestureDetector(
                        onTap: () => setState(() => _tab = i),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: active ? _surfaceElevated : Colors.transparent,
                            borderRadius: BorderRadius.circular(9),
                            boxShadow: active
                                ? [BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 3, offset: const Offset(0, 1))]
                                : null,
                          ),
                          child: Text(label.toUpperCase(),
                              style: _cond(
                                  size: 15,
                                  weight: FontWeight.w800,
                                  spacing: 0.3,
                                  color: active ? _textPrimary : _textMuted)),
                        ),
                      );
                    }
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 16, top: 4),
                      child: Row(children: [
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1C1713),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            seg('Åbne · $aabne', 0),
                            seg('Afsluttede · $lukkede', 1),
                          ]),
                        ),
                      ]),
                    );
                  }),
                  ..._visiblePolls.where((p) {
                    final lukket = p['lukket_at'] != null &&
                        DateTime.parse(p['lukket_at'] as String)
                            .isBefore(DateTime.now());
                    return _tab == 0 ? !lukket : lukket;
                  }).map((p) {
                    final lukket = p['lukket_at'] != null &&
                        DateTime.parse(p['lukket_at'] as String).isBefore(DateTime.now());
                    final beskr = p['beskrivelse'] as String?;
                    final lukkeInfo = () {
                      if (p['lukket_at'] == null) return 'Åben';
                      final l = DateTime.parse(p['lukket_at'] as String);
                      if (lukket) return 'Afsluttet · du stemte';
                      return 'Lukker ${_omDage(l).toLowerCase()}';
                    }();
                    final isDato = (p['type'] as String?) != 'tekst';
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 11),
                      child: Opacity(
                        opacity: lukket ? 0.8 : 1,
                        child: Container(
                          decoration: BoxDecoration(
                            color: _surfaceDark,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: _borderSubtle),
                          ),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: () => _open(p),
                            child: Padding(
                              padding: const EdgeInsets.all(15),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(children: [
                                    if (lukket)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 9, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: _textMuted.withValues(alpha: 0.16),
                                          borderRadius: BorderRadius.circular(999),
                                        ),
                                        child: Text('LUKKET',
                                            style: _body(
                                                size: 10,
                                                weight: FontWeight.w700,
                                                spacing: 1,
                                                color: _textSecondary)),
                                      )
                                    else
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 9, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: _success.withValues(alpha: 0.16),
                                          borderRadius: BorderRadius.circular(999),
                                        ),
                                        child: Text('ÅBEN',
                                            style: _body(
                                                size: 10,
                                                weight: FontWeight.w700,
                                                spacing: 1,
                                                color: _success)),
                                      ),
                                    const SizedBox(width: 8),
                                    Icon(
                                        isDato
                                            ? Icons.event_outlined
                                            : Icons.how_to_vote_outlined,
                                        size: 13,
                                        color: isDato ? _neon : _textMuted),
                                    const SizedBox(width: 4),
                                    Text(isDato ? 'Datovalg' : 'Afstemning',
                                        style: _body(
                                            size: 10.5,
                                            weight: FontWeight.w700,
                                            color: isDato ? _neon : _textMuted)),
                                    const Spacer(),
                                    Text(lukkeInfo,
                                        style: _body(
                                            size: 11, color: _textSecondary)),
                                    if (_canManagePoll(p))
                                      PopupMenuButton<String>(
                                        icon: const Icon(Icons.more_vert,
                                            size: 18, color: _textMuted),
                                        padding: EdgeInsets.zero,
                                        onSelected: (v) {
                                          if (v == 'edit') _editPoll(p);
                                          if (v == 'delete') _deletePoll(p);
                                        },
                                        itemBuilder: (_) => const [
                                          PopupMenuItem(
                                            value: 'edit',
                                            child: Row(children: [
                                              Icon(Icons.edit_outlined,
                                                  size: 18, color: _textSecondary),
                                              SizedBox(width: 10),
                                              Text('Redigér'),
                                            ]),
                                          ),
                                          PopupMenuItem(
                                            value: 'delete',
                                            child: Row(children: [
                                              Icon(Icons.delete_outline,
                                                  size: 18, color: _danger),
                                              SizedBox(width: 10),
                                              Text('Slet'),
                                            ]),
                                          ),
                                        ],
                                      ),
                                  ]),
                                  const SizedBox(height: 10),
                                  Text((p['titel'] as String).toUpperCase(),
                                      style: _cond(
                                          size: 18, weight: FontWeight.w800)),
                                  // Hvilke hold er spurgt? Tom = klub-bred.
                                  if (_groupNamesOf(p).isNotEmpty) ...[
                                    const SizedBox(height: 5),
                                    Wrap(
                                      spacing: 6,
                                      runSpacing: 6,
                                      children: [
                                        for (final navn in _groupNamesOf(p))
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 9, vertical: 3),
                                            decoration: BoxDecoration(
                                              color: _surfaceElevated,
                                              borderRadius:
                                                  BorderRadius.circular(999),
                                              border: Border.all(
                                                  color: _borderSubtle),
                                            ),
                                            child: Text(navn,
                                                style: _body(
                                                    size: 10.5,
                                                    weight: FontWeight.w700,
                                                    color: _textSecondary)),
                                          ),
                                      ],
                                    ),
                                  ],
                                  if (beskr != null && beskr.isNotEmpty) ...[
                                    const SizedBox(height: 3),
                                    Text(beskr,
                                        style: _body(
                                            size: 12.5, color: _textSecondary)),
                                  ],
                                  const SizedBox(height: 12),
                                  Row(children: [
                                    Icon(Icons.arrow_forward,
                                        size: 15,
                                        color: lukket ? _textSecondary : _neon),
                                    const SizedBox(width: 7),
                                    Text(lukket ? 'Se resultat' : 'Åbn og stem',
                                        style: _body(
                                            size: 13,
                                            weight: FontWeight.w600,
                                            color: lukket ? _textSecondary : _neon)),
                                  ]),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Redigér en afstemning — titel, beskrivelse, stemmefrist, hold.
/// (Svarmuligheder redigeres ikke, da de kan have stemmer — slet og opret i så fald.)
class _EditPollSheet extends StatefulWidget {
  final Map<String, dynamic> poll;
  const _EditPollSheet({required this.poll});
  @override
  State<_EditPollSheet> createState() => _EditPollSheetState();
}

class _EditPollSheetState extends State<_EditPollSheet> {
  late final _titel =
      TextEditingController(text: widget.poll['titel'] as String? ?? '');
  late final _beskr =
      TextEditingController(text: widget.poll['beskrivelse'] as String? ?? '');
  DateTime? _frist;
  List<Map<String, dynamic>> _groups = const [];
  final Set<String> _groupIds = {}; // tom = klub-bred
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _groupIds.addAll(_pollGroupIds(widget.poll));
    final l = widget.poll['lukket_at'] as String?;
    if (l != null) _frist = DateTime.parse(l).toLocal();
    _loadGroups();
  }

  @override
  void dispose() {
    _titel.dispose();
    _beskr.dispose();
    super.dispose();
  }

  Future<void> _loadGroups() async {
    try {
      final rows = await supabase
          .from('groups')
          .select('id, navn, farve, sort')
          .order('sort');
      if (mounted) {
        setState(() => _groups = List<Map<String, dynamic>>.from(rows as List));
      }
    } catch (_) {}
  }

  Future<void> _save() async {
    if (_titel.text.trim().isEmpty) {
      _snack(context, 'Titel må ikke være tom', _gold);
      return;
    }
    setState(() => _saving = true);
    try {
      await supabase.from('polls').update({
        'titel': _titel.text.trim(),
        'beskrivelse':
            _beskr.text.trim().isEmpty ? null : _beskr.text.trim(),
        'group_ids': _groupIds.isEmpty ? null : _groupIds.toList(),
        'group_id': _groupIds.length == 1 ? _groupIds.first : null,
        'lukket_at': _frist?.toUtc().toIso8601String(),
      }).eq('id', widget.poll['id']);
      if (!mounted) return;
      _snack(context, 'Afstemning opdateret', _success);
      Navigator.of(context).pop(true);
    } on PostgrestException catch (e) {
      if (mounted) _snack(context, e.message, _danger);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _chip(String label, String? id) {
    final active = id == null ? _groupIds.isEmpty : _groupIds.contains(id);
    return GestureDetector(
      onTap: () => setState(() {
        if (id == null) {
          _groupIds.clear();
        } else {
          if (!_groupIds.add(id)) _groupIds.remove(id);
        }
      }),
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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.9),
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
                Expanded(child: Text('REDIGÉR AFSTEMNING',
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_groups.isNotEmpty) ...[
                      Text('Hvem kan stemme?',
                          style: _body(size: 13, weight: FontWeight.w600,
                              color: _textSecondary)),
                      const SizedBox(height: 8),
                      Wrap(spacing: 8, runSpacing: 8, children: [
                        _chip('Alle', null),
                        for (final g in _groups)
                          _chip(g['navn'] as String, g['id'] as String),
                      ]),
                      const SizedBox(height: 16),
                    ],
                    TextField(
                      controller: _titel,
                      decoration: const InputDecoration(labelText: 'Titel'),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _beskr,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Beskrivelse',
                        helperText: 'Valgfri',
                      ),
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
                              : 'Afstemningen lukker automatisk på dette tidspunkt',
                          style: const TextStyle(color: _textMuted, fontSize: 11),
                        ),
                      ),
                    ]),
                  ],
                ),
              ),
            ),
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
                        : const Text('Gem'),
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

class PollDetailScreen extends StatefulWidget {
  final Map<String, dynamic> poll;
  const PollDetailScreen({super.key, required this.poll});
  @override
  State<PollDetailScreen> createState() => _PollDetailScreenState();
}

class _PollDetailScreenState extends State<PollDetailScreen> {
  List<Map<String, dynamic>> _options = const [];
  Map<String, bool> _myVotes = {};
  Map<String, int> _yesCounts = {}; // option_id → antal "kan"/"valgt" (svar=true)
  int _totalVoters = 0;
  bool _loading = true;
  String? _error;

  // ── Stemme-overblik (kun staff/opretter/kaptajn) ──────────────────────────
  /// Alle der forventes at stemme: holdets medlemmer uden trænerne.
  List<Map<String, dynamic>> _eligible = const [];
  /// option_id → navnene på dem der kan den dato.
  Map<String, List<String>> _jaNavne = {};
  /// Muligheder foldet ud med navne (staff).
  final Set<String> _udvidede = {};
  /// Alle der har afgivet mindst ét svar — også dem der kun har svaret nej.
  Set<String> _responded = {};
  final Set<String> _remindSkip = {}; // fravalgt inden rykker sendes
  bool _canManage = false;
  bool _busy = false;

  bool get _isText => widget.poll['type'] == 'tekst';
  bool get _allowMultiple => widget.poll['allow_multiple'] != false;


  bool get _lukket =>
      widget.poll['lukket_at'] != null &&
      DateTime.parse(widget.poll['lukket_at'] as String).isBefore(DateTime.now());

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// [stille] = genindlæs uden at vise spinneren. Bruges efter en stemme:
  /// udskiftes indholdet med en loader, mister listen sin scroll-position og
  /// hopper til toppen — irriterende når man skal sætte flueben ved 26 datoer.
  Future<void> _load({bool stille = false}) async {
    if (!stille) setState(() { _loading = true; _error = null; });
    try {
      final userId = supabase.auth.currentUser!.id;
      final options = await supabase
          .from('poll_options')
          .select('id, option_tid, beskrivelse, heldags')
          .eq('poll_id', widget.poll['id'])
          // Ældste dato først. Uden ascending sorterer klienten faldende.
          .order('option_tid', ascending: true);

      final optList = List<Map<String, dynamic>>.from(options as List);
      final optIds  = optList.map((o) => o['id'] as String).toList();

      // Alle svar (til resultat-bjælker) — ikke kun mine.
      final allResponses = optIds.isEmpty
          ? const <Map<String, dynamic>>[]
          : List<Map<String, dynamic>>.from(await supabase
              .from('poll_responses')
              .select('poll_option_id, user_id, svar')
              .inFilter('poll_option_id', optIds) as List);

      final votes = <String, bool>{};
      final counts = <String, int>{ for (final id in optIds) id: 0 };
      final voters = <String>{};
      final responded = <String>{};
      for (final r in allResponses) {
        final oid  = r['poll_option_id'] as String;
        final uid  = r['user_id'] as String;
        final svar = r['svar'] as bool;
        responded.add(uid);
        if (svar) {
          counts[oid] = (counts[oid] ?? 0) + 1;
          voters.add(uid);
        }
        if (uid == userId) votes[oid] = svar;
      }

      // Stemme-overblik: hvem må se det, og hvem forventes at stemme?
      final gids = _pollGroupIds(widget.poll);
      final res = await Future.wait([
        supabase.from('profiles').select('id, navn, rolle').order('navn'),
        supabase.from('group_members')
            .select('group_id, user_id, is_captain, is_trainer'),
      ]);
      final profiles = List<Map<String, dynamic>>.from(res[0] as List);
      final gm = List<Map<String, dynamic>>.from(res[1] as List);

      // Navne pr. dato — sorteret, så listen står ens hver gang.
      final navnById = {
        for (final p in profiles) p['id'] as String: p['navn'] as String? ?? '?'
      };
      final jaNavne = <String, List<String>>{ for (final id in optIds) id: [] };
      for (final r in allResponses) {
        if (r['svar'] != true) continue;
        final oid = r['poll_option_id'] as String;
        jaNavne[oid]?.add(navnById[r['user_id'] as String] ?? '(ukendt)');
      }
      for (final l in jaNavne.values) {
        l.sort();
      }

      final me = profiles.firstWhere((p) => p['id'] == userId,
          orElse: () => const <String, dynamic>{});
      final isStaff = me['rolle'] == 'admin' || me['rolle'] == 'træner';
      final erKaptajn = gm.any((r) =>
          r['user_id'] == userId &&
          r['is_captain'] == true &&
          gids.contains(r['group_id']));
      final canManage = isStaff ||
          widget.poll['created_by'] == userId ||
          erKaptajn;

      // Stemme-pligtige: holdets medlemmer der ikke er trænere dér. Uden hold
      // (klub-bred) forventes alle. Den der har stemt tælles altid med.
      final playerIds = <String>{};
      for (final r in gm) {
        if (r['is_trainer'] == true) continue;
        if (gids.contains(r['group_id'])) playerIds.add(r['user_id'] as String);
      }
      final eligible = profiles
          .where((p) => gids.isEmpty
              ? true
              : playerIds.contains(p['id']) || responded.contains(p['id']))
          .toList();

      setState(() {
        _options     = optList;
        _myVotes     = votes;
        _yesCounts   = counts;
        _totalVoters = voters.length;
        _jaNavne     = jaNavne;
        _responded   = responded;
        _eligible    = eligible;
        _canManage   = canManage;
        _loading     = false;
      });
    } catch (e) {
      setState(() { _loading = false; _error = e.toString(); });
    }
  }

  List<Map<String, dynamic>> get _harStemt =>
      _eligible.where((p) => _responded.contains(p['id'])).toList();
  List<Map<String, dynamic>> get _manglerAtStemme =>
      _eligible.where((p) => !_responded.contains(p['id'])).toList();

  Future<void> _sendRykker() async {
    final modtagere = _manglerAtStemme
        .where((p) => !_remindSkip.contains(p['id']))
        .length;
    if (modtagere == 0) return;
    setState(() => _busy = true);
    try {
      final n = await supabase.rpc('send_poll_reminders', params: {
        'p_poll_id': widget.poll['id'],
        'p_exclude': _remindSkip.toList(),
      });
      if (!mounted) return;
      _snack(context,
          n == 0 ? 'Ingen at påminde' : 'Rykker sendt til $n', _success);
    } on PostgrestException catch (e) {
      if (mounted) _snack(context, e.message, _danger);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Hvem har stemt, hvad stemte de, og hvem mangler. Kun for staff, opretter
  /// og kaptajn — spillerne ser kun de anonyme resultat-bjælker.
  Widget _stemmeOverblik(ThemeData theme) {
    if (!_canManage || _eligible.isEmpty) return const SizedBox.shrink();
    final stemt = _harStemt;
    final mangler = _manglerAtStemme;
    final skalPaamindes =
        mangler.where((p) => !_remindSkip.contains(p['id'])).length;

    Widget person(Map<String, dynamic> p, {required bool harStemt}) {
      final navn = p['navn'] as String? ?? '(ukendt)';
      final id = p['id'] as String;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: [
            _InitialAvatar(navn: navn, size: 32),
            const SizedBox(width: 11),
            Expanded(
              child: Text(navn,
                  style: _body(size: 14, weight: FontWeight.w600),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            if (harStemt)
              const Icon(Icons.check_circle, size: 18, color: _success),
            if (!harStemt)
              IconButton(
                onPressed: () => setState(() => _remindSkip.contains(id)
                    ? _remindSkip.remove(id)
                    : _remindSkip.add(id)),
                icon: Icon(
                    _remindSkip.contains(id)
                        ? Icons.notifications_off_outlined
                        : Icons.notifications_active_outlined,
                    size: 18,
                    color: _remindSkip.contains(id) ? _textMuted : _neon),
                visualDensity: VisualDensity.compact,
                tooltip: _remindSkip.contains(id)
                    ? 'Påmindes ikke'
                    : 'Får en rykker',
              ),
          ],
        ),
      );
    }

    Widget header(String tekst, int antal, Color farve) => Padding(
          padding: const EdgeInsets.only(top: 14, bottom: 2),
          child: Row(children: [
            Text(tekst,
                style: _body(
                    size: 12,
                    weight: FontWeight.w700,
                    color: _textSecondary,
                    spacing: 1)),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                  color: farve.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(999)),
              child: Text('$antal',
                  style: _body(
                      size: 11, weight: FontWeight.w700, color: farve)),
            ),
          ]),
        );

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 6, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            header('HAR STEMT', stemt.length, _success),
            if (stemt.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text('Ingen har svaret endnu',
                    style: _body(size: 13, color: _textMuted)),
              )
            else
              for (final p in stemt) person(p, harStemt: true),
            header('MANGLER AT STEMME', mangler.length, _gold),
            if (mangler.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text('Alle har svaret 🎉',
                    style: _body(size: 13, color: _success)),
              )
            else ...[
              for (final p in mangler) person(p, harStemt: false),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed:
                      (_busy || skalPaamindes == 0 || _lukket) ? null : _sendRykker,
                  icon: _busy
                      ? const SizedBox(
                          width: 16, height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.notifications_active, size: 18),
                  label: Text(_lukket
                      ? 'Afstemningen er lukket'
                      : skalPaamindes == 0
                          ? 'Ingen valgt'
                          : 'Påmind $skalPaamindes der mangler'),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                    'Rykkeren lander i deres notifikations-klokke. Tryk på '
                    'klokken ud for en person for at springe dem over.',
                    style: _body(size: 11.5, color: _textMuted)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _vote(String optionId, bool svar) async {
    final originalVote = _myVotes[optionId];
    setState(() => _myVotes = {..._myVotes, optionId: svar});
    try {
      await supabase.from('poll_responses').upsert({
        'poll_option_id': optionId,
        'user_id':        supabase.auth.currentUser!.id,
        'svar':           svar,
      }, onConflict: 'poll_option_id,user_id');
      await _load(stille: true); // opdatér tal uden at nulstille scroll
    } on PostgrestException catch (e) {
      setState(() {
        final map = {..._myVotes};
        if (originalVote == null) {
          map.remove(optionId);
        } else {
          map[optionId] = originalVote;
        }
        _myVotes = map;
      });
      if (mounted) _snack(context, e.message, Colors.red);
    }
  }

  /// Enkelt-valg (tekst-afstemning uden "tillad flere svar"): vælg netop ét.
  Future<void> _voteSingle(String optionId) async {
    final prev = {..._myVotes};
    setState(() => _myVotes = {
          for (final o in _options) o['id'] as String: o['id'] == optionId
        });
    try {
      final uid = supabase.auth.currentUser!.id;
      final rows = _options
          .map((o) => {
                'poll_option_id': o['id'],
                'user_id': uid,
                'svar': o['id'] == optionId,
              })
          .toList();
      await supabase
          .from('poll_responses')
          .upsert(rows, onConflict: 'poll_option_id,user_id');
      await _load(stille: true);
    } on PostgrestException catch (e) {
      setState(() => _myVotes = prev);
      if (mounted) _snack(context, e.message, Colors.red);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final beskr = widget.poll['beskrivelse'] as String?;

    final lukketAt = widget.poll['lukket_at'] as String?;
    final fristStr = lukketAt == null
        ? 'Ingen stemmefrist'
        : (_lukket
            ? 'Afsluttet ${_fmtDateTime(DateTime.parse(lukketAt).toLocal())}'
            : 'Stemmefrist ${_fmtDateTime(DateTime.parse(lukketAt).toLocal())}');

    return Scaffold(
      appBar: AppBar(
        title: const Text('AFSTEMNING'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _ErrorView(error: _error!, onRetry: _load)
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 700),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text((widget.poll['titel'] as String).toUpperCase(),
                                style: _cond(size: 20, weight: FontWeight.w800)),
                            const SizedBox(height: 5),
                            Row(children: [
                              const Icon(Icons.schedule,
                                  size: 14, color: _textSecondary),
                              const SizedBox(width: 6),
                              Text(fristStr,
                                  style: _body(size: 12.5, color: _textSecondary)),
                            ]),
                            const SizedBox(height: 12),
                            if (beskr != null && beskr.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Text(beskr,
                                    style: theme.textTheme.bodyMedium
                                        ?.copyWith(color: _textSecondary)),
                              ),
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12, top: 4),
                              child: Text(
                                _lukket
                                    ? 'Afsluttet — afstemningen er låst'
                                    : _isText
                                        ? (_allowMultiple
                                            ? 'Vælg de svar der passer'
                                            : 'Vælg ét svar')
                                        : 'Sæt flueben ved de datoer du kan',
                                style: _body(size: 12, color: _textMuted),
                              ),
                            ),
                            Card(
                              child: Padding(
                                padding: const EdgeInsets.all(6),
                                child: Column(
                                  children: [
                                    for (final o in _options)
                                      if (_isText)
                                        _PollTextRow(
                                          label: o['beskrivelse'] as String? ?? '',
                                          selected:
                                              _myVotes[o['id'] as String] == true,
                                          count: _yesCounts[o['id'] as String] ?? 0,
                                          total: _totalVoters,
                                          single: !_allowMultiple,
                                          locked: _lukket,
                                          onTap: () {
                                            final id = o['id'] as String;
                                            final sel =
                                                _myVotes[id] == true;
                                            if (_allowMultiple) {
                                              _vote(id, !sel);
                                            } else if (!sel) {
                                              _voteSingle(id);
                                            }
                                          },
                                        )
                                      else
                                        _PollCheckRow(
                                          tid: DateTime.parse(
                                              o['option_tid'] as String).toLocal(),
                                          heldags: _optionHeldags(o),
                                          label: o['beskrivelse'] as String?,
                                          checked:
                                              _myVotes[o['id'] as String] == true,
                                          yesCount:
                                              _yesCounts[o['id'] as String] ?? 0,
                                          maxYes: _yesCounts.values.isEmpty
                                              ? 0
                                              : _yesCounts.values.fold<int>(
                                                  0, (m, v) => v > m ? v : m),
                                          locked: _lukket,
                                          onToggle: () => _vote(
                                              o['id'] as String,
                                              !(_myVotes[o['id'] as String] ==
                                                  true)),
                                          // Kun staff kan folde navnene ud.
                                          jaNavne:
                                              _jaNavne[o['id'] as String] ??
                                                  const [],
                                          udvidet: _udvidede
                                              .contains(o['id'] as String),
                                          onUdvid: !_canManage
                                              ? null
                                              : () => setState(() {
                                                    final id =
                                                        o['id'] as String;
                                                    _udvidede.contains(id)
                                                        ? _udvidede.remove(id)
                                                        : _udvidede.add(id);
                                                  }),
                                        ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            _stemmeOverblik(theme),
                            if (!_isText) ...[
                              const SizedBox(height: 12),
                              OutlinedButton.icon(
                                onPressed: () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        FavoritePairsScreen(poll: widget.poll),
                                  ),
                                ),
                                icon: const Icon(Icons.favorite_border, size: 18),
                                label: const Text('Favorit-par pr. dato'),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }
}

/// Én linje navne bag et ikon — "Kan: Anders, Bo, Carl".
class _NavneLinje extends StatelessWidget {
  final IconData ikon;
  final Color farve;
  final String tekst;
  final List<String> navne;
  const _NavneLinje({
    required this.ikon,
    required this.farve,
    required this.tekst,
    required this.navne,
  });

  @override
  Widget build(BuildContext context) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(ikon, size: 15, color: farve),
      const SizedBox(width: 7),
      Text('$tekst:',
          style: _body(size: 12.5, weight: FontWeight.w700, color: farve)),
      const SizedBox(width: 6),
      Expanded(
        child: Text(navne.isEmpty ? 'ingen' : navne.join(', '),
            style: _body(
                size: 12.5,
                color: navne.isEmpty ? _textMuted : _textPrimary)),
      ),
    ]);
  }
}

/// Checkbox-række med resultat-bjælke — "kan du denne dato?"
class _PollCheckRow extends StatelessWidget {
  final DateTime tid;
  final bool heldags; // hele dagen → vis kun datoen
  final String? label;
  final bool checked;
  final int yesCount;
  final int maxYes;
  final bool locked;
  final VoidCallback onToggle;
  // Hvem kan denne dato. Kun udfyldt for staff/opretter/kaptajn.
  final List<String> jaNavne;
  final bool udvidet;
  final VoidCallback? onUdvid;

  const _PollCheckRow({
    required this.tid,
    this.heldags = false,
    required this.label,
    required this.checked,
    required this.yesCount,
    required this.maxYes,
    required this.locked,
    required this.onToggle,
    this.jaNavne = const [],
    this.udvidet = false,
    this.onUdvid,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final frac = maxYes == 0 ? 0.0 : yesCount / maxYes;
    final barColor = checked ? _success : _neon;
    return InkWell(
      onTap: locked ? null : onToggle,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        child: Column(
          children: [
            Row(
              children: [
                // Checkbox
                Container(
                  width: 22, height: 22,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: checked ? _success : Colors.transparent,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: checked ? _success : _textMuted,
                      width: 1.5,
                    ),
                  ),
                  child: checked
                      ? const Icon(Icons.check, size: 15, color: _onSuccess)
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_fmtOption(tid, heldags: heldags),
                          style: theme.textTheme.bodyLarge
                              ?.copyWith(fontWeight: FontWeight.w600)),
                      if (label != null && label!.isNotEmpty)
                        Text(label!, style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // Tallet er sin egen knap for staff: fold ud og se navnene.
                // Selve rækken bliver ved med at afgive din egen stemme.
                if (onUdvid == null)
                  Text('$yesCount',
                      style: _cond(size: 18, weight: FontWeight.w800,
                          color: checked ? _success : _textSecondary))
                else
                  InkWell(
                    onTap: onUdvid,
                    borderRadius: BorderRadius.circular(999),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Text('$yesCount',
                            style: _cond(size: 18, weight: FontWeight.w800,
                                color: checked ? _success : _textSecondary)),
                        const SizedBox(width: 4),
                        Icon(udvidet ? Icons.expand_less : Icons.expand_more,
                            size: 18, color: _textMuted),
                      ]),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: frac.clamp(0.0, 1.0),
                minHeight: 8,
                backgroundColor: _surfaceElevated,
                valueColor: AlwaysStoppedAnimation(barColor),
              ),
            ),
            if (udvidet) ...[
              const SizedBox(height: 10),
              _NavneLinje(
                  ikon: Icons.check_circle,
                  farve: _success,
                  tekst: 'Kan',
                  navne: jaNavne),
            ],
          ],
        ),
      ),
    );
  }
}

/// Svarmulighed-række (tekst-afstemning) med resultat-procent.
class _PollTextRow extends StatelessWidget {
  final String label;
  final bool selected;
  final int count;
  final int total;
  final bool single; // true = radio (ét valg), false = checkbox (flere)
  final bool locked;
  final VoidCallback onTap;
  const _PollTextRow({
    required this.label,
    required this.selected,
    required this.count,
    required this.total,
    required this.single,
    required this.locked,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final pct = total == 0 ? 0.0 : count / total;
    final barColor = selected ? _success : _neon;
    return InkWell(
      onTap: locked ? null : onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 22, height: 22,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: selected ? _success : Colors.transparent,
                    borderRadius: BorderRadius.circular(single ? 999 : 6),
                    border: Border.all(
                        color: selected ? _success : _textMuted, width: 1.5),
                  ),
                  child: selected
                      ? const Icon(Icons.check, size: 15, color: Colors.white)
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(label,
                      style: _body(size: 14, weight: FontWeight.w600)),
                ),
                const SizedBox(width: 8),
                Text('${(pct * 100).round()}%',
                    style: _cond(
                        size: 16,
                        weight: FontWeight.w800,
                        color: selected ? _success : _textSecondary)),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: pct.clamp(0.0, 1.0),
                minHeight: 8,
                backgroundColor: _surfaceElevated,
                valueColor: AlwaysStoppedAnimation(barColor),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tab 4: Bødekassen — leaderboard + per-spiller historik
// ─────────────────────────────────────────────────────────────────────────────

