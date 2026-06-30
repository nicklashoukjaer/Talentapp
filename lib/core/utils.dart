// Auto-split (del af biblioteket padel_app)
// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
part of '../main.dart';

String _fmtDate(DateTime d) {
  final l = d.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(l.day)}.${two(l.month)}.${l.year}';
}

String _fmtDateTime(DateTime d) {
  final l = d.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(l.day)}.${two(l.month)}.${l.year} ${two(l.hour)}:${two(l.minute)}';
}

String _fmtTime(DateTime d) {
  final l = d.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(l.hour)}:${two(l.minute)}';
}

/// Kompakt "for X tid siden" + dato/klokkeslæt — admin kan se hvornår
/// status sidst blev sat (især når en spiller har sendt afbud).
String _fmtRelative(DateTime t) {
  final l = t.toLocal();
  final diff = DateTime.now().difference(l);
  String stamp;
  String two(int n) => n.toString().padLeft(2, '0');
  if (diff.inSeconds < 60) {
    stamp = 'lige nu';
  } else if (diff.inMinutes < 60) {
    stamp = '${diff.inMinutes} min siden';
  } else if (diff.inHours < 24) {
    stamp = '${diff.inHours} t siden';
  } else if (diff.inDays < 7) {
    stamp = '${diff.inDays} d siden';
  } else {
    stamp = '${two(l.day)}.${two(l.month)} ${two(l.hour)}:${two(l.minute)}';
  }
  return '· $stamp';
}

/// øre → "X kr" (heltal) eller "X,YZ kr" hvis der er decimaler
String _fmtKr(int oere) {
  if (oere == 0) return '0 kr';
  if (oere % 100 == 0) return '${oere ~/ 100} kr';
  final kr = oere / 100;
  return '${kr.toStringAsFixed(2).replaceAll('.', ',')} kr';
}

void _snack(BuildContext ctx, String text, Color color) {
  ScaffoldMessenger.of(ctx).showSnackBar(
    SnackBar(content: Text(text), backgroundColor: color),
  );
}

class _ErrorView extends StatelessWidget {
  final String       error;
  final VoidCallback onRetry;
  const _ErrorView({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 16),
            Text(error, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('Prøv igen')),
          ],
        ),
      ),
    );
  }
}

class _MissingEnvApp extends StatelessWidget {
  const _MissingEnvApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.warning_amber_rounded, size: 64, color: Colors.orange),
                const SizedBox(height: 16),
                const Text('SUPABASE_URL og SUPABASE_ANON_KEY mangler',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center),
                const SizedBox(height: 8),
                const Text('Start appen med --dart-define for begge nøgler.',
                    textAlign: TextAlign.center),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
