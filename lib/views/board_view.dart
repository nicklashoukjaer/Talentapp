// Auto-split (del af biblioteket padel_app)
// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
part of '../main.dart';

class TrainingBoardScreen extends StatefulWidget {
  final Map<String, dynamic> training;
  const TrainingBoardScreen({super.key, required this.training});
  @override
  State<TrainingBoardScreen> createState() => _TrainingBoardScreenState();
}

class _BoardItem {
  final String userId;
  final String navn;
  final String status;
  const _BoardItem(this.userId, this.navn, this.status);
}

class _TrainingBoardScreenState extends State<TrainingBoardScreen> {
  List<_BoardItem> _items = const [];
  bool _loading = true;
  bool _sendingReminders = false;
  String? _error;

  static const _statuses = ['tilmeldt', 'venteliste', 'afmeldt'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final rows = await supabase
          .from('training_participants')
          .select('user_id, status, profiles!training_participants_user_id_fkey(navn)')
          .eq('training_id', widget.training['id'])
          .order('registered_at');
      final list = (rows as List).map((r) {
        final m = r as Map<String, dynamic>;
        final profile = m['profiles'] as Map<String, dynamic>?;
        return _BoardItem(
          m['user_id'] as String,
          profile?['navn'] as String? ?? '(ukendt)',
          m['status'] as String,
        );
      }).toList();
      setState(() { _items = list; _loading = false; });
    } catch (e) {
      setState(() { _loading = false; _error = e.toString(); });
    }
  }

  Future<void> _move(_BoardItem item, String newStatus) async {
    if (item.status == newStatus) return;
    final original = _items;
    setState(() {
      _items = _items.map((i) =>
        i.userId == item.userId ? _BoardItem(i.userId, i.navn, newStatus) : i,
      ).toList();
    });
    try {
      await supabase
          .from('training_participants')
          .update({'status': newStatus})
          .eq('training_id', widget.training['id'])
          .eq('user_id', item.userId);
    } on PostgrestException catch (e) {
      setState(() => _items = original);
      if (mounted) _snack(context, e.message, Colors.red);
    }
  }

  Future<void> _sendReminders() async {
    setState(() => _sendingReminders = true);
    try {
      final count = await supabase.rpc('send_training_reminders',
          params: {'p_training_id': widget.training['id']});
      if (!mounted) return;
      _snack(context,
          'Rykker sendt til $count medlem${count == 1 ? '' : 'mer'}',
          Colors.green);
    } on PostgrestException catch (e) {
      if (mounted) _snack(context, e.message, Colors.red);
    } finally {
      if (mounted) setState(() => _sendingReminders = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.training['titel'] as String),
        actions: [
          IconButton(
            onPressed: _load,
            icon: const Icon(Icons.refresh),
            tooltip: 'Opdater',
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: FilledButton.icon(
              onPressed: _sendingReminders ? null : _sendReminders,
              icon: _sendingReminders
                  ? const SizedBox(width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.notifications_active_outlined),
              label: const Text('Send rykker'),
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _ErrorView(error: _error!, onRetry: _load)
              : Padding(
                  padding: const EdgeInsets.all(16),
                  child: LayoutBuilder(builder: (ctx, constraints) {
                    final wide = constraints.maxWidth > 800;
                    final cols = _statuses.map((s) => Expanded(
                      child: _BoardColumn(
                        status: s,
                        items: _items.where((i) => i.status == s).toList(),
                        onAccept: (item) => _move(item, s),
                      ),
                    )).toList();
                    if (wide) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (int i = 0; i < cols.length; i++) ...[
                            cols[i],
                            if (i != cols.length - 1) const SizedBox(width: 12),
                          ],
                        ],
                      );
                    }
                    return Column(
                      children: [
                        for (int i = 0; i < cols.length; i++) ...[
                          SizedBox(height: 220, child: cols[i]),
                          if (i != cols.length - 1) const SizedBox(height: 12),
                        ],
                      ],
                    );
                  }),
                ),
    );
  }
}

class _BoardColumn extends StatelessWidget {
  final String status;
  final List<_BoardItem> items;
  final ValueChanged<_BoardItem> onAccept;
  const _BoardColumn({
    required this.status,
    required this.items,
    required this.onAccept,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (label, color, icon) = switch (status) {
      'tilmeldt'   => ('Tilmeldt',   Colors.green,  Icons.check_circle),
      'venteliste' => ('Venteliste', Colors.orange, Icons.hourglass_top),
      'afmeldt'    => ('Afmeldt',    Colors.grey,   Icons.cancel),
      _            => (status,        Colors.blue,   Icons.help),
    };
    return DragTarget<_BoardItem>(
      onWillAcceptWithDetails: (d) => d.data.status != status,
      onAcceptWithDetails: (d) => onAccept(d.data),
      builder: (ctx, candidate, rejected) {
        final highlight = candidate.isNotEmpty;
        return Container(
          decoration: BoxDecoration(
            color: highlight ? color.withValues(alpha: 0.10) : theme.colorScheme.surfaceContainerHighest,
            border: Border.all(color: highlight ? color : Colors.transparent, width: 2),
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(icon, color: color),
                  const SizedBox(width: 8),
                  Text(label, style: theme.textTheme.titleMedium),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: color, borderRadius: BorderRadius.circular(12)),
                    child: Text('${items.length}',
                        style: const TextStyle(color: Colors.white,
                            fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: items.isEmpty
                    ? Center(child: Text('Ingen',
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.grey)))
                    : ListView.builder(
                        itemCount: items.length,
                        itemBuilder: (_, i) => _BoardChip(item: items[i]),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _BoardChip extends StatelessWidget {
  final _BoardItem item;
  const _BoardChip({required this.item});

  @override
  Widget build(BuildContext context) {
    final tile = Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        dense: true,
        leading: CircleAvatar(
          radius: 14,
          child: Text(item.navn.isNotEmpty ? item.navn[0].toUpperCase() : '?',
              style: const TextStyle(fontSize: 12)),
        ),
        title: Text(item.navn),
        trailing: const Icon(Icons.drag_indicator, size: 18, color: Colors.grey),
      ),
    );
    return LongPressDraggable<_BoardItem>(
      data: item,
      delay: const Duration(milliseconds: 150),
      feedback: Material(
        elevation: 6,
        borderRadius: BorderRadius.circular(8),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 240),
          child: tile,
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.3, child: tile),
      child: tile,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// iCal export (web download)
// ─────────────────────────────────────────────────────────────────────────────

