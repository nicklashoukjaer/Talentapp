// Auto-split (del af biblioteket padel_app)
// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
part of '../main.dart';

class DashboardTab extends StatefulWidget {
  final bool isFullAdmin; // true = admin, false = træner (kun create-handlinger)
  const DashboardTab({super.key, required this.isFullAdmin});
  @override
  State<DashboardTab> createState() => DashboardTabState();
}

class DashboardTabState extends State<DashboardTab> {
  // Trænings-data
  List<Map<String, dynamic>> _trainings = const [];
  Map<String, int> _signedUp = const {};
  bool _loadingTrainings = true;
  String? _trainingsError;

  // Polls-data
  List<Map<String, dynamic>> _polls = const [];
  bool _loadingPolls = true;
  String? _pollsError;

  // Bøde-data
  List<Map<String, dynamic>> _profiles = const [];
  List<Map<String, dynamic>> _fineTypes = const [];
  List<Map<String, dynamic>> _pendingFines = const [];
  bool _loadingFines = true;
  String? _finesError;

  // Aktiv sektion-fane: 0 = Bøder, 1 = Medlemmer, 2 = Betaling
  int _dashSection = 0;

  @override
  void initState() {
    super.initState();
    reloadTrainings();
    reloadPolls();
    reloadFines();
  }

  Future<void> _reloadAll() async {
    await Future.wait([reloadTrainings(), reloadPolls(), reloadFines()]);
  }

  Future<void> reloadTrainings() async {
    setState(() { _loadingTrainings = true; _trainingsError = null; });
    try {
      final trainings = await supabase
          .from('trainings')
          .select('id, titel, max_deltagere, start_tid, slut_tid, adresse, tilmeldings_deadline')
          .order('start_tid');
      final tList = List<Map<String, dynamic>>.from(trainings as List);
      final ids = tList.map((t) => t['id'] as String).toList();

      final parts = ids.isEmpty
          ? const <Map<String, dynamic>>[]
          : List<Map<String, dynamic>>.from(await supabase
              .from('training_participants')
              .select('training_id, status')
              .inFilter('training_id', ids) as List);

      final counts = <String, int>{};
      for (final r in parts) {
        if (r['status'] == 'tilmeldt') {
          final id = r['training_id'] as String;
          counts[id] = (counts[id] ?? 0) + 1;
        }
      }

      setState(() {
        _trainings = tList;
        _signedUp  = counts;
        _loadingTrainings = false;
      });
    } catch (e) {
      setState(() { _loadingTrainings = false; _trainingsError = e.toString(); });
    }
  }

  Future<void> reloadPolls() async {
    setState(() { _loadingPolls = true; _pollsError = null; });
    try {
      final rows = await supabase
          .from('polls')
          .select('id, titel, beskrivelse, lukket_at, created_at')
          .order('created_at', ascending: false);
      setState(() {
        _polls = List<Map<String, dynamic>>.from(rows as List);
        _loadingPolls = false;
      });
    } catch (e) {
      setState(() { _loadingPolls = false; _pollsError = e.toString(); });
    }
  }

  Future<void> reloadFines() async {
    setState(() { _loadingFines = true; _finesError = null; });
    try {
      final results = await Future.wait([
        supabase.from('profiles').select('id, navn, rolle').order('navn'),
        supabase.from('fine_types').select('id, titel, belob_oere, aktiv').order('titel'),
        // VIGTIGT: profiles har 3 FK'er fra fines (user_id, given_by, approved_by)
        // — disambigueres med fines_user_id_fkey
        supabase.from('fines')
            .select('id, user_id, titel, belob_oere, begrundelse, created_at, '
                    'profiles!fines_user_id_fkey(navn)')
            .eq('status', 'ubetalt')
            .order('created_at', ascending: false),
      ]);

      setState(() {
        _profiles     = List<Map<String, dynamic>>.from(results[0] as List);
        _fineTypes    = List<Map<String, dynamic>>.from(results[1] as List);
        _pendingFines = List<Map<String, dynamic>>.from(results[2] as List);
        _loadingFines = false;
      });
    } catch (e) {
      setState(() { _loadingFines = false; _finesError = e.toString(); });
    }
  }

  Future<void> _openCreateTraining() async {
    final created = await showDialog<bool>(
      context: context,
      builder: (_) => const CreateTrainingDialog(),
    );
    if (created == true) reloadTrainings();
  }

  Future<void> _openCreatePoll() async {
    final created = await showDialog<bool>(
      context: context,
      builder: (_) => const CreatePollDialog(),
    );
    if (created == true) reloadPolls();
  }

  void _openBoard(Map<String, dynamic> training) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => TrainingBoardScreen(training: training),
    )).then((_) => reloadTrainings());
  }

  void _openSynergyReport(Map<String, dynamic> poll) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => SynergyReportScreen(poll: poll),
    ));
  }

  Future<void> _approvePayment(String fineId) async {
    try {
      await supabase.from('fines').update({
        'status':      'godkendt_betalt',
        'approved_by': supabase.auth.currentUser!.id,
        'paid_at':     DateTime.now().toUtc().toIso8601String(),
      }).eq('id', fineId);
      if (mounted) _snack(context, 'Bøde godkendt som betalt', Colors.green);
      await reloadFines();
    } on PostgrestException catch (e) {
      if (mounted) _snack(context, e.message, Colors.red);
    }
  }

  Future<void> _approveSuggestion(String id, int kr) async {
    try {
      await supabase.from('fine_types').update({
        'belob_oere': kr * 100,
        'aktiv':      true,
      }).eq('id', id);
      if (mounted) _snack(context, 'Bødetype godkendt og aktiveret', Colors.green);
      await reloadFines();
    } on PostgrestException catch (e) {
      if (mounted) _snack(context, e.message, Colors.red);
      rethrow;
    }
  }

  Future<void> _changeRole(String userId, String newRole) async {
    try {
      await supabase.from('profiles').update({'rolle': newRole}).eq('id', userId);
      if (mounted) {
        _snack(context,
            newRole == 'admin' ? 'Spiller er nu admin' : 'Admin-rettigheder fjernet',
            newRole == 'admin' ? Colors.green : _textSecondary);
      }
      await reloadFines(); // genindlæser profiles med ny rolle
    } on PostgrestException catch (e) {
      if (mounted) _snack(context, e.message, Colors.red);
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: RefreshIndicator(
        onRefresh: _reloadAll,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildHero(),
                    const SizedBox(height: 20),
                    _buildQuickActions(),
                    if (widget.isFullAdmin) ...[
                      const SizedBox(height: 28),
                      _SectionPills(
                        active: _dashSection,
                        pendingCount: _pendingFines.length,
                        onChanged: (i) => setState(() => _dashSection = i),
                      ),
                      const SizedBox(height: 20),
                      switch (_dashSection) {
                        1 => _buildMembersSection(),
                        2 => const _MobilePayConfigCard(),
                        _ => _buildFineSection(),
                      },
                    ],
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHero() {
    final theme = Theme.of(context);
    final title = widget.isFullAdmin
        ? 'ADMIN KOMMANDOCENTRAL'
        : 'TRÆNER PANEL';
    final subtitle = widget.isFullAdmin
        ? 'Lynhurtige handlinger til at styre holdet'
        : 'Opret træninger, kampe og afstemninger';
    return Padding(
      padding: const EdgeInsets.only(left: 4, top: 4),
      child: Row(
        children: [
          Container(
            width: 4, height: 36,
            decoration: const BoxDecoration(
              color: _neon,
              borderRadius: BorderRadius.all(Radius.circular(2)),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title,
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.headlineSmall?.copyWith(
                        letterSpacing: 1.5)),
                Text(subtitle,
                    maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActions() {
    final tiles = <Widget>[
      _ActionTile(
        icon: Icons.add_circle_outline,
        label: 'Ny begivenhed',
        hint:  'Enkelt eller serie',
        onTap: _openCreateTraining,
      ),
      _ActionTile(
        icon: Icons.bar_chart,
        label: 'Ny afstemning',
        hint:  'Multi-dato + synergi',
        onTap: _openCreatePoll,
      ),
      if (widget.isFullAdmin)
        _ActionTile(
          icon: Icons.gavel,
          label: 'Lyn-bøde',
          hint:  'Spiller + type',
          onTap: () async {
            final ok = await showDialog<bool>(
              context: context,
              builder: (_) => const GiveFineDialog(),
            );
            if (ok == true) reloadFines();
          },
        ),
      if (widget.isFullAdmin)
        _ActionTile(
          icon: Icons.group_outlined,
          label: 'Medlemmer',
          hint:  'Roller & staff',
          onTap: () => setState(() => _dashSection = 1),
        ),
    ];
    return LayoutBuilder(builder: (ctx, constraints) {
      // Bredt: alle fliser på én række. Ellers 2 pr. række (2×2-grid).
      final perRow = constraints.maxWidth > 600 ? tiles.length : 2;
      const gap = 12.0;
      final rows = <Widget>[];
      for (var i = 0; i < tiles.length; i += perRow) {
        final end = (i + perRow) > tiles.length ? tiles.length : (i + perRow);
        final chunk = tiles.sublist(i, end);
        // IntrinsicHeight giver Row'en en afgrænset højde, så stretch (ens
        // flise-højde) virker i ListViewens ellers uendelige lodrette rum.
        rows.add(IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var j = 0; j < perRow; j++) ...[
                Expanded(child: j < chunk.length ? chunk[j] : const SizedBox()),
                if (j != perRow - 1) const SizedBox(width: gap),
              ],
            ],
          ),
        ));
        if (i + perRow < tiles.length) rows.add(const SizedBox(height: gap));
      }
      return Column(children: rows);
    });
  }

  Widget _buildTrainingSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(
          title: 'Træninger & Kampe',
          icon: Icons.sports_tennis,
          actionLabel: 'Opret træning',
          onAction: _openCreateTraining,
        ),
        const SizedBox(height: 12),
        if (_loadingTrainings)
          const Padding(padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()))
        else if (_trainingsError != null)
          Text(_trainingsError!, style: const TextStyle(color: Colors.red))
        else if (_trainings.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Ingen træninger endnu — Ctrl+K → "opret".',
                style: TextStyle(color: Colors.grey)),
          )
        else
          ..._trainings.map((t) {
            final start = DateTime.parse(t['start_tid'] as String).toLocal();
            final max   = t['max_deltagere'] as int?;
            final cnt   = _signedUp[t['id']] ?? 0;
            final addr  = t['adresse'] as String;
            final hasAddress = addr.isNotEmpty && addr != _addressUnspecified;
            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: ListTile(
                leading: const Icon(Icons.sports_tennis),
                title: Text(t['titel'] as String),
                subtitle: Text(
                  '${_fmtDateTime(start)} · '
                  '${max == null ? "$cnt tilmeldt · ∞" : "$cnt/$max tilmeldt"}'
                  '${hasAddress ? " · $addr" : ""}',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _openBoard(t),
              ),
            );
          }),
      ],
    );
  }

  Widget _buildPollSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(
          title: 'Afstemninger & Holdbygger',
          icon: Icons.insights,
          actionLabel: 'Opret afstemning',
          onAction: _openCreatePoll,
        ),
        const SizedBox(height: 12),
        if (_loadingPolls)
          const Padding(padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()))
        else if (_pollsError != null)
          Text(_pollsError!, style: const TextStyle(color: Colors.red))
        else if (_polls.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Ingen afstemninger endnu — Ctrl+K → "opret afstemning".',
              style: TextStyle(color: Colors.grey),
            ),
          )
        else
          ..._polls.map((p) {
            final beskr  = p['beskrivelse'] as String?;
            final lukket = p['lukket_at'] != null &&
                DateTime.parse(p['lukket_at'] as String).isBefore(DateTime.now());
            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: ListTile(
                leading: Icon(lukket ? Icons.lock_outline : Icons.insights,
                    color: lukket ? Colors.grey : Theme.of(context).colorScheme.primary),
                title: Text(p['titel'] as String),
                subtitle: Text(
                  beskr != null && beskr.isNotEmpty
                      ? beskr
                      : 'Klik for synergi-rapport',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _openSynergyReport(p),
              ),
            );
          }),
      ],
    );
  }

  Widget _buildFineSection() {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.gavel, size: 28, color: theme.colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(child: Text('Bøde-administration',
                style: theme.textTheme.headlineSmall)),
            IconButton(
              onPressed: reloadFines,
              icon: const Icon(Icons.refresh),
              tooltip: 'Opdater',
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_loadingFines)
          const Padding(padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()))
        else if (_finesError != null)
          Text(_finesError!, style: const TextStyle(color: Colors.red))
        else ...[
          _GiveFineCard(
            profiles:  _profiles,
            fineTypes: _fineTypes.where((t) => t['aktiv'] == true).toList(),
            onIssued:  reloadFines,
          ),
          const SizedBox(height: 16),
          _PendingFinesCard(
            fines: _pendingFines,
            onApprove: _approvePayment,
          ),
          const SizedBox(height: 16),
          _PendingSuggestionsCard(
            suggestions: _fineTypes.where((t) => t['aktiv'] == false).toList(),
            onApprove:   _approveSuggestion,
          ),
          const SizedBox(height: 16),
          _CreateFineTypeCard(
            existingTypes: _fineTypes.where((t) => t['aktiv'] == true).toList(),
            onCreated:     reloadFines,
          ),
        ],
      ],
    );
  }

  Widget _buildMembersSection() {
    final theme = Theme.of(context);
    final currentUserId = supabase.auth.currentUser?.id;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.admin_panel_settings,
                size: 28, color: theme.colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(child: Text('Medlemsstyring & Rettigheder',
                style: theme.textTheme.headlineSmall)),
            IconButton(
              onPressed: reloadFines,
              icon: const Icon(Icons.refresh),
              tooltip: 'Opdater',
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_loadingFines)
          const Padding(padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()))
        else
          _MemberRolesCard(
            profiles: _profiles,
            currentUserId: currentUserId ?? '',
            onChangeRole: _changeRole,
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Admin: MobilePay-opsætning (kun synlig for admins)
// ─────────────────────────────────────────────────────────────────────────────
class _MobilePayConfigCard extends StatefulWidget {
  const _MobilePayConfigCard();
  @override
  State<_MobilePayConfigCard> createState() => _MobilePayConfigCardState();
}

class _MobilePayConfigCardState extends State<_MobilePayConfigCard> {
  final _ctrl = TextEditingController();
  bool _saving = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final box = ClubConfig.cachedBox ?? await ClubConfig.fetchMobilePayBox();
    if (!mounted) return;
    setState(() {
      _ctrl.text = box ?? '';
      _loading = false;
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final v = _ctrl.text.trim();
    if (v.isEmpty) {
      _snack(context, 'Indtast et Box-ID eller et fuldt MobilePay-link', Colors.orange);
      return;
    }
    setState(() => _saving = true);
    try {
      await ClubConfig.updateMobilePayBox(v);
      if (mounted) _snack(context, 'MobilePay-opsætning gemt ✓', Colors.green);
    } on PostgrestException catch (e) {
      if (mounted) _snack(context, 'Kunne ikke gemme: ${e.message}', Colors.red);
    } catch (e) {
      if (mounted) _snack(context, 'Kunne ikke gemme: $e', Colors.red);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.account_balance_wallet_outlined,
                    color: Color(0xFF0055FF)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Admin: MobilePay Opsætning 🎾',
                      style: theme.textTheme.titleMedium),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Indtast holdets MobilePay Box-ID (fx 1234567) ELLER et fuldt '
              'Box-link. Det bruges automatisk når spillere betaler deres bøder.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 14),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(8),
                child: Center(child: CircularProgressIndicator()),
              )
            else ...[
              TextField(
                controller: _ctrl,
                decoration: const InputDecoration(
                  labelText: 'Box-ID eller fuldt Box-link',
                  prefixIcon: Icon(Icons.qr_code_2_outlined),
                  hintText: 'fx 1234567  ·  eller  https://qr.mobilepay.dk/box/…',
                ),
                onSubmitted: (_) => _save(),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 16, height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.save_outlined),
                  label: const Text('Gem indstillinger'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF0055FF),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MemberRolesCard extends StatefulWidget {
  final List<Map<String, dynamic>> profiles;
  final String currentUserId;
  final Future<void> Function(String userId, String newRole) onChangeRole;
  const _MemberRolesCard({
    required this.profiles,
    required this.currentUserId,
    required this.onChangeRole,
  });
  @override
  State<_MemberRolesCard> createState() => _MemberRolesCardState();
}

class _MemberRolesCardState extends State<_MemberRolesCard> {
  final Set<String> _saving = {};

  Future<void> _setRole(Map<String, dynamic> profile, String newRole) async {
    final id = profile['id'] as String;
    setState(() => _saving.add(id));
    try {
      await widget.onChangeRole(id, newRole);
    } catch (_) {
      // _changeRole viser allerede fejl-snack
    } finally {
      if (mounted) setState(() => _saving.remove(id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    int rolleRank(String r) {
      if (r == 'admin') return 0;
      if (r == 'træner') return 1;
      return 2; // medlem
    }
    final sorted = [...widget.profiles]
      ..sort((a, b) {
        final cmp = rolleRank(a['rolle'] as String)
            .compareTo(rolleRank(b['rolle'] as String));
        if (cmp != 0) return cmp;
        return (a['navn'] as String).toLowerCase()
            .compareTo((b['navn'] as String).toLowerCase());
      });
    final adminCount  = sorted.where((p) => p['rolle'] == 'admin').length;
    final trainerCount = sorted.where((p) => p['rolle'] == 'træner').length;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.shield_outlined, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text('Holdets staff',
                    style: theme.textTheme.titleMedium),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                      '$adminCount admin · $trainerCount træner',
                      style: TextStyle(
                          color: theme.colorScheme.onPrimaryContainer,
                          fontWeight: FontWeight.bold,
                          fontSize: 12)),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Admin = fuld adgang (bøder, roller). Træner = kan oprette '
              'begivenheder og optager ikke en spillerplads. Du kan ikke '
              'ændre din egen rolle.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            if (sorted.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: Text('Ingen profiler endnu')),
              )
            else
              ...sorted.map((p) {
                final id    = p['id']    as String;
                final navn  = p['navn']  as String;
                final rolle = p['rolle'] as String;
                final isMe  = id == widget.currentUserId;
                final saving = _saving.contains(id);

                final (rolleLabel, rolleColor) = switch (rolle) {
                  'admin'  => ('ADMIN',  _neon),
                  'træner' => ('TRÆNER', Colors.lightBlue.shade300),
                  _        => ('MEDLEM', _textSecondary),
                };

                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 18,
                        backgroundColor: rolleColor.withValues(alpha: 0.18),
                        child: Text(
                          navn.isNotEmpty ? navn[0].toUpperCase() : '?',
                          style: TextStyle(
                              color: rolleColor,
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(navn,
                                      style: theme.textTheme.bodyLarge?.copyWith(
                                          fontWeight: FontWeight.w600),
                                      overflow: TextOverflow.ellipsis),
                                ),
                                if (isMe) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: theme.colorScheme.primaryContainer,
                                      borderRadius: BorderRadius.circular(3),
                                    ),
                                    child: const Text('DIG',
                                        style: TextStyle(
                                            fontSize: 9,
                                            letterSpacing: 1,
                                            fontWeight: FontWeight.bold,
                                            color: _neon)),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 2),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(
                                color: rolleColor.withValues(alpha: 0.18),
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: Text(rolleLabel,
                                  style: TextStyle(
                                      color: rolleColor,
                                      fontSize: 9,
                                      letterSpacing: 1.2,
                                      fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (isMe)
                        Tooltip(
                          message: 'Du kan ikke ændre din egen rolle',
                          child: Container(
                            width: 40, height: 40,
                            alignment: Alignment.center,
                            child: Icon(Icons.lock_outline,
                                size: 18, color: _textMuted),
                          ),
                        )
                      else
                        SizedBox(
                          width: 130,
                          child: saving
                              ? const Center(
                                  child: SizedBox(width: 18, height: 18,
                                      child: CircularProgressIndicator(strokeWidth: 2)))
                              : DropdownButtonFormField<String>(
                                  value: rolle,
                                  isDense: true,
                                  isExpanded: true,
                                  decoration: const InputDecoration(
                                    isDense: true,
                                    contentPadding: EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 6),
                                  ),
                                  items: const [
                                    DropdownMenuItem(value: 'medlem',
                                        child: Text('Medlem', style: TextStyle(fontSize: 13))),
                                    DropdownMenuItem(value: 'træner',
                                        child: Text('Træner', style: TextStyle(fontSize: 13))),
                                    DropdownMenuItem(value: 'admin',
                                        child: Text('Admin', style: TextStyle(fontSize: 13))),
                                  ],
                                  onChanged: (v) {
                                    if (v != null && v != rolle) _setRole(p, v);
                                  },
                                ),
                        ),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String hint;
  final VoidCallback onTap;
  const _ActionTile({
    required this.icon,
    required this.label,
    required this.hint,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _surfaceDark,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _borderSubtle),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 38, height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: _neon.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 20, color: _neon),
            ),
            const SizedBox(height: 12),
            Text(label,
                style: _body(
                    size: 14, weight: FontWeight.w700, spacing: 0.2),
                maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 2),
            Text(hint,
                style: _body(size: 11, color: _textSecondary),
                maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }
}

/// Sektion-piller til dashboardet: Bøder · Medlemmer · Betaling.
class _SectionPills extends StatelessWidget {
  final int active;
  final int pendingCount;
  final ValueChanged<int> onChanged;
  const _SectionPills({
    required this.active,
    required this.pendingCount,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    const labels = ['Bøder', 'Medlemmer', 'Betaling'];
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: _surfaceDark,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _borderSubtle),
      ),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: GestureDetector(
                onTap: () => onChanged(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  height: 38,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: active == i ? _neon : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(labels[i],
                          style: _body(
                              size: 13,
                              weight: FontWeight.w700,
                              color: active == i ? Colors.white : _textSecondary)),
                      if (i == 0 && pendingCount > 0) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: active == 0
                                ? Colors.white.withValues(alpha: 0.25)
                                : _gold,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text('$pendingCount',
                              style: _body(
                                  size: 10,
                                  weight: FontWeight.w800,
                                  color: active == 0 ? Colors.white : _onGold)),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;
  final String actionLabel;
  final VoidCallback onAction;
  const _SectionHeader({
    required this.title,
    required this.icon,
    required this.actionLabel,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 28, color: theme.colorScheme.primary),
        const SizedBox(width: 12),
        Expanded(child: Text(title, style: theme.textTheme.headlineSmall)),
        FilledButton.icon(
          onPressed: onAction,
          icon: const Icon(Icons.add, size: 18),
          label: Text(actionLabel),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Bøde-cards (inline i Dashboard) + GiveFineDialog (Ctrl+K version)
// ─────────────────────────────────────────────────────────────────────────────

class _GiveFineCard extends StatefulWidget {
  final List<Map<String, dynamic>> profiles;
  final List<Map<String, dynamic>> fineTypes;
  final VoidCallback onIssued;
  const _GiveFineCard({
    required this.profiles,
    required this.fineTypes,
    required this.onIssued,
  });
  @override
  State<_GiveFineCard> createState() => _GiveFineCardState();
}

class _GiveFineCardState extends State<_GiveFineCard> {
  String? _userId;
  String? _typeId;
  final _begrundelse = TextEditingController();
  final _spillerCtrl = TextEditingController();
  final _typeCtrl = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _begrundelse.dispose();
    _spillerCtrl.dispose();
    _typeCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_userId == null || _typeId == null) {
      _snack(context, 'Vælg både spiller og bødetype', Colors.orange);
      return;
    }
    setState(() => _saving = true);
    try {
      // titel og belob_oere udelades bevidst — snapshot_fine-trigger fylder dem
      await supabase.from('fines').insert({
        'user_id':      _userId,
        'given_by':     supabase.auth.currentUser!.id,
        'fine_type_id': _typeId,
        'begrundelse':  _begrundelse.text.trim().isEmpty
                          ? null : _begrundelse.text.trim(),
      });
      if (!mounted) return;
      _snack(context, 'Bøde uddelt', Colors.green);
      setState(() {
        _userId = null;
        _typeId = null;
        _begrundelse.clear();
        _spillerCtrl.clear();
        _typeCtrl.clear();
      });
      widget.onIssued();
    } on PostgrestException catch (e) {
      if (mounted) _snack(context, e.message, Colors.red);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    int? selectedAmount;
    for (final t in widget.fineTypes) {
      if (t['id'] == _typeId) {
        selectedAmount = (t['belob_oere'] as num).toInt();
        break;
      }
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.add_circle_outline, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text('Uddel bøde', style: theme.textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 12),
            DropdownMenu<String>(
              controller: _spillerCtrl,
              initialSelection: _userId,
              expandedInsets: EdgeInsets.zero,
              enableFilter: true,
              requestFocusOnTap: true,
              menuHeight: 320,
              label: const Text('Spiller'),
              leadingIcon: const Icon(Icons.person_outline),
              hintText: 'Vælg spiller',
              dropdownMenuEntries: [
                for (final p in widget.profiles)
                  DropdownMenuEntry<String>(
                    value: p['id'] as String,
                    label: p['navn'] as String,
                  ),
              ],
              onSelected: (v) => setState(() => _userId = v),
            ),
            const SizedBox(height: 12),
            DropdownMenu<String>(
              controller: _typeCtrl,
              initialSelection: _typeId,
              expandedInsets: EdgeInsets.zero,
              enableFilter: true,
              requestFocusOnTap: true,
              menuHeight: 320,
              label: const Text('Bødetype'),
              leadingIcon: const Icon(Icons.gavel),
              hintText: 'Vælg bødetype',
              dropdownMenuEntries: [
                for (final t in widget.fineTypes)
                  DropdownMenuEntry<String>(
                    value: t['id'] as String,
                    label: '${t['titel']} · ${_fmtKr((t['belob_oere'] as num).toInt())}',
                  ),
              ],
              onSelected: (v) => setState(() => _typeId = v),
            ),
            if (selectedAmount != null) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: _neon.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _neon.withValues(alpha: 0.4)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.payments_outlined, color: _neon, size: 20),
                    const SizedBox(width: 10),
                    Text('Beløb der uddeles', style: theme.textTheme.bodyMedium),
                    const Spacer(),
                    Text(_fmtKr(selectedAmount),
                        style: theme.textTheme.titleLarge
                            ?.copyWith(color: _neon, fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _begrundelse,
                    decoration: const InputDecoration(
                      labelText: 'Begrundelse (valgfri)',
                      prefixIcon: Icon(Icons.notes_outlined),
                    ),
                    onSubmitted: (_) => _submit(),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: _saving ? null : _submit,
                  icon: _saving
                      ? const SizedBox(width: 16, height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.check),
                  label: const Text('Udfør'),
                ),
              ],
            ),
            if (widget.fineTypes.isEmpty) ...[
              const SizedBox(height: 8),
              Text('Opret en bødetype først (nederst)',
                  style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.orange.shade800,
                      fontStyle: FontStyle.italic)),
            ],
          ],
        ),
      ),
    );
  }
}

class _PendingFinesCard extends StatelessWidget {
  final List<Map<String, dynamic>> fines;
  final Future<void> Function(String fineId) onApprove;
  const _PendingFinesCard({required this.fines, required this.onApprove});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.schedule, color: _gold),
                const SizedBox(width: 8),
                Text('Afventende betalinger',
                    style: theme.textTheme.titleMedium),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                  decoration: BoxDecoration(
                    color: fines.isEmpty
                        ? _surfaceElevated
                        : _gold,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text('${fines.length}',
                      style: _body(
                          size: 12,
                          weight: FontWeight.w800,
                          color: fines.isEmpty ? _textSecondary : _onGold)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (fines.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text('Ingen ubetalte bøder — alt er checket ud 🎉',
                    style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant)),
              )
            else
              ...fines.map((f) {
                final spiller = (f['profiles'] as Map<String, dynamic>?)?['navn']
                    as String? ?? '(ukendt)';
                final titel   = f['titel'] as String;
                final oere    = (f['belob_oere'] as num).toInt();
                final beg     = f['begrundelse'] as String?;
                final created = DateTime.parse(f['created_at'] as String).toLocal();
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('$spiller — $titel',
                                style: theme.textTheme.bodyLarge?.copyWith(
                                    fontWeight: FontWeight.w600)),
                            Text('${_fmtKr(oere)} · ${_fmtDate(created)}'
                                '${beg != null && beg.isNotEmpty ? " · $beg" : ""}',
                                style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant)),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        onPressed: () => onApprove(f['id'] as String),
                        icon: const Icon(Icons.check, size: 16),
                        label: const Text('Godkend'),
                        style: FilledButton.styleFrom(
                          backgroundColor: _success,
                          foregroundColor: _onSuccess,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        ),
                      ),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}

class _CreateFineTypeCard extends StatefulWidget {
  final List<Map<String, dynamic>> existingTypes;
  final VoidCallback onCreated;
  const _CreateFineTypeCard({required this.existingTypes, required this.onCreated});
  @override
  State<_CreateFineTypeCard> createState() => _CreateFineTypeCardState();
}

class _CreateFineTypeCardState extends State<_CreateFineTypeCard> {
  final _titel = TextEditingController();
  final _krCtrl = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _titel.dispose();
    _krCtrl.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final titel = _titel.text.trim();
    final kr = int.tryParse(_krCtrl.text.trim());
    if (titel.isEmpty || kr == null || kr <= 0) {
      _snack(context, 'Indtast titel og beløb i hele kroner', Colors.orange);
      return;
    }
    setState(() => _saving = true);
    try {
      await supabase.from('fine_types').insert({
        'titel':      titel,
        'belob_oere': kr * 100,  // kr → øre
      });
      if (!mounted) return;
      _snack(context, 'Bødetype "$titel" oprettet', Colors.green);
      _titel.clear();
      _krCtrl.clear();
      widget.onCreated();
    } on PostgrestException catch (e) {
      if (mounted) _snack(context, e.message, Colors.red);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.style_outlined, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text('Bødetyper', style: theme.textTheme.titleMedium),
                const Spacer(),
                Text('${widget.existingTypes.length} typer',
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant)),
              ],
            ),
            if (widget.existingTypes.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 6, runSpacing: 6,
                children: widget.existingTypes.map((t) {
                  final aktiv = t['aktiv'] == true;
                  return Chip(
                    label: Text(
                      '${t['titel']} · ${_fmtKr((t['belob_oere'] as num).toInt())}',
                      style: TextStyle(
                          fontSize: 12,
                          color: aktiv ? null : Colors.grey),
                    ),
                    backgroundColor: aktiv
                        ? theme.colorScheme.surfaceContainerHighest
                        : theme.colorScheme.surfaceContainerLow,
                    visualDensity: VisualDensity.compact,
                    side: BorderSide.none,
                  );
                }).toList(),
              ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _titel,
                    textInputAction: TextInputAction.next,
                    onSubmitted: (_) => FocusScope.of(context).nextFocus(),
                    decoration: const InputDecoration(
                      labelText: 'Titel',
                      hintText: 'F.eks. "Hul i battet"',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _krCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _create(),
                    decoration: const InputDecoration(
                      labelText: 'Beløb (kr)',
                      hintText: '100',
                      suffixText: 'kr',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: _saving ? null : _create,
                  icon: _saving
                      ? const SizedBox(width: 16, height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.add),
                  label: const Text('Opret type'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// GiveFineDialog — Ctrl+K lyn-formular (selvloadende)
// ─────────────────────────────────────────────────────────────────────────────

class GiveFineDialog extends StatefulWidget {
  const GiveFineDialog({super.key});
  @override
  State<GiveFineDialog> createState() => _GiveFineDialogState();
}

class _GiveFineDialogState extends State<GiveFineDialog> {
  List<Map<String, dynamic>> _profiles = const [];
  List<Map<String, dynamic>> _fineTypes = const [];
  String? _userId;
  String? _typeId;
  final _begrundelse = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _begrundelse.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        supabase.from('profiles').select('id, navn').order('navn'),
        supabase.from('fine_types')
            .select('id, titel, belob_oere')
            .eq('aktiv', true)
            .order('titel'),
      ]);
      setState(() {
        _profiles  = List<Map<String, dynamic>>.from(results[0] as List);
        _fineTypes = List<Map<String, dynamic>>.from(results[1] as List);
        _loading = false;
      });
    } catch (e) {
      setState(() { _loading = false; _error = e.toString(); });
    }
  }

  Future<void> _submit() async {
    if (_userId == null || _typeId == null) {
      _snack(context, 'Vælg både spiller og bødetype', Colors.orange);
      return;
    }
    setState(() => _saving = true);
    try {
      await supabase.from('fines').insert({
        'user_id':      _userId,
        'given_by':     supabase.auth.currentUser!.id,
        'fine_type_id': _typeId,
        'begrundelse':  _begrundelse.text.trim().isEmpty
                          ? null : _begrundelse.text.trim(),
      });
      if (mounted) Navigator.of(context).pop(true);
    } on PostgrestException catch (e) {
      if (mounted) _snack(context, e.message, Colors.red);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _loading
              ? const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator()))
              : _error != null
                  ? _ErrorView(error: _error!, onRetry: _load)
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.gavel,
                                color: Theme.of(context).colorScheme.primary),
                            const SizedBox(width: 8),
                            Text('Uddel bøde — Lyn-formular',
                                style: Theme.of(context).textTheme.titleLarge),
                          ],
                        ),
                        const SizedBox(height: 24),
                        DropdownButtonFormField<String>(
                          value: _userId,
                          isExpanded: true,
                          autofocus: true,
                          decoration: const InputDecoration(
                            labelText: 'Spiller',
                            prefixIcon: Icon(Icons.person_outline),
                          ),
                          items: _profiles.map((p) => DropdownMenuItem<String>(
                                value: p['id'] as String,
                                child: Text(p['navn'] as String,
                                    overflow: TextOverflow.ellipsis),
                              )).toList(),
                          onChanged: (v) => setState(() => _userId = v),
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          value: _typeId,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Bødetype',
                            prefixIcon: Icon(Icons.gavel),
                          ),
                          items: _fineTypes.map((t) => DropdownMenuItem<String>(
                                value: t['id'] as String,
                                child: Text(
                                  '${t['titel']} (${_fmtKr((t['belob_oere'] as num).toInt())})',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              )).toList(),
                          onChanged: (v) => setState(() => _typeId = v),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _begrundelse,
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => _submit(),
                          decoration: const InputDecoration(
                            labelText: 'Begrundelse (valgfri)',
                            prefixIcon: Icon(Icons.notes_outlined),
                          ),
                        ),
                        const SizedBox(height: 24),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              onPressed: _saving ? null : () => Navigator.of(context).pop(false),
                              child: const Text('Annullér'),
                            ),
                            const SizedBox(width: 8),
                            FilledButton.icon(
                              onPressed: _saving ? null : _submit,
                              icon: _saving
                                  ? const SizedBox(width: 16, height: 16,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2, color: Colors.white))
                                  : const Icon(Icons.check),
                              label: const Text('Udfør'),
                            ),
                          ],
                        ),
                      ],
                    ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SuggestFineTypeDialog — medlem foreslår ny bødetype (afventer admin)
// ─────────────────────────────────────────────────────────────────────────────

class SuggestFineTypeDialog extends StatefulWidget {
  const SuggestFineTypeDialog({super.key});
  @override
  State<SuggestFineTypeDialog> createState() => _SuggestFineTypeDialogState();
}

class _SuggestFineTypeDialogState extends State<SuggestFineTypeDialog> {
  final _ctrl = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final titel = _ctrl.text.trim();
    if (titel.isEmpty) {
      _snack(context, 'Indtast et navn på bøden', Colors.orange);
      return;
    }
    setState(() => _saving = true);
    try {
      // belob_oere = 1 er placeholder (CHECK > 0). aktiv = false markerer som forslag.
      // Admin sætter rigtigt beløb og aktiverer via _PendingSuggestionsCard.
      await supabase.from('fine_types').insert({
        'titel':      titel,
        'belob_oere': 1,
        'aktiv':      false,
      });
      if (!mounted) return;
      _snack(context, 'Forslag sendt til godkendelse', Colors.green);
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
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.lightbulb_outline,
                      color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Text('Foreslå ny bødetype',
                      style: theme.textTheme.titleLarge),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Send et forslag til admin/træneren — de sætter beløbet '
                'og aktiverer bøden, hvis den godkendes.',
                style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _ctrl,
                autofocus: true,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _submit(),
                decoration: const InputDecoration(
                  labelText: 'Navn på bøden',
                  hintText: 'F.eks. "Slog bolden ud af hallen"',
                  prefixIcon: Icon(Icons.gavel_outlined),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _saving ? null : () => Navigator.of(context).pop(false),
                    child: const Text('Annullér'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _saving ? null : _submit,
                    icon: _saving
                        ? const SizedBox(width: 16, height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.send),
                    label: const Text('Send til godkendelse'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _PendingSuggestionsCard (admin) — godkend forslag + sæt sats
// ─────────────────────────────────────────────────────────────────────────────

class _PendingSuggestionsCard extends StatefulWidget {
  final List<Map<String, dynamic>> suggestions;
  final Future<void> Function(String id, int kr) onApprove;
  const _PendingSuggestionsCard({
    required this.suggestions,
    required this.onApprove,
  });
  @override
  State<_PendingSuggestionsCard> createState() => _PendingSuggestionsCardState();
}

class _PendingSuggestionsCardState extends State<_PendingSuggestionsCard> {
  // Hver række har sit eget kr-input. Map fra suggestion.id → controller.
  final Map<String, TextEditingController> _ctrls = {};
  final Set<String> _saving = {};

  @override
  void dispose() {
    for (final c in _ctrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _ctrlFor(String id) =>
      _ctrls.putIfAbsent(id, () => TextEditingController());

  Future<void> _approve(Map<String, dynamic> sug) async {
    final id = sug['id'] as String;
    final ctrl = _ctrlFor(id);
    final kr = int.tryParse(ctrl.text.trim());
    if (kr == null || kr <= 0) {
      _snack(context, 'Indtast en sats i hele kroner', Colors.orange);
      return;
    }
    setState(() => _saving.add(id));
    try {
      await widget.onApprove(id, kr);
      // Efter approve forsvinder rækken fra listen — ryd controller
      _ctrls.remove(id)?.dispose();
    } catch (_) {
      // onApprove viser allerede fejl-snack
    } finally {
      if (mounted) setState(() => _saving.remove(id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.lightbulb_outline, color: Colors.amber.shade700),
                const SizedBox(width: 8),
                Text('Afventende bødeforslag',
                    style: theme.textTheme.titleMedium),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                  decoration: BoxDecoration(
                    color: widget.suggestions.isEmpty
                        ? theme.colorScheme.surfaceContainerHighest
                        : Colors.amber.shade100,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text('${widget.suggestions.length}',
                      style: TextStyle(
                          color: widget.suggestions.isEmpty
                              ? theme.colorScheme.onSurfaceVariant
                              : Colors.amber.shade900,
                          fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (widget.suggestions.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  'Ingen forslag fra medlemmerne lige nu',
                  style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant),
                ),
              )
            else
              ...widget.suggestions.map((s) {
                final id    = s['id']    as String;
                final titel = s['titel'] as String;
                final ctrl  = _ctrlFor(id);
                final isSaving = _saving.contains(id);
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(titel,
                                style: theme.textTheme.bodyLarge?.copyWith(
                                    fontWeight: FontWeight.w600)),
                            Text('Foreslået af medlem · afventer beløb',
                                style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                    fontStyle: FontStyle.italic)),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      SizedBox(
                        width: 130,
                        child: TextField(
                          controller: ctrl,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => _approve(s),
                          decoration: const InputDecoration(
                            labelText: 'Sats',
                            hintText: '50',
                            suffixText: 'kr',
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        onPressed: isSaving ? null : () => _approve(s),
                        icon: isSaving
                            ? const SizedBox(width: 16, height: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.check, size: 16),
                        label: const Text('Godkend & Opret'),
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.green.shade700,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                        ),
                      ),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Create training dialog (Fase 2)
// ─────────────────────────────────────────────────────────────────────────────

class CreateTrainingDialog extends StatefulWidget {
  const CreateTrainingDialog({super.key});
  @override
  State<CreateTrainingDialog> createState() => _CreateTrainingDialogState();
}

class _CreateTrainingDialogState extends State<CreateTrainingDialog> {
  final _formKey  = GlobalKey<FormState>();
  final _titel    = TextEditingController();
  final _beskr    = TextEditingController();
  final _maxCtrl  = TextEditingController();
  final _adresse  = TextEditingController();
  final _weeksCtrl = TextEditingController(text: '8');

  DateTime? _start;
  DateTime? _slut;
  DateTime? _deadline;
  bool _recurring = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _weeksCtrl.addListener(() {
      if (mounted) setState(() {});
    });
  }

  int get _plannedWeeks {
    if (!_recurring) return 1;
    final n = int.tryParse(_weeksCtrl.text.trim()) ?? 0;
    return n.clamp(1, 52);
  }

  @override
  void dispose() {
    _titel.dispose();
    _beskr.dispose();
    _maxCtrl.dispose();
    _adresse.dispose();
    _weeksCtrl.dispose();
    super.dispose();
  }

  Map<String, dynamic> _buildRow({
    required DateTime start,
    required DateTime slut,
    required DateTime deadline,
    required int? maxVal,
    required String adresseVal,
    required String userId,
  }) {
    return {
      'titel':                _titel.text.trim(),
      'beskrivelse':          _beskr.text.trim().isEmpty ? null : _beskr.text.trim(),
      'max_deltagere':        maxVal,
      'start_tid':            start.toUtc().toIso8601String(),
      'slut_tid':             slut.toUtc().toIso8601String(),
      'adresse':              adresseVal,
      'tilmeldings_deadline': deadline.toUtc().toIso8601String(),
      'created_by':           userId,
    };
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_start == null || _slut == null) {
      _snack(context, 'Vælg dato + tid for start og slut', Colors.orange);
      return;
    }
    if (!_slut!.isAfter(_start!)) {
      _snack(context, 'Sluttidspunkt skal være efter start', Colors.orange);
      return;
    }
    // Hvis frist ikke er sat: brug start_tid (= reelt "ingen frist", tilmelding
    // er åben helt til begivenheden begynder)
    final effectiveDeadline = _deadline ?? _start!;
    if (effectiveDeadline.isAfter(_start!)) {
      _snack(context, 'Deadline skal være før start', Colors.orange);
      return;
    }

    // Tom = ubegrænset (null sendes til DB; RPC + UI håndterer det som "∞")
    final maxRaw = _maxCtrl.text.trim();
    final int? maxVal = maxRaw.isEmpty ? null : int.tryParse(maxRaw);
    final adresseRaw = _adresse.text.trim();
    final adresseVal = adresseRaw.isEmpty ? _addressUnspecified : adresseRaw;
    final userId = supabase.auth.currentUser!.id;
    final weeks = _plannedWeeks;

    final rows = List<Map<String, dynamic>>.generate(weeks, (i) {
      final delta = Duration(days: 7 * i);
      return _buildRow(
        start:    _start!.add(delta),
        slut:     _slut!.add(delta),
        deadline: effectiveDeadline.add(delta),
        maxVal:   maxVal,
        adresseVal: adresseVal,
        userId:   userId,
      );
    });

    setState(() => _saving = true);
    try {
      await supabase.from('trainings').insert(rows);
      if (!mounted) return;
      if (weeks > 1) {
        _snack(context, '$weeks ugentlige begivenheder oprettet', Colors.green);
      }
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
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Opret begivenhed', style: theme.textTheme.titleLarge),
                const SizedBox(height: 24),
                TextFormField(
                  controller: _titel,
                  autofocus: true,
                  textInputAction: TextInputAction.next,
                  onFieldSubmitted: (_) => FocusScope.of(context).nextFocus(),
                  decoration: const InputDecoration(labelText: 'Titel'),
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
                    helperText: 'Valgfri — Shift+Enter for ny linje',
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _maxCtrl,
                        textInputAction: TextInputAction.next,
                        onFieldSubmitted: (_) => FocusScope.of(context).nextFocus(),
                        decoration: const InputDecoration(
                          labelText: 'Max deltagere',
                          helperText: 'Tom = ubegrænset',
                          hintText: '∞',
                        ),
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: TextFormField(
                        controller: _adresse,
                        textInputAction: TextInputAction.next,
                        onFieldSubmitted: (_) => FocusScope.of(context).nextFocus(),
                        decoration: const InputDecoration(
                          labelText: 'Adresse',
                          helperText: 'Valgfri',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                _QuickDateTimeField(
                  label: 'Start',
                  value: _start,
                  onChanged: (v) => setState(() => _start = v),
                ),
                const SizedBox(height: 12),
                _QuickDateTimeField(
                  label: 'Slut',
                  value: _slut,
                  fallbackDate: _start,
                  onChanged: (v) => setState(() => _slut = v),
                ),
                const SizedBox(height: 12),
                _QuickDateTimeField(
                  label: 'Tilmeldingsfrist (valgfri)',
                  value: _deadline,
                  fallbackDate: _start,
                  onChanged: (v) => setState(() => _deadline = v),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 4, left: 4),
                  child: Text(
                    _deadline == null
                        ? 'Tom = åben til begivenheden begynder'
                        : ' ',
                    style: const TextStyle(color: _textMuted, fontSize: 11),
                  ),
                ),
                const SizedBox(height: 20),
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: theme.dividerColor),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    children: [
                      SwitchListTile(
                        value: _recurring,
                        onChanged: (v) => setState(() => _recurring = v),
                        secondary: const Icon(Icons.event_repeat),
                        title: const Text('Gentag ugentligt'),
                        subtitle: const Text('Opretter en serie af begivenheder på samme ugedag'),
                      ),
                      if (_recurring) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                          child: TextFormField(
                            controller: _weeksCtrl,
                            textInputAction: TextInputAction.done,
                            onFieldSubmitted: (_) => _save(),
                            decoration: const InputDecoration(
                              labelText: 'Antal uger frem',
                              hintText: '8',
                              prefixIcon: Icon(Icons.repeat),
                            ),
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              LengthLimitingTextInputFormatter(2),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          child: Row(
                            children: [
                              Icon(Icons.info_outline, size: 16,
                                  color: theme.colorScheme.primary),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  _start == null
                                      ? 'Vælg starttidspunkt for at se serie'
                                      : 'Opretter $_plannedWeeks begivenheder — '
                                        'fra ${_fmtDate(_start!)} til '
                                        '${_fmtDate(_start!.add(Duration(days: 7 * (_plannedWeeks - 1))))}',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.primary,
                                      fontWeight: FontWeight.w600),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: _saving ? null : () => Navigator.of(context).pop(false),
                      child: const Text('Annullér'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: _saving ? null : _save,
                      child: _saving
                          ? const SizedBox(width: 18, height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : Text(_recurring ? 'Opret serie' : 'Opret'),
                    ),
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
// Create poll dialog (Fase 3)
// ─────────────────────────────────────────────────────────────────────────────

