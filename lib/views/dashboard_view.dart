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
  // Bøde-data
  List<Map<String, dynamic>> _fineTypes = const [];
  List<Map<String, dynamic>> _pendingFines = const [];
  bool _loadingFines = true;
  String? _finesError;

  // Åben under-skærm i Admin: null = menu. Ellers 'members'/'fine'/'mobilepay'.
  String? _openSection;

  @override
  void initState() {
    super.initState();
    reloadFines();
  }

  Future<void> _reloadAll() async {
    await reloadFines();
  }

  Future<void> reloadFines() async {
    setState(() { _loadingFines = true; _finesError = null; });
    try {
      final results = await Future.wait([
        supabase.from('fine_types').select('id, titel, belob_oere, aktiv, hold_group_id, group_id').order('titel'),
        // VIGTIGT: profiles har 3 FK'er fra fines (user_id, given_by, approved_by)
        // — disambigueres med fines_user_id_fkey
        supabase.from('fines')
            .select('id, user_id, titel, belob_oere, begrundelse, created_at, '
                    'profiles!fines_user_id_fkey(navn)')
            .eq('status', 'ubetalt')
            .order('created_at', ascending: false),
      ]);

      setState(() {
        _fineTypes    = List<Map<String, dynamic>>.from(results[0] as List);
        _pendingFines = List<Map<String, dynamic>>.from(results[1] as List);
        _loadingFines = false;
      });
    } catch (e) {
      setState(() { _loadingFines = false; _finesError = e.toString(); });
    }
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

  Future<void> _deleteFine(String fineId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Slet bøde?'),
        content: const Text('Bøden fjernes permanent. Brug dette hvis den '
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
          await supabase.from('fines').delete().eq('id', fineId).select();
      if (mounted) {
        _snack(
          context,
          (deleted as List).isEmpty
              ? 'Kunne ikke slette — mangler du rettigheder?'
              : 'Bøde slettet',
          (deleted).isEmpty ? _danger : _textSecondary,
        );
      }
      await reloadFines();
    } on PostgrestException catch (e) {
      if (mounted) _snack(context, e.message, _danger);
      await reloadFines();
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
      body: _openSection == null ? _adminMenu() : _sectionView(),
    );
  }

  // ── Admin-menu (matcher prototypen) ─────────────────────────────────────────
  Widget _adminMenu() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: [
                  Container(width: 4, height: 22,
                      decoration: BoxDecoration(
                          color: _neon, borderRadius: BorderRadius.circular(999))),
                  const SizedBox(width: 10),
                  Text('ADMIN', style: _cond(size: 24, weight: FontWeight.w800)),
                ]),
                const Padding(
                  padding: EdgeInsets.fromLTRB(14, 4, 0, 18),
                  child: Text(
                    'Opsætning & styring — begivenheder, afstemninger og bøder '
                    'oprettes med +-knappen.',
                    style: TextStyle(color: _textSecondary, fontSize: 12.5),
                  ),
                ),
                _menuCard(Icons.groups_outlined, 'Medlemmer & hold',
                    'Sæt på hold · roller · kaptajn · slet',
                    () => setState(() => _openSection = 'members')),
                _menuCard(Icons.layers_outlined, 'Holdgrupper',
                    'Saml hold der deler bødekasse og bødetyper',
                    () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const HoldGroupsScreen()))),
                _menuCard(Icons.gavel_outlined, 'Bøde-opsætning',
                    'Godkend · bødetyper pr. hold · udeblivelse',
                    () => setState(() => _openSection = 'fine')),
                if (widget.isFullAdmin)
                  _menuCard(Icons.account_balance_wallet_outlined, 'MobilePay',
                      'Boks pr. holdgruppe + fælles',
                      () => setState(() => _openSection = 'mobilepay')),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _menuCard(IconData icon, String titel, String sub, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(15),
        child: Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            color: _surfaceDark,
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: _borderSubtle),
          ),
          child: Row(children: [
            Container(
              width: 44, height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: _neon.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: _neon, size: 21),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(titel, style: _body(size: 15, weight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(sub,
                      style: _body(size: 11.5, color: _textSecondary),
                      maxLines: 2, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: _textMuted),
          ]),
        ),
      ),
    );
  }

  Widget _sectionView() {
    final title = switch (_openSection) {
      'members' => 'Medlemmer & hold',
      'fine' => 'Bøde-opsætning',
      'mobilepay' => 'MobilePay',
      _ => 'Admin',
    };
    return Column(
      children: [
        // Topbar med tilbage-pil.
        Container(
          color: const Color(0xFF241914),
          padding: EdgeInsets.fromLTRB(
              8, MediaQuery.of(context).padding.top + 10, 14, 12),
          child: Row(children: [
            IconButton(
              onPressed: () => setState(() => _openSection = null),
              icon: const Icon(Icons.chevron_left, color: _textSecondary),
            ),
            Expanded(
              child: Text(title.toUpperCase(),
                  style: _cond(size: 18, weight: FontWeight.w800)),
            ),
          ]),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _reloadAll,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 760),
                    child: switch (_openSection) {
                      'members' => _buildMembersSection(),
                      'mobilepay' => const _MobilePayConfigCard(),
                      _ => _buildFineSection(),
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFineSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_loadingFines)
          const Padding(padding: EdgeInsets.all(40),
              child: Center(child: CircularProgressIndicator()))
        else if (_finesError != null)
          Text(_finesError!, style: const TextStyle(color: Colors.red))
        else ...[
          // Godkend-flow (matcher prototypen: afventende betalinger + forslag)
          _PendingFinesCard(
            fines: _pendingFines,
            onApprove: _approvePayment,
            onDelete: _deleteFine,
          ),
          const SizedBox(height: 14),
          _PendingSuggestionsCard(
            suggestions: _fineTypes.where((t) => t['aktiv'] == false).toList(),
            onApprove:   _approveSuggestion,
          ),
          const SizedBox(height: 14),
          // Bødetyper pr. fællesskab
          _CreateFineTypeCard(
            existingTypes: _fineTypes.where((t) => t['aktiv'] == true).toList(),
            onCreated:     reloadFines,
          ),
          if (widget.isFullAdmin) ...[
            const SizedBox(height: 14),
            _NoShowFineCard(
              fineTypes: _fineTypes.where((t) => t['aktiv'] == true).toList(),
            ),
          ],
        ],
      ],
    );
  }

  Widget _buildMembersSection() {
    return _MembersAdminView(
      isAdmin: widget.isFullAdmin,
      currentUserId: supabase.auth.currentUser?.id ?? '',
      onChangeRole: _changeRole,
    );
  }
}

/// Indgang til Holdgrupper-skærmen (medlems-sektionen).
/// Holdgrupper — saml hold der deler bødekasse/bødetyper/MobilePay.
class HoldGroupsScreen extends StatefulWidget {
  const HoldGroupsScreen({super.key});
  @override
  State<HoldGroupsScreen> createState() => _HoldGroupsScreenState();
}

class _HoldGroupsScreenState extends State<HoldGroupsScreen> {
  List<Map<String, dynamic>> _holdGroups = const [];
  List<Map<String, dynamic>> _holds = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await Future.wait([
        supabase.from('hold_groups').select('id, navn, mobilepay_box_id').order('created_at'),
        supabase.from('groups').select('id, navn, farve, hold_group_id').order('sort'),
      ]);
      if (!mounted) return;
      setState(() {
        _holdGroups = List<Map<String, dynamic>>.from(res[0] as List);
        _holds = List<Map<String, dynamic>>.from(res[1] as List);
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> _holdsFor(String groupId) =>
      _holds.where((h) => h['hold_group_id'] == groupId).toList();

  Future<void> _openSheet({Map<String, dynamic>? existing}) async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _HoldGroupSheet(existing: existing, allHolds: _holds),
    );
    if (changed == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final solo = _holds.where((h) => h['hold_group_id'] == null).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('HOLDGRUPPER')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 700),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Saml hold der hører sammen. Hold i samme gruppe deler '
                          'bødekasse og bødetyper, men planlægger stadig kampe og '
                          'afstemninger hver for sig.',
                          style: _body(size: 12.5, color: _textSecondary),
                        ),
                        const SizedBox(height: 18),
                        if (_holdGroups.isNotEmpty) ...[
                          _sectionLabel('Grupper'),
                          for (final hg in _holdGroups) _groupCard(hg),
                          const SizedBox(height: 6),
                        ],
                        InkWell(
                          onTap: () => _openSheet(),
                          borderRadius: BorderRadius.circular(13),
                          child: Container(
                            padding: const EdgeInsets.all(13),
                            decoration: BoxDecoration(
                              border: Border.all(
                                  color: _neon.withValues(alpha: 0.5)),
                              borderRadius: BorderRadius.circular(13),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.add, size: 16, color: _neon),
                                const SizedBox(width: 8),
                                Text('Ny gruppe',
                                    style: _body(
                                        size: 13.5,
                                        weight: FontWeight.w700,
                                        color: _neon)),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 22),
                        _sectionLabel('Selvstændige hold'),
                        if (solo.isEmpty)
                          Text('Alle hold er i en gruppe.',
                              style: _body(size: 12.5, color: _textMuted))
                        else
                          Container(
                            decoration: BoxDecoration(
                              color: _surfaceDark,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: _borderSubtle),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            child: Column(
                              children: [
                                for (var i = 0; i < solo.length; i++)
                                  Container(
                                    decoration: BoxDecoration(
                                      border: Border(
                                        top: i == 0
                                            ? BorderSide.none
                                            : const BorderSide(color: _borderSubtle),
                                      ),
                                    ),
                                    padding: const EdgeInsets.symmetric(vertical: 11),
                                    child: Row(children: [
                                      Icon(Icons.layers_outlined,
                                          size: 16,
                                          color: _hex(solo[i]['farve'] as String?)),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(solo[i]['navn'] as String,
                                            style: _body(
                                                size: 14,
                                                weight: FontWeight.w600)),
                                      ),
                                      Text('egen bødekasse',
                                          style: _body(size: 11, color: _textMuted)),
                                    ]),
                                  ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  static Color _hex(String? h) {
    if (h == null || h.isEmpty) return _neon;
    return Color(int.parse(h.replaceFirst('#', ''), radix: 16) | 0xFF000000);
  }

  Widget _sectionLabel(String s) => Padding(
        padding: const EdgeInsets.only(bottom: 9),
        child: Text(s.toUpperCase(),
            style: _body(
                size: 11, weight: FontWeight.w700, spacing: 0.6, color: _textMuted)),
      );

  Widget _groupCard(Map<String, dynamic> hg) {
    final holds = _holdsFor(hg['id'] as String);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _surfaceDark,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.layers_outlined, size: 18, color: _neon),
            const SizedBox(width: 9),
            Expanded(
              child: Text((hg['navn'] as String).toUpperCase(),
                  style: _cond(size: 16, weight: FontWeight.w800)),
            ),
            GestureDetector(
              onTap: () => _openSheet(existing: hg),
              child: Text('Redigér',
                  style: _body(size: 12, weight: FontWeight.w700, color: _neon)),
            ),
          ]),
          const SizedBox(height: 10),
          if (holds.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text('Ingen hold i gruppen endnu',
                  style: _body(size: 12.5, color: _textMuted)),
            )
          else
            for (final h in holds)
              Padding(
                padding: const EdgeInsets.only(bottom: 7),
                child: Row(children: [
                  const Icon(Icons.chevron_right, size: 15, color: _textMuted),
                  const SizedBox(width: 4),
                  Text(h['navn'] as String,
                      style: _body(size: 13.5, weight: FontWeight.w600)),
                ]),
              ),
          const SizedBox(height: 3),
          Container(
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: _borderSubtle)),
            ),
            padding: const EdgeInsets.only(top: 9),
            child: Row(children: [
              const Icon(Icons.check, size: 14, color: _success),
              const SizedBox(width: 6),
              Text('Deler bødekasse og bødetyper',
                  style: _body(size: 11.5, color: _textMuted)),
            ]),
          ),
        ],
      ),
    );
  }
}

/// Opret/redigér en holdgruppe — navn + hvilke hold der er med.
class _HoldGroupSheet extends StatefulWidget {
  final Map<String, dynamic>? existing;
  final List<Map<String, dynamic>> allHolds;
  const _HoldGroupSheet({this.existing, required this.allHolds});
  @override
  State<_HoldGroupSheet> createState() => _HoldGroupSheetState();
}

class _HoldGroupSheetState extends State<_HoldGroupSheet> {
  late final _navn =
      TextEditingController(text: widget.existing?['navn'] as String? ?? '');
  late final Set<String> _selected = widget.existing == null
      ? <String>{}
      : widget.allHolds
          .where((h) => h['hold_group_id'] == widget.existing!['id'])
          .map((h) => h['id'] as String)
          .toSet();
  bool _saving = false;

  @override
  void dispose() {
    _navn.dispose();
    super.dispose();
  }

  static Color _hex(String? h) {
    if (h == null || h.isEmpty) return _neon;
    return Color(int.parse(h.replaceFirst('#', ''), radix: 16) | 0xFF000000);
  }

  Future<void> _save() async {
    final navn = _navn.text.trim();
    if (navn.isEmpty) {
      _snack(context, 'Giv gruppen et navn', _gold);
      return;
    }
    setState(() => _saving = true);
    try {
      String groupId;
      if (widget.existing == null) {
        final row = await supabase
            .from('hold_groups')
            .insert({'navn': navn}).select('id').single();
        groupId = row['id'] as String;
      } else {
        groupId = widget.existing!['id'] as String;
        await supabase
            .from('hold_groups')
            .update({'navn': navn}).eq('id', groupId);
      }
      // Sæt/ryd hold_group_id for de berørte hold.
      for (final h in widget.allHolds) {
        final id = h['id'] as String;
        final shouldBeIn = _selected.contains(id);
        final currently = h['hold_group_id'];
        if (shouldBeIn && currently != groupId) {
          await supabase.from('groups')
              .update({'hold_group_id': groupId}).eq('id', id);
        } else if (!shouldBeIn && currently == groupId) {
          await supabase.from('groups')
              .update({'hold_group_id': null}).eq('id', id);
        }
      }
      if (!mounted) return;
      _snack(context, 'Holdgruppe gemt', _success);
      Navigator.of(context).pop(true);
    } on PostgrestException catch (e) {
      if (mounted) _snack(context, e.message, _danger);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Slet holdgruppe?'),
        content: const Text('Holdene bliver selvstændige igen. Bødetyper og '
            'MobilePay knyttet til gruppen fjernes.'),
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
      await supabase
          .from('hold_groups')
          .delete()
          .eq('id', widget.existing!['id']);
      if (!mounted) return;
      _snack(context, 'Holdgruppe slettet', _textSecondary);
      Navigator.of(context).pop(true);
    } on PostgrestException catch (e) {
      if (mounted) _snack(context, e.message, _danger);
    }
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
              Text(widget.existing == null ? 'NY HOLDGRUPPE' : 'REDIGÉR HOLDGRUPPE',
                  style: _cond(size: 20, weight: FontWeight.w800)),
              const SizedBox(height: 14),
              TextField(
                controller: _navn,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                    labelText: 'Navn', hintText: 'F.eks. "Herrer" eller "Ungdom"'),
              ),
              const SizedBox(height: 16),
              Text('Hvilke hold er med?',
                  style: _body(size: 13, weight: FontWeight.w600, color: _textSecondary)),
              const SizedBox(height: 4),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      for (final h in widget.allHolds)
                        Builder(builder: (_) {
                          final id = h['id'] as String;
                          final otherGroup = h['hold_group_id'] != null &&
                              h['hold_group_id'] != widget.existing?['id'];
                          return CheckboxListTile(
                            value: _selected.contains(id),
                            onChanged: (v) => setState(() {
                              if (v == true) {
                                _selected.add(id);
                              } else {
                                _selected.remove(id);
                              }
                            }),
                            activeColor: _neon,
                            contentPadding: EdgeInsets.zero,
                            controlAffinity: ListTileControlAffinity.leading,
                            secondary: Container(
                              width: 14, height: 14,
                              decoration: BoxDecoration(
                                  color: _hex(h['farve'] as String?),
                                  shape: BoxShape.circle),
                            ),
                            title: Text(h['navn'] as String),
                            subtitle: otherGroup
                                ? Text('Flyttes fra en anden gruppe',
                                    style: _body(size: 11, color: _gold))
                                : null,
                          );
                        }),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(children: [
                if (widget.existing != null)
                  IconButton(
                    onPressed: _saving ? null : _delete,
                    icon: const Icon(Icons.delete_outline, color: _danger),
                    tooltip: 'Slet gruppe',
                  ),
                Expanded(
                  child: TextButton(
                    onPressed: _saving ? null : () => Navigator.of(context).pop(),
                    style: TextButton.styleFrom(foregroundColor: _textSecondary),
                    child: const Text('Annullér'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(width: 18, height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('Gem'),
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

/// Bundsheet til at oprette en ny gruppe — eller redigere en eksisterende
/// (når [existing] er sat). Returnerer {navn, type, farve} eller null.
class _NewGroupSheet extends StatefulWidget {
  final Map<String, dynamic>? existing;
  const _NewGroupSheet({this.existing});
  @override
  State<_NewGroupSheet> createState() => _NewGroupSheetState();
}

class _NewGroupSheetState extends State<_NewGroupSheet> {
  late final _navn =
      TextEditingController(text: widget.existing?['navn'] as String? ?? '');
  late String _type = widget.existing?['type'] as String? ?? 'hold';
  late String _farve = widget.existing?['farve'] as String? ?? '#E8622C';
  static const _colors = [
    '#E8622C', '#3DA9FC', '#F2A63B', '#34C759', '#B892FF', '#E5544E'
  ];

  @override
  void dispose() {
    _navn.dispose();
    super.dispose();
  }

  static Color _hex(String h) =>
      Color(int.parse(h.replaceFirst('#', ''), radix: 16) | 0xFF000000);

  void _save() {
    if (_navn.text.trim().isEmpty) {
      _snack(context, 'Giv gruppen et navn', _gold);
      return;
    }
    Navigator.pop(context, {
      'navn': _navn.text.trim(),
      'type': _type,
      'farve': _farve,
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: Container(
          margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _surfaceDark,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _borderSubtle),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(widget.existing == null ? 'NY GRUPPE' : 'REDIGÉR GRUPPE',
                  style: _cond(size: 20, weight: FontWeight.w800)),
              const SizedBox(height: 14),
              TextField(
                controller: _navn,
                autofocus: true,
                decoration: const InputDecoration(
                    labelText: 'Navn', hintText: 'F.eks. "Hold 3" eller "Veteraner"'),
              ),
              const SizedBox(height: 16),
              Text('Type',
                  style: _body(size: 13, weight: FontWeight.w600, color: _textSecondary)),
              const SizedBox(height: 8),
              Wrap(spacing: 8, children: [
                for (final t in const [
                  ('hold', 'Hold'),
                  ('kamp-trup', 'Kamp-trup'),
                  ('anden', 'Anden')
                ])
                  ChoiceChip(
                    label: Text(t.$2),
                    selected: _type == t.$1,
                    onSelected: (_) => setState(() => _type = t.$1),
                    selectedColor: _neon,
                    labelStyle: TextStyle(
                        color: _type == t.$1 ? Colors.white : _textPrimary),
                  ),
              ]),
              const SizedBox(height: 16),
              Text('Farve',
                  style: _body(size: 13, weight: FontWeight.w600, color: _textSecondary)),
              const SizedBox(height: 8),
              Wrap(spacing: 10, children: [
                for (final c in _colors)
                  GestureDetector(
                    onTap: () => setState(() => _farve = c),
                    child: Container(
                      width: 34, height: 34,
                      decoration: BoxDecoration(
                        color: _hex(c),
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: _farve == c ? Colors.white : Colors.transparent,
                            width: 2),
                      ),
                      child: _farve == c
                          ? const Icon(Icons.check, size: 18, color: Colors.white)
                          : null,
                    ),
                  ),
              ]),
              const SizedBox(height: 20),
              Row(children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    style: TextButton.styleFrom(foregroundColor: _textSecondary),
                    child: const Text('Annullér'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: FilledButton(
                      onPressed: _save,
                      child: Text(widget.existing == null
                          ? 'Opret gruppe'
                          : 'Gem')),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Admin → Medlemmer & hold (matcher prototypen: faner, søg, liste, hold-detalje)
// ─────────────────────────────────────────────────────────────────────────────

// Faste avatar-farver (deterministisk pr. navn) — som prototypens palet.
const List<Color> _avatarPalette = [
  _neon,
  Color(0xFF4A3226),
  Color(0xFF2B4A5E),
  Color(0xFF3A2B22),
  Color(0xFFB57BE0),
  Color(0xFF5A4A3A),
  Color(0xFF3DA9FC),
];
Color _avatarColorFor(String name) {
  if (name.isEmpty) return _surfaceElevated;
  var h = 0;
  for (final c in name.codeUnits) {
    h = (h * 31 + c) & 0x7fffffff;
  }
  return _avatarPalette[h % _avatarPalette.length];
}

Color _groupHex(String? h) {
  if (h == null || h.isEmpty) return _textSecondary;
  return Color(int.parse(h.replaceFirst('#', ''), radix: 16) | 0xFF000000);
}

class _MembersAdminView extends StatefulWidget {
  final bool isAdmin;
  final String currentUserId;
  final Future<void> Function(String userId, String newRole) onChangeRole;
  const _MembersAdminView({
    required this.isAdmin,
    required this.currentUserId,
    required this.onChangeRole,
  });
  @override
  State<_MembersAdminView> createState() => _MembersAdminViewState();
}

class _MembersAdminViewState extends State<_MembersAdminView> {
  List<Map<String, dynamic>> _groups = const [];
  List<Map<String, dynamic>> _members = const [];
  Map<String, Set<String>> _membership = {}; // uid → gruppe-id'er
  Map<String, Set<String>> _captains = {};   // uid → gruppe-id'er (kaptajn)
  Map<String, int> _skyldigt = {};           // uid → ubetalt øre
  bool _loading = true;
  String _tab = 'medlemmer';
  String _search = '';
  String? _teamOpen; // null = liste. Ellers gruppe-id eller 'none' (uden hold).

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await Future.wait([
        supabase.from('groups').select('id, navn, type, farve, sort').order('sort'),
        supabase.from('profiles').select('id, navn, rolle, email').order('navn'),
        supabase.from('group_members').select('group_id, user_id, is_captain'),
        supabase.from('fine_leaderboard').select('id, skyldigt_oere'),
      ]);
      final gm = List<Map<String, dynamic>>.from(res[2] as List);
      final map = <String, Set<String>>{};
      final caps = <String, Set<String>>{};
      for (final r in gm) {
        final uid = r['user_id'] as String;
        final gid = r['group_id'] as String;
        (map[uid] ??= {}).add(gid);
        if (r['is_captain'] == true) (caps[uid] ??= {}).add(gid);
      }
      final skyldigt = <String, int>{};
      for (final r in List<Map<String, dynamic>>.from(res[3] as List)) {
        skyldigt[r['id'] as String] = (r['skyldigt_oere'] as num?)?.toInt() ?? 0;
      }
      if (!mounted) return;
      setState(() {
        _groups = List<Map<String, dynamic>>.from(res[0] as List);
        _members = List<Map<String, dynamic>>.from(res[1] as List);
        _membership = map;
        _captains = caps;
        _skyldigt = skyldigt;
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _groupName(String gid) {
    final g = _groups.where((g) => g['id'] == gid);
    return g.isEmpty ? '' : g.first['navn'] as String;
  }

  // Rolle-badge (label + farve) — kaptajn vises hvis medlemmet er kaptajn nogen steder.
  (String, Color) _roleBadge(Map<String, dynamic> m) {
    final rolle = m['rolle'] as String? ?? 'medlem';
    if (rolle == 'admin') return ('ADMIN', _gold);
    if (rolle == 'træner') return ('TRÆNER', _info);
    if ((_captains[m['id']] ?? const {}).isNotEmpty) return ('KAPTAJN', _info);
    return ('SPILLER', _textSecondary);
  }

  Future<void> _openEdit(Map<String, dynamic> m) async {
    final id = m['id'] as String;
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _MemberSheet(
        profile: m,
        isMe: id == widget.currentUserId,
        isAdmin: widget.isAdmin,
        groups: _groups,
        memberGids: {...(_membership[id] ?? const {})},
        captainGids: {...(_captains[id] ?? const {})},
        skyldigtOere: _skyldigt[id] ?? 0,
        onChangeRole: widget.onChangeRole,
      ),
    );
    if (changed == true) _load();
  }

  Future<void> _newHold() async {
    final res = await showModalBottomSheet<Map<String, String>>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => const _NewGroupSheet(),
    );
    if (res == null) return;
    try {
      final nextSort = _groups
              .map((g) => (g['sort'] as num?)?.toInt() ?? 0)
              .fold<int>(0, (m, v) => v > m ? v : m) +
          1;
      await supabase.from('groups').insert({
        'navn': res['navn'],
        'type': res['type'],
        'farve': res['farve'],
        'sort': nextSort,
      });
      if (mounted) _snack(context, 'Hold oprettet', _success);
      _load();
    } on PostgrestException catch (e) {
      if (mounted) _snack(context, e.message, _danger);
    }
  }

  Future<void> _editHold(Map<String, dynamic> g) async {
    final res = await showModalBottomSheet<Map<String, String>>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _NewGroupSheet(existing: g),
    );
    if (res == null) return;
    try {
      await supabase.from('groups').update({
        'navn': res['navn'],
        'type': res['type'],
        'farve': res['farve'],
      }).eq('id', g['id']);
      if (mounted) _snack(context, 'Hold opdateret', _success);
      _load();
    } on PostgrestException catch (e) {
      if (mounted) _snack(context, e.message, _danger);
    }
  }

  Future<void> _deleteHold(Map<String, dynamic> g) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Slet hold?'),
        content: Text('"${g['navn']}" fjernes. Begivenheder for holdet '
            'bliver synlige for alle.'),
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
      await supabase.from('groups').delete().eq('id', g['id']);
      if (mounted) {
        _snack(context, 'Hold slettet', _textSecondary);
        setState(() => _teamOpen = null);
      }
      _load();
    } on PostgrestException catch (e) {
      if (mounted) _snack(context, e.message, _danger);
    }
  }

  // ── Byggeblokke ─────────────────────────────────────────────────────────────
  Widget _segTabs() {
    Widget seg(String value, String label) {
      final active = _tab == value;
      return Expanded(
        child: GestureDetector(
          onTap: () => setState(() => _tab = value),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: active ? _surfaceElevated : Colors.transparent,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Text(label,
                style: _cond(
                    size: 15,
                    weight: FontWeight.w800,
                    spacing: 0.3,
                    color: active ? _textPrimary : _textMuted)),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
          color: _bgBlack, borderRadius: BorderRadius.circular(12)),
      child: Row(children: [
        seg('medlemmer', 'Medlemmer'),
        seg('hold', 'Hold'),
      ]),
    );
  }

  Widget _memberRow(Map<String, dynamic> m, bool first) {
    final navn = m['navn'] as String? ?? '?';
    final gids = _membership[m['id']] ?? const <String>{};
    final teams = gids.map(_groupName).where((s) => s.isNotEmpty).join(' · ');
    final (badge, badgeColor) = _roleBadge(m);
    return InkWell(
      onTap: () => _openEdit(m),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(
          border: first
              ? null
              : const Border(top: BorderSide(color: _borderSubtle)),
        ),
        child: Row(children: [
          Container(
            width: 34, height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
                color: _avatarColorFor(navn), shape: BoxShape.circle),
            child: Text(navn.isEmpty ? '?' : navn[0].toUpperCase(),
                style: _body(
                    size: 13, weight: FontWeight.w700, color: Colors.white)),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(navn,
                    style: _body(size: 14, weight: FontWeight.w600),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(teams.isEmpty ? 'Uden hold' : teams,
                    style: _body(
                        size: 11.5,
                        color: teams.isEmpty ? _gold : _textSecondary),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
            decoration: BoxDecoration(
              color: badgeColor.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(badge,
                style: _body(
                    size: 10, weight: FontWeight.w700, color: badgeColor)),
          ),
          const SizedBox(width: 6),
          const Icon(Icons.chevron_right, size: 16, color: _textMuted),
        ]),
      ),
    );
  }

  Widget _listCard(List<Map<String, dynamic>> members) {
    if (members.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 22),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: _surfaceDark,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _borderSubtle),
        ),
        child: Text('Ingen medlemmer',
            style: _body(size: 13, color: _textMuted)),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: _surfaceDark,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _borderSubtle),
      ),
      child: Column(
        children: [
          for (var i = 0; i < members.length; i++)
            _memberRow(members[i], i == 0),
        ],
      ),
    );
  }

  Widget _goldCard(int count) {
    if (count == 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: InkWell(
        onTap: () => setState(() => _teamOpen = 'none'),
        borderRadius: BorderRadius.circular(13),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: _gold.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: _gold.withValues(alpha: 0.35)),
          ),
          child: Row(children: [
            Container(
              width: 34, height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: _gold.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.error_outline, color: _gold, size: 18),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('$count uden hold',
                      style: _body(size: 14, weight: FontWeight.w700)),
                  Text('Skal indplaceres på et hold',
                      style: _body(size: 11.5, color: _textSecondary)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 16, color: _gold),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(40),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final noTeam = _members
        .where((m) => (_membership[m['id']] ?? const {}).isEmpty)
        .toList();

    // ── Hold-detalje ────────────────────────────────────────────────────────
    if (_teamOpen != null) {
      final isNone = _teamOpen == 'none';
      final g = isNone
          ? null
          : _groups.firstWhere((g) => g['id'] == _teamOpen,
              orElse: () => const {});
      final teamMembers = isNone
          ? noTeam
          : _members
              .where((m) => (_membership[m['id']] ?? const {})
                  .contains(_teamOpen))
              .toList();
      final dotColor =
          isNone ? _gold : _groupHex(g?['farve'] as String?);
      final name = isNone ? 'Uden hold' : (g?['navn'] as String? ?? '');
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            InkWell(
              onTap: () => setState(() => _teamOpen = null),
              borderRadius: BorderRadius.circular(8),
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(Icons.chevron_left, color: _textSecondary),
              ),
            ),
            const SizedBox(width: 4),
            Container(
              width: 11, height: 11,
              decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(name.toUpperCase(),
                  style: _cond(size: 17, weight: FontWeight.w800)),
            ),
            Text('${teamMembers.length} spillere',
                style: _body(size: 12, color: _textSecondary)),
            if (!isNone && widget.isAdmin && g != null) ...[
              IconButton(
                onPressed: () => _editHold(g),
                icon: const Icon(Icons.edit_outlined, size: 18, color: _textMuted),
                visualDensity: VisualDensity.compact,
                tooltip: 'Redigér hold',
              ),
              IconButton(
                onPressed: () => _deleteHold(g),
                icon: const Icon(Icons.delete_outline, size: 18, color: _textMuted),
                visualDensity: VisualDensity.compact,
                tooltip: 'Slet hold',
              ),
            ],
          ]),
          const SizedBox(height: 14),
          _listCard(teamMembers),
        ],
      );
    }

    // ── Liste (faner) ─────────────────────────────────────────────────────────
    final filtered = _tab == 'medlemmer'
        ? (_search.trim().isEmpty
            ? _members
            : _members
                .where((m) => (m['navn'] as String? ?? '')
                    .toLowerCase()
                    .contains(_search.trim().toLowerCase()))
                .toList())
        : _members;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _segTabs(),
        const SizedBox(height: 16),
        if (_tab == 'medlemmer') ...[
          // Søgefelt
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 2),
            decoration: BoxDecoration(
              color: _surfaceElevated,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _borderSubtle),
            ),
            child: Row(children: [
              const Icon(Icons.search, size: 16, color: _textMuted),
              const SizedBox(width: 9),
              Expanded(
                child: TextField(
                  onChanged: (v) => setState(() => _search = v),
                  style: _body(size: 14),
                  decoration: InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    hintText: 'Søg medlem…',
                    hintStyle: _body(size: 14, color: _textMuted),
                  ),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 14),
          _goldCard(noTeam.length),
          _listCard(filtered),
        ] else ...[
          // Hold-faner: hold-kort → detalje
          for (final g in _groups) ...[
            InkWell(
              onTap: () => setState(() => _teamOpen = g['id'] as String),
              borderRadius: BorderRadius.circular(14),
              child: Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _surfaceDark,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _borderSubtle),
                ),
                child: Row(children: [
                  Container(
                    width: 11, height: 11,
                    decoration: BoxDecoration(
                        color: _groupHex(g['farve'] as String?),
                        shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(g['navn'] as String,
                            style: _body(size: 14.5, weight: FontWeight.w700)),
                        Text(
                            '${_members.where((m) => (_membership[m['id']] ?? const {}).contains(g['id'])).length} spillere',
                            style: _body(size: 11.5, color: _textSecondary)),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right, size: 16, color: _textMuted),
                ]),
              ),
            ),
          ],
          // Nyt hold
          InkWell(
            onTap: _newHold,
            borderRadius: BorderRadius.circular(13),
            child: Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.symmetric(vertical: 13),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(13),
                border: Border.all(
                    color: _neon.withValues(alpha: 0.5),
                    style: BorderStyle.solid),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.add, size: 16, color: _neon),
                const SizedBox(width: 8),
                Text('Nyt hold',
                    style: _body(size: 13.5, weight: FontWeight.w700, color: _neon)),
              ]),
            ),
          ),
          _goldCard(noTeam.length),
        ],
      ],
    );
  }
}

/// Medlems-sheet — navn, rolle, hold (+ kaptajn), nulstil kodeord, slet.
class _MemberSheet extends StatefulWidget {
  final Map<String, dynamic> profile;
  final bool isMe;
  final bool isAdmin;
  final List<Map<String, dynamic>> groups;
  final Set<String> memberGids;
  final Set<String> captainGids;
  final int skyldigtOere;
  final Future<void> Function(String userId, String newRole) onChangeRole;
  const _MemberSheet({
    required this.profile,
    required this.isMe,
    required this.isAdmin,
    required this.groups,
    required this.memberGids,
    required this.captainGids,
    required this.skyldigtOere,
    required this.onChangeRole,
  });
  @override
  State<_MemberSheet> createState() => _MemberSheetState();
}

class _MemberSheetState extends State<_MemberSheet> {
  late final TextEditingController _navn =
      TextEditingController(text: widget.profile['navn'] as String? ?? '');
  late String _rolle = widget.profile['rolle'] as String? ?? 'medlem';
  late final Set<String> _teams = {...widget.memberGids};
  late final Set<String> _caps = {...widget.captainGids};
  bool _saving = false;
  bool _sendingReset = false;

  String get _id => widget.profile['id'] as String;
  String? get _email => widget.profile['email'] as String?;

  @override
  void dispose() {
    _navn.dispose();
    super.dispose();
  }

  Future<void> _sendReset() async {
    final email = _email;
    if (email == null || email.isEmpty) {
      _snack(context, 'Medlemmet har ingen e-mail registreret', _gold);
      return;
    }
    setState(() => _sendingReset = true);
    try {
      await supabase.auth.resetPasswordForEmail(email,
          redirectTo: _passwordResetRedirect);
      if (mounted) _snack(context, 'Nulstil-mail sendt til $email', _success);
    } on AuthException catch (e) {
      if (mounted) _snack(context, e.message, _danger);
    } catch (e) {
      if (mounted) _snack(context, 'Kunne ikke sende mail: $e', _danger);
    } finally {
      if (mounted) setState(() => _sendingReset = false);
    }
  }

  Future<void> _save() async {
    final navn = _navn.text.trim();
    if (navn.isEmpty) {
      _snack(context, 'Navn må ikke være tomt', _gold);
      return;
    }
    setState(() => _saving = true);
    try {
      final origNavn = widget.profile['navn'] as String? ?? '';
      final origRolle = widget.profile['rolle'] as String? ?? 'medlem';
      if (navn != origNavn) {
        await supabase.from('profiles').update({'navn': navn}).eq('id', _id);
      }
      if (!widget.isMe && _rolle != origRolle) {
        await widget.onChangeRole(_id, _rolle);
      }
      // Hold-diffs
      final added = _teams.difference(widget.memberGids);
      final removed = widget.memberGids.difference(_teams);
      for (final gid in added) {
        await supabase.from('group_members').insert({
          'group_id': gid,
          'user_id': _id,
          'is_captain': _caps.contains(gid),
        });
      }
      for (final gid in removed) {
        await supabase
            .from('group_members')
            .delete()
            .eq('group_id', gid)
            .eq('user_id', _id);
      }
      // Kaptajn-diffs på hold der bevares
      for (final gid in _teams.intersection(widget.memberGids)) {
        final want = _caps.contains(gid);
        if (want != widget.captainGids.contains(gid)) {
          await supabase
              .from('group_members')
              .update({'is_captain': want})
              .eq('group_id', gid)
              .eq('user_id', _id);
        }
      }
      if (!mounted) return;
      _snack(context, 'Medlem opdateret', _success);
      Navigator.of(context).pop(true);
    } on PostgrestException catch (e) {
      if (mounted) _snack(context, e.message, _danger);
    } catch (e) {
      if (mounted) _snack(context, 'Kunne ikke gemme: $e', _danger);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final navn = widget.profile['navn'] as String? ?? 'medlemmet';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Fjern $navn?'),
        content: Text(
          'Personen fjernes HELT fra appen — medlemmer, bødekassen, '
          'afstemninger og alle begivenheder. Det kan ikke fortrydes.'
          '${widget.skyldigtOere > 0 ? '\n\n$navn har ${_fmtKr(widget.skyldigtOere)} ubetalt — beløbet slettes med personen.' : ''}',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annullér')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: _danger),
            child: const Text('Ja, fjern'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await supabase.rpc('admin_delete_member', params: {'p_user_id': _id});
      if (!mounted) return;
      _snack(context, '$navn er fjernet', _textSecondary);
      Navigator.of(context).pop(true);
    } on PostgrestException catch (e) {
      if (mounted) _snack(context, e.message, _danger);
    }
  }

  Widget _roleChip(String label, String value) {
    final active = _rolle == value;
    return Expanded(
      child: GestureDetector(
        onTap: widget.isMe ? null : () => setState(() => _rolle = value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(vertical: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? _neon : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(label,
              style: _body(
                  size: 13,
                  weight: FontWeight.w700,
                  color: active ? Colors.white : _textSecondary)),
        ),
      ),
    );
  }

  Widget _teamRow(Map<String, dynamic> g) {
    final gid = g['id'] as String;
    final on = _teams.contains(gid);
    final cap = _caps.contains(gid);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Container(
          width: 10, height: 10,
          decoration: BoxDecoration(
              color: _groupHex(g['farve'] as String?), shape: BoxShape.circle),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(g['navn'] as String,
              style: _body(
                  size: 14,
                  weight: FontWeight.w600,
                  color: on ? _textPrimary : _textSecondary)),
        ),
        // Kaptajn-stjerne (kun når medlemmet er på holdet)
        if (on)
          IconButton(
            onPressed: () => setState(
                () => cap ? _caps.remove(gid) : _caps.add(gid)),
            icon: Icon(cap ? Icons.star : Icons.star_border,
                size: 20, color: cap ? _gold : _textMuted),
            visualDensity: VisualDensity.compact,
            tooltip: cap ? 'Kaptajn' : 'Gør til kaptajn',
          ),
        Switch(
          value: on,
          onChanged: (v) => setState(() {
            if (v) {
              _teams.add(gid);
            } else {
              _teams.remove(gid);
              _caps.remove(gid);
            }
          }),
        ),
      ]),
    );
  }

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
                Expanded(child: Text('REDIGÉR MEDLEM',
                    style: theme.textTheme.titleLarge)),
                IconButton(
                  onPressed: _saving ? null : () => Navigator.of(context).pop(false),
                  icon: const Icon(Icons.close),
                  color: _textSecondary,
                ),
              ]),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: _navn,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Navn',
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                    ),
                    if (_email != null && _email!.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Row(children: [
                        const Icon(Icons.mail_outline, size: 15, color: _textMuted),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(_email!,
                              style: _body(size: 12, color: _textMuted),
                              overflow: TextOverflow.ellipsis),
                        ),
                      ]),
                    ],
                    const SizedBox(height: 20),
                    Text('ROLLE',
                        style: _body(
                            size: 12, weight: FontWeight.w700,
                            color: _textSecondary, spacing: 1)),
                    const SizedBox(height: 8),
                    if (!widget.isAdmin && widget.profile['rolle'] == 'admin')
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: _surfaceElevated,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: _borderSubtle),
                        ),
                        child: Row(children: [
                          const Icon(Icons.shield_outlined,
                              size: 16, color: _textMuted),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text('Admin — kun en anden admin kan ændre '
                                'denne rolle.',
                                style: _body(size: 12, color: _textSecondary)),
                          ),
                        ]),
                      )
                    else
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: _bgBlack,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: _borderSubtle),
                        ),
                        child: Row(children: [
                          _roleChip('Spiller', 'medlem'),
                          _roleChip('Træner', 'træner'),
                          if (widget.isAdmin) _roleChip('Admin', 'admin'),
                        ]),
                      ),
                    if (widget.isMe) ...[
                      const SizedBox(height: 6),
                      Text('Du kan ikke ændre din egen rolle',
                          style: _body(size: 11, color: _textMuted)),
                    ],
                    const SizedBox(height: 20),
                    Text('HOLD',
                        style: _body(
                            size: 12, weight: FontWeight.w700,
                            color: _textSecondary, spacing: 1)),
                    const SizedBox(height: 4),
                    Text('Tænd for de hold personen er på. Stjernen gør '
                        'medlemmet til kaptajn for holdet.',
                        style: _body(size: 11.5, color: _textMuted)),
                    const SizedBox(height: 8),
                    if (widget.groups.isEmpty)
                      Text('Ingen hold oprettet endnu',
                          style: _body(size: 13, color: _textMuted))
                    else
                      for (final g in widget.groups) _teamRow(g),
                    const SizedBox(height: 20),
                    Text('KODEORD',
                        style: _body(
                            size: 12, weight: FontWeight.w700,
                            color: _textSecondary, spacing: 1)),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _sendingReset ? null : _sendReset,
                      icon: _sendingReset
                          ? const SizedBox(width: 16, height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.lock_reset, size: 20),
                      label: Text(_sendingReset
                          ? 'Sender…'
                          : 'Send nulstil-kodeord-mail'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                    if (widget.isAdmin && !widget.isMe) ...[
                      const SizedBox(height: 20),
                      TextButton.icon(
                        onPressed: _delete,
                        icon: const Icon(Icons.delete_outline, size: 20),
                        label: const Text('Fjern medlem fra klubben'),
                        style: TextButton.styleFrom(
                          foregroundColor: _danger,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ],
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
                    onPressed: _saving ? null : () => Navigator.of(context).pop(false),
                    style: TextButton.styleFrom(
                      foregroundColor: _textSecondary,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
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
                        : const Text('Gem'),
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
// Admin: MobilePay-opsætning (kun synlig for admins)
// ─────────────────────────────────────────────────────────────────────────────
class _MobilePayConfigCard extends StatefulWidget {
  const _MobilePayConfigCard();
  @override
  State<_MobilePayConfigCard> createState() => _MobilePayConfigCardState();
}

class _MobilePayConfigCardState extends State<_MobilePayConfigCard> {
  bool _loading = true;
  List<Map<String, dynamic>> _holdGroups = const []; // holdgrupper (fællesskaber)
  List<Map<String, dynamic>> _soloHolds = const [];  // hold uden holdgruppe
  String? _clubBox;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      _clubBox = await ClubConfig.fetchMobilePayBox();
      final res = await Future.wait([
        supabase.from('hold_groups').select('id, navn, mobilepay_box_id').order('created_at'),
        supabase.from('groups').select('id, navn, hold_group_id, mobilepay_box_id').order('sort'),
      ]);
      _holdGroups = List<Map<String, dynamic>>.from(res[0] as List);
      _soloHolds = List<Map<String, dynamic>>.from(res[1] as List)
          .where((h) => h['hold_group_id'] == null)
          .toList();
    } catch (_) {
      _clubBox ??= ClubConfig.cachedBox;
    }
    if (!mounted) return;
    setState(() => _loading = false);
  }

  // scope: 'club' | 'hg:<id>' | 'solo:<id>'
  Future<void> _persist(String scope, String? value) async {
    final v = (value ?? '').trim();
    try {
      if (scope == 'club') {
        await ClubConfig.updateMobilePayBox(v);
        _clubBox = v;
      } else {
        final boxVal = v.isEmpty ? null : v;
        if (scope.startsWith('hg:')) {
          final id = scope.substring(3);
          await supabase.from('hold_groups')
              .update({'mobilepay_box_id': boxVal}).eq('id', id);
          final idx = _holdGroups.indexWhere((e) => e['id'] == id);
          if (idx >= 0) _holdGroups[idx]['mobilepay_box_id'] = boxVal;
        } else {
          final id = scope.substring(5);
          await supabase.from('groups')
              .update({'mobilepay_box_id': boxVal}).eq('id', id);
          final idx = _soloHolds.indexWhere((e) => e['id'] == id);
          if (idx >= 0) _soloHolds[idx]['mobilepay_box_id'] = boxVal;
        }
      }
      if (mounted) {
        _snack(context, 'MobilePay-opsætning gemt ✓', _success);
        setState(() {});
      }
    } on PostgrestException catch (e) {
      if (mounted) _snack(context, 'Kunne ikke gemme: ${e.message}', _danger);
    } catch (e) {
      if (mounted) _snack(context, 'Kunne ikke gemme: $e', _danger);
    }
  }

  Future<void> _editBox({
    required String scope,
    required String name,
    required String current,
    required bool isClub,
  }) async {
    final res = await showModalBottomSheet<String?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _MobilePayBoxSheet(
        name: name,
        current: current,
        isClub: isClub,
      ),
    );
    // null = annulleret. Ellers gem (tom streng = ryd boksen).
    if (res != null) await _persist(scope, res);
  }

  Widget _boxCard({
    required String scope,
    required String name,
    required String? box,
    required bool isClub,
  }) {
    final has = (box ?? '').trim().isNotEmpty;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: () => _editBox(
            scope: scope, name: name, current: box ?? '', isClub: isClub),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _surfaceDark,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _borderSubtle),
          ),
          child: Row(children: [
            Container(
              width: 40, height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: _info.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(11),
              ),
              child: const Icon(Icons.account_balance_wallet_outlined,
                  color: _info, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(name, style: _body(size: 14, weight: FontWeight.w700)),
                  Text(
                    has
                        ? 'MobilePay-boks $box'
                        : (isClub
                            ? 'Ingen fælles boks endnu — tryk for at tilføje'
                            : 'Ingen boks endnu — tryk for at tilføje'),
                    style: _body(
                        size: 11.5, color: has ? _textSecondary : _gold),
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 16, color: _textMuted),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(40),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Text(
            'Hvert hold-fællesskab har sin egen MobilePay-boks. Spillernes '
            'betalinger åbner boksen med beløbet udfyldt.',
            style: _body(size: 12.5, color: _textSecondary, height: 1.5),
          ),
        ),
        for (final g in _holdGroups)
          _boxCard(
            scope: 'hg:${g['id']}',
            name: g['navn'] as String,
            box: g['mobilepay_box_id'] as String?,
            isClub: false,
          ),
        for (final h in _soloHolds)
          _boxCard(
            scope: 'solo:${h['id']}',
            name: h['navn'] as String,
            box: h['mobilepay_box_id'] as String?,
            isClub: false,
          ),
        _boxCard(
          scope: 'club',
          name: 'Fælles (fallback)',
          box: _clubBox,
          isClub: true,
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
          decoration: BoxDecoration(
            color: _neon.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _neon.withValues(alpha: 0.25)),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.info_outline, size: 16, color: _neon),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                'Kun admin kan ændre MobilePay. Når et nyt hold oprettes, står '
                'det her uden boks — du tilføjer boksens link fra MobilePay. '
                '"Fælles" bruges når et fællesskab ikke har sin egen boks.',
                style: _body(size: 12, color: _textSecondary, height: 1.4),
              ),
            ),
          ]),
        ),
      ],
    );
  }
}

/// Bundsheet: redigér MobilePay-boks for ét fællesskab. Returnerer den nye
/// værdi (tom streng = ryd boksen) eller null ved annullering.
class _MobilePayBoxSheet extends StatefulWidget {
  final String name;
  final String current;
  final bool isClub;
  const _MobilePayBoxSheet({
    required this.name,
    required this.current,
    required this.isClub,
  });
  @override
  State<_MobilePayBoxSheet> createState() => _MobilePayBoxSheetState();
}

class _MobilePayBoxSheetState extends State<_MobilePayBoxSheet> {
  late final _ctrl = TextEditingController(text: widget.current);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _save() {
    final v = _ctrl.text.trim();
    if (widget.isClub && v.isEmpty) {
      _snack(context, 'Indtast et Box-ID eller et fuldt MobilePay-link', _gold);
      return;
    }
    Navigator.of(context).pop(v);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
              Text('MOBILEPAY-BOKS',
                  style: _body(
                      size: 12, weight: FontWeight.w700,
                      color: _textSecondary, spacing: 1)),
              const SizedBox(height: 4),
              Text(widget.name,
                  style: theme.textTheme.titleLarge),
              const SizedBox(height: 14),
              TextField(
                controller: _ctrl,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'Box-ID eller fuldt Box-link',
                  prefixIcon: const Icon(Icons.qr_code_2_outlined),
                  hintText: 'fx 1234567  ·  eller  https://qr.mobilepay.dk/box/…',
                  helperText: widget.isClub
                      ? 'Fælles boks — bruges når fællesskabet ikke har sin egen'
                      : 'Tom = fællesskabet bruger den fælles boks',
                ),
                onSubmitted: (_) => _save(),
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
                    onPressed: _save,
                    style: FilledButton.styleFrom(backgroundColor: _info),
                    child: const Text('Gem boks'),
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

/// Admin: vælg hvilken bødetype der bruges som udeblivelses-bøde + til/fra for
/// automatisk opkrævning ved sent afbud (4c).
class _NoShowFineCard extends StatefulWidget {
  final List<Map<String, dynamic>> fineTypes;
  const _NoShowFineCard({required this.fineTypes});
  @override
  State<_NoShowFineCard> createState() => _NoShowFineCardState();
}

class _NoShowFineCardState extends State<_NoShowFineCard> {
  bool _loading = true;
  bool _saving = false;
  bool _auto = false;
  String? _typeId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final c = await ClubConfig.fetchNoShowConfig();
    if (!mounted) return;
    setState(() {
      // Behold kun typen hvis den stadig findes/aktiv.
      _typeId = widget.fineTypes.any((t) => t['id'] == c.fineTypeId)
          ? c.fineTypeId
          : null;
      _auto = c.autoEnabled;
      _loading = false;
    });
  }

  Future<void> _save() async {
    if (_auto && _typeId == null) {
      _snack(context, 'Vælg en bødetype før automatisk opkrævning kan slås til',
          _gold);
      return;
    }
    setState(() => _saving = true);
    try {
      await ClubConfig.updateNoShowConfig(fineTypeId: _typeId, autoEnabled: _auto);
      if (mounted) _snack(context, 'Udeblivelses-bøde gemt ✓', _success);
    } on PostgrestException catch (e) {
      if (mounted) _snack(context, 'Kunne ikke gemme: ${e.message}', _danger);
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
            Row(children: [
              const Icon(Icons.event_busy_outlined, color: _gold),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Udeblivelses-bøde',
                    style: theme.textTheme.titleMedium),
              ),
            ]),
            const SizedBox(height: 6),
            Text(
              'Vælg hvilken bødetype der uddeles ved udeblivelse og sent afbud. '
              'Bruges af "Hvem mødte ikke op?"-tjekket og (hvis slået til) '
              'automatisk når nogen melder afbud efter fristen.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 14),
            if (_loading)
              const Padding(padding: EdgeInsets.all(8),
                  child: Center(child: CircularProgressIndicator()))
            else if (widget.fineTypes.isEmpty)
              Text('Opret en bødetype først (ovenfor).',
                  style: _body(size: 13, color: _textMuted))
            else ...[
              DropdownButtonFormField<String?>(
                value: _typeId,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Bødetype',
                  prefixIcon: Icon(Icons.gavel),
                ),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('— Ingen valgt —',
                        style: TextStyle(fontStyle: FontStyle.italic)),
                  ),
                  for (final t in widget.fineTypes)
                    DropdownMenuItem<String?>(
                      value: t['id'] as String,
                      child: Text(
                          '${t['titel']} · ${_fmtKr((t['belob_oere'] as num).toInt())}',
                          overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (v) => setState(() => _typeId = v),
              ),
              const SizedBox(height: 6),
              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: _borderSubtle),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: SwitchListTile(
                  value: _auto,
                  onChanged: (v) => setState(() => _auto = v),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                  title: const Text('Opkræv automatisk ved sent afbud'),
                  subtitle: Text(
                    _auto
                        ? 'Melder en spiller afbud efter fristen, uddeles bøden med det samme.'
                        : 'Fra: sent afbud koster ikke automatisk en bøde.',
                    style: _body(size: 11.5, color: _textSecondary),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(width: 16, height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.save_outlined),
                  label: const Text('Gem'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Bøde-cards (inline i Dashboard) + GiveFineDialog (Ctrl+K version)
// ─────────────────────────────────────────────────────────────────────────────

class _PendingFinesCard extends StatelessWidget {
  final List<Map<String, dynamic>> fines;
  final Future<void> Function(String fineId) onApprove;
  final Future<void> Function(String fineId) onDelete;
  const _PendingFinesCard({
    required this.fines,
    required this.onApprove,
    required this.onDelete,
  });

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
                      IconButton(
                        onPressed: () => onDelete(f['id'] as String),
                        icon: const Icon(Icons.delete_outline, size: 20, color: _danger),
                        tooltip: 'Slet bøde (givet forkert)',
                        visualDensity: VisualDensity.compact,
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
  String? _busyId; // id på den type der lige nu slettes (spinner)
  List<Map<String, dynamic>> _holdGroups = const [];
  List<Map<String, dynamic>> _soloHolds = const [];
  String _scope = 'club'; // 'club' | 'hg:<id>' | 'solo:<id>'

  @override
  void initState() {
    super.initState();
    _loadScopes();
  }

  Future<void> _loadScopes() async {
    try {
      final res = await Future.wait([
        supabase.from('hold_groups').select('id, navn').order('created_at'),
        supabase.from('groups').select('id, navn, hold_group_id').order('sort'),
      ]);
      if (!mounted) return;
      setState(() {
        _holdGroups = List<Map<String, dynamic>>.from(res[0] as List);
        _soloHolds = List<Map<String, dynamic>>.from(res[1] as List)
            .where((h) => h['hold_group_id'] == null)
            .toList();
      });
    } catch (_) {}
  }

  bool _matchesScope(Map<String, dynamic> t) {
    if (_scope == 'club') {
      return t['hold_group_id'] == null && t['group_id'] == null;
    }
    if (_scope.startsWith('hg:')) {
      return t['hold_group_id'] == _scope.substring(3);
    }
    return t['group_id'] == _scope.substring(5);
  }

  Map<String, dynamic> _scopeOwner() {
    if (_scope.startsWith('hg:')) {
      return {'hold_group_id': _scope.substring(3), 'group_id': null};
    }
    if (_scope.startsWith('solo:')) {
      return {'hold_group_id': null, 'group_id': _scope.substring(5)};
    }
    return {'hold_group_id': null, 'group_id': null};
  }

  /// Opret eller redigér via dialog.
  Future<void> _openEditor({Map<String, dynamic>? existing}) async {
    final result = await showDialog<({String titel, int kr})>(
      context: context,
      builder: (_) => _FineTypeDialog(existing: existing),
    );
    if (result == null) return;
    try {
      if (existing == null) {
        await supabase.from('fine_types').insert({
          'titel':      result.titel,
          'belob_oere': result.kr * 100,
          ..._scopeOwner(),
        });
        if (mounted) _snack(context, 'Bødetype "${result.titel}" oprettet', _success);
      } else {
        await supabase.from('fine_types').update({
          'titel':      result.titel,
          'belob_oere': result.kr * 100,
        }).eq('id', existing['id']);
        if (mounted) _snack(context, 'Bødetype opdateret', _success);
      }
      widget.onCreated();
    } on PostgrestException catch (e) {
      if (mounted) _snack(context, e.message, _danger);
    }
  }

  Future<void> _delete(Map<String, dynamic> type) async {
    final titel = type['titel'] as String;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Slet bødetype?'),
        content: Text('"$titel" fjernes fra listen. Allerede uddelte bøder '
            'påvirkes ikke.'),
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
    setState(() => _busyId = type['id'] as String);
    try {
      await supabase.from('fine_types').delete().eq('id', type['id']);
      if (mounted) _snack(context, 'Bødetype slettet', _textSecondary);
      widget.onCreated();
    } on PostgrestException {
      // Typisk FK-fejl hvis typen er i brug på eksisterende bøder.
      if (mounted) {
        _snack(context,
            'Kunne ikke slette "$titel" — den er sandsynligvis i brug på '
            'eksisterende bøder.',
            _danger);
      }
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final types = widget.existingTypes.where(_matchesScope).toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.style_outlined, color: _neon),
                const SizedBox(width: 8),
                Text('Bødetyper', style: theme.textTheme.titleMedium),
                const Spacer(),
                Text('${types.length} ${types.length == 1 ? "type" : "typer"}',
                    style: _body(size: 12, color: _textSecondary)),
              ],
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _scope,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Gælder for',
                prefixIcon: Icon(Icons.layers_outlined),
              ),
              items: [
                const DropdownMenuItem(value: 'club', child: Text('Fælles – alle hold')),
                for (final g in _holdGroups)
                  DropdownMenuItem(value: 'hg:${g['id']}', child: Text(g['navn'] as String)),
                for (final h in _soloHolds)
                  DropdownMenuItem(
                      value: 'solo:${h['id']}',
                      child: Text('${h['navn']} · selvstændigt')),
              ],
              onChanged: (v) => setState(() => _scope = v ?? 'club'),
            ),
            const SizedBox(height: 12),
            if (types.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text('Ingen bødetyper endnu — opret den første nedenfor.',
                    style: _body(size: 13, color: _textMuted)),
              )
            else
              Container(
                decoration: BoxDecoration(
                  color: _bgBlack,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _borderSubtle),
                ),
                child: Column(
                  children: [
                    for (var i = 0; i < types.length; i++)
                      _FineTypeRow(
                        type: types[i],
                        isFirst: i == 0,
                        deleting: _busyId == types[i]['id'],
                        onEdit: () => _openEditor(existing: types[i]),
                        onDelete: () => _delete(types[i]),
                      ),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _openEditor(),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Ny bødetype'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Én bødetype i listen — titel, beløb, redigér og slet.
class _FineTypeRow extends StatelessWidget {
  final Map<String, dynamic> type;
  final bool isFirst;
  final bool deleting;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  const _FineTypeRow({
    required this.type,
    required this.isFirst,
    required this.deleting,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final titel = type['titel'] as String;
    final oere  = (type['belob_oere'] as num).toInt();
    return Container(
      decoration: BoxDecoration(
        border: Border(
          top: isFirst
              ? BorderSide.none
              : const BorderSide(color: _borderSubtle),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
      child: Row(
        children: [
          Expanded(
            child: Text(titel,
                style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
                maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(width: 8),
          Text(_fmtKr(oere),
              style: _cond(size: 17, weight: FontWeight.w800, color: _neon)),
          const SizedBox(width: 4),
          IconButton(
            onPressed: onEdit,
            icon: const Icon(Icons.edit_outlined, size: 19),
            tooltip: 'Redigér',
            color: _textSecondary,
            visualDensity: VisualDensity.compact,
          ),
          deleting
              ? const Padding(
                  padding: EdgeInsets.all(10),
                  child: SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: _danger)),
                )
              : IconButton(
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline, size: 19),
                  tooltip: 'Slet',
                  color: _danger,
                  visualDensity: VisualDensity.compact,
                ),
        ],
      ),
    );
  }
}

/// Dialog til at oprette/redigere en bødetype.
class _FineTypeDialog extends StatefulWidget {
  final Map<String, dynamic>? existing;
  const _FineTypeDialog({this.existing});
  @override
  State<_FineTypeDialog> createState() => _FineTypeDialogState();
}

class _FineTypeDialogState extends State<_FineTypeDialog> {
  late final TextEditingController _titel;
  late final TextEditingController _krCtrl;

  @override
  void initState() {
    super.initState();
    _titel = TextEditingController(text: widget.existing?['titel'] as String? ?? '');
    final oere = (widget.existing?['belob_oere'] as num?)?.toInt();
    _krCtrl = TextEditingController(text: oere == null ? '' : '${oere ~/ 100}');
  }

  @override
  void dispose() {
    _titel.dispose();
    _krCtrl.dispose();
    super.dispose();
  }

  void _save() {
    final titel = _titel.text.trim();
    final kr = int.tryParse(_krCtrl.text.trim());
    if (titel.isEmpty || kr == null || kr <= 0) {
      _snack(context, 'Indtast titel og beløb i hele kroner', _gold);
      return;
    }
    Navigator.pop(context, (titel: titel, kr: kr));
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    return AlertDialog(
      title: Text(isEdit ? 'Redigér bødetype' : 'Ny bødetype'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _titel,
            autofocus: true,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'Titel',
              hintText: 'F.eks. "Hul i battet"',
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _krCtrl,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _save(),
            decoration: const InputDecoration(
              labelText: 'Beløb',
              hintText: '100',
              suffixText: 'kr',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annullér')),
        FilledButton(
          onPressed: _save,
          child: Text(isEdit ? 'Gem' : 'Opret'),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// GiveFineDialog — Ctrl+K lyn-formular (selvloadende)
// ─────────────────────────────────────────────────────────────────────────────

/// Map: spiller-id → sæt af fællesskabs-nøgler (`hg:<id>` / `solo:<group_id>`).
Future<Map<String, Set<String>>> _loadPlayerCommunities() async {
  final res = await Future.wait([
    supabase.from('group_members').select('user_id, group_id'),
    supabase.from('groups').select('id, hold_group_id'),
  ]);
  final holdGroupOf = {
    for (final g in List<Map<String, dynamic>>.from(res[1] as List))
      g['id'] as String: g['hold_group_id'] as String?
  };
  final map = <String, Set<String>>{};
  for (final r in List<Map<String, dynamic>>.from(res[0] as List)) {
    final uid = r['user_id'] as String;
    final gid = r['group_id'] as String;
    final hg = holdGroupOf[gid];
    (map[uid] ??= {}).add(hg != null ? 'hg:$hg' : 'solo:$gid');
  }
  return map;
}

/// Bødetyper der gælder en spiller: fælles (begge null) + spillerens fællesskaber.
List<Map<String, dynamic>> _typesForCommunities(
    List<Map<String, dynamic>> types, Set<String> comms) {
  return types.where((t) {
    final hg = t['hold_group_id'] as String?;
    final gid = t['group_id'] as String?;
    if (hg == null && gid == null) return true;
    if (hg != null) return comms.contains('hg:$hg');
    return comms.contains('solo:$gid');
  }).toList();
}

class GiveFineDialog extends StatefulWidget {
  // Fuld admin ser alle spillere; en bøde-admin ser kun sit/sine holds spillere.
  final bool isFullAdmin;
  const GiveFineDialog({super.key, this.isFullAdmin = true});
  @override
  State<GiveFineDialog> createState() => _GiveFineDialogState();
}

class _GiveFineDialogState extends State<GiveFineDialog> {
  List<Map<String, dynamic>> _profiles = const [];
  List<Map<String, dynamic>> _fineTypes = const [];
  Map<String, Set<String>> _communities = {};
  String? _userId;
  String? _typeId;
  final _begrundelse = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  String? _error;

  /// Bødetyper der gælder den valgte spiller (fælles + spillerens fællesskaber).
  List<Map<String, dynamic>> get _typesForSelected => _userId == null
      ? _fineTypes.where((t) =>
          t['hold_group_id'] == null && t['group_id'] == null).toList()
      : _typesForCommunities(_fineTypes, _communities[_userId] ?? const {});

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
            .select('id, titel, belob_oere, hold_group_id, group_id')
            .eq('aktiv', true)
            .order('titel'),
      ]);
      _communities = await _loadPlayerCommunities();
      var profiles = List<Map<String, dynamic>>.from(results[0] as List);

      // Kaptajn (ikke staff): begræns til spillere på de hold hvor brugeren
      // er kaptajn.
      if (!widget.isFullAdmin) {
        final uid = supabase.auth.currentUser!.id;
        final myCap = await supabase
            .from('group_members')
            .select('group_id')
            .eq('user_id', uid)
            .eq('is_captain', true);
        final gids = List<Map<String, dynamic>>.from(myCap as List)
            .map((r) => r['group_id'] as String)
            .toList();
        final allowed = <String>{};
        if (gids.isNotEmpty) {
          final mem = await supabase
              .from('group_members')
              .select('user_id')
              .inFilter('group_id', gids);
          for (final r in List<Map<String, dynamic>>.from(mem as List)) {
            allowed.add(r['user_id'] as String);
          }
        }
        profiles = profiles
            .where((p) => allowed.contains(p['id'] as String))
            .toList();
      }

      setState(() {
        _profiles  = profiles;
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
                          onChanged: (v) => setState(() {
                            _userId = v;
                            // Nulstil valgt type hvis den ikke gælder spilleren.
                            if (!_typesForSelected
                                .any((t) => t['id'] == _typeId)) {
                              _typeId = null;
                            }
                          }),
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          value: _typeId,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Bødetype',
                            prefixIcon: Icon(Icons.gavel),
                          ),
                          items: _typesForSelected.map((t) => DropdownMenuItem<String>(
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

  DateTime? _dato;   // begivenhedens dato
  TimeOfDay? _fra;   // fra-tid (påkrævet)
  TimeOfDay? _til;   // til-tid (valgfri)
  // Tilmeldingsfrist som antal dage FØR hver begivenhed (relativ, så den
  // følger med i en serie). null = ingen frist (åben til begivenheden starter).
  int? _deadlineDaysBefore;
  // Synlighed: antal dage FØR hver begivenhed den bliver synlig for spillere.
  // null = straks synlig. Bruges især til serier, så spillerne ikke ser 15
  // aktiviteter på én gang.
  int? _visibleDaysBefore;

  static DateTime _combine(DateTime d, TimeOfDay t) =>
      DateTime(d.year, d.month, d.day, t.hour, t.minute);

  Widget _dateField() {
    return InkWell(
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
  }

  Widget _timeField(String label, TimeOfDay? value, ValueChanged<TimeOfDay?> onChanged) {
    return InkWell(
      onTap: () async {
        final t = await _showQuickTimePicker(context, value);
        if (t != null) onChanged(t);
      },
      borderRadius: BorderRadius.circular(11),
      child: InputDecorator(
        decoration: InputDecoration(
            labelText: label, prefixIcon: const Icon(Icons.schedule, size: 18)),
        child: Text(
          value == null
              ? 'Vælg tid'
              : '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}',
          style: TextStyle(
              color: value == null ? _textMuted : _neon,
              fontWeight: FontWeight.w700,
              letterSpacing: value == null ? 0 : 1.2),
        ),
      ),
    );
  }
  bool _recurring = false;
  bool _saving = false;
  List<Map<String, dynamic>> _groups = const [];
  // Valgte hold. Tom = alle hold (fælles). Kan indeholde ét eller flere hold.
  final Set<String> _groupIds = {};

  @override
  void initState() {
    super.initState();
    _weeksCtrl.addListener(() {
      if (mounted) setState(() {});
    });
    _loadGroups();
  }

  Future<void> _loadGroups() async {
    try {
      final userId = supabase.auth.currentUser!.id;
      final results = await Future.wait([
        supabase.from('groups').select('id, navn, type, farve, sort').order('sort'),
        supabase.from('group_members').select('group_id').eq('user_id', userId),
      ]);
      if (!mounted) return;
      final groups = List<Map<String, dynamic>>.from(results[0] as List);
      final myIds = List<Map<String, dynamic>>.from(results[1] as List)
          .map((r) => r['group_id'] as String)
          .toSet();
      setState(() {
        _groups = groups;
        // Forudvælg trænerens hold hvis de kun er på ét (kan stadig ændres).
        if (_groupIds.isEmpty && myIds.length == 1) {
          final only = myIds.first;
          if (groups.any((g) => g['id'] == only)) _groupIds.add(only);
        }
      });
    } catch (_) {}
  }

  /// Fler-vælger: "Alle" (id == null) rydder valget; hvert hold slår til/fra.
  Widget _groupChip(String label, String? id) {
    final active = id == null ? _groupIds.isEmpty : _groupIds.contains(id);
    return GestureDetector(
      onTap: () => setState(() {
        if (id == null) {
          _groupIds.clear();
        } else {
          if (!_groupIds.add(id)) _groupIds.remove(id);
        }
      }),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: active ? _neon : _surfaceElevated,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: active ? _neon : _borderSubtle),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (active && id != null) ...[
              const Icon(Icons.check, size: 15, color: Colors.white),
              const SizedBox(width: 5),
            ],
            Text(label,
                style: _body(
                    size: 13,
                    weight: FontWeight.w600,
                    color: active ? Colors.white : _textPrimary)),
          ],
        ),
      ),
    );
  }

  Widget _deadlineChip(String label, int? daysBefore) {
    final active = _deadlineDaysBefore == daysBefore;
    return GestureDetector(
      onTap: () => setState(() => _deadlineDaysBefore = daysBefore),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: active ? _neon : _surfaceElevated,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: active ? _neon : _borderSubtle),
        ),
        child: Text(label,
            style: _body(
                size: 13,
                weight: FontWeight.w600,
                color: active ? Colors.white : _textPrimary)),
      ),
    );
  }

  Widget _visibleChip(String label, int? daysBefore) {
    final active = _visibleDaysBefore == daysBefore;
    return GestureDetector(
      onTap: () => setState(() => _visibleDaysBefore = daysBefore),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: active ? _neon : _surfaceElevated,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: active ? _neon : _borderSubtle),
        ),
        child: Text(label,
            style: _body(
                size: 13,
                weight: FontWeight.w600,
                color: active ? Colors.white : _textPrimary)),
      ),
    );
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
    required DateTime? synligFra,
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
      'synlig_fra':           synligFra?.toUtc().toIso8601String(),
      'created_by':           userId,
      // Flere hold gemmes i group_ids. group_id holdes i sync (ét hold → dét,
      // ellers null) af hensyn til ældre kode der stadig læser group_id.
      'group_ids':            _groupIds.isEmpty ? null : _groupIds.toList(),
      'group_id':             _groupIds.length == 1 ? _groupIds.first : null,
    };
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_dato == null || _fra == null) {
      _snack(context, 'Vælg dato og fra-tid', Colors.orange);
      return;
    }
    final start = _combine(_dato!, _fra!);
    // Til-tid er valgfri: hvis den ikke er sat, bruges fra + 1,5 time.
    final effectiveSlut =
        _til != null ? _combine(_dato!, _til!) : start.add(const Duration(minutes: 90));
    if (!effectiveSlut.isAfter(start)) {
      _snack(context, 'Til-tid skal være efter fra-tid', Colors.orange);
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
      final evStart = start.add(delta);
      // Fristen er relativ til HVER begivenheds dato: X dage før start.
      // null = ingen frist → åben til begivenheden begynder (= start).
      final deadline = _deadlineDaysBefore == null
          ? evStart
          : evStart.subtract(Duration(days: _deadlineDaysBefore!));
      // Synlighed: bliver synlig X dage før hver begivenhed.
      // null = straks synlig.
      final synligFra = _visibleDaysBefore == null
          ? null
          : evStart.subtract(Duration(days: _visibleDaysBefore!));
      return _buildRow(
        start:    evStart,
        slut:     effectiveSlut.add(delta),
        deadline: deadline,
        synligFra: synligFra,
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
                Expanded(child: Text('OPRET BEGIVENHED',
                    style: theme.textTheme.titleLarge)),
                IconButton(
                  onPressed: _saving ? null : () => Navigator.of(context).pop(false),
                  icon: const Icon(Icons.close),
                  color: _textSecondary,
                ),
              ]),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                if (_groups.isNotEmpty) ...[
                  Row(children: [
                    Text('Hvem kan deltage?',
                        style: _body(
                            size: 13, weight: FontWeight.w600, color: _textSecondary)),
                    const SizedBox(width: 6),
                    Text('vælg ét eller flere hold',
                        style: _body(size: 11, color: _textMuted)),
                  ]),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8, runSpacing: 8,
                    children: [
                      _groupChip('Alle', null),
                      for (final g in _groups)
                        _groupChip(g['navn'] as String, g['id'] as String),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],
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
                _fieldGroup('TILMELDINGSFRIST · valgfri', [
                  Wrap(
                    spacing: 8, runSpacing: 8,
                    children: [
                      _deadlineChip('Ingen frist', null),
                      _deadlineChip('På dagen', 0),
                      _deadlineChip('1 dag før', 1),
                      _deadlineChip('2 dage før', 2),
                      _deadlineChip('3 dage før', 3),
                      _deadlineChip('1 uge før', 7),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 8, left: 2),
                    child: Text(
                      _deadlineDaysBefore == null
                          ? 'Åben til begivenheden begynder'
                          : _deadlineDaysBefore == 0
                              ? 'Tilmelding lukker samme dag kl. '
                                  '${_fra == null ? "start" : "${_fra!.hour.toString().padLeft(2, '0')}:${_fra!.minute.toString().padLeft(2, '0')}"}'
                              : 'Tilmelding lukker $_deadlineDaysBefore '
                                  '${_deadlineDaysBefore == 1 ? "dag" : "dage"} før hver '
                                  'begivenhed',
                      style: const TextStyle(color: _textMuted, fontSize: 11),
                    ),
                  ),
                ]),
                const SizedBox(height: 16),
                _fieldGroup('VIS FOR SPILLERE · valgfri', [
                  Wrap(
                    spacing: 8, runSpacing: 8,
                    children: [
                      _visibleChip('Straks', null),
                      _visibleChip('1 uge før', 7),
                      _visibleChip('2 uger før', 14),
                      _visibleChip('3 uger før', 21),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 8, left: 2),
                    child: Text(
                      _visibleDaysBefore == null
                          ? 'Aktiviteten er synlig for spillerne med det samme'
                          : 'Hver aktivitet dukker først op hos spillerne '
                              '${_visibleDaysBefore! ~/ 7} '
                              '${_visibleDaysBefore == 7 ? "uge" : "uger"} før — '
                              'så de ikke ser hele serien på én gang',
                      style: const TextStyle(color: _textMuted, fontSize: 11),
                    ),
                  ),
                ]),
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
                                  _dato == null
                                      ? 'Vælg dato for at se serie'
                                      : 'Opretter $_plannedWeeks begivenheder — '
                                        'fra ${_fmtDate(_dato!)} til '
                                        '${_fmtDate(_dato!.add(Duration(days: 7 * (_plannedWeeks - 1))))}',
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
                    ],
                  ),
                ),
              ),
            ),
            // Sticky footer
            Container(
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: _borderSubtle)),
              ),
              padding: EdgeInsets.fromLTRB(
                  16, 12, 16, 12 + MediaQuery.of(context).padding.bottom),
              child: Row(children: [
                Expanded(
                  child: TextButton(
                    onPressed: _saving ? null : () => Navigator.of(context).pop(false),
                    style: TextButton.styleFrom(
                      foregroundColor: _textSecondary,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
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
                        : Text(_recurring ? 'Opret serie' : 'Opret'),
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
// Create poll dialog (Fase 3)
// ─────────────────────────────────────────────────────────────────────────────

