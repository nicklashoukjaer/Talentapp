// Auto-split (del af biblioteket padel_app)
// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
part of '../main.dart';

class ProfileTab extends StatefulWidget {
  final Map<String, dynamic> profile;
  final Future<void> Function() onProfileUpdated;
  const ProfileTab({super.key, required this.profile, required this.onProfileUpdated});
  @override
  State<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<ProfileTab> {
  List<Map<String, dynamic>> _otherMembers = const [];
  String? _selectedP1;
  String? _selectedP2;
  bool _loadingMembers = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _selectedP1 = widget.profile['makker_prio_1'] as String?;
    _selectedP2 = widget.profile['makker_prio_2'] as String?;
    _loadMembers();
  }

  Future<void> _loadMembers() async {
    final userId = supabase.auth.currentUser!.id;
    final rows = await supabase
        .from('profiles')
        .select('id, navn')
        .neq('id', userId)
        .order('navn');
    if (!mounted) return;
    setState(() {
      _otherMembers = List<Map<String, dynamic>>.from(rows as List);
      _loadingMembers = false;
    });
  }

  Future<void> _saveMakkere() async {
    if (_selectedP1 != null && _selectedP1 == _selectedP2) {
      _snack(context, 'De to makkere skal være forskellige personer', Colors.orange);
      return;
    }
    setState(() => _saving = true);
    try {
      final userId = supabase.auth.currentUser!.id;
      await supabase.from('profiles').update({
        'makker_prio_1': _selectedP1,
        'makker_prio_2': _selectedP2,
      }).eq('id', userId);
      await widget.onProfileUpdated();
      if (mounted) _snack(context, 'Makkere gemt', Colors.green);
    } on PostgrestException catch (e) {
      if (mounted) _snack(context, e.message, Colors.red);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Column(
              children: [
                _ProfileCard(profile: widget.profile),
                const SizedBox(height: 16),
                if (_loadingMembers)
                  const Center(child: Padding(
                    padding: EdgeInsets.all(32),
                    child: CircularProgressIndicator(),
                  ))
                else
                  _MakkerCard(
                    members: _otherMembers,
                    selectedP1: _selectedP1,
                    selectedP2: _selectedP2,
                    saving: _saving,
                    onChangedP1: (v) => setState(() => _selectedP1 = v),
                    onChangedP2: (v) => setState(() => _selectedP2 = v),
                    onSave: _saveMakkere,
                  ),
                const SizedBox(height: 16),
                const _ChangePasswordCard(),
                const SizedBox(height: 16),
                const _NotificationCard(),
                const SizedBox(height: 16),
                _CalendarSyncCard(userId: widget.profile['id'] as String),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Skift adgangskode — selvbetjening for logget-ind bruger
// ─────────────────────────────────────────────────────────────────────────────

class _ChangePasswordCard extends StatefulWidget {
  const _ChangePasswordCard();
  @override
  State<_ChangePasswordCard> createState() => _ChangePasswordCardState();
}

class _ChangePasswordCardState extends State<_ChangePasswordCard> {
  final _pass = TextEditingController();
  final _pass2 = TextEditingController();
  bool _saving = false;
  bool _obscure = true;

  @override
  void dispose() {
    _pass.dispose();
    _pass2.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final p = _pass.text;
    if (p.length < 6) {
      _snack(context, 'Kodeordet skal være mindst 6 tegn', Colors.orange);
      return;
    }
    if (p != _pass2.text) {
      _snack(context, 'De to kodeord er ikke ens', Colors.orange);
      return;
    }
    setState(() => _saving = true);
    try {
      await supabase.auth.updateUser(UserAttributes(password: p));
      if (!mounted) return;
      _pass.clear();
      _pass2.clear();
      FocusScope.of(context).unfocus();
      _snack(context, 'Adgangskode ændret ✓', Colors.green);
    } on AuthException catch (e) {
      if (mounted) _snack(context, e.message, Colors.red);
    } catch (e) {
      if (mounted) _snack(context, 'Kunne ikke ændre kodeord: $e', Colors.red);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.lock_outline, color: theme.colorScheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('Skift adgangskode',
                      style: theme.textTheme.titleMedium),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text('Vælg et nyt kodeord til din konto.',
                style: theme.textTheme.bodySmall),
            const SizedBox(height: 16),
            TextField(
              controller: _pass,
              obscureText: _obscure,
              decoration: InputDecoration(
                labelText: 'Nyt kodeord',
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  icon: Icon(_obscure
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _pass2,
              obscureText: _obscure,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _save(),
              decoration: const InputDecoration(
                labelText: 'Gentag nyt kodeord',
                prefixIcon: Icon(Icons.lock_outline),
              ),
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(width: 16, height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.check),
                label: Text(_saving ? 'Gemmer…' : 'Gem nyt kodeord'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Push-notifikationer — eksplicit "Aktivér"-knap (supplerer auto-prompten)
// ─────────────────────────────────────────────────────────────────────────────

class _NotificationCard extends StatefulWidget {
  const _NotificationCard();
  @override
  State<_NotificationCard> createState() => _NotificationCardState();
}

class _NotificationCardState extends State<_NotificationCard> {
  bool _busy = false;

  Future<void> _enable() async {
    setState(() => _busy = true);
    final result = await NotificationService.requestPermissionAndSaveToken();
    if (!mounted) return;
    setState(() => _busy = false);
    switch (result) {
      case PushResult.saved:
        _snack(context, 'Notifikationer aktiveret 🎾', Colors.green);
      case PushResult.denied:
        _snack(context,
            'Tilladelse blev ikke givet. Tjek browserens/telefonens '
            'notifikations-indstillinger og prøv igen.',
            Colors.orange);
      case PushResult.notConfigured:
        _snack(context,
            'Notifikationer er ikke konfigureret endnu (mangler App ID).',
            Colors.orange);
      case PushResult.noUser:
        _snack(context, 'Du skal være logget ind.', Colors.orange);
      case PushResult.error:
        _snack(context, 'Noget gik galt. Prøv igen senere.', Colors.red);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.notifications_active_outlined,
                    color: theme.colorScheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('Push-notifikationer',
                      style: theme.textTheme.titleMedium),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Få besked direkte på telefonen om nye træninger, kampe, '
              'afstemninger og bøder. På iPhone kræver det, at appen er '
              'føjet til hjemmeskærmen (iOS 16.4+).',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: _busy ? null : _enable,
                icon: _busy
                    ? const SizedBox(width: 16, height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.notifications_active_outlined),
                label: Text(_busy ? 'Aktiverer…' : 'Aktivér notifikationer'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Kalender-synkronisering — abonnement på Edge Function-feed
// ─────────────────────────────────────────────────────────────────────────────

class _CalendarSyncCard extends StatefulWidget {
  final String userId;
  const _CalendarSyncCard({required this.userId});
  @override
  State<_CalendarSyncCard> createState() => _CalendarSyncCardState();
}

class _CalendarSyncCardState extends State<_CalendarSyncCard> {
  static const _prefKey = 'calendar_sync_enabled';
  bool _enabled = false;

  @override
  void initState() {
    super.initState();
    _enabled = platformStorageGet(_prefKey) == 'true';
  }

  String get _feedUrl =>
      '$_supabaseUrl/functions/v1/calendar-feed?token=${widget.userId}';

  void _toggle(bool v) {
    setState(() => _enabled = v);
    platformStorageSet(_prefKey, v.toString());
  }

  Future<void> _copyUrl() async {
    await Clipboard.setData(ClipboardData(text: _feedUrl));
    if (mounted) _snack(context, 'URL kopieret', Colors.green.shade400);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.calendar_month, color: theme.colorScheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('Automatisk kalender-synkronisering',
                      style: theme.textTheme.titleMedium),
                ),
                Switch(value: _enabled, onChanged: _toggle),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              _enabled
                  ? 'Holdets begivenheder synkroniseres automatisk. '
                    'Abonnér på din personlige URL nedenfor — nye '
                    'træninger/kampe dukker op af sig selv i din kalender.'
                  : 'Tænd kontakten for at abonnere på en personlig '
                    'kalender-feed med alle holdets begivenheder.',
              style: theme.textTheme.bodySmall,
            ),
            if (_enabled) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: _surfaceElevated,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _borderSubtle),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.link, size: 18, color: _neon),
                    const SizedBox(width: 10),
                    Expanded(
                      child: SelectableText(
                        _feedUrl,
                        style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 11.5,
                            color: _textPrimary),
                        maxLines: 2,
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: _copyUrl,
                      icon: const Icon(Icons.content_copy, size: 16),
                      label: const Text('Kopiér'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        minimumSize: const Size(0, 38),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text('Sådan abonnerer du',
                  style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              const _SubInstruction(
                icon: Icons.event,
                title: 'Google Calendar',
                steps: 'Indstillinger → Tilføj kalender → '
                       'Fra URL → indsæt URL → Tilføj kalender',
              ),
              const SizedBox(height: 6),
              const _SubInstruction(
                icon: Icons.apple,
                title: 'iPhone / Apple Calendar',
                steps: 'iOS: Indstillinger → Kalender → Konti → '
                       'Tilføj konto → Andet → Tilføj abonneret '
                       'kalender → indsæt URL.\n'
                       'Mac: Kalender → Fil → Nyt kalender-'
                       'abonnement → indsæt URL.',
              ),
              const SizedBox(height: 6),
              const _SubInstruction(
                icon: Icons.business,
                title: 'Outlook',
                steps: 'Tilføj kalender → Abonner fra webben → '
                       'indsæt URL → Importér',
              ),
              const SizedBox(height: 8),
              Text(
                'Kalenderen opdaterer sig automatisk hver time '
                '(afhænger af klienten — Google er typisk 6-24 t, '
                'Apple/Outlook hver time).',
                style: theme.textTheme.bodySmall?.copyWith(
                    color: _textMuted, fontStyle: FontStyle.italic),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SubInstruction extends StatelessWidget {
  final IconData icon;
  final String title;
  final String steps;
  const _SubInstruction({
    required this.icon,
    required this.title,
    required this.steps,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: _neon),
          const SizedBox(width: 10),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: theme.textTheme.bodySmall?.copyWith(color: _textPrimary),
                children: [
                  TextSpan(
                    text: '$title — ',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  TextSpan(text: steps,
                      style: TextStyle(color: _textSecondary)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  final Map<String, dynamic> profile;
  const _ProfileCard({required this.profile});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final navn = profile['navn'] as String;
    final email = profile['email'] as String;
    final rolle = profile['rolle'] as String;
    final isAdmin = rolle == 'admin';

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
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          Container(
            width: 56, height: 56,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _neon,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(color: _neon.withValues(alpha: 0.35), blurRadius: 14),
              ],
            ),
            child: Text(
              navn.isNotEmpty ? navn[0].toUpperCase() : '?',
              style: _cond(size: 26, weight: FontWeight.w800, color: Colors.white),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(navn.toUpperCase(),
                    style: theme.textTheme.titleLarge,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(email,
                    style: theme.textTheme.bodyMedium?.copyWith(color: _textSecondary),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: isAdmin ? _gold : _surfaceElevated,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(isAdmin ? 'ADMIN' : 'MEDLEM',
                      style: _body(
                          size: 10,
                          weight: FontWeight.w800,
                          spacing: 0.8,
                          color: isAdmin ? _onGold : _textSecondary)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MakkerCard extends StatelessWidget {
  final List<Map<String, dynamic>> members;
  final String? selectedP1;
  final String? selectedP2;
  final bool saving;
  final ValueChanged<String?> onChangedP1;
  final ValueChanged<String?> onChangedP2;
  final VoidCallback onSave;
  const _MakkerCard({
    required this.members,
    required this.selectedP1,
    required this.selectedP2,
    required this.saving,
    required this.onChangedP1,
    required this.onChangedP2,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Mine faste makkere', style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text('Bruges af synergi-rapporten til at finde dine stærkeste hold.',
                style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 24),
            _MakkerDropdown(label: 'Prioritet 1 makker',
                value: selectedP1, members: members, onChanged: onChangedP1),
            const SizedBox(height: 16),
            _MakkerDropdown(label: 'Prioritet 2 makker',
                value: selectedP2, members: members, onChanged: onChangedP2),
            const SizedBox(height: 24),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: saving ? null : onSave,
                icon: saving
                    ? const SizedBox(width: 16, height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.save_outlined),
                label: Text(saving ? 'Gemmer…' : 'Gem makkere'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MakkerDropdown extends StatelessWidget {
  final String label;
  final String? value;
  final List<Map<String, dynamic>> members;
  final ValueChanged<String?> onChanged;
  const _MakkerDropdown({
    required this.label,
    required this.value,
    required this.members,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String?>(
      value: value,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: const Icon(Icons.people_outline),
      ),
      items: [
        const DropdownMenuItem<String?>(
          value: null,
          child: Text('— Ingen valgt —',
              style: TextStyle(fontStyle: FontStyle.italic)),
        ),
        ...members.map((m) => DropdownMenuItem<String?>(
              value: m['id'] as String,
              child: Text(m['navn'] as String),
            )),
      ],
      onChanged: onChanged,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tab 2: Træninger — medlemsvisning
// ─────────────────────────────────────────────────────────────────────────────

