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
    // Tekst-afstemninger har ingen datoer → sortér på oprettelse.
    final tids = options
        .map((o) => o['option_tid'] as String?)
        .whereType<String>()
        .map(DateTime.parse)
        .toList();
    if (tids.isEmpty) return DateTime.parse(poll['created_at'] as String);
    return tids.reduce((a, b) => a.isBefore(b) ? a : b);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Feedet i og ud af cachen
//
// Så Oversigten kan tegne det man så sidst, med det samme, mens friske data
// hentes i baggrunden. Alt herunder er rent additivt — afledningen i
// reload() er urørt.
// ─────────────────────────────────────────────────────────────────────────────

Map<String, dynamic> _participantTilJson(_Participant p) => {
      'navn': p.navn,
      'updatedAt': p.updatedAt.toIso8601String(),
      'isTrainer': p.isTrainer,
    };

_Participant _participantFraJson(Map<String, dynamic> m) => _Participant(
      navn: m['navn'] as String? ?? '',
      updatedAt:
          DateTime.tryParse(m['updatedAt'] as String? ?? '') ?? DateTime.now(),
      isTrainer: m['isTrainer'] == true,
    );

List<Map<String, dynamic>> _pListeTilJson(List<_Participant> l) =>
    l.map(_participantTilJson).toList();

List<_Participant> _pListeFraJson(Object? v) => v is List
    ? v
        .whereType<Map>()
        .map((m) => _participantFraJson(m.cast<String, dynamic>()))
        .toList()
    : <_Participant>[];

Map<String, dynamic>? feedItemTilJson(_FeedItem item) {
  switch (item) {
    case _TrainingFeedItem t:
      return {
        'slags': 'training',
        'training': t.training,
        'myStatus': t.myStatus,
        'signedUpCount': t.signedUpCount,
        'tilmeldte': _pListeTilJson(t.tilmeldte),
        'venteliste': _pListeTilJson(t.venteliste),
        'afmeldte': _pListeTilJson(t.afmeldte),
        'trainere': _pListeTilJson(t.trainere),
      };
    case _PollFeedItem p:
      return {
        'slags': 'poll',
        'poll': p.poll,
        'options': p.options,
        'myVotes': p.myVotes,
        'respondedCount': p.respondedCount,
        'totalMembers': p.totalMembers,
        'votersByOption': {
          for (final e in p.votersByOption.entries)
            e.key: {'yes': e.value.yes, 'no': e.value.no}
        },
      };
  }
}

_FeedItem? feedItemFraJson(Map<String, dynamic> m) {
  try {
    if (m['slags'] == 'training') {
      return _TrainingFeedItem(
        training: (m['training'] as Map).cast<String, dynamic>(),
        myStatus: m['myStatus'] as String?,
        signedUpCount: (m['signedUpCount'] as num?)?.toInt() ?? 0,
        tilmeldte: _pListeFraJson(m['tilmeldte']),
        venteliste: _pListeFraJson(m['venteliste']),
        afmeldte: _pListeFraJson(m['afmeldte']),
        trainere: _pListeFraJson(m['trainere']),
      );
    }
    if (m['slags'] == 'poll') {
      final vb = <String, _OptionVoters>{};
      final raa = m['votersByOption'];
      if (raa is Map) {
        raa.forEach((k, v) {
          if (v is Map) {
            vb[k as String] = _OptionVoters(
              yes: (v['yes'] as List?)?.cast<String>() ?? const [],
              no: (v['no'] as List?)?.cast<String>() ?? const [],
            );
          }
        });
      }
      return _PollFeedItem(
        poll: (m['poll'] as Map).cast<String, dynamic>(),
        options: ((m['options'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => e.cast<String, dynamic>())
            .toList(),
        myVotes: ((m['myVotes'] as Map?) ?? const {})
            .map((k, v) => MapEntry(k as String, v == true)),
        respondedCount: (m['respondedCount'] as num?)?.toInt() ?? 0,
        totalMembers: (m['totalMembers'] as num?)?.toInt() ?? 0,
        votersByOption: vb,
      );
    }
  } catch (_) {
    // En cache fra en ældre udgave kan mangle felter. Så springes den over
    // og der hentes bare friske data — aldrig et nedbrud på grund af cache.
  }
  return null;
}
