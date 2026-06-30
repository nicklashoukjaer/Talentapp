// Auto-split (del af biblioteket padel_app)
// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
part of '../main.dart';

class AppCommand {
  final String label;
  final String? hint;
  final IconData icon;
  final List<String> keywords;
  final FutureOr<void> Function() run;

  const AppCommand({
    required this.label,
    required this.icon,
    required this.run,
    this.hint,
    this.keywords = const [],
  });

  bool matches(String query) {
    if (query.isEmpty) return true;
    final q = query.toLowerCase();
    if (label.toLowerCase().contains(q)) return true;
    return keywords.any((k) => k.toLowerCase().contains(q));
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// App + auth gate
// ─────────────────────────────────────────────────────────────────────────────

// ─── The Clay Court — terracotta-accent på varm jordsort ────────────────────
// Konstant-navnene bevares (_neon, _bgBlack…) for at undgå find/replace-risiko,
// men farveværdierne er omdøbt til Clay Court-paletten.
sealed class _FeedItem {
  DateTime get sortKey;
}

class _Participant {
  final String   navn;
  final DateTime updatedAt;
  final bool     isTrainer;
  const _Participant({
    required this.navn,
    required this.updatedAt,
    this.isTrainer = false,
  });
}

class _TrainingFeedItem extends _FeedItem {
  final Map<String, dynamic> training;
  final String? myStatus;
  final int signedUpCount;     // antal SPILLERE tilmeldt (trænere ikke talt med)
  final List<_Participant> tilmeldte;   // spillere
  final List<_Participant> venteliste;
  final List<_Participant> afmeldte;
  final List<_Participant> trainere;    // trænere med status tilmeldt
  _TrainingFeedItem({
    required this.training,
    required this.myStatus,
    required this.signedUpCount,
    required this.tilmeldte,
    required this.venteliste,
    required this.afmeldte,
    required this.trainere,
  });
  @override
  DateTime get sortKey => DateTime.parse(training['start_tid'] as String);
}

/// Per option: ja-stemmere og nej-stemmere (navne).
class _OptionVoters {
  final List<String> yes;
  final List<String> no;
  const _OptionVoters({required this.yes, required this.no});
}

class _PollFeedItem extends _FeedItem {
  final Map<String, dynamic> poll;
  final List<Map<String, dynamic>> options;
  final Map<String, bool> myVotes;
  final int respondedCount;
  final int totalMembers;
  final Map<String, _OptionVoters> votersByOption; // option_id → voters
  _PollFeedItem({
    required this.poll,
    required this.options,
    required this.myVotes,
    required this.respondedCount,
    required this.totalMembers,
    required this.votersByOption,
  });
  @override
  DateTime get sortKey {
    if (options.isEmpty) return DateTime.parse(poll['created_at'] as String);
    final tids = options.map((o) => DateTime.parse(o['option_tid'] as String));
    return tids.reduce((a, b) => a.isBefore(b) ? a : b);
  }
}

