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

  /// Må den aktuelle bruger slette denne afstemning? (staff, opretter eller
  /// kaptajn for afstemningens hold)
  bool _canManagePoll(Map<String, dynamic> p) {
    if (widget.isStaff) return true;
    if (p['created_by'] == supabase.auth.currentUser?.id) return true;
    final gid = p['group_id'] as String?;
    return gid != null && _myCaptainGroupIds.contains(gid);
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
            .select('id, titel, beskrivelse, lukket_at, created_at, group_id, created_by, type')
            .order('created_at', ascending: false),
        supabase.from('group_members').select('group_id, is_captain').eq('user_id', userId),
      ]);
      final allPolls = List<Map<String, dynamic>>.from(results[0] as List);
      final myGm = List<Map<String, dynamic>>.from(results[1] as List);
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
              final gid = p['group_id'] as String?;
              return gid == null || myIds.contains(gid);
            }).toList();
      if (!mounted) return;
      setState(() {
        _polls = visible;
        _myCaptainGroupIds = myCaptainIds;
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = e.toString(); });
    }
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
                    final aabne = _polls.where((p) => !erLukket(p)).length;
                    final lukkede = _polls.where(erLukket).length;
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
                  ..._polls.where((p) {
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
  String? _groupId;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _groupId = widget.poll['group_id'] as String?;
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
        'group_id': _groupId,
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

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final userId = supabase.auth.currentUser!.id;
      final options = await supabase
          .from('poll_options')
          .select('id, option_tid, beskrivelse')
          .eq('poll_id', widget.poll['id'])
          .order('option_tid');

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
      for (final r in allResponses) {
        final oid  = r['poll_option_id'] as String;
        final svar = r['svar'] as bool;
        if (svar) {
          counts[oid] = (counts[oid] ?? 0) + 1;
          voters.add(r['user_id'] as String);
        }
        if (r['user_id'] == userId) votes[oid] = svar;
      }

      setState(() {
        _options     = optList;
        _myVotes     = votes;
        _yesCounts   = counts;
        _totalVoters = voters.length;
        _loading     = false;
      });
    } catch (e) {
      setState(() { _loading = false; _error = e.toString(); });
    }
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
      await _load(); // opdatér resultat-bjælker
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
      await _load();
    } on PostgrestException catch (e) {
      setState(() => _myVotes = prev);
      if (mounted) _snack(context, e.message, Colors.red);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final beskr = widget.poll['beskrivelse'] as String?;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.poll['titel'] as String),
        actions: [
          IconButton(
            onPressed: _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
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
                                        ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            if (!_isText)
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
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }
}

/// Checkbox-række med resultat-bjælke — "kan du denne dato?"
class _PollCheckRow extends StatelessWidget {
  final DateTime tid;
  final String? label;
  final bool checked;
  final int yesCount;
  final int maxYes;
  final bool locked;
  final VoidCallback onToggle;

  const _PollCheckRow({
    required this.tid,
    required this.label,
    required this.checked,
    required this.yesCount,
    required this.maxYes,
    required this.locked,
    required this.onToggle,
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
                      Text(_fmtDateTime(tid),
                          style: theme.textTheme.bodyLarge
                              ?.copyWith(fontWeight: FontWeight.w600)),
                      if (label != null && label!.isNotEmpty)
                        Text(label!, style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text('$yesCount',
                    style: _cond(size: 18, weight: FontWeight.w800,
                        color: checked ? _success : _textSecondary)),
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

