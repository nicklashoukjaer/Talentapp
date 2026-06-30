// Auto-split (del af biblioteket padel_app)
// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
part of '../main.dart';

String _icsEscape(String s) => s
    .replaceAll(r'\', r'\\')
    .replaceAll(',',  r'\,')
    .replaceAll(';',  r'\;')
    .replaceAll('\n', r'\n');

String _icsDate(DateTime t) {
  final u = t.toUtc();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${u.year}${two(u.month)}${two(u.day)}'
         'T${two(u.hour)}${two(u.minute)}${two(u.second)}Z';
}

String _buildIcs(Map<String, dynamic> t) {
  final start  = DateTime.parse(t['start_tid'] as String);
  final slut   = DateTime.parse(t['slut_tid']  as String);
  final adresse = t['adresse'] as String;
  final titel   = t['titel']   as String;
  final beskr   = t['beskrivelse'] as String?;
  final id      = t['id'] as String;
  final hasAddress = adresse.isNotEmpty && adresse != _addressUnspecified;

  final lines = <String>[
    'BEGIN:VCALENDAR',
    'VERSION:2.0',
    'PRODID:-//DLN Padel//Training//DA',
    'BEGIN:VEVENT',
    'UID:$id@padel.dln.dk',
    'DTSTAMP:${_icsDate(DateTime.now())}',
    'DTSTART:${_icsDate(start)}',
    'DTEND:${_icsDate(slut)}',
    'SUMMARY:${_icsEscape(titel)}',
    if (beskr != null && beskr.isNotEmpty) 'DESCRIPTION:${_icsEscape(beskr)}',
    if (hasAddress) 'LOCATION:${_icsEscape(adresse)}',
    'END:VEVENT',
    'END:VCALENDAR',
  ];
  return lines.join('\r\n');
}

void _downloadIcs(Map<String, dynamic> training) {
  final content = _buildIcs(training);
  final safeName = (training['titel'] as String)
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_');
  platformDownloadText('padel_$safeName.ics', 'text/calendar', content);
}

// ─────────────────────────────────────────────────────────────────────────────
// Fælles hjælpere
// ─────────────────────────────────────────────────────────────────────────────

