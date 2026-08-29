// Auto-split (del af biblioteket padel_app)
// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
part of '../main.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  Map<String, dynamic>? _profile;
  bool   _loading = true;
  bool   _isCaptain = false;   // kaptajn på mindst ét hold → må oprette + styre egne hold
  String? _error;
  int    _selectedIndex = 0;

  final GlobalKey<DashboardTabState> _dashboardKey = GlobalKey<DashboardTabState>();
  final GlobalKey<BodekasseTabState> _bodekasseKey = GlobalKey<BodekasseTabState>();
  bool _paletteOpen = false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
    // Identificér brugeren stille over for OneSignal (sætter external_id, INGEN
    // prompt) så vi kan sende målrettet push. Selve tilladelses-spørgsmålet
    // kommer fra OneSignals slide-prompt eller knappen i Profil — vi auto-
    // spørger ikke her, så ingen risikerer at blive spurgt flere gange.
    final uid = supabase.auth.currentUser?.id;
    if (uid != null) unawaited(NotificationService.identify(uid));
    // Varm MobilePay Box-config så betalingsknappen i Bødekassen er klar.
    unawaited(ClubConfig.fetchMobilePayBox());
    HardwareKeyboard.instance.addHandler(_handleGlobalKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleGlobalKey);
    super.dispose();
  }

  bool _handleGlobalKey(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    if (event.logicalKey != LogicalKeyboardKey.keyK) return false;
    final keys = HardwareKeyboard.instance.logicalKeysPressed;
    final hasMod = keys.contains(LogicalKeyboardKey.controlLeft) ||
                   keys.contains(LogicalKeyboardKey.controlRight) ||
                   keys.contains(LogicalKeyboardKey.metaLeft)    ||
                   keys.contains(LogicalKeyboardKey.metaRight);
    if (!hasMod) return false;
    _openPalette();
    return true;
  }

  Future<void> _loadProfile() async {
    final userId = supabase.auth.currentUser!.id;
    // Instant UI: vis cachet profil med det samme — ingen tom loading-skærm.
    final cached = CacheService.getMap('profile_$userId');
    if (cached != null) {
      _profile = cached;
      _loading = false;
    } else {
      _loading = true;
      _error = null;
    }
    if (mounted) setState(() {});
    // Baggrunds-tjek mod Supabase efter friske data.
    try {
      final row = await supabase
          .from('profiles')
          .select('id, navn, email, rolle, makker_prio_1, makker_prio_2, spiller_side')
          .eq('id', userId)
          .single();
      CacheService.put('profile_$userId', row);
      // Kaptajn-status (fra group_members) — påvirker rettigheder.
      bool captain = false;
      try {
        final gm = await supabase
            .from('group_members')
            .select('is_captain')
            .eq('user_id', userId)
            .eq('is_captain', true)
            .limit(1);
        captain = (gm as List).isNotEmpty;
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _profile = row;
        _isCaptain = captain;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      // Behold cache hvis vi har den (offline-venligt); ellers vis fejl.
      if (_profile == null) setState(() { _loading = false; _error = e.toString(); });
    }
  }

  bool get _isAdmin => _profile?['rolle'] == 'admin';
  bool get _isStaff => _profile?['rolle'] == 'admin' || _profile?['rolle'] == 'træner';
  // Kaptajn eller staff må oprette begivenheder og afstemninger.
  bool get _canCreate => _isStaff || _isCaptain;

  // Indekser: 0=Oversigt, 1=Bødekassen, 2=Afstemninger, 3=Profil, 4=Dashboard
  static const _tabOversigt    = 0;
  static const _tabBoede       = 1;
  static const _tabAfstemning  = 2;
  static const _tabProfil      = 3;
  static const _tabDashboard   = 4;

  final GlobalKey<_OversigtTabState> _oversigtKey = GlobalKey<_OversigtTabState>();
  final GlobalKey<_AfstemningerTabState> _afstemningerKey =
      GlobalKey<_AfstemningerTabState>();

  Future<void> _logout() async => supabase.auth.signOut();

  void _gotoTab(int index) => setState(() => _selectedIndex = index);

  Future<void> _openCreateTraining() async {
    if (!_isStaff) return;
    _gotoTab(_tabDashboard);
    await Future<void>.delayed(const Duration(milliseconds: 40));
    if (!mounted) return;
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const CreateTrainingDialog(),
    );
    if (created == true) {
      _oversigtKey.currentState?.reload();
    }
  }

  Future<void> _openCreatePoll() async {
    if (!_isStaff) return;
    _gotoTab(_tabDashboard);
    await Future<void>.delayed(const Duration(milliseconds: 40));
    if (!mounted) return;
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const CreatePollDialog(),
    );
    if (created == true) {
      _oversigtKey.currentState?.reload();
    }
  }

  Future<void> _openGiveFineDialog() async {
    if (!_isAdmin) return;
    _gotoTab(_tabBoede);
    await Future<void>.delayed(const Duration(milliseconds: 40));
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => const GiveFineDialog(),
    );
    if (ok == true) {
      _bodekasseKey.currentState?.reload();
      _dashboardKey.currentState?.reloadFines();
    }
  }

  // ─── Hurtig-opret fra "+"-knappen på Oversigten — skifter IKKE fane ─────────
  Future<void> _quickCreateTraining() async {
    if (!_canCreate) return;
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const CreateTrainingDialog(),
    );
    if (created == true) {
      _oversigtKey.currentState?.reload();
    }
  }

  Future<void> _quickCreatePoll() async {
    if (!_canCreate) return;
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const CreatePollDialog(),
    );
    if (created == true) {
      _oversigtKey.currentState?.reload();
      _afstemningerKey.currentState?.reload();
    }
  }

  Future<void> _quickGiveFine() async {
    if (!_isStaff && !_isCaptain) return;
    final ok = await showDialog<bool>(
      context: context,
      // Staff (admin/træner) ser alle spillere; kaptajn kun egne hold.
      builder: (_) => GiveFineDialog(isFullAdmin: _isStaff),
    );
    if (ok == true) {
      _bodekasseKey.currentState?.reload();
      _dashboardKey.currentState?.reloadFines();
    }
  }

  Future<void> _openSuggestFineTypeDialog() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => const SuggestFineTypeDialog(),
    );
    if (ok == true) {
      // Admin ser forslaget i deres dashboard
      _dashboardKey.currentState?.reloadFines();
    }
  }

  // ─── Registrer nye Ctrl+K-kommandoer her ────────────────────────────────
  List<AppCommand> _buildCommands() => [
    AppCommand(
      label: 'Gå til Oversigt',
      hint:  'Hub med kommende begivenheder og åbne afstemninger',
      icon:  Icons.bolt,
      keywords: ['oversigt', 'hub', 'hjem', 'home', 'feed', 'begivenheder'],
      run: () => _gotoTab(_tabOversigt),
    ),
    AppCommand(
      label: 'Gå til Bødekassen',
      icon:  Icons.gavel,
      keywords: ['bøde', 'bødekasse', 'fine', 'kasse', 'leaderboard', 'highscore'],
      run: () => _gotoTab(_tabBoede),
    ),
    AppCommand(
      label: 'Gå til Afstemninger',
      icon:  Icons.how_to_vote,
      keywords: ['afstemning', 'afstemninger', 'poll', 'stem', 'vote'],
      run: () => _gotoTab(_tabAfstemning),
    ),
    AppCommand(
      label: 'Gå til Min profil',
      icon:  Icons.person,
      keywords: ['profil', 'mig', 'makker', 'profile'],
      run: () => _gotoTab(_tabProfil),
    ),
    if (_isStaff)
      AppCommand(
        label: 'Gå til Træner Dashboard',
        icon: Icons.dashboard,
        keywords: ['dashboard', 'admin', 'træner', 'staff'],
        run: () => _gotoTab(_tabDashboard),
      ),
    if (_isStaff)
      AppCommand(
        label: 'Se Synergi-rapporter',
        hint:  'Åbner dashboardet med alle poll-rapporter',
        icon:  Icons.insights,
        keywords: ['synergi', 'kemi', 'rapport', 'holdbygger', 'par'],
        run: () => _gotoTab(_tabDashboard),
      ),
    if (_isStaff)
      AppCommand(
        label: 'Opret begivenhed',
        hint:  'Træning, kamp eller event',
        icon:  Icons.add_circle_outline,
        keywords: ['opret', 'ny', 'create', 'kamp', 'nyt', 'træning', 'begivenhed', 'event'],
        run: _openCreateTraining,
      ),
    if (_isStaff)
      AppCommand(
        label: 'Opret afstemning',
        hint:  'Åbner poll-formularen',
        icon:  Icons.poll_outlined,
        keywords: ['opret', 'afstemning', 'poll', 'ny', 'kemi'],
        run: _openCreatePoll,
      ),
    if (_isAdmin) // kun rigtig admin, ikke træner
      AppCommand(
        label: 'Uddel lyn-bøde',
        hint:  'Vælg spiller + bødetype + udfør',
        icon:  Icons.gavel,
        keywords: ['bøde', 'fine', 'straf', 'uddel', 'lyn'],
        run: _openGiveFineDialog,
      ),
    AppCommand(
      label: 'Foreslå ny bødetype',
      hint:  'Send forslag til admin-godkendelse',
      icon:  Icons.lightbulb_outline,
      keywords: ['foreslå', 'forslag', 'bøde', 'ide', 'idé', 'suggest'],
      run: _openSuggestFineTypeDialog,
    ),
    AppCommand(
      label: 'Log ud',
      icon: Icons.logout,
      keywords: ['logout', 'sign out', 'farvel'],
      run: _logout,
    ),
  ];

  Future<void> _openPalette() async {
    if (_paletteOpen) return;
    _paletteOpen = true;
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black54,
      builder: (_) => CommandPalette(commands: _buildCommands()),
    );
    _paletteOpen = false;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_error != null) {
      return Scaffold(body: _ErrorView(error: _error!, onRetry: _loadProfile));
    }

    final navItems = <({IconData icon, IconData selectedIcon, String label})>[
      (icon: Icons.bolt_outlined, selectedIcon: Icons.bolt, label: 'Oversigt'),
      (icon: Icons.gavel_outlined, selectedIcon: Icons.gavel, label: 'Bødekassen'),
      (icon: Icons.how_to_vote_outlined, selectedIcon: Icons.how_to_vote, label: 'Afstemninger'),
      (icon: Icons.person_outline, selectedIcon: Icons.person, label: 'Min profil'),
      if (_isStaff)
        (icon: Icons.settings_outlined, selectedIcon: Icons.settings, label: 'Admin'),
    ];

    final pages = <Widget>[
      OversigtTab(
          key: _oversigtKey, isAdmin: _isStaff, isFullAdmin: _isAdmin),
      BodekasseTab(
        key: _bodekasseKey,
        isAdmin: _isAdmin,
        currentUserId: _profile!['id'] as String,
      ),
      AfstemningerTab(key: _afstemningerKey, isStaff: _isStaff, isAdmin: _isAdmin),
      ProfileTab(profile: _profile!, onProfileUpdated: _loadProfile),
      if (_isStaff) DashboardTab(key: _dashboardKey, isFullAdmin: _isAdmin),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('DE TALENTLØSE', style: TextStyle(letterSpacing: 2)),
              SizedBox(width: 8),
              Text('HJØRRING',
                  style: TextStyle(color: _neon, letterSpacing: 3)),
            ],
          ),
        ),
        actions: [
          // Tragt = hold-filter (som prototypens header) på Oversigt, Bøder
          // og Afstemninger.
          if (_selectedIndex.clamp(0, pages.length - 1) == _tabOversigt ||
              _selectedIndex.clamp(0, pages.length - 1) == _tabBoede ||
              _selectedIndex.clamp(0, pages.length - 1) == _tabAfstemning)
            IconButton(
              onPressed: () {
                final idx = _selectedIndex.clamp(0, pages.length - 1);
                if (idx == _tabOversigt) {
                  _oversigtKey.currentState?.showHoldFilterSheet();
                } else if (idx == _tabBoede) {
                  _bodekasseKey.currentState?.showHoldFilterSheet();
                } else {
                  _afstemningerKey.currentState?.showHoldFilterSheet();
                }
              },
              icon: const Icon(Icons.filter_list, color: _textPrimary),
              tooltip: 'Filtrér på hold',
            ),
          _NotificationsBell(
            isStaff: _isStaff,
            onGotoTab: _gotoTab,
          ),
          // Ctrl+K kun på brede skærme (desktop/web) — skjult på mobil
          if (MediaQuery.of(context).size.width >= 700) ...[
            TextButton.icon(
              onPressed: _openPalette,
              icon: const Icon(Icons.search, size: 16),
              label: const Text('Ctrl+K'),
              style: TextButton.styleFrom(
                foregroundColor: _textSecondary,
                backgroundColor: _surfaceElevated,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
            ),
            const SizedBox(width: 8),
          ],
          IconButton(
            onPressed: _logout,
            icon: const Icon(Icons.logout, color: _textPrimary),
            tooltip: 'Log ud',
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: () {
        final selIdx = _selectedIndex.clamp(0, pages.length - 1);
        final wide = MediaQuery.of(context).size.width >= 700;
        final content = IndexedStack(index: selIdx, children: pages);
        if (!wide) return content;
        return Row(
          children: [
            NavigationRail(
              extended: MediaQuery.of(context).size.width > 900,
              selectedIndex: selIdx,
              onDestinationSelected: _gotoTab,
              destinations: [
                for (final n in navItems)
                  NavigationRailDestination(
                    icon: Icon(n.icon),
                    selectedIcon: Icon(n.selectedIcon),
                    label: Text(n.label),
                  ),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(child: content),
          ],
        );
      }(),
      // Kontekstuel hurtig-opret pr. fane:
      //  Oversigt → begivenhed/afstemning · Afstemninger → ny afstemning ·
      //  Bødekasse → uddel bøde (kun admin).
      floatingActionButton: () {
        final idx = _selectedIndex.clamp(0, pages.length - 1);
        if ((idx == _tabOversigt || idx == _tabDashboard) && _canCreate) {
          return _CreateSpeedDial(
            isAdmin: _isAdmin,
            onNewTraining: _quickCreateTraining,
            onNewPoll: _quickCreatePoll,
            onNewFine: _quickGiveFine,
          );
        }
        if (idx == _tabAfstemning && _canCreate) {
          return FloatingActionButton(
            heroTag: 'fab_poll',
            onPressed: _quickCreatePoll,
            child: const Icon(Icons.add),
          );
        }
        if (idx == _tabBoede && (_isStaff || _isCaptain)) {
          return FloatingActionButton.extended(
            heroTag: 'fab_fine',
            onPressed: _quickGiveFine,
            icon: const Icon(Icons.gavel),
            label: const Text('Uddel bøde'),
          );
        }
        return null;
      }(),
      bottomNavigationBar: MediaQuery.of(context).size.width >= 700
          ? null
          // Baggrund dækker helt ned i bunden; SafeArea skubber selve nav-baren
          // op over iPhonens home-indicator, så labels ikke skæres af.
          : Container(
              color: _bgBlack,
              child: SafeArea(
                top: false,
                // Tving iPhonens målte safe-area ind som gulv, da Flutter web
                // på iOS ofte ikke selv læser env(safe-area-inset-bottom).
                minimum: EdgeInsets.only(bottom: platformSafeAreaBottom()),
                child: NavigationBar(
                  selectedIndex: _selectedIndex.clamp(0, pages.length - 1),
                  onDestinationSelected: _gotoTab,
                  destinations: [
                    for (final n in navItems)
                      NavigationDestination(
                        icon: Icon(n.icon),
                        selectedIcon: Icon(n.selectedIcon),
                        label: n.label,
                      ),
                  ],
                ),
              ),
            ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Command palette (Ctrl+K)
// ─────────────────────────────────────────────────────────────────────────────

class CommandPalette extends StatefulWidget {
  final List<AppCommand> commands;
  const CommandPalette({super.key, required this.commands});
  @override
  State<CommandPalette> createState() => _CommandPaletteState();
}

class _CommandPaletteState extends State<CommandPalette> {
  String _query = '';
  int    _selected = 0;
  final  _searchCtrl = TextEditingController();
  final  _focusNode  = FocusNode();

  @override
  void dispose() {
    _searchCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  List<AppCommand> get _filtered =>
      widget.commands.where((c) => c.matches(_query)).toList();

  void _execute(AppCommand cmd) {
    Navigator.of(context).pop();
    Future.microtask(() => cmd.run());
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final filtered = _filtered;
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      if (filtered.isEmpty) return KeyEventResult.handled;
      setState(() => _selected = (_selected + 1) % filtered.length);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      if (filtered.isEmpty) return KeyEventResult.handled;
      setState(() => _selected = (_selected - 1 + filtered.length) % filtered.length);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      if (filtered.isNotEmpty) _execute(filtered[_selected.clamp(0, filtered.length - 1)]);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      Navigator.of(context).pop();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filtered = _filtered;
    return Dialog(
      alignment: Alignment.topCenter,
      insetPadding: const EdgeInsets.only(top: 96, left: 24, right: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Focus(
          focusNode: _focusNode,
          onKeyEvent: _onKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                child: TextField(
                  autofocus: true,
                  controller: _searchCtrl,
                  decoration: const InputDecoration(
                    hintText: 'Skriv en kommando…',
                    prefixIcon: Icon(Icons.search),
                    border: InputBorder.none,
                    filled: false,
                  ),
                  onChanged: (v) => setState(() {
                    _query = v;
                    _selected = 0;
                  }),
                ),
              ),
              const Divider(height: 1),
              if (filtered.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('Ingen kommandoer matcher',
                      style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant)),
                )
              else
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    itemCount: filtered.length,
                    itemBuilder: (_, i) {
                      final cmd = filtered[i];
                      final isSel = i == _selected.clamp(0, filtered.length - 1);
                      return Container(
                        color: isSel ? theme.colorScheme.primaryContainer : null,
                        child: ListTile(
                          leading: Icon(cmd.icon,
                              color: isSel ? theme.colorScheme.onPrimaryContainer : null),
                          title: Text(cmd.label),
                          subtitle: cmd.hint == null ? null : Text(cmd.hint!),
                          trailing: isSel
                              ? const Icon(Icons.keyboard_return, size: 18)
                              : null,
                          onTap: () => _execute(cmd),
                        ),
                      );
                    },
                  ),
                ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  children: [
                    _Kbd(label: '↑↓'),
                    const SizedBox(width: 4),
                    Text('navigér', style: theme.textTheme.bodySmall),
                    const SizedBox(width: 12),
                    _Kbd(label: 'Enter'),
                    const SizedBox(width: 4),
                    Text('udfør', style: theme.textTheme.bodySmall),
                    const SizedBox(width: 12),
                    _Kbd(label: 'Esc'),
                    const SizedBox(width: 4),
                    Text('luk', style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Kbd extends StatelessWidget {
  final String label;
  const _Kbd({required this.label});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label, style: const TextStyle(
        fontSize: 11, fontFamily: 'monospace', fontWeight: FontWeight.w600,
      )),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Notifikations-klokke — pålidelig in-app inbox (læser notifications-tabellen).
// Ulæst-tælling via lokal "sidst set"-tid, så det virker uden backend-ændringer.
// ─────────────────────────────────────────────────────────────────────────────
class _NotificationsBell extends StatefulWidget {
  final bool isStaff;
  final void Function(int tab) onGotoTab;
  const _NotificationsBell({required this.isStaff, required this.onGotoTab});
  @override
  State<_NotificationsBell> createState() => _NotificationsBellState();
}

class _NotificationsBellState extends State<_NotificationsBell> {
  List<Map<String, dynamic>> _items = const [];
  int _unread = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Læst-status ligger på rækken (`laest_at`), ikke i browserens localStorage
  /// som før — så den er ens på alle enheder og overlever at lagringen ryddes.
  Future<void> _load() async {
    try {
      final uid = supabase.auth.currentUser?.id;
      if (uid == null) return;
      final rows = await supabase
          .from('notifications')
          .select('id, kind, titel, body, created_at, laest_at')
          .eq('recipient_id', uid)
          .order('created_at', ascending: false)
          .limit(50);
      final list = List<Map<String, dynamic>>.from(rows as List);
      final unread = list.where((r) => r['laest_at'] == null).length;
      if (mounted) setState(() { _items = list; _unread = unread; });
    } catch (_) {
      // Ingen adgang/tom — klokken viser bare 0.
    }
  }

  bool _erUlaest(Map<String, dynamic> n) => n['laest_at'] == null;

  /// Åbn det beskeden handler om. Uden det er en notifikation kun en
  /// oplysning man selv skal lede videre ud fra.
  Future<void> _aabn(Map<String, dynamic> n) async {
    final data = n['data'];
    final map = data is Map ? Map<String, dynamic>.from(data) : const {};
    final trainingId = map['training_id'] as String?;
    final pollId = map['poll_id'] as String?;
    final fineTypeId = map['fine_type_id'] as String?;

    Navigator.of(context).pop(); // luk klokke-panelet først

    try {
      if (trainingId != null) {
        final row = await supabase
            .from('trainings')
            .select('id, titel, beskrivelse, max_deltagere, start_tid, slut_tid, '
                'adresse, tilmeldings_deadline, group_id, group_ids, synlig_fra, '
                'created_by, series_id')
            .eq('id', trainingId)
            .maybeSingle();
        if (row == null) {
          if (mounted) _snack(context, 'Begivenheden findes ikke længere', _gold);
          return;
        }
        if (!mounted) return;
        await Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => EventDetailScreen(
              training: Map<String, dynamic>.from(row),
              isStaff: widget.isStaff),
        ));
      } else if (pollId != null) {
        final row = await supabase
            .from('polls')
            .select('id, titel, beskrivelse, lukket_at, created_at, group_id, '
                'group_ids, created_by, type, allow_multiple')
            .eq('id', pollId)
            .maybeSingle();
        if (row == null) {
          if (mounted) _snack(context, 'Afstemningen findes ikke længere', _gold);
          return;
        }
        if (!mounted) return;
        await Navigator.of(context).push(MaterialPageRoute(
          builder: (_) =>
              PollDetailScreen(poll: Map<String, dynamic>.from(row)),
        ));
      } else if (fineTypeId != null) {
        // Bødeforslag godkendes i admin-sektionen.
        widget.onGotoTab(4);
      }
    } catch (e) {
      if (mounted) _snack(context, 'Kunne ikke åbne: $e', _danger);
    }
  }

  /// Har beskeden et sted at hoppe hen?
  bool _kanAabnes(Map<String, dynamic> n) {
    final data = n['data'];
    if (data is! Map) return false;
    if (n['data']['fine_type_id'] != null) return widget.isStaff;
    return data['training_id'] != null || data['poll_id'] != null;
  }

  Future<void> _markerLaest(List<String> ids, void Function() refreshSheet) async {
    if (ids.isEmpty) return;
    final nu = DateTime.now().toUtc().toIso8601String();
    // Opdatér med det samme; serveren er alligevel autoritativ ved næste load.
    setState(() {
      _items = [
        for (final n in _items)
          ids.contains(n['id']) && n['laest_at'] == null
              ? {...n, 'laest_at': nu}
              : n
      ];
      _unread = _items.where(_erUlaest).length;
    });
    refreshSheet();
    try {
      await supabase
          .from('notifications')
          .update({'laest_at': nu})
          .inFilter('id', ids);
    } catch (_) {
      // Slår det fejl, kommer den rigtige tilstand tilbage ved næste _load().
    }
  }

  IconData _iconFor(String? kind) {
    switch (kind) {
      case 'training_oprettet': return Icons.event;
      case 'training_afmeldt': return Icons.person_off_outlined;
      case 'training_rykker':  return Icons.alarm;
      case 'training_tilmeldt_af_anden': return Icons.person_add_alt_1;
      case 'training_aendret': return Icons.edit_calendar;
      case 'boedeforslag': return Icons.lightbulb_outline;
      case 'poll_oprettet':    return Icons.how_to_vote;
      case 'poll_rykker':      return Icons.how_to_vote_outlined;
      case 'boede':            return Icons.gavel;
      default:                 return Icons.notifications_outlined;
    }
  }

  Future<void> _open() async {
    // Åbner man panelet, nulstilles tælleren IKKE længere automatisk — så kan
    // man nå at se hvad der er nyt. Man markerer selv, enkeltvis eller samlet.
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => StatefulBuilder(builder: (ctx, setSheet) {
      return Padding(
        padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top + 40),
        child: Container(
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
                margin: const EdgeInsets.only(top: 10, bottom: 8),
                decoration: BoxDecoration(
                    color: _borderSubtle, borderRadius: BorderRadius.circular(999)),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 12, 8),
                child: Row(children: [
                  Text('NOTIFIKATIONER',
                      style: _cond(size: 20, weight: FontWeight.w800)),
                  const Spacer(),
                  // Vises altid når der er beskeder — også når alt er læst.
                  // Ellers ligner det at funktionen ikke findes.
                  if (_items.isNotEmpty)
                    TextButton.icon(
                      onPressed: _unread == 0
                          ? null
                          : () => _markerLaest(
                              [for (final n in _items)
                                if (_erUlaest(n)) n['id'] as String],
                              () => setSheet(() {})),
                      icon: const Icon(Icons.done_all, size: 17),
                      label: Text(_unread == 0
                          ? 'Alt er læst'
                          : 'Markér alle som læst ($_unread)'),
                      style: TextButton.styleFrom(
                        foregroundColor: _neon,
                        disabledForegroundColor: _textMuted,
                        textStyle: _body(size: 12.5, weight: FontWeight.w600),
                      ),
                    ),
                ]),
              ),
              const Divider(height: 1, color: _borderSubtle),
              if (_items.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(40),
                  child: Text('Ingen notifikationer endnu',
                      style: TextStyle(color: _textMuted)),
                )
              else
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: _items.length,
                    separatorBuilder: (_, __) => const Divider(
                        height: 1, color: _borderSubtle, indent: 68),
                    itemBuilder: (_, i) {
                      final n = _items[i];
                      final ts = DateTime.tryParse(n['created_at'] as String? ?? '');
                      final ulaest = _erUlaest(n);
                      return ListTile(
                        // Ulæste står fremhævet med accent-baggrund og prik.
                        tileColor: ulaest
                            ? _neon.withValues(alpha: 0.07)
                            : Colors.transparent,
                        // Tryk: markér som læst OG hop derhen beskeden
                        // handler om. Er der intet at åbne, markeres den bare.
                        onTap: () {
                          if (ulaest) {
                            _markerLaest(
                                [n['id'] as String], () => setSheet(() {}));
                          }
                          if (_kanAabnes(n)) _aabn(n);
                        },
                        leading: Container(
                          width: 40, height: 40,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                              color: _neon.withValues(alpha: 0.16),
                              shape: BoxShape.circle),
                          child: Icon(_iconFor(n['kind'] as String?),
                              size: 20, color: _neon),
                        ),
                        title: Text(n['titel'] as String? ?? '',
                            style: _body(
                                size: 14,
                                weight:
                                    ulaest ? FontWeight.w700 : FontWeight.w500,
                                color: ulaest ? _textPrimary : _textSecondary)),
                        subtitle: Text(n['body'] as String? ?? '',
                            style: _body(size: 12, color: _textSecondary)),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (ts != null)
                              Text(_fmtRelative(ts).replaceFirst('· ', ''),
                                  style: _body(size: 11, color: _textMuted)),
                            if (ulaest) ...[
                              const SizedBox(width: 8),
                              Container(
                                width: 8, height: 8,
                                decoration: const BoxDecoration(
                                    color: _neon, shape: BoxShape.circle),
                              ),
                            ],
                            if (_kanAabnes(n))
                              const Padding(
                                padding: EdgeInsets.only(left: 4),
                                child: Icon(Icons.chevron_right,
                                    size: 16, color: _textMuted),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              if (_unread > 0)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
                  child: Text('Tryk på en besked for at åbne den og markere '
                      'den som læst.',
                      style: _body(size: 11.5, color: _textMuted)),
                ),
              const SafeArea(top: false, child: SizedBox(height: 8)),
            ],
          ),
        ),
      );
      }),
    );
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        IconButton(
          onPressed: _open,
          icon: const Icon(Icons.notifications_outlined, color: _textPrimary),
          tooltip: 'Notifikationer',
        ),
        if (_unread > 0)
          Positioned(
            top: 8, right: 6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              constraints: const BoxConstraints(minWidth: 16),
              decoration: BoxDecoration(
                  color: _danger, borderRadius: BorderRadius.circular(999)),
              child: Text(_unread > 9 ? '9+' : '$_unread',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w800)),
            ),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Hurtig-opret FAB — åbner et action-sheet (bundsheet). Hele rækken er trykbar.
// ─────────────────────────────────────────────────────────────────────────────
class _CreateSpeedDial extends StatefulWidget {
  final bool isAdmin; // fuld admin → må uddele lyn-bøde
  final VoidCallback onNewTraining;
  final VoidCallback onNewPoll;
  final VoidCallback onNewFine;
  const _CreateSpeedDial({
    required this.isAdmin,
    required this.onNewTraining,
    required this.onNewPoll,
    required this.onNewFine,
  });
  @override
  State<_CreateSpeedDial> createState() => _CreateSpeedDialState();
}

class _CreateSpeedDialState extends State<_CreateSpeedDial> {
  bool _open = false;

  Future<void> _openSheet() async {
    setState(() => _open = true);
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _CreateSheet(
        isAdmin: widget.isAdmin,
        onNewTraining: widget.onNewTraining,
        onNewPoll: widget.onNewPoll,
        onNewFine: widget.onNewFine,
      ),
    );
    if (mounted) setState(() => _open = false);
  }

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton(
      heroTag: 'create_fab',
      onPressed: _openSheet,
      child: AnimatedRotation(
        turns: _open ? 0.125 : 0,
        duration: const Duration(milliseconds: 200),
        child: const Icon(Icons.add),
      ),
    );
  }
}

/// Bundsheet med opret-handlinger — hele rækken (ikon + tekst + chevron) er ét
/// trykbart mål.
class _CreateSheet extends StatelessWidget {
  final bool isAdmin;
  final VoidCallback onNewTraining;
  final VoidCallback onNewPoll;
  final VoidCallback onNewFine;
  const _CreateSheet({
    required this.isAdmin,
    required this.onNewTraining,
    required this.onNewPoll,
    required this.onNewFine,
  });

  Widget _row(BuildContext context, IconData icon, String titel, String under,
      VoidCallback onTap) {
    return InkWell(
      onTap: () {
        Navigator.of(context).pop();
        onTap();
      },
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 44, height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: _neon.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: _neon, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(titel,
                      style: _cond(size: 17, weight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(under, style: _body(size: 12, color: _textSecondary)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: _textMuted),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
        child: Container(
          decoration: BoxDecoration(
            color: _surfaceDark,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _borderSubtle),
          ),
          padding: const EdgeInsets.all(8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
                child: Row(
                  children: [
                    Text('OPRET NY',
                        style: _body(
                            size: 12,
                            weight: FontWeight.w700,
                            spacing: 1.2,
                            color: _textSecondary)),
                  ],
                ),
              ),
              _row(context, Icons.add_circle_outline, 'Opret begivenhed',
                  'Skriv "kamp" eller "træning" — sorteres selv', onNewTraining),
              const Divider(height: 1, color: _borderSubtle),
              _row(context, Icons.bar_chart, 'Ny afstemning',
                  'Find dato der passer holdet', onNewPoll),
              if (isAdmin) ...[
                const Divider(height: 1, color: _borderSubtle),
                _row(context, Icons.gavel, 'Lyn-bøde',
                    'Spiller + type + udfør', onNewFine),
              ],
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: TextButton.styleFrom(
                    foregroundColor: _textSecondary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text('Annullér'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tab 0: OVERSIGT — unified feed (træninger + polls) med quick actions
// ─────────────────────────────────────────────────────────────────────────────

