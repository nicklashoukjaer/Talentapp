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

  @override
  void initState() {
    super.initState();
    _addDate();
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
                _QuickDateTimeField(
                  label: 'Stemmefrist (valgfri)',
                  value: _frist,
                  onChanged: (v) => setState(() => _frist = v),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 4, left: 4, bottom: 4),
                  child: Text(
                    _frist == null
                        ? 'Tom = åben indtil du selv lukker den'
                        : 'Afstemningen lukker automatisk — ingen kan stemme efter',
                    style: const TextStyle(color: _textMuted, fontSize: 11),
                  ),
                ),
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

