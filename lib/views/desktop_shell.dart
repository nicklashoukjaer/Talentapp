// Auto-split (del af biblioteket padel_app)
// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
part of '../main.dart';

// ─────────────────────────────────────────────────────────────────────────────
// PC-stellet: fast sidebar + topbar.
//
// Bruges kun når [isDesktop] er sand. Mobilen (og 700–1100 px) rammer aldrig
// denne fil — den gamle NavigationRail/BottomNav bliver stående som den er.
// ─────────────────────────────────────────────────────────────────────────────

typedef _NavItem = ({IconData icon, IconData selectedIcon, String label});

class _DesktopShell extends StatelessWidget {
  const _DesktopShell({
    required this.navItems,
    required this.selectedIndex,
    required this.onSelect,
    required this.titel,
    required this.child,
    required this.onLogout,
    required this.onOpenPalette,
    this.topbarMidt = const SizedBox.shrink(),
    this.topbarHandlinger = const <Widget>[],
    this.bell,
    this.holdFilter,
  });

  final List<_NavItem> navItems;
  final int selectedIndex;
  final ValueChanged<int> onSelect;

  /// Skærmens titel i topbaren.
  final String titel;

  /// Fane-specifikke kontroller lige efter titlen (fx Alle/Træninger/Kampe).
  final Widget topbarMidt;

  /// Fanens egne handlinger yderst til højre (fx "Opret begivenhed").
  final List<Widget> topbarHandlinger;

  /// Klokken — samme widget som mobilens, bare placeret i topbaren.
  final Widget? bell;

  final Widget child;
  final VoidCallback onLogout;
  final VoidCallback onOpenPalette;

  /// Den aktive fanes hold-filter. Null → afsnittet udelades helt.
  final ValueListenable<HoldFilterModel?>? holdFilter;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sidebar(context),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                height: kTopbarHeight,
                color: _header,
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Row(children: [
                  Text(titel.toUpperCase(),
                      style: _cond(size: 22, weight: FontWeight.w800)),
                  const SizedBox(width: 16),
                  Flexible(child: topbarMidt),
                  const Spacer(),
                  _CtrlKKnap(onTap: onOpenPalette),
                  const SizedBox(width: 12),
                  ?bell,
                  for (final h in topbarHandlinger) ...[
                    const SizedBox(width: 10),
                    h,
                  ],
                ]),
              ),
              const Divider(height: 1, thickness: 1, color: _borderSubtle),
              Expanded(child: child),
            ],
          ),
        ),
      ],
    );
  }

  Widget _sidebar(BuildContext context) {
    return Container(
      width: kSidebarWidth,
      color: _header,
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 6),
            child: Text('DE TALENTLØSE',
                style: TextStyle(
                    fontFamily: 'BarlowCondensed',
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 2,
                    color: _textPrimary)),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Text('HJØRRING',
                style: TextStyle(
                    fontFamily: 'BarlowCondensed',
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 3,
                    color: _neon)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < navItems.length; i++)
                  _navRow(navItems[i], i == selectedIndex, () => onSelect(i)),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              child: holdFilter == null
                  ? const SizedBox.shrink()
                  : ValueListenableBuilder<HoldFilterModel?>(
                      valueListenable: holdFilter!,
                      builder: (_, f, __) => _filterBlok(f),
                    ),
            ),
          ),
          const Divider(height: 1, thickness: 1, color: _borderSubtle),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: _plainRow(Icons.logout, 'Log ud', onLogout),
          ),
        ],
      ),
    );
  }

  Widget _navRow(_NavItem n, bool active, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: active ? _neon.withValues(alpha: 0.14) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            child: Row(children: [
              Icon(active ? n.selectedIcon : n.icon,
                  size: 22, color: active ? _neon : _textMuted),
              const SizedBox(width: 12),
              Expanded(
                child: Text(n.label,
                    overflow: TextOverflow.ellipsis,
                    style: _body(
                        size: 13,
                        weight: active ? FontWeight.w700 : FontWeight.w500,
                        color: active ? _neon : _textMuted)),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _plainRow(IconData icon, String label, VoidCallback onTap) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(children: [
            Icon(icon, size: 18, color: _textMuted),
            const SizedBox(width: 12),
            Text(label, style: _body(size: 12.5, color: _textMuted)),
          ]),
        ),
      ),
    );
  }

  /// Hold-filteret. Tegnes ALTID på faner der har et filter — også når der kun
  /// er ét hold — så det aldrig ser ud som om funktionen mangler.
  Widget _filterBlok(HoldFilterModel? f) {
    if (f == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 18, 20, 0),
          child: Divider(height: 1, thickness: 1, color: _borderSubtle),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 16, 22, 9),
          child: Row(children: [
            const Icon(Icons.filter_list, size: 13, color: _textMuted),
            const SizedBox(width: 7),
            Expanded(
              child: Text('FILTRÉR PÅ HOLD',
                  style: _body(
                      size: 10.5,
                      weight: FontWeight.w700,
                      color: _textMuted,
                      spacing: 1.3)),
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (f.mine.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 2, 10, 6),
                  child: Text('Du er ikke på noget hold endnu.',
                      style: _body(size: 11.5, color: _textMuted)),
                ),
              for (final e in f.mine) _filterRow(f, e, klub: false),
              if (f.klub.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 11, 10, 4),
                  child: Text('HELE KLUBBEN',
                      style: _body(
                          size: 9.5,
                          weight: FontWeight.w700,
                          color: const Color(0xFF6E645C),
                          spacing: 1.3)),
                ),
                for (final e in f.klub) _filterRow(f, e, klub: true),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _filterRow(HoldFilterModel f, HoldFilterEntry e,
      {required bool klub}) {
    final valgt = f.erValgt(e.id, klub: klub);
    // "Alle klubbens hold" er guld i mobilens sheet — samme sprog her.
    final markering = (klub && e.id == null) ? _gold : _neon;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: valgt ? markering.withValues(alpha: 0.14) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: () => f.vaelg(e.id, klub: klub),
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(children: [
              Container(
                width: 9,
                height: 9,
                decoration:
                    BoxDecoration(color: e.farve, shape: BoxShape.circle),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(e.navn,
                    overflow: TextOverflow.ellipsis,
                    style: _body(
                        size: 12.5,
                        weight: valgt ? FontWeight.w700 : FontWeight.w500,
                        color: valgt ? _textPrimary : _textSecondary)),
              ),
              if (valgt)
                Icon(f.multi ? Icons.check_box : Icons.check,
                    size: 14, color: markering)
              else if (e.antal != null)
                Text('${e.antal}',
                    style: _body(
                        size: 11, weight: FontWeight.w600, color: _textMuted)),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Ctrl+K-genvejen i topbaren — samme kommandopalet som på mobilens AppBar.
class _CtrlKKnap extends StatelessWidget {
  const _CtrlKKnap({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _surfaceElevated,
      borderRadius: BorderRadius.circular(11),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(11),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: _borderSubtle),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.search, size: 15, color: _textMuted),
            const SizedBox(width: 8),
            Text('Ctrl+K', style: _body(size: 12.5, color: _textMuted)),
          ]),
        ),
      ),
    );
  }
}
