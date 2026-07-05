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

/// Puls-skeleton-blok til loading-tilstande (i stedet for en spinner på tom flade).
class _Skeleton extends StatefulWidget {
  final double height;
  final double width;
  final double radius;
  const _Skeleton({this.height = 14, this.width = double.infinity, this.radius = 8});
  @override
  State<_Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<_Skeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 900))
    ..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) => Container(
        height: widget.height,
        width: widget.width,
        decoration: BoxDecoration(
          color: Color.lerp(_surfaceDark, _surfaceElevated, _c.value),
          borderRadius: BorderRadius.circular(widget.radius),
        ),
      ),
    );
  }
}

/// Nogle kort-formede skeletons — samme form som rigtige kort.
Widget _skeletonCards({int count = 4}) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (var i = 0; i < count; i++)
        Container(
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _surfaceDark,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _borderSubtle),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Skeleton(height: 12, width: 90, radius: 999),
              SizedBox(height: 14),
              _Skeleton(height: 18, width: 170),
              SizedBox(height: 8),
              _Skeleton(height: 12, width: 230),
              SizedBox(height: 16),
              Row(children: [
                Expanded(child: _Skeleton(height: 42, radius: 12)),
                SizedBox(width: 8),
                Expanded(child: _Skeleton(height: 42, radius: 12)),
              ]),
            ],
          ),
        ),
    ],
  );
}

/// Loading-skærm med skeleton-kort (i stedet for en spinner på tom flade).
Widget _loadingSkeleton() => ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: _skeletonCards(),
          ),
        ),
      ],
    );

/// Rolig tom-tilstand: ikon + titel + evt. undertekst.
class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  const _EmptyState({required this.icon, required this.title, this.subtitle});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 64, color: _textMuted),
          const SizedBox(height: 16),
          Text(title,
              textAlign: TextAlign.center, style: theme.textTheme.titleMedium),
          if (subtitle != null) ...[
            const SizedBox(height: 6),
            Text(subtitle!,
                textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
          ],
        ],
      ),
    );
  }
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
