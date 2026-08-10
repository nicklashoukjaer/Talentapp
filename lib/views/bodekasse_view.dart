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
  List<Map<String, dynamic>> _groups = const [];
  Map<String, Set<String>> _memberIdsByGroup = {}; // group_id → medlemmers user_id
  // Folk der KUN er tilknyttet hold som træner. De hører ikke hjemme i
  // bødekassen — medmindre de rent faktisk har fået en bøde.
  Set<String> _trainerOnlyIds = {};
  Set<String> _myGroupIds = {};
  Set<String> _myCaptainGroupIds = {}; // hold hvor jeg er kaptajn (styrer bøder)
  // Valgte hold i filteret (tom = alle tilladte). Admin kan vælge flere.
  final Set<String> _selectedGroupIds = {};

  /// Må den aktuelle bruger administrere bøder for [playerId]?
  bool _canAdminFineFor(String playerId) {
    if (widget.isAdmin) return true;
    for (final g in _myCaptainGroupIds) {
      if ((_memberIdsByGroup[g] ?? const <String>{}).contains(playerId)) {
        return true;
      }
    }
    return false;
  }
  bool _filterInit = false;   // for at gate cache-hurtigvisning på 1. load
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    reload();
  }

  Future<void> reload() async {
    // Instant UI: vis cachet holdsaldo med det samme — men kun når filteret
    // allerede er initialiseret (ellers ville en spiller kort se hele klubben).
    final cached = CacheService.getList('leaderboard');
    if (cached != null && _filterInit) {
      _rows = cached;
      _loading = false;
      if (mounted) setState(() {});
    } else {
      setState(() { _loading = true; _error = null; });
    }
    try {
      // Highscore = flest bøder gennem tiden (total). Skyldigt bruges til
      // "Du skylder"-callout og ubetalt-markering. Hold + medlemskaber hentes
      // med, så listen kan filtreres pr. hold.
      final results = await Future.wait([
        supabase.from('fine_leaderboard').select().order('total_oere', ascending: false),
        supabase.from('groups').select('id, navn, farve, sort, hold_group_id').order('sort'),
        supabase.from('group_members')
            .select('group_id, user_id, is_captain, is_trainer'),
        supabase.from('hold_groups').select('id, navn').order('created_at'),
      ]);
      final list = List<Map<String, dynamic>>.from(results[0] as List);
      final groups = List<Map<String, dynamic>>.from(results[1] as List);
      final gm = List<Map<String, dynamic>>.from(results[2] as List);
      final holdGroups = List<Map<String, dynamic>>.from(results[3] as List);

      // Fællesskab pr. hold: holdgruppe ('hg:<id>') eller selvstændigt ('solo:<id>').
      // Hold i samme holdgruppe deler bødekasse.
      final hgNavn = {for (final h in holdGroups) h['id'] as String: h['navn'] as String?};
      final communityKeyOf = <String, String>{};
      final communities = <Map<String, dynamic>>[];
      final seenKey = <String>{};
      for (final g in groups) {
        final gid = g['id'] as String;
        final hgId = g['hold_group_id'] as String?;
        final key = hgId != null ? 'hg:$hgId' : 'solo:$gid';
        communityKeyOf[gid] = key;
        if (seenKey.add(key)) {
          communities.add({
            'id': key,
            'navn': hgId != null
                ? (hgNavn[hgId] ?? 'Gruppe')
                : (g['navn'] as String),
            // Holdgruppe → accent (null); selvstændigt → holdets farve.
            'farve': hgId != null ? null : g['farve'],
          });
        }
      }

      final byGroup = <String, Set<String>>{};
      final mine = <String>{};
      final myCap = <String>{};
      // Trænere tælles ikke som spillere i fællesskabets bødekasse, men de
      // beholder adgang til at SE (og filtrere på) deres eget holds kasse.
      final trainerAnywhere = <String>{};
      final playerAnywhere = <String>{};
      final trainerLinks = <({String key, String uid})>[];
      for (final r in gm) {
        final gid = r['group_id'] as String;
        final uid = r['user_id'] as String;
        final key = communityKeyOf[gid];
        if (key == null) continue;
        if (r['is_trainer'] == true) {
          trainerAnywhere.add(uid);
          trainerLinks.add((key: key, uid: uid));
        } else {
          playerAnywhere.add(uid);
          (byGroup[key] ??= <String>{}).add(uid);
        }
        if (uid == widget.currentUserId) {
          mine.add(key);
          if (r['is_captain'] == true) myCap.add(key);
        }
      }
      final trainerOnly = trainerAnywhere.difference(playerAnywhere);
      // Har en træner fået en bøde, hører de alligevel til i det fællesskabs
      // kasse — ellers ville de forsvinde igen så snart man filtrerede på
      // holdet.
      final fined = {
        for (final r in list)
          if (((r['total_oere'] as num?) ?? 0) > 0) r['id'] as String
      };
      for (final l in trainerLinks) {
        if (fined.contains(l.uid)) (byGroup[l.key] ??= <String>{}).add(l.uid);
      }
      CacheService.put('leaderboard', list);
      if (!mounted) return;
      setState(() {
        _rows = list;
        _groups = communities;
        _memberIdsByGroup = byGroup;
        _trainerOnlyIds = trainerOnly;
        _myGroupIds = mine;
        _myCaptainGroupIds = myCap;
        _filterInit = true;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      if (_rows.isEmpty) setState(() { _loading = false; _error = e.toString(); });
    }
  }

  void _open(Map<String, dynamic> row) {
    final id = row['id'] as String;
    final canAdminThis = _canAdminFineFor(id);
    final canOpen = canAdminThis || id == widget.currentUserId;
    if (!canOpen) {
      _snack(context, 'Du kan kun se dit eget holds historik', Colors.orange);
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => FineHistoryScreen(
        userId:   id,
        userName: row['navn'] as String,
        // Bøde-admin for dette hold får godkend/slet-rettigheder her.
        isAdmin:  canAdminThis,
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

  static Color _commHex(Object? farve) {
    final h = farve as String?;
    if (h == null || h.isEmpty) return _neon;
    return Color(int.parse(h.replaceFirst('#', ''), radix: 16) | 0xFF000000);
  }

  // Kort label for det aktive hold-filter (vises i titel-rækken).
  String _filterLabel() {
    if (_selectedGroupIds.length == 1) {
      final g = _groups.firstWhere((g) => g['id'] == _selectedGroupIds.first,
          orElse: () => const {});
      return (g['navn'] as String?) ?? 'Hold';
    }
    return '${_selectedGroupIds.length} hold';
  }

  /// Hold-filter som bundsheet — kaldes af tragt-ikonet i app-headeren.
  /// Admin: multi-valg. Træner/spiller: enkelt-valg blandt egne hold.
  Future<void> showHoldFilterSheet() async {
    final groups = widget.isAdmin
        ? _groups
        : _groups.where((g) => _myGroupIds.contains(g['id'] as String)).toList();
    if (groups.isEmpty) {
      _snack(context, 'Ingen hold at filtrere på', _textSecondary);
      return;
    }
    final multi = widget.isAdmin;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSheet) {
        void toggle(String? id) {
          setState(() {
            if (id == null) {
              _selectedGroupIds.clear();
            } else if (multi) {
              if (_selectedGroupIds.contains(id)) {
                _selectedGroupIds.remove(id);
              } else {
                _selectedGroupIds.add(id);
              }
            } else {
              _selectedGroupIds
                ..clear()
                ..add(id);
            }
          });
          setSheet(() {});
          if (!multi) Navigator.of(ctx).pop();
        }

        Widget option(String? id, String label, Color dot) {
          final selected =
              id == null ? _selectedGroupIds.isEmpty : _selectedGroupIds.contains(id);
          return InkWell(
            onTap: () => toggle(id),
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
                if (selected)
                  Icon(multi ? Icons.check_box : Icons.check,
                      size: 18, color: _neon),
              ]),
            ),
          );
        }

        return SafeArea(
          top: false,
          child: Container(
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            decoration: BoxDecoration(
              color: _surfaceDark,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _borderSubtle),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: [
                  Expanded(
                    child: Text('FILTRÉR PÅ HOLD',
                        style: _cond(size: 20, weight: FontWeight.w800)),
                  ),
                  if (multi)
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      style: TextButton.styleFrom(foregroundColor: _neon),
                      child: const Text('Færdig'),
                    ),
                ]),
                const SizedBox(height: 8),
                option(null, widget.isAdmin ? 'Alle hold' : 'Alle mine hold', _neon),
                for (final g in groups)
                  option(g['id'] as String, g['navn'] as String,
                      _commHex(g['farve'])),
              ],
            ),
          ),
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return _loadingSkeleton();
    if (_error != null) return _ErrorView(error: _error!, onRetry: reload);

    // Grundmængden en bruger overhovedet kan se: admin ser alle; øvrige kun
    // personer på deres egne hold. (Hold-filteret sidder i app-headerens tragt.)
    // Rene trænere holdes ude af ranglisten indtil de faktisk har fået en bøde
    // — så dukker de op på lige fod med alle andre.
    bool visible(Map<String, dynamic> r) =>
        !_trainerOnlyIds.contains(r['id'] as String) ||
        ((r['total_oere'] as num?) ?? 0) > 0;

    Iterable<Map<String, dynamic>> base;
    if (widget.isAdmin) {
      base = _rows.where(visible);
    } else {
      final allowed = <String>{};
      for (final g in _myGroupIds) {
        allowed.addAll(_memberIdsByGroup[g] ?? const <String>{});
      }
      base = _rows.where(
          (r) => visible(r) && allowed.contains(r['id'] as String));
    }

    // Valgte hold indsnævrer yderligere (tom = hele grundmængden).
    final filtered = (_selectedGroupIds.isEmpty
            ? base
            : base.where((r) => _selectedGroupIds.any((g) =>
                (_memberIdsByGroup[g] ?? const <String>{})
                    .contains(r['id'] as String))))
        .toList();

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
                    padding: const EdgeInsets.only(bottom: 16, top: 4),
                    child: Row(children: [
                      const Text('🏆', style: TextStyle(fontSize: 22)),
                      const SizedBox(width: 9),
                      Text('BØDEKASSE',
                          style: _cond(size: 22, weight: FontWeight.w800)),
                      if (_selectedGroupIds.isNotEmpty) ...[
                        const Spacer(),
                        Icon(Icons.filter_list, size: 15, color: _neon),
                        const SizedBox(width: 4),
                        Text(_filterLabel(),
                            style: _body(
                                size: 12, weight: FontWeight.w700, color: _neon)),
                      ],
                    ]),
                  ),
                  if (filtered.isEmpty)
                    const _EmptyState(
                      icon: Icons.emoji_events_outlined,
                      title: 'Ingen bøder endnu',
                      subtitle: 'Bødekassen fyldes når nogen får en bøde',
                    )
                  else ...[
                    _Podium(
                      rows: filtered.take(3).toList(),
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
                    ...filtered.asMap().entries.map((e) => _LeaderboardRow(
                          rank: e.key + 1,
                          row: e.value,
                          isOwn: e.value['id'] == widget.currentUserId,
                          onTap: () => _open(e.value),
                        )),
                    const SizedBox(height: 10),
                    Center(
                      child: TextButton.icon(
                        onPressed: () => showDialog<bool>(
                          context: context,
                          builder: (_) => const SuggestFineTypeDialog(),
                        ),
                        icon: const Icon(Icons.lightbulb_outline, size: 16),
                        label: const Text('Foreslå en bødetype'),
                        style: TextButton.styleFrom(foregroundColor: _textSecondary),
                      ),
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
              const SizedBox(width: 6),
              const Icon(Icons.chevron_right, size: 16, color: _textMuted),
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
  Map<String, String> _giverNames = {}; // given_by → navn
  String? _holdNavn;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  String get _season {
    final now = DateTime.now();
    final startYear = now.month >= 7 ? now.year : now.year - 1;
    return 'Sæson $startYear/${((startYear + 1) % 100).toString().padLeft(2, '0')}';
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final rows = await supabase
          .from('fines')
          .select('id, titel, belob_oere, begrundelse, status, created_at, paid_at, given_by')
          .eq('user_id', widget.userId)
          .order('created_at', ascending: false);
      final fines = List<Map<String, dynamic>>.from(rows as List);

      // Navne på dem der uddelte bøderne.
      final giverIds = fines
          .map((f) => f['given_by'] as String?)
          .whereType<String>()
          .toSet()
          .toList();
      final giverNames = <String, String>{};
      if (giverIds.isNotEmpty) {
        final gp = await supabase
            .from('profiles').select('id, navn').inFilter('id', giverIds);
        for (final p in List<Map<String, dynamic>>.from(gp as List)) {
          giverNames[p['id'] as String] = p['navn'] as String? ?? '';
        }
      }

      // Spillerens hold (til hold-badge i toppen).
      String? hold;
      try {
        final gm = await supabase
            .from('group_members')
            .select('groups(navn, sort)')
            .eq('user_id', widget.userId);
        final gs = List<Map<String, dynamic>>.from(gm as List)
            .map((r) => r['groups'] as Map<String, dynamic>?)
            .whereType<Map<String, dynamic>>()
            .toList()
          ..sort((a, b) => ((a['sort'] as num?)?.toInt() ?? 0)
              .compareTo((b['sort'] as num?)?.toInt() ?? 0));
        if (gs.isNotEmpty) hold = gs.first['navn'] as String?;
      } catch (_) {}

      if (!mounted) return;
      setState(() {
        _fines = fines;
        _giverNames = giverNames;
        _holdNavn = hold;
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = e.toString(); });
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

    final ubetalte = _fines.where((f) => f['status'] == 'ubetalt').toList();
    final betalte = _fines.where((f) => f['status'] == 'godkendt_betalt').toList();
    final isOwn = widget.userId == supabase.auth.currentUser?.id;

    return Scaffold(
      appBar: AppBar(
        title: const Text('BØDE-HISTORIK'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
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
                            // Header: navn + hold-badge + sæson
                            Container(
                              padding: const EdgeInsets.all(18),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [_surfaceElevated, _surfaceDark],
                                ),
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(color: _borderSubtle),
                              ),
                              child: Row(children: [
                                Container(
                                  width: 48, height: 48,
                                  alignment: Alignment.center,
                                  decoration: const BoxDecoration(
                                      color: _neon, shape: BoxShape.circle),
                                  child: Text(
                                      widget.userName.isNotEmpty
                                          ? widget.userName[0].toUpperCase()
                                          : '?',
                                      style: _cond(
                                          size: 22,
                                          weight: FontWeight.w800,
                                          color: Colors.white)),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Row(children: [
                                        Flexible(
                                          child: Text(
                                              widget.userName.toUpperCase(),
                                              style: theme.textTheme.titleLarge,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis),
                                        ),
                                        if (_holdNavn != null) ...[
                                          const SizedBox(width: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 8, vertical: 3),
                                            decoration: BoxDecoration(
                                              color: _neon.withValues(alpha: 0.16),
                                              borderRadius:
                                                  BorderRadius.circular(999),
                                            ),
                                            child: Text(_holdNavn!.toUpperCase(),
                                                style: _body(
                                                    size: 9,
                                                    weight: FontWeight.w800,
                                                    spacing: 0.6,
                                                    color: _neon)),
                                          ),
                                        ],
                                      ]),
                                      const SizedBox(height: 2),
                                      Text(_season,
                                          style: _body(
                                              size: 12, color: _textSecondary)),
                                    ],
                                  ),
                                ),
                              ]),
                            ),
                            const SizedBox(height: 14),
                            // To nøgletal (separate kort, som prototypen)
                            Row(children: [
                              Expanded(
                                child: _statCard('Skyldig nu', totalUbetalt,
                                    totalUbetalt > 0 ? _danger : _success),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child:
                                    _statCard('Betalt i alt', totalBetalt, _success),
                              ),
                            ]),
                            if (totalUbetalt > 0 && isOwn) ...[
                              const SizedBox(height: 14),
                              SizedBox(
                                width: double.infinity,
                                child: FilledButton.icon(
                                  onPressed: () =>
                                      _payWithMobilePay(totalUbetalt),
                                  icon: const Icon(
                                      Icons.account_balance_wallet_outlined),
                                  label: Text(
                                      'Betal ${_fmtKr(totalUbetalt)} via MobilePay'),
                                  style: FilledButton.styleFrom(
                                    backgroundColor: _info,
                                    foregroundColor: const Color(0xFF08243A),
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
                            const SizedBox(height: 20),
                            if (_fines.isEmpty)
                              const Padding(
                                padding: EdgeInsets.all(32),
                                child: Center(
                                    child: Text(
                                        'Ingen bøder endnu — clean record! 🎉')),
                              )
                            else ...[
                              if (ubetalte.isNotEmpty) ...[
                                _groupHeader('UBETALT', ubetalte.length, _danger),
                                for (final f in ubetalte)
                                  _FineHistoryRow(
                                    fine: f,
                                    giverName:
                                        _giverNames[f['given_by'] as String?],
                                    isAdmin: widget.isAdmin,
                                    onApprove: () => _approve(f),
                                    onDelete: widget.isAdmin
                                        ? () => _delete(f)
                                        : null,
                                  ),
                              ],
                              if (betalte.isNotEmpty) ...[
                                if (ubetalte.isNotEmpty)
                                  const SizedBox(height: 14),
                                _groupHeader('BETALT', betalte.length, _success),
                                for (final f in betalte)
                                  _FineHistoryRow(
                                    fine: f,
                                    giverName:
                                        _giverNames[f['given_by'] as String?],
                                    isAdmin: widget.isAdmin,
                                    onApprove: () => _approve(f),
                                    onDelete: widget.isAdmin
                                        ? () => _delete(f)
                                        : null,
                                  ),
                              ],
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _statCard(String label, int oere, Color color) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 14),
      decoration: BoxDecoration(
        color: _surfaceDark,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: _body(size: 11, color: _textSecondary)),
          const SizedBox(height: 4),
          Text(_fmtKr(oere),
              style: _cond(size: 24, weight: FontWeight.w800, color: color)),
        ],
      ),
    );
  }

  Widget _groupHeader(String label, int n, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, left: 2),
      child: Row(children: [
        Container(width: 8, height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 8),
        Text('$label · $n',
            style: _body(
                size: 12, weight: FontWeight.w800, spacing: 0.8, color: color)),
      ]),
    );
  }
}

class _FineHistoryRow extends StatelessWidget {
  final Map<String, dynamic> fine;
  final String? giverName;
  final bool isAdmin;
  final VoidCallback onApprove;
  final VoidCallback? onDelete;
  const _FineHistoryRow({
    required this.fine,
    required this.giverName,
    required this.isAdmin,
    required this.onApprove,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final titel    = fine['titel']       as String;
    final oere     = (fine['belob_oere'] as num).toInt();
    final begrund  = fine['begrundelse'] as String?;
    final status   = fine['status']      as String;
    final created  = DateTime.parse(fine['created_at'] as String).toLocal();
    final isPaid   = status == 'godkendt_betalt';
    final paidAt   = fine['paid_at'] == null
        ? null
        : DateTime.parse(fine['paid_at'] as String).toLocal();

    // Meta-linje: dato · uddelt af · evt. begrundelse.
    final metaParts = <String>['Givet ${_fmtDate(created)}'];
    if (giverName != null && giverName!.isNotEmpty) {
      metaParts.add('af $giverName');
    }
    final meta = metaParts.join(' · ');

    return Opacity(
      opacity: isPaid ? 0.65 : 1,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _surfaceDark,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: isPaid
                  ? _borderSubtle
                  : _danger.withValues(alpha: 0.35)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(isPaid ? Icons.check_circle : Icons.cancel,
                color: isPaid ? _success : _danger, size: 22),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Expanded(
                      child: Text(titel,
                          style: _body(size: 15, weight: FontWeight.w700)),
                    ),
                    Text(_fmtKr(oere),
                        style: _cond(
                            size: 18,
                            weight: FontWeight.w800,
                            color: isPaid ? _textMuted : _danger)
                        .copyWith(
                            decoration:
                                isPaid ? TextDecoration.lineThrough : null,
                            decorationColor: _textMuted)),
                  ]),
                  const SizedBox(height: 2),
                  Text(meta, style: _body(size: 11.5, color: _textSecondary)),
                  if (begrund != null && begrund.isNotEmpty) ...[
                    const SizedBox(height: 5),
                    Text(begrund,
                        style: _body(size: 13, color: _textPrimary)
                            .copyWith(fontStyle: FontStyle.italic)),
                  ],
                  if (isPaid && paidAt != null) ...[
                    const SizedBox(height: 5),
                    Text('Betalt ${_fmtDate(paidAt)}',
                        style: _body(size: 11.5, weight: FontWeight.w600, color: _success)),
                  ],
                  if (isAdmin && (!isPaid || onDelete != null)) ...[
                    const SizedBox(height: 10),
                    Row(children: [
                      if (!isPaid)
                        FilledButton.icon(
                          onPressed: onApprove,
                          icon: const Icon(Icons.check, size: 16),
                          label: const Text('Markér betalt'),
                          style: FilledButton.styleFrom(
                            backgroundColor: _success,
                            foregroundColor: _onSuccess,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                          ),
                        ),
                      const Spacer(),
                      if (onDelete != null)
                        IconButton(
                          onPressed: onDelete,
                          icon: const Icon(Icons.delete_outline,
                              size: 20, color: _danger),
                          tooltip: 'Slet bøde',
                          visualDensity: VisualDensity.compact,
                        ),
                    ]),
                  ],
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

