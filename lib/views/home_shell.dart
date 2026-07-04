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
          .select('id, navn, email, rolle, makker_prio_1, makker_prio_2')
          .eq('id', userId)
          .single();
      CacheService.put('profile_$userId', row);
      if (!mounted) return;
      setState(() { _profile = row; _loading = false; });
    } catch (e) {
      if (!mounted) return;
      // Behold cache hvis vi har den (offline-venligt); ellers vis fejl.
      if (_profile == null) setState(() { _loading = false; _error = e.toString(); });
    }
  }

  bool get _isAdmin => _profile?['rolle'] == 'admin';
  bool get _isStaff => _profile?['rolle'] == 'admin' || _profile?['rolle'] == 'træner';

  // Indekser: 0=Oversigt, 1=Bødekassen, 2=Afstemninger, 3=Profil, 4=Dashboard
  static const _tabOversigt    = 0;
  static const _tabBoede       = 1;
  static const _tabAfstemning  = 2;
  static const _tabProfil      = 3;
  static const _tabDashboard   = 4;

  final GlobalKey<_OversigtTabState> _oversigtKey = GlobalKey<_OversigtTabState>();

  Future<void> _logout() async => supabase.auth.signOut();

  void _gotoTab(int index) => setState(() => _selectedIndex = index);

  Future<void> _openCreateTraining() async {
    if (!_isStaff) return;
    _gotoTab(_tabDashboard);
    await Future<void>.delayed(const Duration(milliseconds: 40));
    if (!mounted) return;
    final created = await showDialog<bool>(
      context: context,
      builder: (_) => const CreateTrainingDialog(),
    );
    if (created == true) {
      _dashboardKey.currentState?.reloadTrainings();
      _oversigtKey.currentState?.reload();
    }
  }

  Future<void> _openCreatePoll() async {
    if (!_isStaff) return;
    _gotoTab(_tabDashboard);
    await Future<void>.delayed(const Duration(milliseconds: 40));
    if (!mounted) return;
    final created = await showDialog<bool>(
      context: context,
      builder: (_) => const CreatePollDialog(),
    );
    if (created == true) {
      _dashboardKey.currentState?.reloadPolls();
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
    if (!_isStaff) return;
    final created = await showDialog<bool>(
      context: context,
      builder: (_) => const CreateTrainingDialog(),
    );
    if (created == true) {
      _oversigtKey.currentState?.reload();
      _dashboardKey.currentState?.reloadTrainings();
    }
  }

  Future<void> _quickCreatePoll() async {
    if (!_isStaff) return;
    final created = await showDialog<bool>(
      context: context,
      builder: (_) => const CreatePollDialog(),
    );
    if (created == true) {
      _oversigtKey.currentState?.reload();
      _dashboardKey.currentState?.reloadPolls();
    }
  }

  Future<void> _quickGiveFine() async {
    if (!_isAdmin) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => const GiveFineDialog(),
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
        (icon: Icons.dashboard_outlined, selectedIcon: Icons.dashboard, label: 'Dashboard'),
    ];

    final pages = <Widget>[
      OversigtTab(key: _oversigtKey, isAdmin: _isStaff),
      BodekasseTab(
        key: _bodekasseKey,
        isAdmin: _isAdmin,
        currentUserId: _profile!['id'] as String,
      ),
      const AfstemningerTab(),
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
      // Hurtig-opret på Oversigten (kun trænere/admins) — nemt fra telefonen.
      floatingActionButton:
          (_isStaff && _selectedIndex.clamp(0, pages.length - 1) == _tabOversigt)
              ? _CreateSpeedDial(
                  isAdmin: _isAdmin,
                  onNewTraining: _quickCreateTraining,
                  onNewPoll: _quickCreatePoll,
                  onNewFine: _quickGiveFine,
                )
              : null,
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

