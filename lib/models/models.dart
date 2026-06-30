// Datamodeller for De Talentløse.
//
// Resten af appen bruger pt. rå Map<String, dynamic> fra Supabase. Disse
// klasser er fundamentet at migrere til gradvist: brug fx Bruger.fromMap(row)
// i stedet for at læse felter direkte fra map'et. De er bevidst simple og
// matcher kolonnenavnene i Supabase-tabellerne.
part of '../main.dart';

/// En bruger/spiller (tabellen `profiles`).
class Bruger {
  final String id;
  final String navn;
  final String? email;
  final bool isAdmin;
  final bool isStaff;

  const Bruger({
    required this.id,
    required this.navn,
    this.email,
    this.isAdmin = false,
    this.isStaff = false,
  });

  factory Bruger.fromMap(Map<String, dynamic> m) => Bruger(
        id: m['id'] as String,
        navn: (m['navn'] as String?) ?? 'Ukendt',
        email: m['email'] as String?,
        isAdmin: (m['is_admin'] as bool?) ?? false,
        isStaff: (m['is_staff'] as bool?) ?? (m['is_admin'] as bool?) ?? false,
      );
}

/// En bøde (tabellen `fines`).
class Boede {
  final String id;
  final String userId;
  final String? titel;
  final int belobOere;
  final String? begrundelse;
  final String status; // 'ubetalt' | 'godkendt_betalt' | ...
  final DateTime? createdAt;
  final DateTime? paidAt;

  const Boede({
    required this.id,
    required this.userId,
    required this.belobOere,
    required this.status,
    this.titel,
    this.begrundelse,
    this.createdAt,
    this.paidAt,
  });

  /// Beløb i hele kroner.
  int get kroner => belobOere ~/ 100;

  /// Er bøden betalt/godkendt?
  bool get erBetalt => status == 'godkendt_betalt';

  factory Boede.fromMap(Map<String, dynamic> m) => Boede(
        id: m['id'] as String,
        userId: m['user_id'] as String,
        titel: m['titel'] as String?,
        belobOere: (m['belob_oere'] as num).toInt(),
        begrundelse: m['begrundelse'] as String?,
        status: (m['status'] as String?) ?? 'ubetalt',
        createdAt: m['created_at'] == null
            ? null
            : DateTime.parse(m['created_at'] as String),
        paidAt: m['paid_at'] == null
            ? null
            : DateTime.parse(m['paid_at'] as String),
      );
}

/// En kamp/træning (en begivenhed med start, slut og deltagere).
class Kamp {
  final String id;
  final String titel;
  final DateTime start;
  final DateTime? slut;
  final String? adresse;
  final int maxDeltagere;

  const Kamp({
    required this.id,
    required this.titel,
    required this.start,
    this.slut,
    this.adresse,
    this.maxDeltagere = 4,
  });

  factory Kamp.fromMap(Map<String, dynamic> m) => Kamp(
        id: m['id'] as String,
        titel: (m['titel'] as String?) ?? 'Begivenhed',
        start: DateTime.parse(m['start'] as String),
        slut: m['slut'] == null ? null : DateTime.parse(m['slut'] as String),
        adresse: m['adresse'] as String?,
        maxDeltagere: (m['max_deltagere'] as num?)?.toInt() ?? 4,
      );
}
