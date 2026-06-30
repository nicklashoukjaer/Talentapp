// Auto-split (del af biblioteket padel_app)
// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
part of '../main.dart';

class OversigtTab extends StatefulWidget {
  final bool isAdmin;
  const OversigtTab({super.key, required this.isAdmin});
  @override
  State<OversigtTab> createState() => _OversigtTabState();
}

/// Klassificer en begivenhed ud fra titlen.
/// Returnerer (isTraining, isKamp). Hvis begge er false → "anden" type
/// (vises i begge under-faner).
({bool training, bool kamp}) _classifyEvent(String titel) {
  final t = titel.toLowerCase();
  final isTraining = t.contains('træning') || t.contains('øvelse');
  final isKamp     = t.contains('kamp'); // dækker også "hjemmekamp", "udekamp"
  return (training: isTraining, kamp: isKamp);
}

bool _showInTrainingTab(String titel) {
  final c = _classifyEvent(titel);
  // TRÆNINGER-fane = matcher træning ELLER er "anden" (ingen kategori)
  return c.training || (!c.training && !c.kamp);
}

bool _showInKampTab(String titel) {
  final c = _classifyEvent(titel);
  return c.kamp || (!c.training && !c.kamp);
}

class _OversigtTabState extends State<OversigtTab> {
  List<_FeedItem> _items = const [];
  bool _loading = true;
  String? _error;
  int _activeView = 0;       // 0 = AKTIVITETER, 1 = AFSTEMNINGER
  int _activitySubview = 0;  // 0 = TRÆNINGER, 1 = KAMPE
  bool _showHistory = false; // når true: arkiverede begivenheder (>24t efter start)
  bool _historyLoaded = false; // lazy: historik (90 dage) hentes først ved behov

  @override
  void initState() {
    super.initState();
    reload();
  }

  Future<void> reload({bool? includeHistory}) async {
    final withHistory = includeHistory ?? _historyLoaded;
    setState(() { _loading = true; _error = null; });
    try {
      final userId = supabase.auth.currentUser!.id;
      // Lazy loading: ved opstart hentes KUN aktive (fra 24t tilbage).
      // Historik (90 dage) hentes først når brugeren trykker på Historik.
      final sinceIso = DateTime.now()
          .subtract(withHistory ? const Duration(days: 90) : const Duration(hours: 24))
          .toUtc().toIso8601String();

      final results = await Future.wait([
        // Træninger 90 dage tilbage og frem
        supabase.from('trainings')
            .select('id, titel, beskrivelse, max_deltagere, start_tid, slut_tid, adresse, tilmeldings_deadline')
            .gte('start_tid', sinceIso).order('start_tid'),
        // Polls (alle — lukkede filtreres client-side)
        supabase.from('polls')
            .select('id, titel, beskrivelse, lukket_at, created_at')
            .order('created_at', ascending: false),
        // Profiles for count
        supabase.from('profiles').select('id'),
      ]);

      final trainings   = List<Map<String, dynamic>>.from(results[0] as List);
      final pollsAll    = List<Map<String, dynamic>>.from(results[1] as List);
      final profileRows = List<Map<String, dynamic>>.from(results[2] as List);

      // Filtrér åbne polls
      final polls = pollsAll.where((p) {
        final l = p['lukket_at'] as String?;
        if (l == null) return true;
        return DateTime.parse(l).isAfter(DateTime.now());
      }).toList();

      // Hent participants og poll-data parallelt (med eksplicit FK for at undgå PGRST201)
      final trainingIds = trainings.map((t) => t['id'] as String).toList();
      final pollIds = polls.map((p) => p['id'] as String).toList();

      final tpFuture = trainingIds.isEmpty
          ? Future.value(const <Map<String, dynamic>>[])
          : supabase.from('training_participants')
              .select('training_id, user_id, status, updated_at, '
                      'profiles!training_participants_user_id_fkey(navn, rolle)')
              .inFilter('training_id', trainingIds)
              .order('updated_at');

      final optionsFuture = pollIds.isEmpty
          ? Future.value(const <Map<String, dynamic>>[])
          : supabase.from('poll_options')
              .select('id, poll_id, option_tid, beskrivelse')
              .inFilter('poll_id', pollIds).order('option_tid');

      final dataResults = await Future.wait([tpFuture, optionsFuture]);
      final allTp      = List<Map<String, dynamic>>.from(dataResults[0] as List);
      final allOptions = List<Map<String, dynamic>>.from(dataResults[1] as List);

      // Hent alle poll_responses (med navne) for disse options
      final optionIds = allOptions.map((o) => o['id'] as String).toList();
      final allPr = optionIds.isEmpty
          ? const <Map<String, dynamic>>[]
          : List<Map<String, dynamic>>.from(await supabase
              .from('poll_responses')
              .select('poll_option_id, user_id, svar, '
                      'profiles!poll_responses_user_id_fkey(navn)')
              .inFilter('poll_option_id', optionIds) as List);

      // Aggregér: deltagere pr. træning/status. Trænere tælles separat
      // og optager ikke en spillerplads.
      final tpGrouped = <String, Map<String, List<_Participant>>>{};
      final myStatusMap = <String, String>{};
      for (final r in allTp) {
        final tid    = r['training_id'] as String;
        final uid    = r['user_id']     as String;
        final status = r['status']      as String;
        final profile = r['profiles'] as Map<String, dynamic>?;
        final navn   = profile?['navn'] as String? ?? '(ukendt)';
        final rolle  = profile?['rolle'] as String? ?? 'medlem';
        final isTrainer = rolle == 'træner';
        final updatedAt = DateTime.parse(r['updated_at'] as String);

        tpGrouped.putIfAbsent(tid, () => {
          'tilmeldt':   <_Participant>[],
          'venteliste': <_Participant>[],
          'afmeldt':    <_Participant>[],
          'træner':     <_Participant>[],
        });

        final participant = _Participant(
          navn: navn, updatedAt: updatedAt, isTrainer: isTrainer);

        if (isTrainer && status == 'tilmeldt') {
          // Træner-spot — optager ikke en spillerplads
          tpGrouped[tid]!['træner']!.add(participant);
        } else {
          tpGrouped[tid]![status]?.add(participant);
        }
        if (uid == userId) myStatusMap[tid] = status;
      }

      // Aggregér: stemmere pr. option
      final votersGrouped = <String, ({List<String> yes, List<String> no})>{};
      final myVotes = <String, bool>{};
      for (final r in allPr) {
        final oid  = r['poll_option_id'] as String;
        final uid  = r['user_id']        as String;
        final svar = r['svar']           as bool;
        final navn = (r['profiles'] as Map<String, dynamic>?)?['navn']
                     as String? ?? '(ukendt)';
        votersGrouped.putIfAbsent(oid, () => (yes: <String>[], no: <String>[]));
        if (svar) {
          votersGrouped[oid]!.yes.add(navn);
        } else {
          votersGrouped[oid]!.no.add(navn);
        }
        if (uid == userId) myVotes[oid] = svar;
      }

      final items = <_FeedItem>[];

      for (final t in trainings) {
        final tid = t['id'] as String;
        final g = tpGrouped[tid] ?? {
          'tilmeldt':   <_Participant>[],
          'venteliste': <_Participant>[],
          'afmeldt':    <_Participant>[],
          'træner':     <_Participant>[],
        };
        items.add(_TrainingFeedItem(
          training: t,
          myStatus: myStatusMap[tid],
          signedUpCount: g['tilmeldt']!.length, // trænere er IKKE i denne liste
          tilmeldte:  g['tilmeldt']!,
          venteliste: g['venteliste']!,
          afmeldte:   g['afmeldt']!,
          trainere:   g['træner']!,
        ));
      }

      for (final p in polls) {
        final pollId = p['id'] as String;
        final options = allOptions.where((o) => o['poll_id'] == pollId).toList();
        final optIds = options.map((o) => o['id'] as String).toSet();
        final respondents = <String>{};
        final voters = <String, _OptionVoters>{};
        for (final oid in optIds) {
          final v = votersGrouped[oid];
          voters[oid] = _OptionVoters(
            yes: v?.yes ?? const [],
            no:  v?.no  ?? const [],
          );
        }
        for (final r in allPr) {
          if (optIds.contains(r['poll_option_id'])) {
            respondents.add(r['user_id'] as String);
          }
        }
        items.add(_PollFeedItem(
          poll: p,
          options: options,
          myVotes: myVotes,
          respondedCount: respondents.length,
          totalMembers: profileRows.length,
          votersByOption: voters,
        ));
      }

      items.sort((a, b) => a.sortKey.compareTo(b.sortKey));

      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (e) {
      setState(() { _loading = false; _error = e.toString(); });
    }
  }

  Future<void> _signUp(_TrainingFeedItem item) async {
    try {
      final status = await supabase.rpc('register_for_training',
          params: {'p_training_id': item.training['id']});
      if (!mounted) return;
      _snack(context,
          status == 'tilmeldt' ? 'Du er tilmeldt' : 'Du er på venteliste',
          status == 'tilmeldt' ? Colors.green.shade400 : Colors.orange.shade400);
      await reload();
    } on PostgrestException catch (e) {
      if (mounted) _snack(context, e.message, Colors.red.shade400);
    }
  }

  /// AFBUD — sætter status='afmeldt'. Virker uanset om brugeren havde en række før.
  Future<void> _decline(_TrainingFeedItem item) async {
    try {
      await supabase.from('training_participants').upsert({
        'training_id': item.training['id'],
        'user_id':     supabase.auth.currentUser!.id,
        'status':      'afmeldt',
      }, onConflict: 'training_id,user_id');
      if (!mounted) return;
      _snack(context, 'Afbud sendt', _textSecondary);
      await reload();
    } on PostgrestException catch (e) {
      if (mounted) _snack(context, e.message, Colors.red.shade400);
    }
  }


  Future<void> _vote(_PollFeedItem item, String optionId, bool svar) async {
    final originalVote = item.myVotes[optionId];
    setState(() {
      final updated = {...item.myVotes, optionId: svar};
      final idx = _items.indexOf(item);
      if (idx >= 0) {
        _items = [..._items]..[idx] = _PollFeedItem(
          poll: item.poll,
          options: item.options,
          myVotes: updated,
          respondedCount: item.respondedCount,
          totalMembers: item.totalMembers,
          votersByOption: item.votersByOption,
        );
      }
    });
    try {
      await supabase.from('poll_responses').upsert({
        'poll_option_id': optionId,
        'user_id':        supabase.auth.currentUser!.id,
        'svar':           svar,
      }, onConflict: 'poll_option_id,user_id');
      // Reload for at få voter-lister opdateret
      await reload();
    } on PostgrestException catch (e) {
      // Rul tilbage
      setState(() {
        final updated = {...item.myVotes};
        if (originalVote == null) {
          updated.remove(optionId);
        } else {
          updated[optionId] = originalVote;
        }
        final idx = _items.indexWhere((it) =>
            it is _PollFeedItem && (it).poll['id'] == item.poll['id']);
        if (idx >= 0) {
          _items = [..._items]..[idx] = _PollFeedItem(
            poll: item.poll,
            options: item.options,
            myVotes: updated,
            respondedCount: item.respondedCount,
            totalMembers: item.totalMembers,
            votersByOption: item.votersByOption,
          );
        }
      });
      if (mounted) _snack(context, e.message, Colors.red.shade400);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return _ErrorView(error: _error!, onRetry: reload);

    final allTrainings = _items.whereType<_TrainingFeedItem>().toList();
    final polls        = _items.whereType<_PollFeedItem>().toList();

    // Arkivering: en begivenhed bliver "historik" 24 timer efter start_tid
    final archiveCutoff = DateTime.now().subtract(const Duration(hours: 24));
    final activeTrainings   = allTrainings.where((t) =>
        DateTime.parse(t.training['start_tid'] as String).isAfter(archiveCutoff))
        .toList();
    final archivedTrainings = allTrainings.where((t) =>
        !DateTime.parse(t.training['start_tid'] as String).isAfter(archiveCutoff))
        .toList()
        // Historik vises nyeste først
        ..sort((a, b) => b.sortKey.compareTo(a.sortKey));

    // Kategorisering af træninger vs kampe
    final source = _showHistory ? archivedTrainings : activeTrainings;
    final trainingItems = source.where((t) =>
        _showInTrainingTab(t.training['titel'] as String)).toList();
    final kampItems = source.where((t) =>
        _showInKampTab(t.training['titel'] as String)).toList();

    final showingTrainings = _activeView == 0;
    final List<_FeedItem> visible;
    if (showingTrainings) {
      visible = (_activitySubview == 0 ? trainingItems : kampItems)
          .cast<_FeedItem>();
    } else {
      visible = polls.cast<_FeedItem>();
    }

    return RefreshIndicator(
      onRefresh: reload,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16, left: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Container(
                          width: 4, height: 32,
                          decoration: const BoxDecoration(
                            color: _neon,
                            borderRadius: BorderRadius.all(Radius.circular(2)),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('OVERSIGT',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.headlineSmall?.copyWith(
                                      letterSpacing: 1.5)),
                              Text('${activeTrainings.length} aktive · '
                                   '${_historyLoaded ? '${archivedTrainings.length} arkiverede · ' : ''}'
                                   '${polls.length} afstemninger',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall),
                            ],
                          ),
                        ),
                        if (showingTrainings)
                          IconButton(
                            onPressed: () {
                              final show = !_showHistory;
                              setState(() => _showHistory = show);
                              if (show && !_historyLoaded) {
                                _historyLoaded = true;
                                reload(includeHistory: true);
                              }
                            },
                            icon: Icon(
                                _showHistory ? Icons.history : Icons.history_outlined,
                                color: _showHistory ? _neon : _textSecondary),
                            tooltip: _showHistory ? 'Vis aktive' : 'Historik',
                          ),
                        IconButton(
                          onPressed: reload,
                          icon: const Icon(Icons.refresh),
                          tooltip: 'Opdater',
                        ),
                      ],
                    ),
                  ),
                  // Segmented switch [AKTIVITETER] / [AFSTEMNINGER]
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: SegmentedButton<int>(
                      style: SegmentedButton.styleFrom(
                        backgroundColor: _surfaceDark,
                        selectedBackgroundColor: _neon,
                        selectedForegroundColor: Colors.black,
                        foregroundColor: _textSecondary,
                        side: const BorderSide(color: _borderSubtle),
                        textStyle: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 0.4),
                      ),
                      segments: [
                        ButtonSegment(
                          value: 0,
                          icon: const Icon(Icons.bolt, size: 18),
                          label: Text('AKTIVITETER · ${source.length}',
                              maxLines: 1, softWrap: false,
                              overflow: TextOverflow.ellipsis),
                        ),
                        ButtonSegment(
                          value: 1,
                          icon: const Icon(Icons.how_to_vote, size: 18),
                          label: Text('AFSTEMNINGER · ${polls.length}',
                              maxLines: 1, softWrap: false,
                              overflow: TextOverflow.ellipsis),
                        ),
                      ],
                      selected: {_activeView},
                      onSelectionChanged: (s) => setState(() => _activeView = s.first),
                    ),
                  ),
                  // Sub-tabs [TRÆNINGER] / [KAMPE] — kun på AKTIVITETER
                  if (showingTrainings)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 20),
                      child: SegmentedButton<int>(
                        style: SegmentedButton.styleFrom(
                          backgroundColor: _bgBlack,
                          selectedBackgroundColor: _neon.withValues(alpha: 0.15),
                          selectedForegroundColor: _neon,
                          foregroundColor: _textMuted,
                          side: const BorderSide(color: _borderSubtle),
                          textStyle: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.2),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8),
                        ),
                        segments: [
                          ButtonSegment(
                            value: 0,
                            icon: const Icon(Icons.fitness_center, size: 14),
                            label: Text('TRÆNINGER · ${trainingItems.length}',
                                maxLines: 1, softWrap: false,
                                overflow: TextOverflow.ellipsis),
                          ),
                          ButtonSegment(
                            value: 1,
                            icon: const Icon(Icons.sports_tennis, size: 14),
                            label: Text('KAMPE · ${kampItems.length}',
                                maxLines: 1, softWrap: false,
                                overflow: TextOverflow.ellipsis),
                          ),
                        ],
                        selected: {_activitySubview},
                        onSelectionChanged: (s) =>
                            setState(() => _activitySubview = s.first),
                      ),
                    )
                  else
                    const SizedBox(height: 12),
                  if (visible.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(40),
                      child: Column(
                        children: [
                          Icon(
                            showingTrainings
                                ? (_showHistory ? Icons.history : Icons.event_busy)
                                : Icons.how_to_vote_outlined,
                            size: 72, color: _textMuted),
                          const SizedBox(height: 16),
                          Text(
                              showingTrainings
                                  ? (_showHistory
                                      ? 'Ingen arkiverede begivenheder'
                                      : (_activitySubview == 0
                                          ? 'Ingen kommende træninger'
                                          : 'Ingen kommende kampe'))
                                  : 'Ingen aktive afstemninger',
                              style: theme.textTheme.titleMedium),
                          const SizedBox(height: 4),
                          Text(
                              _showHistory
                                  ? 'Historik fyldes når begivenheder bliver 24 timer gamle'
                                  : (widget.isAdmin
                                      ? 'Tryk Ctrl+K → "opret" for at komme i gang'
                                      : 'Holdet får besked når noget kommer i kalenderen'),
                              style: theme.textTheme.bodySmall,
                              textAlign: TextAlign.center),
                        ],
                      ),
                    )
                  else
                    ...visible.map((item) => Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: switch (item) {
                        _TrainingFeedItem t => _FeedTrainingCard(
                          item: t,
                          isAdmin: widget.isAdmin,
                          onSignUp:  () => _signUp(t),
                          onDecline: () => _decline(t),
                          onOpenBoard: widget.isAdmin
                              ? () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => TrainingBoardScreen(
                                        training: t.training),
                                  ),
                                ).then((_) => reload())
                              : null,
                        ),
                        _PollFeedItem p => _FeedPollCard(
                          item: p,
                          isAdmin: widget.isAdmin,
                          onVote: (optionId, svar) => _vote(p, optionId, svar),
                          onOpenSynergy: widget.isAdmin
                              ? () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => SynergyReportScreen(
                                        poll: p.poll),
                                  ),
                                )
                              : null,
                        ),
                      },
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

// ─── Træningskort i Oversigt ────────────────────────────────────────────────

class _FeedTrainingCard extends StatefulWidget {
  final _TrainingFeedItem item;
  final bool isAdmin;
  final VoidCallback onSignUp;
  final VoidCallback onDecline;
  final VoidCallback? onOpenBoard;
  const _FeedTrainingCard({
    required this.item,
    required this.isAdmin,
    required this.onSignUp,
    required this.onDecline,
    this.onOpenBoard,
  });
  @override
  State<_FeedTrainingCard> createState() => _FeedTrainingCardState();
}

class _FeedTrainingCardState extends State<_FeedTrainingCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final item = widget.item;
    final t        = item.training;
    final start    = DateTime.parse(t['start_tid'] as String).toLocal();
    final slut     = DateTime.parse(t['slut_tid'] as String).toLocal();
    final deadline = DateTime.parse(t['tilmeldings_deadline'] as String).toLocal();
    final adresse  = t['adresse']  as String;
    final titel    = t['titel']    as String;
    final max      = t['max_deltagere'] as int?;
    final cnt      = item.signedUpCount;
    final status   = item.myStatus;
    final hasAddr  = adresse.isNotEmpty && adresse != _addressUnspecified;
    final deadlinePassed = DateTime.now().isAfter(deadline);
    final canSignUp = !deadlinePassed || widget.isAdmin;
    final full = max != null && cnt >= max;
    final totalParticipants =
        item.tilmeldte.length + item.venteliste.length +
        item.afmeldte.length + item.trainere.length;

    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: _neon.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text('BEGIVENHED',
                          style: TextStyle(
                              color: _neon,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.5)),
                    ),
                    _SquadBadge(
                      signedUp: cnt,
                      max: max,
                      trainerCount: item.trainere.length,
                    ),
                    if (status != null) _MyStatusChip(status: status),
                    if (widget.isAdmin && widget.onOpenBoard != null)
                      Tooltip(
                        message: 'Åbn drag-and-drop board',
                        child: IconButton(
                          onPressed: widget.onOpenBoard,
                          icon: const Icon(Icons.view_kanban_outlined,
                              size: 20, color: _neon),
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(titel, style: theme.textTheme.titleLarge),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.schedule, size: 16, color: _textSecondary),
                    const SizedBox(width: 6),
                    Text('${_fmtDateTime(start)} – ${_fmtTime(slut)}',
                        style: theme.textTheme.bodyMedium),
                  ],
                ),
                if (hasAddr) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.place_outlined, size: 16, color: _textSecondary),
                      const SizedBox(width: 6),
                      Expanded(child: Text(adresse,
                          style: theme.textTheme.bodyMedium,
                          overflow: TextOverflow.ellipsis)),
                    ],
                  ),
                ],
                if (deadlinePassed)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      children: [
                        Icon(Icons.lock_clock, size: 16, color: Colors.red.shade400),
                        const SizedBox(width: 6),
                        Text('Frist overskredet',
                            style: TextStyle(color: Colors.red.shade400, fontSize: 13)),
                      ],
                    ),
                  ),
                const SizedBox(height: 14),
                LayoutBuilder(builder: (ctx, constraints) {
                  final wide = constraints.maxWidth >= 320;
                  final tilmeldBtn = _ActionStatusButton(
                    label: 'TILMELD',
                    color: const Color(0xFF22C55E),
                    icon: Icons.check,
                    active: status == 'tilmeldt' || status == 'venteliste',
                    onPressed: canSignUp ? widget.onSignUp : null,
                  );
                  final afbudBtn = _ActionStatusButton(
                    label: 'AFBUD',
                    color: const Color(0xFFEF4444),
                    icon: Icons.block,
                    active: status == 'afmeldt',
                    onPressed: canSignUp ? widget.onDecline : null,
                  );
                  final calBtn = IconButton.outlined(
                    onPressed: () => _downloadIcs(t),
                    icon: const Icon(Icons.calendar_month_outlined, size: 18),
                    tooltip: 'Tilføj til kalender',
                    style: IconButton.styleFrom(
                      side: const BorderSide(color: _borderSubtle),
                      foregroundColor: _textPrimary,
                    ),
                  );
                  if (wide) {
                    return Row(
                      children: [
                        Expanded(child: tilmeldBtn),
                        const SizedBox(width: 8),
                        Expanded(child: afbudBtn),
                        const SizedBox(width: 8),
                        calBtn,
                      ],
                    );
                  }
                  // Smal skærm — knapperne pakker naturligt
                  return Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [tilmeldBtn, afbudBtn, calBtn],
                  );
                }),
              ],
            ),
          ),
          if (totalParticipants > 0) ...[
            const Divider(height: 1, color: _borderSubtle),
            InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                child: Row(
                  children: [
                    Icon(_expanded ? Icons.expand_less : Icons.expand_more,
                        size: 20, color: _neon),
                    const SizedBox(width: 8),
                    Text(_expanded ? 'Skjul deltagere' : 'Se deltagere',
                        style: const TextStyle(
                            color: _neon,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5)),
                    const Spacer(),
                    Text('$totalParticipants total',
                        style: const TextStyle(
                            color: _textSecondary, fontSize: 12)),
                  ],
                ),
              ),
            ),
            AnimatedCrossFade(
              crossFadeState: _expanded
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              duration: const Duration(milliseconds: 200),
              firstChild: const SizedBox(width: double.infinity, height: 0),
              secondChild: Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                child: Column(
                  children: [
                    if (item.trainere.isNotEmpty) ...[
                      _TrainingParticipantGroup(
                        label: 'TRÆNERE',
                        color: Colors.lightBlue.shade300,
                        icon: Icons.shield,
                        participants: item.trainere,
                      ),
                      const SizedBox(height: 10),
                    ],
                    _TrainingParticipantGroup(
                      label: 'TILMELDT',
                      color: Colors.green.shade400,
                      icon: Icons.check_circle,
                      participants: item.tilmeldte,
                    ),
                    if (item.venteliste.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      _TrainingParticipantGroup(
                        label: 'VENTELISTE',
                        color: Colors.orange.shade400,
                        icon: Icons.hourglass_top,
                        participants: item.venteliste,
                      ),
                    ],
                    if (item.afmeldte.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      _TrainingParticipantGroup(
                        label: 'AFBUD',
                        color: const Color(0xFFEF4444),
                        icon: Icons.block,
                        participants: item.afmeldte,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Trænings-deltagere — viser navn + tidspunkt (især nyttigt for "Afmeldt"
/// gruppen, så admin/træner kan se *hvornår* spilleren meldte afbud).
class _TrainingParticipantGroup extends StatelessWidget {
  final String label;
  final Color color;
  final IconData icon;
  final List<_Participant> participants;
  const _TrainingParticipantGroup({
    required this.label,
    required this.color,
    required this.icon,
    required this.participants,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                    color: color,
                    fontSize: 10,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.bold)),
            const SizedBox(width: 6),
            Text('· ${participants.length}',
                style: const TextStyle(color: _textSecondary, fontSize: 11)),
          ],
        ),
        const SizedBox(height: 6),
        if (participants.isEmpty)
          const Padding(
            padding: EdgeInsets.only(left: 20),
            child: Text('Ingen',
                style: TextStyle(color: _textMuted, fontSize: 13)),
          )
        else
          Wrap(
            spacing: 6, runSpacing: 6,
            children: participants.map((p) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: _surfaceElevated,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                    color: color.withValues(alpha: 0.3), width: 1),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(p.navn,
                      style: const TextStyle(
                          color: _textPrimary, fontSize: 13,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(width: 8),
                  Text(_fmtRelative(p.updatedAt),
                      style: const TextStyle(
                          color: _textMuted, fontSize: 11,
                          fontWeight: FontWeight.w500)),
                ],
              ),
            )).toList(),
          ),
      ],
    );
  }
}

class _ParticipantGroup extends StatelessWidget {
  final String label;
  final Color color;
  final IconData icon;
  final List<String> names;
  const _ParticipantGroup({
    required this.label,
    required this.color,
    required this.icon,
    required this.names,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                    color: color,
                    fontSize: 10,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.bold)),
            const SizedBox(width: 6),
            Text('· ${names.length}',
                style: const TextStyle(
                    color: _textSecondary, fontSize: 11)),
          ],
        ),
        const SizedBox(height: 6),
        if (names.isEmpty)
          const Padding(
            padding: EdgeInsets.only(left: 20),
            child: Text('Ingen',
                style: TextStyle(color: _textMuted, fontSize: 13)),
          )
        else
          Wrap(
            spacing: 6, runSpacing: 6,
            children: names.map((n) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: _surfaceElevated,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                    color: color.withValues(alpha: 0.3), width: 1),
              ),
              child: Text(n,
                  style: const TextStyle(
                      color: _textPrimary, fontSize: 13,
                      fontWeight: FontWeight.w600)),
            )).toList(),
          ),
      ],
    );
  }
}

class _ActionStatusButton extends StatelessWidget {
  final String label;
  final Color color;
  final IconData icon;
  final bool active;
  final VoidCallback? onPressed;
  const _ActionStatusButton({
    required this.label,
    required this.color,
    required this.icon,
    required this.active,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    if (active) {
      return FilledButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 16),
        label: Text(label,
            style: const TextStyle(letterSpacing: 1, fontWeight: FontWeight.w700)),
        style: FilledButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
          minimumSize: const Size(0, 44),
        ),
      );
    }
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 16,
          color: onPressed == null ? _textMuted : color),
      label: Text(label,
          style: TextStyle(
              letterSpacing: 1,
              fontWeight: FontWeight.w700,
              color: onPressed == null ? _textMuted : color)),
      style: OutlinedButton.styleFrom(
        side: BorderSide(
            color: onPressed == null
                ? _borderSubtle
                : color.withValues(alpha: 0.5),
            width: 1),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
        minimumSize: const Size(0, 44),
        foregroundColor: color,
      ),
    );
  }
}

class _SquadBadge extends StatelessWidget {
  final int signedUp;
  final int? max; // null = ubegrænset
  final int trainerCount;
  const _SquadBadge({
    required this.signedUp,
    required this.max,
    this.trainerCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    final full = max != null && signedUp >= max!;
    final color = full ? Colors.orange.shade400 : _neon;
    final base = max == null
        ? '$signedUp · ∞ pladser'
        : '$signedUp/$max på holdet';
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: color.withValues(alpha: 0.4), width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.group, size: 14, color: color),
              const SizedBox(width: 6),
              Text(base,
                  style: TextStyle(
                      color: color, fontSize: 12, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
        if (trainerCount > 0) ...[
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.lightBlue.shade300.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                  color: Colors.lightBlue.shade300.withValues(alpha: 0.4), width: 1),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.shield, size: 12, color: Colors.lightBlue.shade300),
                const SizedBox(width: 4),
                Text('+$trainerCount',
                    style: TextStyle(
                        color: Colors.lightBlue.shade300,
                        fontSize: 12,
                        fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _MyStatusChip extends StatelessWidget {
  final String status;
  const _MyStatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      'tilmeldt'   => ('PÅ HOLDET', Colors.green.shade400),
      'venteliste' => ('VENTELISTE', Colors.orange.shade400),
      'afmeldt'    => ('AFMELDT', _textMuted),
      _            => (status, Colors.blue.shade300),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label,
          style: TextStyle(
              color: color, fontSize: 10,
              fontWeight: FontWeight.bold, letterSpacing: 1)),
    );
  }
}

// ─── Poll-kort i Oversigt ───────────────────────────────────────────────────

class _FeedPollCard extends StatefulWidget {
  final _PollFeedItem item;
  final bool isAdmin;
  final void Function(String optionId, bool svar) onVote;
  final VoidCallback? onOpenSynergy;
  const _FeedPollCard({
    required this.item,
    required this.isAdmin,
    required this.onVote,
    this.onOpenSynergy,
  });
  @override
  State<_FeedPollCard> createState() => _FeedPollCardState();
}

class _FeedPollCardState extends State<_FeedPollCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final item  = widget.item;
    final p     = item.poll;
    final beskr = p['beskrivelse'] as String?;
    final missing = item.totalMembers - item.respondedCount;
    final hasAnyVoter = item.votersByOption.values
        .any((v) => v.yes.isNotEmpty || v.no.isNotEmpty);

    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.purple.shade300.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text('AFSTEMNING',
                          style: TextStyle(
                              color: Colors.purple.shade200,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.5)),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: missing > 0
                            ? Colors.orange.shade400.withValues(alpha: 0.12)
                            : Colors.green.shade400.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                            color: (missing > 0
                                    ? Colors.orange.shade400
                                    : Colors.green.shade400)
                                .withValues(alpha: 0.4),
                            width: 1),
                      ),
                      child: Text(
                        missing > 0
                            ? '$missing mangler at svare'
                            : 'Alle har svaret',
                        style: TextStyle(
                            color: missing > 0
                                ? Colors.orange.shade400
                                : Colors.green.shade400,
                            fontSize: 12,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                    if (widget.isAdmin && widget.onOpenSynergy != null)
                      Tooltip(
                        message: 'Åbn synergi-rapport',
                        child: IconButton(
                          onPressed: widget.onOpenSynergy,
                          icon: const Icon(Icons.insights,
                              size: 20, color: _neon),
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(p['titel'] as String, style: theme.textTheme.titleLarge),
                if (beskr != null && beskr.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(beskr,
                      style: theme.textTheme.bodyMedium?.copyWith(color: _textSecondary)),
                ],
                const SizedBox(height: 14),
                if (item.options.isEmpty)
                  Text('Ingen datoer endnu', style: theme.textTheme.bodySmall)
                else
                  ...item.options.map((o) {
                    final id  = o['id'] as String;
                    final tid = DateTime.parse(o['option_tid'] as String).toLocal();
                    final lbl = o['beskrivelse'] as String?;
                    final my  = item.myVotes[id];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          ConstrainedBox(
                            constraints: const BoxConstraints(minWidth: 140),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(_fmtDateTime(tid),
                                    style: theme.textTheme.bodyLarge?.copyWith(
                                        fontWeight: FontWeight.w600)),
                                if (lbl != null && lbl.isNotEmpty)
                                  Text(lbl, style: theme.textTheme.bodySmall),
                              ],
                            ),
                          ),
                          _MiniVoteBtn(label: 'JA',
                              active: my == true,
                              activeColor: Colors.green.shade400,
                              onPressed: () => widget.onVote(id, true)),
                          _MiniVoteBtn(label: 'NEJ',
                              active: my == false,
                              activeColor: Colors.red.shade400,
                              onPressed: () => widget.onVote(id, false)),
                        ],
                      ),
                    );
                  }),
              ],
            ),
          ),
          if (hasAnyVoter) ...[
            const Divider(height: 1, color: _borderSubtle),
            InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                child: Row(
                  children: [
                    Icon(_expanded ? Icons.expand_less : Icons.expand_more,
                        size: 20, color: _neon),
                    const SizedBox(width: 8),
                    Text(_expanded ? 'Skjul stemmer' : 'Se hvem der har stemt',
                        style: const TextStyle(
                            color: _neon,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5)),
                    const Spacer(),
                    Text('${item.respondedCount} stemmere',
                        style: const TextStyle(
                            color: _textSecondary, fontSize: 12)),
                  ],
                ),
              ),
            ),
            AnimatedCrossFade(
              crossFadeState: _expanded
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              duration: const Duration(milliseconds: 200),
              firstChild: const SizedBox(width: double.infinity, height: 0),
              secondChild: Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                child: Column(
                  children: item.options.map((o) {
                    final id  = o['id'] as String;
                    final tid = DateTime.parse(o['option_tid'] as String).toLocal();
                    final voters = item.votersByOption[id] ??
                        const _OptionVoters(yes: [], no: []);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_fmtDateTime(tid),
                              style: const TextStyle(
                                  color: _textPrimary,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700)),
                          const SizedBox(height: 8),
                          _ParticipantGroup(
                            label: 'JA',
                            color: Colors.green.shade400,
                            icon: Icons.thumb_up,
                            names: voters.yes,
                          ),
                          const SizedBox(height: 10),
                          _ParticipantGroup(
                            label: 'NEJ',
                            color: Colors.red.shade400,
                            icon: Icons.thumb_down,
                            names: voters.no,
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MiniVoteBtn extends StatelessWidget {
  final String label;
  final bool active;
  final Color activeColor;
  final VoidCallback onPressed;
  const _MiniVoteBtn({
    required this.label,
    required this.active,
    required this.activeColor,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    if (active) {
      return SizedBox(
        height: 36,
        child: FilledButton(
          onPressed: onPressed,
          style: FilledButton.styleFrom(
            backgroundColor: activeColor,
            foregroundColor: Colors.black,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            minimumSize: Size.zero,
          ),
          child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
        ),
      );
    }
    return SizedBox(
      height: 36,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          minimumSize: Size.zero,
          foregroundColor: _textPrimary,
          side: const BorderSide(color: _borderSubtle),
        ),
        child: Text(label),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tab 3: Profil + makker-valg
// ─────────────────────────────────────────────────────────────────────────────

