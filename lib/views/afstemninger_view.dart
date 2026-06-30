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
              Icon(Icons.how_to_vote_outlined, size: 64, color: Colors.grey.shade400),
              const SizedBox(height: 16),
              const Text('Ingen aktive afstemninger'),
            ],
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        itemCount: _polls.length,
        itemBuilder: (_, i) {
          final p = _polls[i];
          final lukket = p['lukket_at'] != null &&
              DateTime.parse(p['lukket_at'] as String).isBefore(DateTime.now());
          final beskr = p['beskrivelse'] as String?;
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 700),
              child: Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  leading: Icon(
                    lukket ? Icons.lock_outline : Icons.how_to_vote,
                    color: lukket ? Colors.grey : Colors.teal,
                  ),
                  title: Text(p['titel'] as String),
                  subtitle: Text(
                    beskr != null && beskr.isNotEmpty
                        ? beskr
                        : (lukket ? 'Afsluttet' : 'Klik for at stemme'),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _open(p),
                ),
              ),
            ),
          );
        },
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
      final userId = supabase.auth.currentUser!.id;
      final options = await supabase
          .from('poll_options')
          .select('id, option_tid, beskrivelse')
          .eq('poll_id', widget.poll['id'])
          .order('option_tid');

      final optList = List<Map<String, dynamic>>.from(options as List);
      final optIds  = optList.map((o) => o['id'] as String).toList();

      final responses = optIds.isEmpty
          ? const <Map<String, dynamic>>[]
          : List<Map<String, dynamic>>.from(await supabase
              .from('poll_responses')
              .select('poll_option_id, svar')
              .eq('user_id', userId)
              .inFilter('poll_option_id', optIds) as List);

      final votes = <String, bool>{
        for (final r in responses)
          r['poll_option_id'] as String: r['svar'] as bool,
      };

      setState(() {
        _options = optList;
        _myVotes = votes;
        _loading = false;
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
                          children: [
                            if (beskr != null && beskr.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 16),
                                child: Text(beskr, style: theme.textTheme.bodyMedium),
                              ),
                            ..._options.map((o) {
                              final id = o['id'] as String;
                              final tid = DateTime.parse(o['option_tid'] as String).toLocal();
                              final label = o['beskrivelse'] as String?;
                              final myVote = _myVotes[id];
                              return _PollOptionRow(
                                tid: tid,
                                label: label,
                                myVote: myVote,
                                onYes: () => _vote(id, true),
                                onNo:  () => _vote(id, false),
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

class _PollOptionRow extends StatelessWidget {
  final DateTime tid;
  final String? label;
  final bool? myVote;
  final VoidCallback onYes;
  final VoidCallback onNo;

  const _PollOptionRow({
    required this.tid,
    required this.label,
    required this.myVote,
    required this.onYes,
    required this.onNo,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_fmtDateTime(tid), style: theme.textTheme.titleMedium),
                  if (label != null && label!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(label!, style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant)),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            _VoteButton(
              label: 'JA',
              icon: Icons.thumb_up_outlined,
              activeIcon: Icons.thumb_up,
              active: myVote == true,
              activeColor: Colors.green,
              onPressed: onYes,
            ),
            const SizedBox(width: 8),
            _VoteButton(
              label: 'NEJ',
              icon: Icons.thumb_down_outlined,
              activeIcon: Icons.thumb_down,
              active: myVote == false,
              activeColor: Colors.red.shade700,
              onPressed: onNo,
            ),
          ],
        ),
      ),
    );
  }
}

class _VoteButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final IconData activeIcon;
  final bool active;
  final Color activeColor;
  final VoidCallback onPressed;
  const _VoteButton({
    required this.label,
    required this.icon,
    required this.activeIcon,
    required this.active,
    required this.activeColor,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    if (active) {
      return FilledButton.icon(
        onPressed: onPressed,
        icon: Icon(activeIcon, size: 18),
        label: Text(label),
        style: FilledButton.styleFrom(
          backgroundColor: activeColor,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      );
    }
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tab 4: Bødekassen — leaderboard + per-spiller historik
// ─────────────────────────────────────────────────────────────────────────────

