// Auto-split (del af biblioteket padel_app)
// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
part of '../main.dart';

class AfstemningerTab extends StatefulWidget {
  const AfstemningerTab({super.key});
  @override
  State<AfstemningerTab> createState() => _AfstemningerTabState();
}

class _AfstemningerTabState extends State<AfstemningerTab> {
  List<Map<String, dynamic>> _polls = const [];
  bool _loading = true;
  String? _error;
  int _tab = 0; // 0 = Åbne, 1 = Afsluttede

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final rows = await supabase
          .from('polls')
          .select('id, titel, beskrivelse, lukket_at, created_at')
          .order('created_at', ascending: false);
      setState(() {
        _polls = List<Map<String, dynamic>>.from(rows as List);
        _loading = false;
      });
    } catch (e) {
      setState(() { _loading = false; _error = e.toString(); });
    }
  }

  void _open(Map<String, dynamic> poll) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PollDetailScreen(poll: poll),
    )).then((_) => _load());
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return _ErrorView(error: _error!, onRetry: _load);
    if (_polls.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.how_to_vote_outlined, size: 64, color: _textMuted),
              const SizedBox(height: 16),
              const Text('Ingen aktive afstemninger'),
            ],
          ),
        ),
      );
    }
    final theme = Theme.of(context);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 700),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16, left: 4, top: 4),
                    child: Row(children: [
                      Container(
                        width: 4, height: 32,
                        decoration: const BoxDecoration(
                          color: _neon,
                          borderRadius: BorderRadius.all(Radius.circular(2)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text('AFSTEMNINGER', style: theme.textTheme.headlineSmall),
                    ]),
                  ),
                  // Åbne / Afsluttede — pille-toggle
                  Builder(builder: (context) {
                    bool erLukket(Map<String, dynamic> p) =>
                        p['lukket_at'] != null &&
                        DateTime.parse(p['lukket_at'] as String)
                            .isBefore(DateTime.now());
                    final aabne = _polls.where((p) => !erLukket(p)).length;
                    final lukkede = _polls.where(erLukket).length;
                    Widget seg(String label, int i) {
                      final active = _tab == i;
                      return Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() => _tab = i),
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
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: _surfaceDark,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: _borderSubtle),
                        ),
                        child: Row(children: [
                          seg('Åbne · $aabne', 0),
                          seg('Afsluttede · $lukkede', 1),
                        ]),
                      ),
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
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Opacity(
                        opacity: lukket ? 0.75 : 1,
                        child: Card(
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: () => _open(p),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(children: [
                                    if (lukket)
                                      const Icon(Icons.check_circle,
                                          size: 18, color: _success)
                                    else
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 9, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: _neon.withValues(alpha: 0.16),
                                          borderRadius: BorderRadius.circular(999),
                                        ),
                                        child: Text('ÅBEN',
                                            style: _body(
                                                size: 10,
                                                weight: FontWeight.w700,
                                                spacing: 1,
                                                color: _neon)),
                                      ),
                                    const Spacer(),
                                    Text(lukkeInfo,
                                        style: _body(size: 12, color: _textSecondary)),
                                    const SizedBox(width: 6),
                                    const Icon(Icons.chevron_right,
                                        size: 20, color: _textMuted),
                                  ]),
                                  const SizedBox(height: 10),
                                  Text(p['titel'] as String,
                                      style: theme.textTheme.titleLarge),
                                  if (beskr != null && beskr.isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Text(beskr,
                                        style: theme.textTheme.bodyMedium
                                            ?.copyWith(color: _textSecondary)),
                                  ],
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

class PollDetailScreen extends StatefulWidget {
  final Map<String, dynamic> poll;
  const PollDetailScreen({super.key, required this.poll});
  @override
  State<PollDetailScreen> createState() => _PollDetailScreenState();
}

class _PollDetailScreenState extends State<PollDetailScreen> {
  List<Map<String, dynamic>> _options = const [];
  Map<String, bool> _myVotes = {};
  Map<String, int> _yesCounts = {}; // option_id → antal "kan" (svar=true)
  bool _loading = true;
  String? _error;

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
      for (final r in allResponses) {
        final oid  = r['poll_option_id'] as String;
        final svar = r['svar'] as bool;
        if (svar) counts[oid] = (counts[oid] ?? 0) + 1;
        if (r['user_id'] == userId) votes[oid] = svar;
      }

      setState(() {
        _options   = optList;
        _myVotes   = votes;
        _yesCounts = counts;
        _loading   = false;
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
                                      _PollCheckRow(
                                        tid: DateTime.parse(
                                            o['option_tid'] as String).toLocal(),
                                        label: o['beskrivelse'] as String?,
                                        checked: _myVotes[o['id'] as String] == true,
                                        yesCount: _yesCounts[o['id'] as String] ?? 0,
                                        maxYes: _yesCounts.values.isEmpty
                                            ? 0
                                            : _yesCounts.values
                                                .fold<int>(0, (m, v) => v > m ? v : m),
                                        locked: _lukket,
                                        onToggle: () => _vote(
                                            o['id'] as String,
                                            !(_myVotes[o['id'] as String] == true)),
                                      ),
                                  ],
                                ),
                              ),
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

// ─────────────────────────────────────────────────────────────────────────────
// Tab 4: Bødekassen — leaderboard + per-spiller historik
// ─────────────────────────────────────────────────────────────────────────────

