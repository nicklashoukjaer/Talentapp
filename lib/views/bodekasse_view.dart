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
      // Highscore = flest bøder gennem tiden (total). Skyldigt bruges til
      // "Du skylder"-callout og ubetalt-markering.
      final rows = await supabase
          .from('fine_leaderboard')
          .select()
          .order('total_oere', ascending: false);
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

  /// Åbner MobilePay med det skyldige beløb forudfyldt — til spillerens holds boks.
  Future<void> _payWithMobilePay(int oere) async {
    final box = await _resolveMobilePayBox(context);
    if (box == null) return; // resolver har allerede vist besked / bruger fortrød
    final uri = Uri.parse(mobilePayLinkFor(box, oere));
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      _snack(context, 'Kunne ikke åbne MobilePay', _danger);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_loading) return _loadingSkeleton();
    if (_error != null) return _ErrorView(error: _error!, onRetry: reload);

    return RefreshIndicator(
      onRefresh: reload,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
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
                    const _EmptyState(
                      icon: Icons.emoji_events_outlined,
                      title: 'Ingen bøder endnu',
                      subtitle: 'Bødekassen fyldes når nogen får en bøde',
                    )
                  else ...[
                    _Podium(
                      rows: _rows.take(3).toList(),
                      currentUserId: widget.currentUserId,
                    ),
                    const SizedBox(height: 20),
                    Builder(builder: (context) {
                      final myRow = _rows.cast<Map<String, dynamic>?>().firstWhere(
                          (r) => r!['id'] == widget.currentUserId,
                          orElse: () => null);
                      final mySkyldigt =
                          myRow == null ? 0 : (myRow['skyldigt_oere'] as num).toInt();
                      if (mySkyldigt <= 0) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 20),
                        child: _DuSkylderCallout(
                          oere: mySkyldigt,
                          onPay: () => _payWithMobilePay(mySkyldigt),
                        ),
                      );
                    }),
                    ..._rows.asMap().entries.map((e) => _LeaderboardRow(
                          rank: e.key + 1,
                          row: e.value,
                          isOwn: e.value['id'] == widget.currentUserId,
                          onTap: () => _open(e.value),
                        )),
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

/// Podium (top 3) — #1 i midten, højere og i accent; #2 og #3 lavere.
class _Podium extends StatelessWidget {
  final List<Map<String, dynamic>> rows;
  final String currentUserId;
  const _Podium({required this.rows, required this.currentUserId});

  @override
  Widget build(BuildContext context) {
    Map<String, dynamic>? at(int i) => i < rows.length ? rows[i] : null;
    // Rækkefølge: #2 · #1 · #3
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(child: _PodiumSpot(row: at(1), rank: 2, currentUserId: currentUserId)),
        const SizedBox(width: 8),
        Expanded(child: _PodiumSpot(row: at(0), rank: 1, currentUserId: currentUserId)),
        const SizedBox(width: 8),
        Expanded(child: _PodiumSpot(row: at(2), rank: 3, currentUserId: currentUserId)),
      ],
    );
  }
}

class _PodiumSpot extends StatelessWidget {
  final Map<String, dynamic>? row;
  final int rank;
  final String currentUserId;
  const _PodiumSpot({
    required this.row,
    required this.rank,
    required this.currentUserId,
  });

  @override
  Widget build(BuildContext context) {
    final isFirst = rank == 1;
    final avatarSize = isFirst ? 56.0 : 46.0;
    final pedestalH  = isFirst ? 60.0 : (rank == 2 ? 44.0 : 32.0);
    final navn  = row?['navn'] as String? ?? '—';
    final total = row == null ? 0 : (row!['total_oere'] as num).toInt();
    final isMe  = row != null && row!['id'] == currentUserId;
    final empty = row == null;

    final avatarColor = empty
        ? _surfaceElevated
        : (isFirst ? _neon : _surfaceElevated);
    final initial = navn.trim().isEmpty || empty
        ? '–'
        : navn.trim().substring(0, 1).toUpperCase();

    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        if (isFirst)
          const Padding(
            padding: EdgeInsets.only(bottom: 2),
            child: Text('👑', style: TextStyle(fontSize: 20)),
          ),
        Container(
          width: avatarSize,
          height: avatarSize,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: avatarColor,
            shape: BoxShape.circle,
            border: Border.all(
              color: isFirst ? _neon : _borderSubtle,
              width: isFirst ? 3 : 1,
            ),
            boxShadow: isFirst
                ? [BoxShadow(color: _neon.withValues(alpha: 0.4), blurRadius: 16)]
                : null,
          ),
          child: Text(initial,
              style: _cond(
                  size: avatarSize * 0.4,
                  weight: FontWeight.w800,
                  color: isFirst ? Colors.white : _textSecondary)),
        ),
        const SizedBox(height: 8),
        Text(isMe ? '$navn · Dig' : navn,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: _body(
                size: 12,
                weight: FontWeight.w600,
                color: empty ? _textMuted : _textPrimary)),
        const SizedBox(height: 2),
        Text('$rank',
            style: _body(size: 11, color: _textMuted)),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          height: pedestalH,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isFirst
                ? _neon.withValues(alpha: 0.16)
                : _surfaceDark,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            border: Border.all(
                color: isFirst ? _neon.withValues(alpha: 0.4) : _borderSubtle),
          ),
          child: Text(_fmtKr(total),
              style: _cond(
                  size: isFirst ? 20 : 16,
                  weight: FontWeight.w800,
                  color: empty ? _textMuted : (isFirst ? _neon : _textPrimary))),
        ),
      ],
    );
  }
}

/// "Du skylder"-callout — rød-tonet kort med MobilePay-betaling.
class _DuSkylderCallout extends StatelessWidget {
  final int oere;
  final VoidCallback onPay;
  const _DuSkylderCallout({required this.oere, required this.onPay});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _danger.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _danger.withValues(alpha: 0.5)),
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        runSpacing: 12,
        spacing: 12,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('DU SKYLDER',
                  style: _body(
                      size: 11,
                      weight: FontWeight.w700,
                      spacing: 1.2,
                      color: _danger)),
              const SizedBox(height: 2),
              Text(_fmtKr(oere),
                  style: _cond(size: 22, weight: FontWeight.w800, color: _danger)),
            ],
          ),
          FilledButton.icon(
            onPressed: onPay,
            icon: const Icon(Icons.account_balance_wallet_outlined, size: 18),
            label: const Text('Betal med MobilePay'),
            style: FilledButton.styleFrom(
              backgroundColor: _success,
              foregroundColor: _onSuccess,
            ),
          ),
        ],
      ),
    );
  }
}

/// Rangliste-række — rang-badge (guld/sølv) + navn + ubetalt + total.
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
    final navn      = row['navn']          as String;
    final total     = (row['total_oere']    as num).toInt();
    final ubetalteN = (row['ubetalte_antal'] as num).toInt();

    final (rankBg, rankFg) = switch (rank) {
      1 => (_gold,   _onGold),
      2 => (_silver, _bgBlack),
      3 => (const Color(0xFFB07B4F), Colors.white),
      _ => (_surfaceElevated, _textSecondary),
    };

    return RepaintBoundary(
      child: Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 34, height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: rankBg, shape: BoxShape.circle),
                child: Text('$rank',
                    style: _cond(size: 17, weight: FontWeight.w800, color: rankFg)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
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
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: _neon.withValues(alpha: 0.16),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text('DIG',
                                style: _body(
                                    size: 9,
                                    weight: FontWeight.w700,
                                    spacing: 0.6,
                                    color: _neon)),
                          ),
                        ],
                      ],
                    ),
                    if (ubetalteN > 0)
                      Text('$ubetalteN ubetalt${ubetalteN == 1 ? "" : "e"}',
                          style: _body(
                              size: 12, weight: FontWeight.w600, color: _danger)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_fmtKr(total),
                      style: _cond(size: 18, weight: FontWeight.w800)),
                  Text('total', style: _body(size: 11, color: _textMuted)),
                ],
              ),
            ],
          ),
        ),
      ),
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

  /// Sletter en bøde permanent (fx hvis den er givet forkert).
  Future<void> _delete(Map<String, dynamic> fine) async {
    final titel = fine['titel'] as String? ?? 'bøde';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Slet bøde?'),
        content: Text('"$titel" fjernes permanent. Brug dette hvis bøden '
            'er givet ved en fejl.'),
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
      final deleted =
          await supabase.from('fines').delete().eq('id', fine['id']).select();
      if (!mounted) return;
      _snack(
        context,
        (deleted as List).isEmpty
            ? 'Kunne ikke slette — mangler du rettigheder?'
            : 'Bøde slettet',
        (deleted).isEmpty ? _danger : _textSecondary,
      );
      await _load();
    } on PostgrestException catch (e) {
      if (mounted) _snack(context, e.message, _danger);
      await _load();
    }
  }

  /// Åbner MobilePay med det skyldige beløb forudfyldt — til spillerens holds boks.
  Future<void> _payWithMobilePay(int oere) async {
    final box = await _resolveMobilePayBox(context);
    if (box == null) return; // resolver har allerede vist besked / bruger fortrød
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
                                    backgroundColor: _success,
                                    foregroundColor: _onSuccess,
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
                                onDelete: widget.isAdmin ? () => _delete(f) : null,
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
  final VoidCallback? onDelete;
  const _FineHistoryRow({
    required this.fine,
    required this.isAdmin,
    required this.onApprove,
    this.onDelete,
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
                      if (isAdmin) ...[
                        const Spacer(),
                        if (!isPaid)
                          FilledButton.icon(
                            onPressed: onApprove,
                            icon: const Icon(Icons.check, size: 16),
                            label: const Text('Godkend'),
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.green.shade700,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            ),
                          ),
                        if (onDelete != null)
                          IconButton(
                            onPressed: onDelete,
                            icon: const Icon(Icons.delete_outline, size: 20, color: _danger),
                            tooltip: 'Slet bøde',
                            visualDensity: VisualDensity.compact,
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
// MobilePay: find spillerens holds boks (med valg hvis flere hold har egen boks)
// ─────────────────────────────────────────────────────────────────────────────

/// Finder det MobilePay Box-ID en spiller skal betale til:
///  • spilleren er på ét hold med egen boks → brug den
///  • flere hold med hver sin boks → spørg hvilket
///  • ingen hold-boks → klubbens fælles boks (club_config)
/// Returnerer null hvis der ikke er sat en boks op, eller brugeren fortryder
/// (i så fald har funktionen selv vist en besked).
Future<String?> _resolveMobilePayBox(BuildContext context) async {
  final userId = supabase.auth.currentUser?.id;
  String? box;
  if (userId != null) {
    final teams = await ClubConfig.teamBoxesForUser(userId);
    if (teams.length == 1) {
      box = teams.first.box;
    } else if (teams.length > 1) {
      if (!context.mounted) return null;
      final chosen = await showModalBottomSheet<({String navn, String box})>(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (_) => _TeamBoxChooser(teams: teams),
      );
      if (chosen == null) return null; // fortrudt
      box = chosen.box;
    }
  }
  // Ingen hold-boks → fælles boks.
  box ??= ClubConfig.cachedBox ?? await ClubConfig.fetchMobilePayBox();
  if (box == null || box.trim().isEmpty || box.trim() == 'VORES_BOX_NUMMER') {
    if (context.mounted) {
      _snack(context,
          'MobilePay er ikke sat op endnu — en admin kan indtaste Box-ID under Admin → Betaling.',
          _gold);
    }
    return null;
  }
  return box;
}

/// Bottom sheet: vælg hvilket holds MobilePay-boks der betales til.
class _TeamBoxChooser extends StatelessWidget {
  final List<({String navn, String box})> teams;
  const _TeamBoxChooser({required this.teams});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: _surfaceDark,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        border: Border(top: BorderSide(color: _borderSubtle)),
      ),
      child: SafeArea(
        top: false,
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
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
              child: Row(children: [
                const Icon(Icons.groups_outlined, color: _neon),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Hvilket hold betaler du til?',
                      style: _cond(size: 18, weight: FontWeight.w700)),
                ),
              ]),
            ),
            for (final t in teams)
              ListTile(
                leading: const Icon(Icons.account_balance_wallet_outlined,
                    color: _success),
                title: Text(t.navn,
                    style: _body(size: 15, weight: FontWeight.w600)),
                trailing: const Icon(Icons.chevron_right, color: _textMuted),
                onTap: () => Navigator.of(context).pop(t),
              ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tab 5: Træner Dashboard — Træninger + Afstemninger + Bøde-administration
// ─────────────────────────────────────────────────────────────────────────────

