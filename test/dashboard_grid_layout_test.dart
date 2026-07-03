// Regressionstest for dashboard-handlingsgrid'et.
//
// Bug: en Row med CrossAxisAlignment.stretch inde i en ListView (uendelig
// lodret højde) kaster en layout-exception. Fix: wrap Row'en i IntrinsicHeight.
// Denne test reproducerer strukturen og sikrer at den renderer uden fejl.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _tile(String label) => Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF211A16),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0x14FFFFFF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 38, height: 38, color: Colors.orange),
          const SizedBox(height: 12),
          Text(label),
          const SizedBox(height: 2),
          const Text('undertekst'),
        ],
      ),
    );

/// Samme grid-opbygning som DashboardTab._buildQuickActions.
Widget _grid(List<Widget> tiles) {
  const perRow = 2;
  const gap = 12.0;
  final rows = <Widget>[];
  for (var i = 0; i < tiles.length; i += perRow) {
    final end = (i + perRow) > tiles.length ? tiles.length : (i + perRow);
    final chunk = tiles.sublist(i, end);
    rows.add(IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var j = 0; j < perRow; j++) ...[
            Expanded(child: j < chunk.length ? chunk[j] : const SizedBox()),
            if (j != perRow - 1) const SizedBox(width: gap),
          ],
        ],
      ),
    ));
    if (i + perRow < tiles.length) rows.add(const SizedBox(height: gap));
  }
  return Column(children: rows);
}

void main() {
  testWidgets('handlings-grid renderer uden layout-exception i ListView',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _grid([
                      _tile('Ny begivenhed'),
                      _tile('Ny afstemning'),
                      _tile('Lyn-bøde'),
                      _tile('Medlemmer'),
                    ]),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ));

    // Ingen exception under layout + alle fire fliser til stede.
    expect(tester.takeException(), isNull);
    expect(find.text('Ny begivenhed'), findsOneWidget);
    expect(find.text('Medlemmer'), findsOneWidget);
  });
}
