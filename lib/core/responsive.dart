// Auto-split (del af biblioteket padel_app)
// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
part of '../main.dart';

// ─────────────────────────────────────────────────────────────────────────────
// PC-visning
//
// Alt herunder er ren tilføjelse: mobilen rammer aldrig disse kodestier.
// Grænsen er bevidst sat højt (1100 px). Under den kører præcis den samme
// kode som hidtil — inkl. den eksisterende NavigationRail fra 700 px og op.
// ─────────────────────────────────────────────────────────────────────────────

const double kDesktopBreakpoint = 1100;

bool isDesktop(BuildContext context) =>
    MediaQuery.of(context).size.width >= kDesktopBreakpoint;

/// Mål på PC-stelet — holdt ét sted, så sidebar og topbar ikke driver fra
/// hinanden på tværs af faner.
const double kSidebarWidth = 216;
const double kTopbarHeight = 62;

/// Holdets farve fra databasen (`groups.farve`) som Color. Tom/ukendt værdi
/// falder tilbage på accentfarven, så en prik aldrig forsvinder.
Color holdFarve(Object? farve) {
  final h = farve as String?;
  if (h == null || h.isEmpty) return _neon;
  return Color(int.parse(h.replaceFirst('#', ''), radix: 16) | 0xFF000000);
}

/// Ét hold som hold-filteret kan tegne.
class HoldFilterEntry {
  const HoldFilterEntry({
    required this.id,
    required this.navn,
    required this.farve,
    this.antal,
  });

  /// `null` = "alle" på sit niveau (alle mine hold / alle klubbens hold).
  final String? id;
  final String navn;
  final Color farve;

  /// Valgfrit tal i højre side (fx antal medlemmer). Skjules når det er null.
  final int? antal;
}

/// Den kontrakt en fane skal opfylde for at sidebaren kan tegne dens hold-
/// filter. Fanen beholder sin egen state — sidebaren læser den og kalder
/// tilbage. Ingen state flyttes op, så mobilens tragt-sheet virker uændret.
class HoldFilterModel {
  const HoldFilterModel({
    required this.mine,
    required this.klub,
    required this.erValgt,
    required this.vaelg,
    this.multi = false,
  });

  /// Mine hold — første element er altid "alle mine hold" (id == null).
  final List<HoldFilterEntry> mine;

  /// Hele klubben — tom liste for ikke-admins, så afsnittet udelades.
  final List<HoldFilterEntry> klub;

  /// Er dette punkt valgt lige nu? `klub` skiller de to niveauer ad, præcis
  /// som `_allTeams` gør i Oversigt.
  final bool Function(String? id, {required bool klub}) erValgt;

  /// Brugeren klikkede på et punkt.
  final void Function(String? id, {required bool klub}) vaelg;

  /// Kan flere hold være valgt samtidig (Afstemninger og Bødekassen)?
  final bool multi;

  /// Kompakt aftryk af hvad filteret VISER lige nu — bruges til at afgøre om
  /// sidebaren skal tegnes om. Lukninger (`vaelg`) er nye ved hver build og
  /// duer derfor ikke til sammenligning.
  String get signatur {
    final b = StringBuffer(multi ? 'm' : 's');
    void skriv(List<HoldFilterEntry> liste, bool erKlub) {
      b.write(erKlub ? '|K' : '|M');
      for (final e in liste) {
        b.write('/${e.id ?? "*"}:${e.navn}:${e.antal ?? "-"}:'
            '${erValgt(e.id, klub: erKlub) ? 1 : 0}');
      }
    }

    skriv(mine, false);
    skriv(klub, true);
    return b.toString();
  }
}

/// Én fanes hold-filter, som PC-sidebaren abonnerer på.
///
/// Fanen beholder sin egen state; den melder blot ind når filteret har ændret
/// sig. Hver fane har sin egen notifier, så en IndexedStack der bygger alle
/// faner på én gang ikke kan komme til at overskrive hinandens filter.
mixin HoldFilterKilde<T extends StatefulWidget> on State<T> {
  final ValueNotifier<HoldFilterModel?> holdFilterNotifier =
      ValueNotifier<HoldFilterModel?>(null);

  String? _sidsteFilterSignatur;

  /// Kaldes fra fanens `build`. Tegner kun sidebaren om når filteret reelt er
  /// et andet — ellers ville hver eneste build udløse en ny opdatering.
  void meldHoldFilter(HoldFilterModel? m) {
    final sig = m?.signatur;
    if (sig == _sidsteFilterSignatur) return;
    _sidsteFilterSignatur = sig;
    // Aldrig midt i en build: sidebaren lytter og ville blive bedt om at
    // bygge om, mens den selv er ved at blive bygget.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) holdFilterNotifier.value = m;
    });
  }

  @override
  void dispose() {
    holdFilterNotifier.dispose();
    super.dispose();
  }
}
