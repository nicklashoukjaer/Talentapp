// Auto-split (del af biblioteket padel_app)
// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
part of '../main.dart';

class TraeningerTab extends StatefulWidget {
  final bool isAdmin;
  const TraeningerTab({super.key, required this.isAdmin});
  @override
  State<TraeningerTab> createState() => _TraeningerTabState();
}

class _TraeningerTabState extends State<TraeningerTab> {
  List<Map<String, dynamic>> _trainings = const [];
  Map<String, String> _myStatus = const {};
  Map<String, int>    _signedUp = const {};
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
      final trainings = await supabase
          .from('trainings')
          .select('id, titel, beskrivelse, max_deltagere, start_tid, slut_tid, adresse, tilmeldings_deadline')
          .gte('start_tid', DateTime.now().toUtc().toIso8601String())
          .order('start_tid');

      final tList = List<Map<String, dynamic>>.from(trainings as List);
      final ids   = tList.map((t) => t['id'] as String).toList();

      final futures = <Future>[
        supabase
            .from('training_participants')
            .select('training_id, status')
            .eq('user_id', userId),
        if (ids.isNotEmpty)
          supabase
              .from('training_participants')
              .select('training_id, status')
              .inFilter('training_id', ids)
        else
          Future.value(const []),
      ];
      final results = await Future.wait(futures);

      final myRows  = List<Map<String, dynamic>>.from(results[0] as List);
      final allRows = List<Map<String, dynamic>>.from(results[1] as List);

      final myStatus = <String, String>{
        for (final r in myRows) r['training_id'] as String: r['status'] as String,
      };
      final counts = <String, int>{};
      for (final r in allRows) {
        if (r['status'] == 'tilmeldt') {
          final id = r['training_id'] as String;
          counts[id] = (counts[id] ?? 0) + 1;
        }
      }

      setState(() {
        _trainings = tList;
        _myStatus  = myStatus;
        _signedUp  = counts;
        _loading   = false;
      });
    } catch (e) {
      setState(() { _loading = false; _error = e.toString(); });
    }
  }

  Future<void> _signUp(Map<String, dynamic> training) async {
    try {
      final status = await supabase.rpc('register_for_training',
          params: {'p_training_id': training['id']});
      if (!mounted) return;
      _snack(context,
          status == 'tilmeldt' ? 'Du er tilmeldt' : 'Du er på venteliste',
          status == 'tilmeldt' ? Colors.green : Colors.orange);
      await _load();
    } on PostgrestException catch (e) {
      if (mounted) _snack(context, e.message, Colors.red);
    }
  }

  Future<void> _withdraw(Map<String, dynamic> training) async {
    try {
      final userId = supabase.auth.currentUser!.id;
      await supabase.from('training_participants').update({'status': 'afmeldt'})
          .eq('training_id', training['id'])
          .eq('user_id', userId);
      if (!mounted) return;
      _snack(context, 'Du er meldt fra', Colors.grey);
      await _load();
    } on PostgrestException catch (e) {
      if (mounted) _snack(context, e.message, Colors.red);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return _ErrorView(error: _error!, onRetry: _load);
    if (_trainings.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.event_busy, size: 64, color: Colors.grey.shade400),
              const SizedBox(height: 16),
              const Text('Ingen kommende træninger'),
              const SizedBox(height: 8),
              if (widget.isAdmin)
                const Text('Tryk Ctrl+K → "opret" for at komme i gang.',
                    style: TextStyle(color: Colors.grey)),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        itemCount: _trainings.length,
        itemBuilder: (_, i) {
          final t = _trainings[i];
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 700),
              child: _TrainingCard(
                training: t,
                myStatus: _myStatus[t['id']],
                signedUpCount: _signedUp[t['id']] ?? 0,
                isAdmin: widget.isAdmin,
                onSignUp:   () => _signUp(t),
                onWithdraw: () => _withdraw(t),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _TrainingCard extends StatelessWidget {
  final Map<String, dynamic> training;
  final String? myStatus;
  final int signedUpCount;
  final bool isAdmin;
  final VoidCallback onSignUp;
  final VoidCallback onWithdraw;
  const _TrainingCard({
    required this.training,
    required this.myStatus,
    required this.signedUpCount,
    required this.isAdmin,
    required this.onSignUp,
    required this.onWithdraw,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final start    = DateTime.parse(training['start_tid'] as String).toLocal();
    final slut     = DateTime.parse(training['slut_tid'] as String).toLocal();
    final deadline = DateTime.parse(training['tilmeldings_deadline'] as String).toLocal();
    final adresse  = training['adresse'] as String;
    final titel    = training['titel'] as String;
    final beskr    = training['beskrivelse'] as String?;
    final max      = training['max_deltagere'] as int?;

    final deadlinePassed = DateTime.now().isAfter(deadline);
    final canSignUp = !deadlinePassed || isAdmin;
    final hasAddress = adresse.isNotEmpty && adresse != _addressUnspecified;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: Text(titel, style: theme.textTheme.titleLarge)),
                _StatusChip(status: myStatus),
              ],
            ),
            if (beskr != null && beskr.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(beskr, style: theme.textTheme.bodyMedium),
            ],
            const SizedBox(height: 12),
            _InfoRow(icon: Icons.schedule,
                text: '${_fmtDateTime(start)} – ${_fmtTime(slut)}'),
            if (hasAddress)
              _InfoRow(icon: Icons.place_outlined, text: adresse),
            _InfoRow(
              icon: Icons.group_outlined,
              text: max == null
                  ? '$signedUpCount tilmeldt · ∞'
                  : '$signedUpCount/$max tilmeldt',
              color: (max != null && signedUpCount >= max) ? Colors.orange.shade800 : null,
            ),
            _InfoRow(
              icon: deadlinePassed ? Icons.lock_clock : Icons.timer_outlined,
              text: deadlinePassed
                  ? 'Frist overskredet (${_fmtDateTime(deadline)})'
                  : 'Tilmeldingsfrist ${_fmtDateTime(deadline)}',
              color: deadlinePassed ? Colors.red.shade700 : null,
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (myStatus == null || myStatus == 'afmeldt')
                  FilledButton.icon(
                    onPressed: canSignUp ? onSignUp : null,
                    icon: const Icon(Icons.check_circle_outline),
                    label: const Text('Tilmeld'),
                  )
                else
                  OutlinedButton.icon(
                    onPressed: canSignUp ? onWithdraw : null,
                    icon: const Icon(Icons.cancel_outlined),
                    label: const Text('Meld fra'),
                  ),
                OutlinedButton.icon(
                  onPressed: () => _downloadIcs(training),
                  icon: const Icon(Icons.calendar_month_outlined),
                  label: const Text('Tilføj til kalender'),
                ),
                if (deadlinePassed && !isAdmin)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text('Tilmelding lukket',
                      style: TextStyle(color: Colors.grey.shade600,
                        fontStyle: FontStyle.italic)),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color? color;
  const _InfoRow({required this.icon, required this.text, this.color});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color ?? Colors.grey.shade700),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: TextStyle(color: color))),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String? status;
  const _StatusChip({required this.status});
  @override
  Widget build(BuildContext context) {
    if (status == null) return const SizedBox.shrink();
    final (label, color) = switch (status) {
      'tilmeldt'   => ('Tilmeldt',   Colors.green),
      'venteliste' => ('Venteliste', Colors.orange),
      'afmeldt'    => ('Afmeldt',    Colors.grey),
      _            => (status!,      Colors.blueGrey),
    };
    return Chip(
      label: Text(label, style: const TextStyle(color: Colors.white, fontSize: 12)),
      backgroundColor: color,
      visualDensity: VisualDensity.compact,
      side: BorderSide.none,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tab 3: Afstemninger — medlemsvisning
// ─────────────────────────────────────────────────────────────────────────────

