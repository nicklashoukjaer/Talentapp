// Auto-split (del af biblioteket padel_app)
// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
part of '../main.dart';

class BodekasseTab extends StatefulWidget {
  final bool isAdmin;
  final String currentUserId;
  const BodekasseTab({super.key, required this.isAdmin, required this.currentUserId});
  @override
  State<BodekasseTab> createState() => BodekasseTabState();
}

class BodekasseTabState extends State<BodekasseTab> {
  List<Map<String, dynamic>> _rows = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    reload();
  }

  Future<void> reload() async {
    // Instant UI: vis cachet holdsaldo med det samme.
    final cached = CacheService.getList('leaderboard');
    if (cached != null) {
      _rows = cached;
      _loading = false;
      if (mounted) setState(() {});
    } else {
      setState(() { _loading = true; _error = null; });
    }
    try {
      final rows = await supabase
          .from('fine_leaderboard')
          .select()
          .order('skyldigt_oere', ascending: false);
      final list = List<Map<String, dynamic>>.from(rows as List);
      CacheService.put('leaderboard', list);
      if (!mounted) return;
      setState(() { _rows = list; _loading = false; });
    } catch (e) {
      if (!mounted) return;
      if (_rows.isEmpty) setState(() { _loading = false; _error = e.toString(); });
    }
  }

  void _open(Map<String, dynamic> row) {
    final canOpen = widget.isAdmin || row['id'] == widget.currentUserId;
    if (!canOpen) {
      _snack(context, 'Kun admins kan se andre spilleres historik', Colors.orange);
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => FineHistoryScreen(
        userId:   row['id']   as String,
        userName: row['navn'] as String,
        isAdmin:  widget.isAdmin,
      ),
    )).then((_) => reload());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return _ErrorView(error: _error!, onRetry: reload);

    return RefreshIndicator(
      onRefresh: reload,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16, left: 8, top: 8),
                    child: LayoutBuilder(builder: (ctx, constraints) {
                      final wide = constraints.maxWidth >= 480;
                      final titleRow = Row(
                        children: [
                          Icon(Icons.emoji_events, size: 28, color: Colors.amber.shade700),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text('Bødekasse — Highscore',
                                style: theme.textTheme.headlineSmall,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                          ),
                        ],
                      );
                      final actions = Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          OutlinedButton.icon(
                            onPressed: () async {
                              await showDialog<bool>(
                                context: context,
                                builder: (_) => const SuggestFineTypeDialog(),
                              );
                            },
                            icon: const Icon(Icons.lightbulb_outline, size: 18),
                            label: const Text('Foreslå'),
                          ),
                          const SizedBox(width: 4),
                          IconButton(
                            onPressed: reload,
                            icon: const Icon(Icons.refresh),
                            tooltip: 'Opdater',
                          ),
                        ],
                      );
                      if (wide) {
                        return Row(
                          children: [
                            Expanded(child: titleRow),
                            actions,
                          ],
                        );
                      }
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          titleRow,
                          const SizedBox(height: 8),
                          actions,
                        ],
                      );
                    }),
                  ),
                  if (_rows.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(child: Text('Ingen profiler endnu')),
                    )
                  else
                    ..._rows.asMap().entries.map((e) => _LeaderboardRow(
                          rank: e.key + 1,
                          row: e.value,
                          isOwn: e.value['id'] == widget.currentUserId,
                          onTap: () => _open(e.value),
                        )),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LeaderboardRow extends StatelessWidget {
  final int rank;
  final Map<String, dynamic> row;
  final bool isOwn;
  final VoidCallback onTap;
  const _LeaderboardRow({
    required this.rank,
    required this.row,
    required this.isOwn,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final navn       = row['navn']         as String;
    final skyldigt   = (row['skyldigt_oere'] as num).toInt();
    final betalt     = (row['betalt_oere']   as num).toInt();
    final total      = (row['total_oere']    as num).toInt();
    final ubetalteN  = (row['ubetalte_antal'] as num).toInt();

    final (rankBg, rankFg) = switch (rank) {
      1 => (Colors.amber.shade700, Colors.white),
      2 => (Colors.grey.shade400,  Colors.white),
      3 => (Colors.brown.shade400, Colors.white),
      _ => (theme.colorScheme.surfaceContainerHighest,
            theme.colorScheme.onSurfaceVariant),
    };

    final stats = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _StatColumn(
          label: 'Skyldigt',
          value: _fmtKr(skyldigt),
          color: skyldigt > 0 ? Colors.red.shade700 : Colors.grey,
          bold: skyldigt > 0,
        ),
        const SizedBox(width: 8),
        _StatColumn(
          label: 'Betalt',
          value: _fmtKr(betalt),
          color: Colors.green.shade700,
        ),
        const SizedBox(width: 8),
        _StatColumn(
          label: 'Total',
          value: _fmtKr(total),
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ],
    );

    final nameBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Flexible(
              child: Text(navn,
                  style: theme.textTheme.titleMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ),
            if (isOwn) ...[
              const SizedBox(width: 6),
              Chip(
                label: const Text('Mig', style: TextStyle(fontSize: 10)),
                visualDensity: VisualDensity.compact,
                backgroundColor: theme.colorScheme.primaryContainer,
                side: BorderSide.none,
              ),
            ],
          ],
        ),
        if (ubetalteN > 0)
          Text('$ubetalteN ubetalt${ubetalteN == 1 ? "" : "e"}',
              style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.red.shade700,
                  fontWeight: FontWeight.w600)),
      ],
    );

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: LayoutBuilder(builder: (ctx, constraints) {
            // Under ~480 px stables stats lodret under navnet — pænere på mobil
            final compact = constraints.maxWidth < 480;
            final rankCircle = Container(
              width: 36, height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: rankBg, shape: BoxShape.circle),
              child: Text('$rank',
                  style: TextStyle(color: rankFg,
                      fontSize: 16, fontWeight: FontWeight.bold)),
            );
            if (compact) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  rankCircle,
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        nameBlock,
                        const SizedBox(height: 8),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: stats,
                        ),
                      ],
                    ),
                  ),
                ],
              );
            }
            return Row(
              children: [
                rankCircle,
                const SizedBox(width: 14),
                Expanded(flex: 3, child: nameBlock),
                const SizedBox(width: 8),
                stats,
              ],
            );
          }),
        ),
      ),
    );
  }
}

class _StatColumn extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final bool bold;
  const _StatColumn({
    required this.label,
    required this.value,
    required this.color,
    this.bold = false,
  });
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 78,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(label, style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant)),
          Text(value, style: TextStyle(
              color: color,
              fontWeight: bold ? FontWeight.bold : FontWeight.w600,
              fontSize: 14)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// FineHistoryScreen — bøde-historik for én spiller
// ─────────────────────────────────────────────────────────────────────────────

class FineHistoryScreen extends StatefulWidget {
  final String userId;
  final String userName;
  final bool isAdmin;
  const FineHistoryScreen({
    super.key,
    required this.userId,
    required this.userName,
    required this.isAdmin,
  });
  @override
  State<FineHistoryScreen> createState() => _FineHistoryScreenState();
}

class _FineHistoryScreenState extends State<FineHistoryScreen> {
  List<Map<String, dynamic>> _fines = const [];
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
          .from('fines')
          .select('id, titel, belob_oere, begrundelse, status, created_at, paid_at')
          .eq('user_id', widget.userId)
          .order('created_at', ascending: false);
      setState(() {
        _fines = List<Map<String, dynamic>>.from(rows as List);
        _loading = false;
      });
    } catch (e) {
      setState(() { _loading = false; _error = e.toString(); });
    }
  }

  Future<void> _approve(Map<String, dynamic> fine) async {
    try {
      await supabase.from('fines').update({
        'status':      'godkendt_betalt',
        'approved_by': supabase.auth.currentUser!.id,
        'paid_at':     DateTime.now().toUtc().toIso8601String(),
      }).eq('id', fine['id']);
      if (mounted) _snack(context, 'Markeret som betalt', Colors.green);
      await _load();
    } on PostgrestException catch (e) {
      if (mounted) _snack(context, e.message, Colors.red);
    }
  }

  /// Åbner MobilePay med det skyldige beløb forudfyldt (øre → kroner).
  Future<void> _payWithMobilePay(int oere) async {
    var box = ClubConfig.cachedBox;
    box ??= await ClubConfig.fetchMobilePayBox();
    if (box == null || box.trim().isEmpty || box.trim() == 'VORES_BOX_NUMMER') {
      if (mounted) {
        _snack(context,
            'MobilePay er ikke sat op endnu — en admin kan indtaste Box-ID under Dashboard.',
            Colors.orange);
      }
      return;
    }
    final uri = Uri.parse(mobilePayLinkFor(box, oere));
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      _snack(context, 'Kunne ikke åbne MobilePay', Colors.red);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final totalUbetalt = _fines
        .where((f) => f['status'] == 'ubetalt')
        .fold<int>(0, (s, f) => s + ((f['belob_oere'] as num).toInt()));
    final totalBetalt = _fines
        .where((f) => f['status'] == 'godkendt_betalt')
        .fold<int>(0, (s, f) => s + ((f['belob_oere'] as num).toInt()));

    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.userName} — bødehistorik'),
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
                            Card(
                              child: Padding(
                                padding: const EdgeInsets.all(20),
                                child: Row(
                                  children: [
                                    Expanded(child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('Skyldigt nu',
                                            style: theme.textTheme.bodySmall?.copyWith(
                                                color: theme.colorScheme.onSurfaceVariant)),
                                        Text(_fmtKr(totalUbetalt),
                                            style: theme.textTheme.headlineMedium?.copyWith(
                                                color: totalUbetalt > 0 ? Colors.red.shade700 : Colors.grey)),
                                      ],
                                    )),
                                    Container(
                                      width: 1, height: 56,
                                      color: theme.dividerColor,
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('Betalt total',
                                            style: theme.textTheme.bodySmall?.copyWith(
                                                color: theme.colorScheme.onSurfaceVariant)),
                                        Text(_fmtKr(totalBetalt),
                                            style: theme.textTheme.headlineMedium?.copyWith(
                                                color: Colors.green.shade700)),
                                      ],
                                    )),
                                  ],
                                ),
                              ),
                            ),
                            if (totalUbetalt > 0 &&
                                widget.userId ==
                                    supabase.auth.currentUser?.id) ...[
                              const SizedBox(height: 16),
                              SizedBox(
                                width: double.infinity,
                                child: FilledButton.icon(
                                  onPressed: () =>
                                      _payWithMobilePay(totalUbetalt),
                                  icon: const Icon(
                                      Icons.account_balance_wallet_outlined),
                                  label: const Text('Betal med MobilePay'),
                                  style: FilledButton.styleFrom(
                                    backgroundColor: const Color(0xFF0055FF),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 16),
                                    textStyle: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 15,
                                        letterSpacing: 0.3),
                                  ),
                                ),
                              ),
                            ],
                            const SizedBox(height: 16),
                            if (_fines.isEmpty)
                              const Padding(
                                padding: EdgeInsets.all(32),
                                child: Center(child: Text('Ingen bøder endnu — clean record! 🎉')),
                              )
                            else
                              ..._fines.map((f) => _FineHistoryRow(
                                fine: f,
                                isAdmin: widget.isAdmin,
                                onApprove: () => _approve(f),
                              )),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }
}

class _FineHistoryRow extends StatelessWidget {
  final Map<String, dynamic> fine;
  final bool isAdmin;
  final VoidCallback onApprove;
  const _FineHistoryRow({
    required this.fine,
    required this.isAdmin,
    required this.onApprove,
  });

  @override
  Widget build(BuildContext context) {
    final theme    = Theme.of(context);
    final titel    = fine['titel']      as String;
    final oere     = (fine['belob_oere'] as num).toInt();
    final begrund  = fine['begrundelse'] as String?;
    final status   = fine['status']      as String;
    final created  = DateTime.parse(fine['created_at'] as String).toLocal();
    final isPaid   = status == 'godkendt_betalt';

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(isPaid ? Icons.check_circle : Icons.cancel,
                color: isPaid ? Colors.green : Colors.red.shade700, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(titel,
                          style: theme.textTheme.titleMedium)),
                      Text(_fmtKr(oere),
                          style: theme.textTheme.titleMedium?.copyWith(
                              color: isPaid ? Colors.grey : Colors.red.shade700,
                              fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text('Givet ${_fmtDate(created)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant)),
                  if (begrund != null && begrund.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(begrund,
                        style: theme.textTheme.bodyMedium?.copyWith(
                            fontStyle: FontStyle.italic)),
                  ],
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Chip(
                        label: Text(isPaid ? 'Godkendt betalt' : 'Ubetalt',
                            style: const TextStyle(color: Colors.white, fontSize: 11)),
                        backgroundColor: isPaid ? Colors.green : Colors.red.shade700,
                        visualDensity: VisualDensity.compact,
                        side: BorderSide.none,
                      ),
                      if (isAdmin && !isPaid) ...[
                        const Spacer(),
                        FilledButton.icon(
                          onPressed: onApprove,
                          icon: const Icon(Icons.check, size: 16),
                          label: const Text('Godkend betaling'),
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.green.shade700,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tab 5: Træner Dashboard — Træninger + Afstemninger + Bøde-administration
// ─────────────────────────────────────────────────────────────────────────────

