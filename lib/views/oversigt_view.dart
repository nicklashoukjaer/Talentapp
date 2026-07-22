// Auto-split (del af biblioteket padel_app)
// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
part of '../main.dart';

/// Holdene en aktivitet gælder. Nye rækker bruger group_ids (flere hold);
/// gamle rækker falder tilbage til det enkelte group_id. Tom = alle hold.
List<String> _trainingGroupIds(Map<String, dynamic> t) {
  final arr = t['group_ids'];
  if (arr is List && arr.isNotEmpty) {
    return arr.map((e) => e.toString()).toList();
  }
  final single = t['group_id'] as String?;
  return (single == null || single.isEmpty) ? const [] : [single];
}

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
  List<Map<String, dynamic>> _groups = const []; // grupper brugeren er på
  Set<String> _myGroupIds = {};   // brugerens gruppe-id'er
  Set<String> _myCaptainGroupIds = {}; // hold hvor brugeren er kaptajn
  String? _switcherGroupId;       // valgt hold i switcheren (null = alle mine)

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
            .select('id, titel, beskrivelse, max_deltagere, start_tid, slut_tid, adresse, tilmeldings_deadline, group_id, group_ids, synlig_fra, created_by')
            .gte('start_tid', sinceIso).order('start_tid'),
        // Polls (alle — lukkede filtreres client-side)
        supabase.from('polls')
            .select('id, titel, beskrivelse, lukket_at, created_at, group_id, created_by')
            .order('created_at', ascending: false),
        // Profiles for count
        supabase.from('profiles').select('id'),
        // Grupper + mit medlemskab (til hold-filtrering)
        supabase.from('groups').select('id, navn, type, farve, sort').order('sort'),
        supabase.from('group_members').select('group_id, is_captain').eq('user_id', userId),
      ]);

      final trainingsRaw = List<Map<String, dynamic>>.from(results[0] as List);
      // Synlighed: spillere ser kun aktiviteter der er "åbnet" (synlig_fra er
      // null eller passeret). Staff (admin/træner) ser altid alt.
      final nowVis = DateTime.now();
      final trainings = widget.isAdmin
          ? trainingsRaw
          : trainingsRaw.where((t) {
              final sf = t['synlig_fra'] as String?;
              if (sf == null) return true;
              return !DateTime.parse(sf).toLocal().isAfter(nowVis);
            }).toList();
      final pollsAll    = List<Map<String, dynamic>>.from(results[1] as List);
      final profileRows = List<Map<String, dynamic>>.from(results[2] as List);
      final groups      = List<Map<String, dynamic>>.from(results[3] as List);
      final myGmRows    = List<Map<String, dynamic>>.from(results[4] as List);
      final myGroupIds  = myGmRows.map((r) => r['group_id'] as String).toSet();
      final myCaptainGroupIds = myGmRows
          .where((r) => r['is_captain'] == true)
          .map((r) => r['group_id'] as String)
          .toSet();

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

      // Gæster/afløsere pr. træning (tæller med i "tilmeldt X/Y").
      final guestCounts = <String, int>{};
      if (trainingIds.isNotEmpty) {
        try {
          final gRows = await supabase
              .from('training_guests')
              .select('training_id')
              .inFilter('training_id', trainingIds);
          for (final r in List<Map<String, dynamic>>.from(gRows as List)) {
            final tid = r['training_id'] as String;
            guestCounts[tid] = (guestCounts[tid] ?? 0) + 1;
          }
        } catch (_) {}
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
          signedUpCount: g['tilmeldt']!.length + (guestCounts[tid] ?? 0),
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
        _groups = groups;
        _myGroupIds = myGroupIds;
        _myCaptainGroupIds = myCaptainGroupIds;
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

  /// AFBUD — sætter status='afmeldt'. Efter fristen advares der om at det kan
  /// koste en udeblivelses-bøde (4a); selve afbud+bøde sker server-side.
  Future<void> _decline(_TrainingFeedItem item) async {
    final deadline =
        DateTime.parse(item.training['tilmeldings_deadline'] as String).toLocal();
    final late = DateTime.now().isAfter(deadline);
    final wasSignedUp =
        item.myStatus == 'tilmeldt' || item.myStatus == 'venteliste';

    if (late && wasSignedUp) {
      final cfg = await ClubConfig.fetchNoShowConfig();
      final willFine = cfg.autoEnabled && cfg.fineTypeId != null;
      final kr = _fmtKr(cfg.belobOere ?? 0);
      if (!mounted) return;
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Row(children: [
            const Icon(Icons.warning_amber_rounded, color: _gold),
            const SizedBox(width: 8),
            const Expanded(child: Text('Fristen er overskredet')),
          ]),
          content: Text(willFine
              ? 'Melder du afbud nu, koster det en udeblivelses-bøde på $kr.'
              : 'Tilmeldingsfristen er overskredet. Vil du melde afbud alligevel?'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Behold min tilmelding')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(backgroundColor: _danger),
              child: Text(willFine ? 'Meld afbud · $kr' : 'Meld afbud'),
            ),
          ],
        ),
      );
      if (ok != true) return;
      try {
        final oere = await supabase.rpc('late_cancel_training',
            params: {'p_training_id': item.training['id']});
        if (!mounted) return;
        final fined = (oere is num) && oere > 0;
        _snack(
            context,
            fined
                ? 'Afbud sendt — bøde på ${_fmtKr((oere).toInt())} tilføjet'
                : 'Afbud sendt',
            fined ? _gold : _textSecondary);
        await reload();
      } on PostgrestException catch (e) {
        if (mounted) _snack(context, e.message, Colors.red.shade400);
      }
      return;
    }

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

  Future<bool> _confirmDelete(String hvad, String navn) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Slet $hvad?'),
        content: Text('"$navn" fjernes permanent for alle. Det kan ikke fortrydes.'),
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
    return ok == true;
  }

  Future<void> _deleteTraining(_TrainingFeedItem item) async {
    final id = item.training['id'] as String;
    final titel = item.training['titel'] as String;
    if (!await _confirmDelete('begivenhed', titel)) return;
    try {
      // Fjern tilmeldinger først (hvis FK ikke sletter dem automatisk).
      await supabase.from('training_participants').delete().eq('training_id', id);
      final deleted = await supabase.from('trainings').delete().eq('id', id).select();
      if (!mounted) return;
      _snack(
        context,
        (deleted as List).isEmpty
            ? 'Kunne ikke slette — mangler du rettigheder?'
            : 'Begivenhed slettet',
        (deleted).isEmpty ? _danger : _textSecondary,
      );
      await reload();
    } on PostgrestException catch (e) {
      if (mounted) _snack(context, e.message, _danger);
      await reload();
    }
  }

  /// Må den aktuelle bruger redigere/slette denne aktivitet? (staff, opretter
  /// eller kaptajn for et af aktivitetens hold)
  bool _canManageTraining(Map<String, dynamic> t) {
    if (widget.isAdmin) return true;
    if (t['created_by'] == supabase.auth.currentUser?.id) return true;
    return _trainingGroupIds(t).any(_myCaptainGroupIds.contains);
  }

  bool _canManagePoll(Map<String, dynamic> p) {
    if (widget.isAdmin) return true;
    if (p['created_by'] == supabase.auth.currentUser?.id) return true;
    final gid = p['group_id'] as String?;
    return gid != null && _myCaptainGroupIds.contains(gid);
  }

  /// Navne på de hold en aktivitet gælder (tom = alle hold → vis intet).
  List<String> _groupNamesFor(Map<String, dynamic> t) {
    return _trainingGroupIds(t)
        .map((id) {
          final g = _groups.firstWhere((e) => e['id'] == id,
              orElse: () => const <String, dynamic>{});
          return g['navn'] as String?;
        })
        .whereType<String>()
        .toList();
  }

  Future<void> _publishTraining(_TrainingFeedItem item) async {
    final id = item.training['id'] as String;
    try {
      // synlig_fra = null → straks synlig for alle (overstyrer det planlagte tidspunkt).
      final updated = await supabase.from('trainings')
          .update({'synlig_fra': null}).eq('id', id).select();
      if (!mounted) return;
      _snack(
        context,
        (updated as List).isEmpty
            ? 'Kunne ikke udgive — mangler du rettigheder?'
            : 'Udgivet — nu synlig for spillerne',
        (updated).isEmpty ? _danger : _success,
      );
      await reload();
    } on PostgrestException catch (e) {
      if (mounted) _snack(context, e.message, _danger);
    }
  }

  Future<void> _deletePoll(_PollFeedItem item) async {
    final id = item.poll['id'] as String;
    final titel = item.poll['titel'] as String;
    if (!await _confirmDelete('afstemning', titel)) return;
    try {
      final opts = await supabase.from('poll_options').select('id').eq('poll_id', id);
      final optIds = (opts as List).map((o) => o['id'] as String).toList();
      if (optIds.isNotEmpty) {
        await supabase.from('poll_responses').delete().inFilter('poll_option_id', optIds);
      }
      await supabase.from('poll_options').delete().eq('poll_id', id);
      final deleted = await supabase.from('polls').delete().eq('id', id).select();
      if (!mounted) return;
      _snack(
        context,
        (deleted as List).isEmpty
            ? 'Kunne ikke slette — mangler du rettigheder?'
            : 'Afstemning slettet',
        (deleted).isEmpty ? _danger : _textSecondary,
      );
      await reload();
    } on PostgrestException catch (e) {
      if (mounted) _snack(context, e.message, _danger);
      await reload();
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
    if (_loading) return _loadingSkeleton();
    if (_error != null) return _ErrorView(error: _error!, onRetry: reload);

    // Hold-filtrering: vis kun begivenheder/afstemninger for hold jeg er på
    // (eller fælles uden hold). Switcheren filtrerer yderligere til ét hold.
    // Afstemninger hører til ét hold; aktiviteter kan høre til flere.
    bool visibleGroup(String? gid) {
      final mine = gid == null || _myGroupIds.contains(gid);
      if (!mine) return false;
      if (_switcherGroupId != null && gid != null && gid != _switcherGroupId) {
        return false;
      }
      return true;
    }
    // Flere hold: tom liste = alle. Synlig hvis mindst ét hold er mit; switcheren
    // kræver at det valgte hold er blandt aktivitetens hold.
    bool visibleGroups(List<String> gids) {
      if (gids.isEmpty) return true; // fælles for alle
      if (!gids.any(_myGroupIds.contains)) return false;
      if (_switcherGroupId != null && !gids.contains(_switcherGroupId)) {
        return false;
      }
      return true;
    }
    final polls = _items
        .whereType<_PollFeedItem>()
        .where((p) => visibleGroup(p.poll['group_id'] as String?))
        .toList();
    bool visibleToMe(_TrainingFeedItem t) =>
        visibleGroups(_trainingGroupIds(t.training));
    final allTrainings =
        _items.whereType<_TrainingFeedItem>().where(visibleToMe).toList();

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
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
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
                        IconButton(
                          onPressed: reload,
                          icon: const Icon(Icons.refresh),
                          tooltip: 'Opdater',
                        ),
                      ],
                    ),
                  ),
                  // Hold-switcher — kun hvis brugeren er på mindst ét hold
                  if (_groups.where((g) => _myGroupIds.contains(g['id'])).isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: _HoldSwitcher(
                        groups: _groups
                            .where((g) => _myGroupIds.contains(g['id']))
                            .toList(),
                        selectedId: _switcherGroupId,
                        onChanged: (id) => setState(() => _switcherGroupId = id),
                      ),
                    ),
                  // Kommende / Historik — pille-toggle (kun på AKTIVITETER)
                  if (showingTrainings)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: _KommendeHistorikToggle(
                        showHistory: _showHistory,
                        onChanged: (show) {
                          setState(() => _showHistory = show);
                          if (show && !_historyLoaded) {
                            _historyLoaded = true;
                            reload(includeHistory: true);
                          }
                        },
                      ),
                    ),
                  // (Aktiviteter/Afstemninger-segmentet fjernet — afstemninger
                  //  har sin egen fane. Oversigt viser kun aktiviteter.)
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
                  else ...[
                    // Sæson-oversigtskort øverst i Historik-visningen
                    if (showingTrainings && _showHistory)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: _SeasonSummaryCard(
                          trainings: visible.cast<_TrainingFeedItem>(),
                        ),
                      ),
                    // Web/bred skærm: sæson-matrix (spiller × dato)
                    if (showingTrainings && _showHistory &&
                        MediaQuery.of(context).size.width >= 700)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: _SeasonMatrix(
                          trainings: visible.cast<_TrainingFeedItem>(),
                        ),
                      ),
                    // "Næste på programmet"-hero — kun den næste kommende aktivitet
                    if (showingTrainings && !_showHistory)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: GestureDetector(
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => EventDetailScreen(
                                training: (visible.first as _TrainingFeedItem).training,
                                isStaff: widget.isAdmin,
                                canManage: _canManageTraining(
                                    (visible.first as _TrainingFeedItem).training),
                              ),
                            ),
                          ).then((_) => reload()),
                          child: _NextUpHero(
                            item: visible.first as _TrainingFeedItem,
                            isAdmin: widget.isAdmin,
                            onSignUp:  () => _signUp(visible.first as _TrainingFeedItem),
                            onDecline: () => _decline(visible.first as _TrainingFeedItem),
                          ),
                        ),
                      ),
                    // På bred skærm i historik erstattes kort-listen af matrixen
                    if (!(showingTrainings && _showHistory &&
                        MediaQuery.of(context).size.width >= 700))
                      ...(showingTrainings && !_showHistory ? visible.skip(1) : visible)
                          .map((item) => RepaintBoundary(child: Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: switch (item) {
                        _TrainingFeedItem t => (showingTrainings && _showHistory)
                            ? _HistoryTrainingCard(item: t)
                            : _FeedTrainingCard(
                          item: t,
                          isAdmin: widget.isAdmin,
                          canManage: _canManageTraining(t.training),
                          groupNames: _groupNamesFor(t.training),
                          onSignUp:  () => _signUp(t),
                          onDecline: () => _decline(t),
                          onDelete: _canManageTraining(t.training)
                              ? () => _deleteTraining(t) : null,
                          onPublish: widget.isAdmin ? () => _publishTraining(t) : null,
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
                          onDelete: _canManagePoll(p.poll)
                              ? () => _deletePoll(p) : null,
                          onOpenSynergy: widget.isAdmin
                              ? () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => FavoritePairsScreen(
                                        poll: p.poll),
                                  ),
                                )
                              : null,
                        ),
                      },
                    ))),
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

// ─── Træningskort i Oversigt ────────────────────────────────────────────────

class _FeedTrainingCard extends StatefulWidget {
  final _TrainingFeedItem item;
  final bool isAdmin;
  final VoidCallback onSignUp;
  final VoidCallback onDecline;
  final VoidCallback? onOpenBoard;
  final VoidCallback? onDelete;
  final VoidCallback? onPublish;
  final List<String> groupNames;
  final bool canManage; // kaptajn/staff/opretter → må redigere/slette
  const _FeedTrainingCard({
    required this.item,
    required this.isAdmin,
    this.canManage = false,
    this.groupNames = const [],
    required this.onSignUp,
    required this.onDecline,
    this.onOpenBoard,
    this.onDelete,
    this.onPublish,
  });
  @override
  State<_FeedTrainingCard> createState() => _FeedTrainingCardState();
}

class _FeedTrainingCardState extends State<_FeedTrainingCard> {
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
    // Synlighed: er aktiviteten stadig skjult for spillerne? (kun relevant for staff)
    final synligFraStr = t['synlig_fra'] as String?;
    final hiddenUntil = synligFraStr == null
        ? null : DateTime.parse(synligFraStr).toLocal();
    final isHidden = hiddenUntil != null && hiddenUntil.isAfter(DateTime.now());
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
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: _surfaceElevated,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text('KOMMENDE',
                          style: _body(
                              size: 10,
                              weight: FontWeight.w700,
                              spacing: 1.2,
                              color: _textSecondary)),
                    ),
                    _SquadBadge(
                      signedUp: cnt,
                      max: max,
                      trainerCount: item.trainere.length,
                    ),
                    for (final navn in widget.groupNames)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 9, vertical: 4),
                        decoration: BoxDecoration(
                          color: _neon.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(navn.toUpperCase(),
                            style: _body(
                                size: 10,
                                weight: FontWeight.w700,
                                spacing: 0.8,
                                color: _neon)),
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
                    if (widget.onDelete != null)
                      Tooltip(
                        message: 'Slet begivenhed',
                        child: IconButton(
                          onPressed: widget.onDelete,
                          icon: const Icon(Icons.delete_outline,
                              size: 20, color: _danger),
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
                if (widget.isAdmin && isHidden && widget.onPublish != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
                    decoration: BoxDecoration(
                      color: _gold.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _gold.withValues(alpha: 0.4)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.visibility_off_outlined,
                            size: 18, color: _gold),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Skjult for spillerne',
                                  style: _body(
                                      size: 12,
                                      weight: FontWeight.w700,
                                      color: _gold)),
                              Text('Bliver synlig ${_fmtDateTime(hiddenUntil)}',
                                  style: _body(size: 11, color: _textSecondary)),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.icon(
                          onPressed: widget.onPublish,
                          icon: const Icon(Icons.campaign_outlined, size: 18),
                          label: const Text('Udgiv nu'),
                          style: FilledButton.styleFrom(
                            backgroundColor: _gold,
                            foregroundColor: _onGold,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 10),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                LayoutBuilder(builder: (ctx, constraints) {
                  final wide = constraints.maxWidth >= 320;
                  final tilmeldBtn = _ActionStatusButton(
                    label: 'TILMELD',
                    color: _success,
                    icon: Icons.check,
                    active: status == 'tilmeldt' || status == 'venteliste',
                    onPressed: canSignUp ? widget.onSignUp : null,
                  );
                  // Afbud er også muligt EFTER fristen hvis man er tilmeldt —
                  // så kan man melde sent afbud (med evt. bøde, håndteres i _decline).
                  final canDecline = canSignUp ||
                      status == 'tilmeldt' ||
                      status == 'venteliste';
                  final afbudBtn = _ActionStatusButton(
                    label: 'AFBUD',
                    color: _danger,
                    icon: Icons.block,
                    active: status == 'afmeldt',
                    onPressed: canDecline ? widget.onDecline : null,
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
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => EventDetailScreen(
                    training: t, isStaff: widget.isAdmin,
                    canManage: widget.canManage),
              )),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                child: Row(
                  children: [
                    if (item.tilmeldte.isNotEmpty) ...[
                      _AvatarStack(
                          names: item.tilmeldte.map((p) => p.navn).toList(),
                          size: 26, maxShown: 4),
                      const SizedBox(width: 10),
                    ],
                    Text('${item.tilmeldte.length} tilmeldt',
                        style: const TextStyle(
                            color: _success,
                            fontSize: 13,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(width: 8),
                    const Text('· tryk for detaljer',
                        style: TextStyle(color: _textMuted, fontSize: 12)),
                    const Spacer(),
                    const Icon(Icons.chevron_right, size: 20, color: _textSecondary),
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
  final VoidCallback? onDelete;
  const _FeedPollCard({
    required this.item,
    required this.isAdmin,
    required this.onVote,
    this.onOpenSynergy,
    this.onDelete,
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
                    if (widget.onDelete != null)
                      Tooltip(
                        message: 'Slet afstemning',
                        child: IconButton(
                          onPressed: widget.onDelete,
                          icon: const Icon(Icons.delete_outline,
                              size: 20, color: _danger),
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

// ─── Redesign-widgets: pille-toggle, hero, sæson-historik ───────────────────

/// "Om X dage"-tekst ud fra kalenderdage til start.
String _omDage(DateTime start) {
  final now = DateTime.now();
  final today   = DateTime(now.year, now.month, now.day);
  final dayOf   = DateTime(start.year, start.month, start.day);
  final days    = dayOf.difference(today).inDays;
  if (days < 0)  return 'Afholdt';
  if (days == 0) return start.isAfter(now) ? 'I dag' : 'I gang';
  if (days == 1) return 'I morgen';
  if (days < 7)  return 'Om $days dage';
  if (days < 14) return 'Om 1 uge';
  return 'Om ${(days / 7).round()} uger';
}

/// Sæson-label ("2025/26") ud fra en dato — sæsonen starter i juli.
String _saeson(DateTime d) {
  final startYear = d.month >= 7 ? d.year : d.year - 1;
  final endShort  = ((startYear + 1) % 100).toString().padLeft(2, '0');
  return '$startYear/$endShort';
}

/// Initial-avatar (cirkel med forbogstav). [attended]=false → afbud-styling.
class _InitialAvatar extends StatelessWidget {
  final String navn;
  final double size;
  final bool attended;
  const _InitialAvatar({
    required this.navn,
    this.size = 28,
    this.attended = true,
  });

  @override
  Widget build(BuildContext context) {
    final initial = navn.trim().isEmpty ? '?' : navn.trim().substring(0, 1).toUpperCase();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: attended ? _neon : _surfaceElevated,
        shape: BoxShape.circle,
        border: attended
            ? Border.all(color: _bgBlack, width: 2)
            : Border.all(color: _danger.withValues(alpha: 0.5), width: 1),
      ),
      child: Text(
        initial,
        style: _cond(
          size: size * 0.42,
          weight: FontWeight.w800,
          color: attended ? Colors.white : _textMuted,
        ),
      ),
    );
  }
}

/// Overlappende avatar-række (26–28px, -8px overlap).
class _AvatarStack extends StatelessWidget {
  final List<String> names;
  final double size;
  final int maxShown;
  const _AvatarStack({required this.names, this.size = 26, this.maxShown = 5});

  @override
  Widget build(BuildContext context) {
    if (names.isEmpty) return const SizedBox.shrink();
    final shown = names.take(maxShown).toList();
    final step  = size - 8;
    final width = shown.length == 1
        ? size
        : size + (shown.length - 1) * step;
    return SizedBox(
      height: size,
      width: width,
      child: Stack(
        children: [
          for (var i = 0; i < shown.length; i++)
            Positioned(
              left: i * step,
              child: _InitialAvatar(navn: shown[i], size: size),
            ),
        ],
      ),
    );
  }
}

/// Hold-switcher — Alle / Hold 1 / Hold 2 / Kamp-trup (kun brugerens hold).
class _HoldSwitcher extends StatelessWidget {
  final List<Map<String, dynamic>> groups;
  final String? selectedId;
  final ValueChanged<String?> onChanged;
  const _HoldSwitcher({
    required this.groups,
    required this.selectedId,
    required this.onChanged,
  });

  static Color _hex(String? h) {
    if (h == null || h.isEmpty) return _neon;
    return Color(int.parse(h.replaceFirst('#', ''), radix: 16) | 0xFF000000);
  }

  @override
  Widget build(BuildContext context) {
    Widget chip(String label, String? id, Color color) {
      final active = selectedId == id;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: GestureDetector(
          onTap: () => onChanged(id),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              color: active ? color : _surfaceDark,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: active ? color : _borderSubtle),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (id != null) ...[
                Container(
                  width: 8, height: 8,
                  decoration: BoxDecoration(
                      color: active ? Colors.white : color,
                      shape: BoxShape.circle),
                ),
                const SizedBox(width: 7),
              ],
              Text(label,
                  style: _body(
                      size: 13,
                      weight: FontWeight.w700,
                      color: active ? Colors.white : _textSecondary)),
            ]),
          ),
        ),
      );
    }

    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        children: [
          chip('Alle', null, _neon),
          for (final g in groups)
            chip(g['navn'] as String, g['id'] as String, _hex(g['farve'] as String?)),
        ],
      ),
    );
  }
}

/// Kommende / Historik — pille-toggle.
class _KommendeHistorikToggle extends StatelessWidget {
  final bool showHistory;
  final ValueChanged<bool> onChanged;
  const _KommendeHistorikToggle({
    required this.showHistory,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    Widget seg(String label, bool isHistory) {
      final active = showHistory == isHistory;
      return Expanded(
        child: GestureDetector(
          onTap: () => onChanged(isHistory),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: active ? _neon : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              label,
              style: _body(
                size: 13,
                weight: FontWeight.w700,
                spacing: 0.3,
                color: active ? Colors.white : _textSecondary,
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: _surfaceDark,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _borderSubtle),
      ),
      child: Row(children: [seg('Kommende', false), seg('Historik', true)]),
    );
  }
}

/// "Næste på programmet"-hero — den næste kommende aktivitet, fremhævet.
class _NextUpHero extends StatelessWidget {
  final _TrainingFeedItem item;
  final bool isAdmin;
  final VoidCallback onSignUp;
  final VoidCallback onDecline;
  const _NextUpHero({
    required this.item,
    required this.isAdmin,
    required this.onSignUp,
    required this.onDecline,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t        = item.training;
    final start    = DateTime.parse(t['start_tid'] as String).toLocal();
    final slut     = DateTime.parse(t['slut_tid'] as String).toLocal();
    final deadline = DateTime.parse(t['tilmeldings_deadline'] as String).toLocal();
    final adresse  = t['adresse'] as String;
    final titel    = t['titel'] as String;
    final max      = t['max_deltagere'] as int?;
    final cnt      = item.signedUpCount;
    final status   = item.myStatus;
    final hasAddr  = adresse.isNotEmpty && adresse != _addressUnspecified;
    final deadlinePassed = DateTime.now().isAfter(deadline);
    final canSignUp = !deadlinePassed || isAdmin;
    final names = item.tilmeldte.map((p) => p.navn).toList();

    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_surfaceElevated, _surfaceDark],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _neon.withValues(alpha: 0.35), width: 1.5),
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text('NÆSTE PÅ PROGRAMMET',
                    style: _body(
                        size: 11,
                        weight: FontWeight.w700,
                        spacing: 1.4,
                        color: _neon)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: _neon,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(_omDage(start),
                    style: _body(
                        size: 12, weight: FontWeight.w700, color: Colors.white)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(titel.toUpperCase(), style: theme.textTheme.titleLarge),
          const SizedBox(height: 8),
          Row(children: [
            const Icon(Icons.schedule, size: 15, color: _textSecondary),
            const SizedBox(width: 6),
            Expanded(
              child: Text('${_fmtDateTime(start)} – ${_fmtTime(slut)}',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: _textSecondary)),
            ),
          ]),
          if (hasAddr) ...[
            const SizedBox(height: 4),
            Row(children: [
              const Icon(Icons.place_outlined, size: 15, color: _textSecondary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(adresse,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: _textSecondary),
                    overflow: TextOverflow.ellipsis),
              ),
            ]),
          ],
          const SizedBox(height: 14),
          Row(children: [
            if (names.isNotEmpty) ...[
              _AvatarStack(names: names),
              const SizedBox(width: 10),
            ],
            Text(
              max == null ? '$cnt tilmeldt' : '$cnt af $max tilmeldt',
              style: _body(size: 13, weight: FontWeight.w600, color: _textSecondary),
            ),
          ]),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(
              child: _ActionStatusButton(
                label: 'TILMELD',
                color: _success,
                icon: Icons.check,
                active: status == 'tilmeldt' || status == 'venteliste',
                onPressed: canSignUp ? onSignUp : null,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _ActionStatusButton(
                label: 'AFBUD',
                color: _danger,
                icon: Icons.block,
                active: status == 'afmeldt',
                onPressed: canSignUp ? onDecline : null,
              ),
            ),
          ]),
        ],
      ),
    );
  }
}

/// Sæson-oversigtskort (vises øverst i Historik) — din deltagelse.
class _SeasonSummaryCard extends StatelessWidget {
  final List<_TrainingFeedItem> trainings;
  const _SeasonSummaryCard({required this.trainings});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total    = trainings.length;
    final attended = trainings.where((t) => t.myStatus == 'tilmeldt').length;
    final pct      = total == 0 ? 0.0 : attended / total;
    final pctText  = '${(pct * 100).round()}%';
    final saeson   = trainings.isEmpty
        ? _saeson(DateTime.now())
        : _saeson(trainings
            .map((t) => DateTime.parse(t.training['start_tid'] as String))
            .reduce((a, b) => a.isAfter(b) ? a : b));

    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_surfaceElevated, _surfaceDark],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _borderSubtle),
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text('SÆSON $saeson',
                    style: theme.textTheme.titleLarge),
              ),
              Text('$total træninger',
                  style: _body(size: 13, color: _textSecondary)),
            ],
          ),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: pct,
                  minHeight: 8,
                  backgroundColor: _surfaceElevated,
                  valueColor: const AlwaysStoppedAnimation(_success),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Text(pctText,
                style: _cond(size: 20, weight: FontWeight.w800, color: _success)),
          ]),
          const SizedBox(height: 10),
          Text('Din deltagelse · $attended af $total',
              style: _body(size: 13, color: _textSecondary)),
        ],
      ),
    );
  }
}

/// Afholdt træning i historikken — dato-blok + fremmøde + deltager-avatarer.
class _HistoryTrainingCard extends StatelessWidget {
  final _TrainingFeedItem item;
  const _HistoryTrainingCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t      = item.training;
    final start  = DateTime.parse(t['start_tid'] as String).toLocal();
    final titel  = t['titel'] as String;
    final adresse = t['adresse'] as String? ?? '';
    final max    = t['max_deltagere'] as int?;
    final attended = item.tilmeldte.length;
    final afbud    = item.afmeldte.length;
    final full   = max != null && attended >= max;
    final denom  = max ?? (attended + afbud);
    final frac   = denom == 0 ? 0.0 : attended / denom;
    final hasAddr = adresse.isNotEmpty && adresse != _addressUnspecified;
    const months = ['JAN','FEB','MAR','APR','MAJ','JUN','JUL','AUG','SEP','OKT','NOV','DEC'];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
              // Dato-blok
              Container(
                width: 52,
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: _surfaceElevated,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(children: [
                  Text('${start.day}',
                      style: _cond(size: 22, weight: FontWeight.w800, color: _neon)),
                  Text(months[start.month - 1],
                      style: _body(size: 10, weight: FontWeight.w600, spacing: 0.5, color: _textSecondary)),
                ]),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(titel.toUpperCase(),
                        style: theme.textTheme.titleMedium,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 3),
                    Text(
                      '${_fmtTime(start)}${hasAddr ? ' · $adresse' : ''}',
                      style: _body(size: 12, color: _textSecondary),
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // DELTOG X/Y
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('DELTOG',
                      style: _body(
                          size: 9, weight: FontWeight.w700, spacing: 0.8,
                          color: _textMuted)),
                  Text(max == null ? '$attended' : '$attended/$max',
                      style: _cond(
                          size: 18, weight: FontWeight.w800,
                          color: full ? _success : _textPrimary)),
                ],
              ),
            ]),
            const SizedBox(height: 10),
            // Fremmøde-måler
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: frac.clamp(0.0, 1.0),
                minHeight: 6,
                backgroundColor: _surfaceElevated,
                valueColor: const AlwaysStoppedAnimation(_success),
              ),
            ),
            if (item.tilmeldte.isNotEmpty || item.afmeldte.isNotEmpty) ...[
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Wrap(
                      spacing: 6, runSpacing: 6,
                      children: [
                        for (final p in item.tilmeldte)
                          _InitialAvatar(navn: p.navn, size: 28, attended: true),
                        for (final p in item.afmeldte)
                          _InitialAvatar(navn: p.navn, size: 28, attended: false),
                      ],
                    ),
                  ),
                  if (afbud > 0) ...[
                    const SizedBox(width: 8),
                    Text('$afbud afbud',
                        style: _body(size: 12, weight: FontWeight.w600, color: _danger)),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Sæson-matrix (web) — spiller × dato med deltager-status.
class _SeasonMatrix extends StatelessWidget {
  final List<_TrainingFeedItem> trainings;
  const _SeasonMatrix({required this.trainings});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Kolonner = træninger sorteret ældst→nyest
    final cols = [...trainings]
      ..sort((a, b) => DateTime.parse(a.training['start_tid'] as String)
          .compareTo(DateTime.parse(b.training['start_tid'] as String)));

    // Spillere (efter navn) → status pr. kolonne: 'deltog' | 'afbud' | 'intet'
    final status = <String, Map<int, String>>{};
    for (var c = 0; c < cols.length; c++) {
      for (final p in cols[c].tilmeldte) {
        (status[p.navn] ??= {})[c] = 'deltog';
      }
      for (final p in cols[c].afmeldte) {
        (status[p.navn] ??= {})[c] = 'afbud';
      }
    }
    final players = status.keys.toList()..sort();

    String two(int n) => n.toString().padLeft(2, '0');
    String colLabel(int c) {
      final d = DateTime.parse(cols[c].training['start_tid'] as String).toLocal();
      return '${two(d.day)}.${two(d.month)}';
    }

    const nameW = 130.0;
    const cellW = 46.0;
    const totalW = 54.0;

    Widget cell(String? s) {
      final (bg, fg, glyph) = switch (s) {
        'deltog' => (_success.withValues(alpha: 0.16), _success, '✓'),
        'afbud'  => (_danger.withValues(alpha: 0.16), _danger, '✕'),
        _        => (_surfaceElevated, _textMuted, '–'),
      };
      return SizedBox(
        width: cellW,
        child: Center(
          child: Container(
            width: 24, height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
            child: Text(glyph, style: _body(size: 13, weight: FontWeight.w700, color: fg)),
          ),
        ),
      );
    }

    Widget headerRow() => Row(
          children: [
            SizedBox(
                width: nameW,
                child: Text('SPILLER',
                    style: _body(size: 11, weight: FontWeight.w700, spacing: 0.8, color: _textSecondary))),
            for (var c = 0; c < cols.length; c++)
              SizedBox(
                  width: cellW,
                  child: Center(
                      child: Text(colLabel(c),
                          style: _body(size: 11, weight: FontWeight.w600, color: _textSecondary)))),
            SizedBox(
                width: totalW,
                child: Center(
                    child: Text('I ALT',
                        style: _body(size: 11, weight: FontWeight.w700, spacing: 0.6, color: _textSecondary)))),
          ],
        );

    Widget playerRow(String navn) {
      final s = status[navn] ?? const {};
      final deltog = s.values.where((v) => v == 'deltog').length;
      return Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: _borderSubtle)),
        ),
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            SizedBox(
              width: nameW,
              child: Row(children: [
                _InitialAvatar(navn: navn, size: 26),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(navn,
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: _body(size: 13, weight: FontWeight.w600))),
              ]),
            ),
            for (var c = 0; c < cols.length; c++) cell(s[c]),
            SizedBox(
                width: totalW,
                child: Center(
                    child: Text('$deltog/${cols.length}',
                        style: _cond(size: 15, weight: FontWeight.w800)))),
          ],
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('SÆSON-HISTORIK', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            if (players.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text('Ingen registreret deltagelse endnu',
                    style: theme.textTheme.bodySmall),
              )
            else
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    headerRow(),
                    for (final navn in players) playerRow(navn),
                  ],
                ),
              ),
            const SizedBox(height: 14),
            // Legende
            Wrap(
              spacing: 16,
              runSpacing: 6,
              children: const [
                _MatrixLegend(color: _success, glyph: '✓', label: 'Deltog'),
                _MatrixLegend(color: _danger, glyph: '✕', label: 'Afbud'),
                _MatrixLegend(color: _textMuted, glyph: '–', label: 'Intet svar'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MatrixLegend extends StatelessWidget {
  final Color color;
  final String glyph;
  final String label;
  const _MatrixLegend({required this.color, required this.glyph, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 20, height: 20,
          alignment: Alignment.center,
          decoration: BoxDecoration(
              color: color.withValues(alpha: 0.16), shape: BoxShape.circle),
          child: Text(glyph, style: _body(size: 11, weight: FontWeight.w700, color: color)),
        ),
        const SizedBox(width: 6),
        Text(label, style: _body(size: 12, color: _textSecondary)),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Begivenheds-detalje (9b) — hvem er tilmeldt/afbud/mangler + admin-svar
// ─────────────────────────────────────────────────────────────────────────────
class _AttPerson {
  final String id, navn;
  final DateTime? svarTid;
  _AttPerson(this.id, this.navn, this.svarTid);
}

String _fmtSvar(DateTime d) {
  const m = ['jan','feb','mar','apr','maj','jun','jul','aug','sep','okt','nov','dec'];
  final l = d.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${l.day}. ${m[l.month - 1]} · ${two(l.hour)}:${two(l.minute)}';
}

class EventDetailScreen extends StatefulWidget {
  final Map<String, dynamic> training;
  final bool isStaff;
  // Må redigere/slette (kaptajn for holdet, opretter, eller staff).
  final bool canManage;
  const EventDetailScreen({
    super.key,
    required this.training,
    required this.isStaff,
    bool? canManage,
  }) : canManage = canManage ?? isStaff;
  @override
  State<EventDetailScreen> createState() => _EventDetailScreenState();
}

class _EventDetailScreenState extends State<EventDetailScreen> {
  List<_AttPerson> _tilmeldt = const [];
  List<_AttPerson> _afbud = const [];
  List<_AttPerson> _mangler = const [];
  List<Map<String, dynamic>> _guests = const []; // afløsere (uden konto)
  bool _loading = true;
  String? _error;
  bool _busy = false;
  String? _myId;
  int _tab = 0;          // 0 = Deltagere, 1 = Kommentarer
  int _commentCount = 0; // vist på kommentar-fanen
  bool _showAllMissing = false; // fold lange "mangler svar"-lister ud
  bool _afbudExpanded = false;   // fold afbud-striben ud

  @override
  void initState() {
    super.initState();
    _myId = supabase.auth.currentUser?.id;
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final tid = widget.training['id'];
      final results = await Future.wait([
        supabase.from('training_participants')
            .select('user_id, status, updated_at, '
                'profiles!training_participants_user_id_fkey(navn)')
            .eq('training_id', tid),
        supabase.from('profiles').select('id, navn').order('navn'),
      ]);
      final parts = List<Map<String, dynamic>>.from(results[0] as List);
      var profiles = List<Map<String, dynamic>>.from(results[1] as List);
      final byUser = {for (final p in parts) p['user_id'] as String: p};

      // Holdspecifik aktivitet: vis kun medlemmer af aktivitetens hold(s).
      // Alle der allerede har svaret beholdes uanset (fx en træner/admin).
      final groupIds = _trainingGroupIds(widget.training);
      if (groupIds.isNotEmpty) {
        final gm = await supabase
            .from('group_members')
            .select('user_id')
            .inFilter('group_id', groupIds);
        final eligible = List<Map<String, dynamic>>.from(gm as List)
            .map((r) => r['user_id'] as String)
            .toSet();
        profiles = profiles
            .where((p) =>
                eligible.contains(p['id'] as String) ||
                byUser.containsKey(p['id'] as String))
            .toList();
      }

      final tilmeldt = <_AttPerson>[], afbud = <_AttPerson>[], mangler = <_AttPerson>[];
      for (final prof in profiles) {
        final id = prof['id'] as String;
        final navn = prof['navn'] as String? ?? '(ukendt)';
        final part = byUser[id];
        if (part == null) {
          mangler.add(_AttPerson(id, navn, null));
        } else {
          final status = part['status'] as String;
          final ts = part['updated_at'] == null
              ? null
              : DateTime.parse(part['updated_at'] as String);
          if (status == 'afmeldt') {
            afbud.add(_AttPerson(id, navn, ts));
          } else {
            tilmeldt.add(_AttPerson(id, navn, ts));
          }
        }
      }
      // Antal kommentarer (til fane-badgen) + afløsere.
      int commentCount = _commentCount;
      List<Map<String, dynamic>> guests = _guests;
      try {
        final res = await Future.wait([
          supabase.from('training_comments').select('id').eq('training_id', tid),
          supabase.from('training_guests')
              .select('id, navn, added_by, profiles(navn)')
              .eq('training_id', tid).order('created_at'),
        ]);
        commentCount = (res[0] as List).length;
        guests = List<Map<String, dynamic>>.from(res[1] as List);
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _tilmeldt = tilmeldt;
        _afbud = afbud;
        _mangler = mangler;
        _guests = guests;
        _commentCount = commentCount;
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = e.toString(); });
    }
  }

  Future<void> _setStatus(String userId, String status) async {
    setState(() => _busy = true);
    try {
      await supabase.from('training_participants').upsert({
        'training_id': widget.training['id'],
        'user_id': userId,
        'status': status,
      }, onConflict: 'training_id,user_id');
      await _load();
    } on PostgrestException catch (e) {
      if (mounted) _snack(context, e.message, _danger);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _noShowCheck() async {
    final cfg = await ClubConfig.fetchNoShowConfig();
    if (cfg.fineTypeId == null) {
      if (mounted) {
        _snack(context,
            'Vælg først en udeblivelses-bøde under Admin → Bøder', _gold);
      }
      return;
    }
    if (!mounted) return;
    final selected = await showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _NoShowSheet(
        tilmeldte: _tilmeldt,
        belobOere: cfg.belobOere ?? 0,
        titel: cfg.titel ?? 'Udeblivelse',
      ),
    );
    if (selected == null || selected.isEmpty) return;
    setState(() => _busy = true);
    try {
      final giver = supabase.auth.currentUser!.id;
      // titel/beløb udelades — snapshot-trigger på fines fylder dem.
      final rows = selected
          .map((uid) => {
                'user_id': uid,
                'given_by': giver,
                'fine_type_id': cfg.fineTypeId,
                'begrundelse': 'Udeblivelse',
              })
          .toList();
      await supabase.from('fines').insert(rows);
      if (mounted) {
        _snack(
            context,
            '${selected.length} udeblivelses-bøde${selected.length == 1 ? "" : "r"} uddelt',
            _success);
      }
    } on PostgrestException catch (e) {
      if (mounted) _snack(context, e.message, _danger);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addGuest() async {
    final navn = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _AddGuestSheet(),
    );
    if (navn == null || navn.trim().isEmpty) return;
    try {
      await supabase.from('training_guests').insert({
        'training_id': widget.training['id'],
        'navn': navn.trim(),
        'added_by': _myId,
      });
      await _load();
      if (mounted) _snack(context, 'Afløser tilføjet', _success);
    } on PostgrestException catch (e) {
      if (mounted) _snack(context, e.message, _danger);
    }
  }

  Future<void> _deleteGuest(String id) async {
    try {
      await supabase.from('training_guests').delete().eq('id', id);
      await _load();
    } on PostgrestException catch (e) {
      if (mounted) _snack(context, e.message, _danger);
    }
  }

  Widget _guestsSection() {
    if (_guests.isEmpty && !widget.isStaff) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_guests.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 8, top: 4),
            child: Row(children: [
              const Icon(Icons.person_add_alt, size: 16, color: _gold),
              const SizedBox(width: 6),
              Text('AFLØSERE · ${_guests.length}',
                  style: _body(
                      size: 12,
                      weight: FontWeight.w700,
                      spacing: 0.8,
                      color: _gold)),
            ]),
          ),
          for (final g in _guests) _guestRow(g),
          const SizedBox(height: 8),
        ],
        if (widget.isStaff)
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: _busy ? null : _addGuest,
              icon: const Icon(Icons.person_add_alt_1, size: 18),
              label: const Text('Tilføj afløser'),
              style: OutlinedButton.styleFrom(
                foregroundColor: _gold,
                side: BorderSide(color: _gold.withValues(alpha: 0.5)),
              ),
            ),
          ),
        const SizedBox(height: 4),
      ],
    );
  }

  Widget _guestRow(Map<String, dynamic> g) {
    final navn = g['navn'] as String? ?? 'Gæst';
    final by = (g['profiles'] as Map<String, dynamic>?)?['navn'] as String?;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        Container(
          width: 34, height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _surfaceElevated,
            shape: BoxShape.circle,
            border: Border.all(color: _gold.withValues(alpha: 0.6)),
          ),
          child: Text(navn.isNotEmpty ? navn[0].toUpperCase() : 'G',
              style: _cond(size: 15, weight: FontWeight.w800, color: _gold)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Flexible(
                  child: Text(navn,
                      style: _body(size: 14, weight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                  decoration: BoxDecoration(
                      color: _gold.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(999)),
                  child: Text('GÆST',
                      style: _body(
                          size: 9, weight: FontWeight.w800, color: _gold)),
                ),
              ]),
              if (by != null)
                Text('Tilføjet af $by',
                    style: _body(size: 11, color: _textMuted)),
            ],
          ),
        ),
        if (widget.isStaff)
          IconButton(
            onPressed: () => _deleteGuest(g['id'] as String),
            icon: const Icon(Icons.close, size: 18, color: _textMuted),
            tooltip: 'Fjern afløser',
            visualDensity: VisualDensity.compact,
          ),
      ]),
    );
  }

  Future<void> _remindMissing() async {
    setState(() => _busy = true);
    try {
      final count = await supabase.rpc('send_training_reminders',
          params: {'p_training_id': widget.training['id']});
      if (mounted) {
        _snack(context, 'Rykker sendt til $count medlem${count == 1 ? '' : 'mer'}',
            _success);
      }
    } on PostgrestException catch (e) {
      if (mounted) _snack(context, e.message, _danger);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit() async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EditEventSheet(training: widget.training),
    );
    if (changed == true && mounted) Navigator.of(context).pop(true);
  }

  Future<void> _publish() async {
    setState(() => _busy = true);
    try {
      final id = widget.training['id'];
      await supabase.from('trainings')
          .update({'synlig_fra': null}).eq('id', id);
      widget.training['synlig_fra'] = null; // opdater lokalt så banneret forsvinder
      if (mounted) {
        _snack(context, 'Udgivet — nu synlig for spillerne', _success);
        setState(() {});
      }
    } on PostgrestException catch (e) {
      if (mounted) _snack(context, e.message, _danger);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Slet begivenhed?'),
        content: Text('"${widget.training['titel']}" og alle tilmeldinger '
            'fjernes permanent for alle.'),
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
    setState(() => _busy = true);
    try {
      final id = widget.training['id'];
      await supabase.from('training_participants').delete().eq('training_id', id);
      await supabase.from('trainings').delete().eq('id', id);
      if (mounted) {
        _snack(context, 'Begivenhed slettet', _textSecondary);
        Navigator.of(context).pop(true);
      }
    } on PostgrestException catch (e) {
      if (mounted) {
        _snack(context, e.message, _danger);
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = widget.training;
    final start = DateTime.parse(t['start_tid'] as String).toLocal();
    final slut = t['slut_tid'] == null
        ? null
        : DateTime.parse(t['slut_tid'] as String).toLocal();
    final adresse = t['adresse'] as String? ?? '';
    final hasAddr = adresse.isNotEmpty && adresse != _addressUnspecified;
    final synligFraStr = t['synlig_fra'] as String?;
    final hiddenUntil = synligFraStr == null
        ? null : DateTime.parse(synligFraStr).toLocal();
    final isHidden = hiddenUntil != null && hiddenUntil.isAfter(DateTime.now());
    final started = start.isBefore(DateTime.now());

    return Scaffold(
      appBar: AppBar(
        title: Text((t['titel'] as String).toUpperCase()),
        actions: [
          if (widget.canManage)
            IconButton(
              onPressed: _busy ? null : _edit,
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Redigér',
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _ErrorView(error: _error!, onRetry: _load)
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                  children: [
                    Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 700),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(children: [
                              const Icon(Icons.schedule, size: 15, color: _textSecondary),
                              const SizedBox(width: 6),
                              Text('${_fmtDateTime(start)}${slut != null ? ' – ${_fmtTime(slut)}' : ''}',
                                  style: theme.textTheme.bodyMedium
                                      ?.copyWith(color: _textSecondary)),
                            ]),
                            if (hasAddr) ...[
                              const SizedBox(height: 4),
                              Row(children: [
                                const Icon(Icons.place_outlined, size: 15, color: _textSecondary),
                                const SizedBox(width: 6),
                                Expanded(child: Text(adresse,
                                    style: theme.textTheme.bodyMedium
                                        ?.copyWith(color: _textSecondary))),
                              ]),
                            ],
                            const SizedBox(height: 16),
                            _DetailTabs(
                              tab: _tab,
                              commentCount: _commentCount,
                              onChanged: (v) => setState(() => _tab = v),
                            ),
                            const SizedBox(height: 14),
                            if (_tab == 1)
                              _EventComments(
                                trainingId: t['id'] as String,
                                isStaff: widget.isStaff,
                                onCountChanged: (n) {
                                  if (mounted && n != _commentCount) {
                                    setState(() => _commentCount = n);
                                  }
                                },
                              ),
                            if (_tab == 0) ...[
                            if (widget.isStaff && isHidden) ...[
                              const SizedBox(height: 14),
                              Container(
                                padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
                                decoration: BoxDecoration(
                                  color: _gold.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: _gold.withValues(alpha: 0.4)),
                                ),
                                child: Row(children: [
                                  const Icon(Icons.visibility_off_outlined,
                                      size: 18, color: _gold),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('Skjult for spillerne',
                                            style: _body(
                                                size: 12,
                                                weight: FontWeight.w700,
                                                color: _gold)),
                                        Text('Bliver synlig ${_fmtDateTime(hiddenUntil)}',
                                            style: _body(
                                                size: 11, color: _textSecondary)),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  FilledButton.icon(
                                    onPressed: _busy ? null : _publish,
                                    icon: const Icon(Icons.campaign_outlined, size: 18),
                                    label: const Text('Udgiv nu'),
                                    style: FilledButton.styleFrom(
                                      backgroundColor: _gold,
                                      foregroundColor: _onGold,
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 14, vertical: 10),
                                    ),
                                  ),
                                ]),
                              ),
                            ],
                            if (widget.isStaff) ...[
                              const SizedBox(height: 14),
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: _gold.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: _gold.withValues(alpha: 0.35)),
                                ),
                                child: Row(children: [
                                  const Icon(Icons.info_outline, size: 18, color: _gold),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                        'Du kan sætte tilmeld/afbud på andres vegne — tryk ✓/✗ ved spilleren.',
                                        style: _body(size: 12, color: _textSecondary)),
                                  ),
                                ]),
                              ),
                            ],
                            const SizedBox(height: 18),
                            _tilmeldtSection(),
                            _guestsSection(),
                            _manglerSection(),
                            _afbudSection(),
                            if (widget.isStaff && _mangler.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              SizedBox(
                                width: double.infinity,
                                child: FilledButton.icon(
                                  onPressed: _busy ? null : _remindMissing,
                                  icon: const Icon(Icons.notifications_active_outlined, size: 18),
                                  label: const Text('Påmind alle der mangler'),
                                ),
                              ),
                            ],
                            if (widget.isStaff && started && _tilmeldt.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton.icon(
                                  onPressed: _busy ? null : _noShowCheck,
                                  icon: const Icon(Icons.event_busy_outlined, size: 18),
                                  label: const Text('Hvem mødte ikke op?'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: _gold,
                                    side: BorderSide(color: _gold.withValues(alpha: 0.5)),
                                  ),
                                ),
                              ),
                            ],
                            if (widget.canManage) ...[
                              const SizedBox(height: 20),
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton.icon(
                                  onPressed: _busy ? null : _delete,
                                  icon: const Icon(Icons.delete_outline, size: 18),
                                  label: const Text('Slet begivenhed'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: _danger,
                                    side: const BorderSide(color: _danger),
                                  ),
                                ),
                              ),
                            ],
                            ], // slut på Deltagere-fanen (_tab == 0)
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }

  // ── 13b: renere fremmøde-overblik ──────────────────────────────────────────

  Widget _sectionHeader(String label, int n, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 4),
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

  /// Én række for en person der HAR svaret — rolig: navn, tidsstempel, status-prik.
  /// For staff kan man trykke på prikken for at ændre svaret.
  Widget _answeredRow(_AttPerson p, {required bool tilmeldt}) {
    final isMe = p.id == _myId;
    final color = tilmeldt ? _success : _danger;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(children: [
        _InitialAvatar(navn: p.navn, size: 32),
        const SizedBox(width: 12),
        Expanded(
          child: Row(children: [
            Flexible(
              child: Text(p.navn,
                  style: _body(size: 14, weight: FontWeight.w600),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            if (isMe)
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: Text('· dig', style: _body(size: 12, color: _neon)),
              ),
          ]),
        ),
        if (p.svarTid != null)
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: Text(_fmtSvar(p.svarTid!),
                style: _body(size: 11, color: _textMuted)),
          ),
        if (widget.isStaff)
          GestureDetector(
            onTap: _busy
                ? null
                : () => _setStatus(p.id, tilmeldt ? 'afmeldt' : 'tilmeldt'),
            child: Container(
              width: 26, height: 26,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.16),
                shape: BoxShape.circle,
                border: Border.all(color: color.withValues(alpha: 0.5)),
              ),
              child: Icon(
                  tilmeldt ? Icons.check : Icons.close, size: 14, color: color),
            ),
          )
        else
          Container(width: 10, height: 10,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      ]),
    );
  }

  Widget _tilmeldtSection() {
    if (_tilmeldt.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('TILMELDT', _tilmeldt.length + _guests.length, _success),
        for (final p in _tilmeldt) _answeredRow(p, tilmeldt: true),
        const SizedBox(height: 4),
      ],
    );
  }

  Widget _manglerSection() {
    if (_mangler.isEmpty) return const SizedBox.shrink();
    const cutoff = 6;
    final showAll = _showAllMissing || _mangler.length <= cutoff;
    final shown = showAll ? _mangler : _mangler.take(cutoff).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        _sectionHeader('MANGLER SVAR', _mangler.length, _textMuted),
        for (final p in shown)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(children: [
              _InitialAvatar(navn: p.navn, size: 32),
              const SizedBox(width: 12),
              Expanded(
                child: Text(p.navn,
                    style: _body(size: 14, weight: FontWeight.w600),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
              if (widget.isStaff) ...[
                _miniBtn(Icons.check, _success, () => _setStatus(p.id, 'tilmeldt')),
                const SizedBox(width: 6),
                _miniBtn(Icons.close, _danger, () => _setStatus(p.id, 'afmeldt')),
              ],
            ]),
          ),
        if (!showAll)
          TextButton(
            onPressed: () => setState(() => _showAllMissing = true),
            child: Text('Vis alle ${_mangler.length}'),
          ),
        const SizedBox(height: 4),
      ],
    );
  }

  Widget _afbudSection() {
    if (_afbud.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => setState(() => _afbudExpanded = !_afbudExpanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(children: [
              const Icon(Icons.cancel, size: 16, color: _danger),
              const SizedBox(width: 8),
              Text('AFBUD · ${_afbud.length}',
                  style: _body(
                      size: 12, weight: FontWeight.w800, spacing: 0.8,
                      color: _danger)),
              const SizedBox(width: 10),
              if (!_afbudExpanded)
                Expanded(
                  child: _AvatarStack(
                      names: _afbud.map((p) => p.navn).toList(), size: 24),
                )
              else
                const Spacer(),
              Icon(_afbudExpanded ? Icons.expand_less : Icons.expand_more,
                  size: 20, color: _textMuted),
            ]),
          ),
        ),
        if (_afbudExpanded)
          for (final p in _afbud) _answeredRow(p, tilmeldt: false),
        const SizedBox(height: 4),
      ],
    );
  }

  Widget _miniBtn(IconData icon, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: _busy ? null : onTap,
      child: Container(
        width: 34, height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.5)),
        ),
        child: Icon(icon, size: 18, color: color),
      ),
    );
  }
}

/// Fane-skift i begivenheds-detaljen: Deltagere / Kommentarer (m. antal-badge).
class _DetailTabs extends StatelessWidget {
  final int tab;
  final int commentCount;
  final ValueChanged<int> onChanged;
  const _DetailTabs({
    required this.tab,
    required this.commentCount,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    Widget seg(String label, int i, {int? badge}) {
      final active = tab == i;
      return Expanded(
        child: GestureDetector(
          onTap: () => onChanged(i),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: active ? _neon : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label,
                    style: _body(
                        size: 13,
                        weight: FontWeight.w700,
                        color: active ? Colors.white : _textSecondary)),
                if (badge != null && badge > 0) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: active
                          ? Colors.white.withValues(alpha: 0.25)
                          : _surfaceElevated,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text('$badge',
                        style: _body(
                            size: 10,
                            weight: FontWeight.w800,
                            color: active ? Colors.white : _textSecondary)),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: _surfaceDark,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _borderSubtle),
      ),
      child: Row(children: [
        seg('Deltagere', 0),
        seg('Kommentarer', 1, badge: commentCount),
      ]),
    );
  }
}

/// Kommentar-tråd på en begivenhed — chat-bobler (egne til højre i accent).
class _EventComments extends StatefulWidget {
  final String trainingId;
  final bool isStaff;
  final ValueChanged<int> onCountChanged;
  const _EventComments({
    required this.trainingId,
    required this.isStaff,
    required this.onCountChanged,
  });
  @override
  State<_EventComments> createState() => _EventCommentsState();
}

class _EventCommentsState extends State<_EventComments> {
  List<Map<String, dynamic>> _comments = const [];
  bool _loading = true;
  bool _posting = false;
  final _ctrl = TextEditingController();
  String? get _myId => supabase.auth.currentUser?.id;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final rows = await supabase
          .from('training_comments')
          .select('id, user_id, body, created_at, profiles(navn, rolle)')
          .eq('training_id', widget.trainingId)
          .order('created_at');
      if (!mounted) return;
      final list = List<Map<String, dynamic>>.from(rows as List);
      setState(() {
        _comments = list;
        _loading = false;
      });
      widget.onCountChanged(list.length);
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _post() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _myId == null) return;
    setState(() => _posting = true);
    try {
      await supabase.from('training_comments').insert({
        'training_id': widget.trainingId,
        'user_id': _myId,
        'body': text,
      });
      _ctrl.clear();
      if (mounted) FocusScope.of(context).unfocus();
      await _load();
    } on PostgrestException catch (e) {
      if (mounted) _snack(context, e.message, _danger);
    } finally {
      if (mounted) setState(() => _posting = false);
    }
  }

  Future<void> _delete(String id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Slet kommentar?'),
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
      await supabase.from('training_comments').delete().eq('id', id);
      await _load();
    } on PostgrestException catch (e) {
      if (mounted) _snack(context, e.message, _danger);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_loading)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_comments.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 22),
            child: Text('Ingen kommentarer endnu — vær den første.',
                textAlign: TextAlign.center,
                style: _body(size: 13, color: _textMuted)),
          )
        else
          for (final c in _comments) _bubble(c),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: _surfaceElevated,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: _borderSubtle),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _ctrl,
                minLines: 1,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  hintText: 'Skriv en kommentar…',
                  border: InputBorder.none,
                  isDense: true,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          _posting
              ? const SizedBox(
                  width: 44, height: 44,
                  child: Center(
                      child: SizedBox(
                          width: 18, height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))))
              : IconButton.filled(
                  onPressed: _post,
                  icon: const Icon(Icons.send, size: 18),
                  style: IconButton.styleFrom(
                      backgroundColor: _neon, foregroundColor: Colors.white),
                ),
        ]),
      ],
    );
  }

  Widget _bubble(Map<String, dynamic> c) {
    final mine = c['user_id'] == _myId;
    final prof = c['profiles'] as Map<String, dynamic>?;
    final navn = prof?['navn'] as String? ?? '(ukendt)';
    final rolle = prof?['rolle'] as String? ?? 'medlem';
    final isTrainer = rolle == 'træner' || rolle == 'admin';
    final created = DateTime.parse(c['created_at'] as String).toLocal();
    final canDelete = mine || widget.isStaff;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment:
            mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            Text(mine ? 'Dig' : navn,
                style: _body(
                    size: 11, weight: FontWeight.w700, color: _textSecondary)),
            if (isTrainer && !mine) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                    color: _neon.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(999)),
                child: Text('TRÆNER',
                    style: _body(
                        size: 9, weight: FontWeight.w800, color: _neon)),
              ),
            ],
            const SizedBox(width: 6),
            Text(_fmtRelative(created).replaceFirst('· ', ''),
                style: _body(size: 10, color: _textMuted)),
          ]),
          const SizedBox(height: 3),
          GestureDetector(
            onLongPress: canDelete ? () => _delete(c['id'] as String) : null,
            child: Container(
              constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.72),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: mine
                    ? _neon.withValues(alpha: 0.16)
                    : _surfaceElevated,
                borderRadius: BorderRadius.circular(13),
                border: Border.all(
                    color: mine
                        ? _neon.withValues(alpha: 0.35)
                        : _borderSubtle),
              ),
              child: Text(c['body'] as String,
                  style: _body(size: 14, color: _textPrimary)),
            ),
          ),
        ],
      ),
    );
  }
}

/// Bundsheet: tilføj en afløser/gæst på navn (uden konto).
class _AddGuestSheet extends StatefulWidget {
  const _AddGuestSheet();
  @override
  State<_AddGuestSheet> createState() => _AddGuestSheetState();
}

class _AddGuestSheetState extends State<_AddGuestSheet> {
  final _navn = TextEditingController();

  @override
  void dispose() {
    _navn.dispose();
    super.dispose();
  }

  void _submit() {
    final v = _navn.text.trim();
    if (v.isEmpty) {
      _snack(context, 'Skriv et navn på afløseren', _gold);
      return;
    }
    Navigator.of(context).pop(v);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: Container(
          margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: _surfaceDark,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _borderSubtle),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('TILFØJ AFLØSER',
                  style: _cond(size: 20, weight: FontWeight.w800)),
              const SizedBox(height: 6),
              Text('Vises som "Gæst" i tilmeldt-listen og kan få bøde som alle '
                  'andre. Knyttet til denne ene begivenhed.',
                  style: _body(size: 12.5, color: _textSecondary)),
              const SizedBox(height: 16),
              TextField(
                controller: _navn,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _submit(),
                decoration: const InputDecoration(
                  labelText: 'Navn på afløseren',
                  prefixIcon: Icon(Icons.person_outline),
                ),
              ),
              const SizedBox(height: 18),
              Row(children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: TextButton.styleFrom(foregroundColor: _textSecondary),
                    child: const Text('Annullér'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    onPressed: _submit,
                    child: const Text('Tilføj til tilmeldte'),
                  ),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Hvem mødte ikke op?" (4b) — kryds de udeblevne af → uddel bøder.
class _NoShowSheet extends StatefulWidget {
  final List<_AttPerson> tilmeldte;
  final int belobOere;
  final String titel;
  const _NoShowSheet({
    required this.tilmeldte,
    required this.belobOere,
    required this.titel,
  });
  @override
  State<_NoShowSheet> createState() => _NoShowSheetState();
}

class _NoShowSheetState extends State<_NoShowSheet> {
  final Set<String> _picked = {};

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = _picked.length * widget.belobOere;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.85),
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
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('HVEM MØDTE IKKE OP?',
                      style: theme.textTheme.titleLarge),
                  const SizedBox(height: 4),
                  Text('Kryds de tilmeldte af som udeblev — de får '
                      '"${widget.titel}" (${_fmtKr(widget.belobOere)}).',
                      style: _body(size: 12.5, color: _textSecondary)),
                ],
              ),
            ),
            Flexible(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                children: [
                  for (final p in widget.tilmeldte)
                    CheckboxListTile(
                      value: _picked.contains(p.id),
                      onChanged: (v) => setState(() {
                        if (v == true) {
                          _picked.add(p.id);
                        } else {
                          _picked.remove(p.id);
                        }
                      }),
                      activeColor: _danger,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: Text(p.navn,
                          style: _body(size: 14.5, weight: FontWeight.w600)),
                      dense: true,
                    ),
                ],
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('${_picked.length} udeblevet',
                          style: _body(
                              size: 12, weight: FontWeight.w700, color: _danger)),
                      Text('Bøde i alt: ${_fmtKr(total)}',
                          style: _body(size: 12, color: _textSecondary)),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: _picked.isEmpty
                      ? null
                      : () => Navigator.of(context).pop(_picked),
                  icon: const Icon(Icons.gavel, size: 18),
                  label: const Text('Uddel bøder'),
                  style: FilledButton.styleFrom(
                    backgroundColor: _gold,
                    foregroundColor: _onGold,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
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

/// Redigér begivenhed (11b) — bundsheet med grupperede dato/tid-felter.
class _EditEventSheet extends StatefulWidget {
  final Map<String, dynamic> training;
  const _EditEventSheet({required this.training});
  @override
  State<_EditEventSheet> createState() => _EditEventSheetState();
}

class _EditEventSheetState extends State<_EditEventSheet> {
  late final TextEditingController _titel;
  late final TextEditingController _adresse;
  late final TextEditingController _maxCtrl;
  DateTime? _dato;
  TimeOfDay? _fra;
  TimeOfDay? _til;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final t = widget.training;
    _titel = TextEditingController(text: t['titel'] as String? ?? '');
    final adr = t['adresse'] as String? ?? '';
    _adresse = TextEditingController(text: adr == _addressUnspecified ? '' : adr);
    final mx = t['max_deltagere'];
    _maxCtrl = TextEditingController(text: mx == null ? '' : '$mx');
    final start = DateTime.parse(t['start_tid'] as String).toLocal();
    _dato = DateTime(start.year, start.month, start.day);
    _fra = TimeOfDay(hour: start.hour, minute: start.minute);
    if (t['slut_tid'] != null) {
      final slut = DateTime.parse(t['slut_tid'] as String).toLocal();
      _til = TimeOfDay(hour: slut.hour, minute: slut.minute);
    }
  }

  @override
  void dispose() {
    _titel.dispose();
    _adresse.dispose();
    _maxCtrl.dispose();
    super.dispose();
  }

  static DateTime _combine(DateTime d, TimeOfDay t) =>
      DateTime(d.year, d.month, d.day, t.hour, t.minute);

  Future<void> _save() async {
    if (_titel.text.trim().isEmpty) {
      _snack(context, 'Titel er påkrævet', _gold);
      return;
    }
    if (_dato == null || _fra == null) {
      _snack(context, 'Vælg dato og fra-tid', _gold);
      return;
    }
    final start = _combine(_dato!, _fra!);
    final slut =
        _til != null ? _combine(_dato!, _til!) : start.add(const Duration(minutes: 90));
    if (!slut.isAfter(start)) {
      _snack(context, 'Til-tid skal være efter fra-tid', _gold);
      return;
    }
    setState(() => _saving = true);
    try {
      final maxRaw = _maxCtrl.text.trim();
      await supabase.from('trainings').update({
        'titel': _titel.text.trim(),
        'start_tid': start.toUtc().toIso8601String(),
        'slut_tid': slut.toUtc().toIso8601String(),
        'adresse': _adresse.text.trim().isEmpty
            ? _addressUnspecified
            : _adresse.text.trim(),
        'max_deltagere': maxRaw.isEmpty ? null : int.tryParse(maxRaw),
      }).eq('id', widget.training['id']);
      if (mounted) {
        _snack(context, 'Begivenhed opdateret', _success);
        Navigator.pop(context, true);
      }
    } on PostgrestException catch (e) {
      if (mounted) {
        _snack(context, e.message, _danger);
        setState(() => _saving = false);
      }
    }
  }

  Widget _dateField() => InkWell(
        onTap: () async {
          final d = await _showQuickDatePicker(context, _dato ?? DateTime.now());
          if (d != null) setState(() => _dato = d);
        },
        borderRadius: BorderRadius.circular(11),
        child: InputDecorator(
          decoration: const InputDecoration(
              labelText: 'Dato', prefixIcon: Icon(Icons.event)),
          child: Text(_dato == null ? 'Vælg dato' : _fmtDate(_dato!),
              style: TextStyle(color: _dato == null ? _textMuted : null)),
        ),
      );

  Widget _timeField(String label, TimeOfDay? v, ValueChanged<TimeOfDay?> onCh) =>
      InkWell(
        onTap: () async {
          final t = await _showQuickTimePicker(context, v);
          if (t != null) onCh(t);
        },
        borderRadius: BorderRadius.circular(11),
        child: InputDecorator(
          decoration: InputDecoration(
              labelText: label, prefixIcon: const Icon(Icons.schedule, size: 18)),
          child: Text(
            v == null
                ? 'Vælg tid'
                : '${v.hour.toString().padLeft(2, '0')}:${v.minute.toString().padLeft(2, '0')}',
            style: TextStyle(
                color: v == null ? _textMuted : _neon,
                fontWeight: FontWeight.w700,
                letterSpacing: v == null ? 0 : 1.2),
          ),
        ),
      );

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
                Expanded(child: Text('REDIGÉR BEGIVENHED',
                    style: theme.textTheme.titleLarge)),
                IconButton(
                  onPressed: _saving ? null : () => Navigator.pop(context),
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
                    TextField(
                      controller: _titel,
                      decoration: const InputDecoration(labelText: 'Titel'),
                    ),
                    const SizedBox(height: 16),
                    _fieldGroup('DATO & TIDSPUNKT', [
                      _dateField(),
                      const SizedBox(height: 10),
                      Row(children: [
                        Expanded(child: _timeField('Fra', _fra, (t) => setState(() => _fra = t))),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 6),
                          child: Icon(Icons.arrow_forward, size: 16, color: _textMuted),
                        ),
                        Expanded(child: _timeField('Til · valgfri', _til, (t) => setState(() => _til = t))),
                      ]),
                    ]),
                    const SizedBox(height: 16),
                    Row(children: [
                      Expanded(
                        child: TextField(
                          controller: _maxCtrl,
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          decoration: const InputDecoration(
                              labelText: 'Max', hintText: '∞'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: TextField(
                          controller: _adresse,
                          decoration: const InputDecoration(labelText: 'Sted'),
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
                    onPressed: _saving ? null : () => Navigator.pop(context),
                    style: TextButton.styleFrom(foregroundColor: _textSecondary),
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
                        : const Text('Gem ændringer'),
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
// Tab 3: Profil + makker-valg
// ─────────────────────────────────────────────────────────────────────────────

