// Prøver fordelingen af. Den kender hverken database eller skærm, så den
// kan køres her uden opsætning — og det er den eneste del af tavlen hvor
// en regnefejl ikke kan ses med det blotte øje.
import 'package:flutter_test/flutter_test.dart';
import 'package:padel_app/main.dart';

TavleSpiller sp(String id, {String? side}) =>
    TavleSpiller(id: id, navn: id.toUpperCase(), side: side);

void main() {
  group('parPoint', () {
    test('venstre + højre giver point, to ens trækker fra', () {
      const ind = FordelingsInput(spillere: []);
      expect(parPoint(sp('a', side: 'venstre'), sp('b', side: 'hoejre'), ind),
          Vaegte.sidePasser);
      expect(parPoint(sp('a', side: 'venstre'), sp('b', side: 'venstre'), ind),
          Vaegte.sideKolliderer);
    });

    test('"begge" og ukendt side straffes ikke', () {
      const ind = FordelingsInput(spillere: []);
      expect(parPoint(sp('a', side: 'begge'), sp('b', side: 'begge'), ind), 0);
      expect(parPoint(sp('a'), sp('b', side: 'venstre'), ind), 0);
    });

    test('stjernen vægter, men taber til "spillet sammen i dag"', () {
      final n = parNoegle('a', 'b');
      final medStjerne = FordelingsInput(spillere: const [], kemi: {n});
      expect(parPoint(sp('a'), sp('b'), medStjerne), Vaegte.kemi);

      final ogsaaIDag =
          FordelingsInput(spillere: const [], kemi: {n}, sammenIDag: {n});
      expect(parPoint(sp('a'), sp('b'), ogsaaIDag), lessThan(0),
          reason: 'et stjernepar må ikke få hinanden to runder i træk');
    });

    test('gensidig favorit lægger tillæg til den bedste retning', () {
      final enVej = FordelingsInput(spillere: const [], favoritter: {
        'a': ['b']
      });
      expect(parPoint(sp('a'), sp('b'), enVej), Vaegte.favorit1);

      final beggeVeje = FordelingsInput(spillere: const [], favoritter: {
        'a': ['b'],
        'b': ['a'],
      });
      expect(parPoint(sp('a'), sp('b'), beggeVeje),
          Vaegte.favorit1 + Vaegte.gensidig);
    });

    test('historik trækker fra, men har et loft', () {
      final n = parNoegle('a', 'b');
      final mange = FordelingsInput(spillere: const [], historik: {n: 99});
      expect(parPoint(sp('a'), sp('b'), mange), Vaegte.sammenFoerLoft);
    });
  });

  group('fordel', () {
    final otte = [for (var i = 0; i < 8; i++) sp('s$i')];

    test('to baner fylder fire par og ingen sidder over', () {
      final r = fordel(FordelingsInput(spillere: otte, baner: 2));
      expect(r.baner.length, 2);
      expect(r.baenk, isEmpty);
      expect(r.alle.length, 8, reason: 'ingen må forsvinde');
    });

    test('flere tilmeldte end pladser sætter resten på bænken', () {
      final ti = [for (var i = 0; i < 10; i++) sp('s$i')];
      final r = fordel(FordelingsInput(spillere: ti, baner: 2));
      expect(r.baenk.length, 2);
      expect(r.alle.length, 10);
    });

    test('den der har spillet færrest kommer ind før de øvrige', () {
      final ti = [for (var i = 0; i < 10; i++) sp('s$i')];
      // Alle har spillet to runder undtagen s9, som har spillet nul.
      final r = fordel(FordelingsInput(
        spillere: ti,
        baner: 2,
        runderSpillet: {for (var i = 0; i < 9; i++) 's$i': 2},
      ));
      expect(r.baenk.map((s) => s.id), isNot(contains('s9')));
    });

    test('fast par holdes sammen', () {
      final n = parNoegle('s0', 's5');
      final r = fordel(
          FordelingsInput(spillere: otte, baner: 2, fastePar: {n}));
      final sammen = r.parrene.any((p) => p.noegle == n);
      expect(sammen, isTrue);
    });

    test('fast par hvor kun den ene er med, springes over', () {
      final kunEn = [for (var i = 0; i < 8; i++) sp('s$i')];
      final n = parNoegle('s0', 'ukendt');
      final r = fordel(
          FordelingsInput(spillere: kunEn, baner: 2, fastePar: {n}));
      expect(r.alle.length, 8);
      expect(r.alle.map((s) => s.id), contains('s0'));
    });

    test('låste par bliver stående', () {
      final laast = [sp('s2'), sp('s3')];
      final r = fordel(FordelingsInput(
          spillere: otte, baner: 2, laaste: [laast]));
      expect(r.parrene.any((p) => p.noegle == parNoegle('s2', 's3')), isTrue);
    });

    test('siderne parres på tværs når det kan lade sig gøre', () {
      final fire = [
        sp('v1', side: 'venstre'),
        sp('v2', side: 'venstre'),
        sp('h1', side: 'hoejre'),
        sp('h2', side: 'hoejre'),
      ];
      final r = fordel(FordelingsInput(spillere: fire, baner: 1));
      for (final p in r.parrene) {
        if (!p.erHelt) continue;
        expect(p.spillere[0].side, isNot(p.spillere[1].side),
            reason: 'to venstrespillere skulle ikke stå sammen');
      }
    });

    test('opdelt holder holdene for sig', () {
      final r = fordel(FordelingsInput(
        spillere: otte,
        baner: 2,
        tilstand: 'opdelt',
        holdAf: {
          for (var i = 0; i < 8; i++) 's$i': i < 4 ? 'T1' : 'T2',
        },
      ));
      for (final p in r.parrene) {
        if (!p.erHelt) continue;
        final a = int.parse(p.spillere[0].id.substring(1));
        final b = int.parse(p.spillere[1].id.substring(1));
        expect(a < 4, b < 4,
            reason: 'et par må ikke gå på tværs af hold i opdelt tilstand');
      }
    });

    test('faste par ignoreres når kontakten er slået fra', () {
      // Sådan kalder skærmen når _brugFastePar er false: tom mængde.
      final r = fordel(FordelingsInput(
          spillere: otte, baner: 2, fastePar: const {}));
      expect(r.alle.length, 8);
    });

    test('ingen spiller optræder to steder', () {
      final tolv = [for (var i = 0; i < 12; i++) sp('s$i')];
      final r = fordel(FordelingsInput(spillere: tolv, baner: 2));
      final ids = r.alle.map((s) => s.id).toList();
      expect(ids.toSet().length, ids.length);
      expect(ids.length, 12);
    });
  });

  group('Opstilling', () {
    test('byt flytter begge veje og efterlader ikke en halv ombytning', () {
      final op = Opstilling(baner: [
        TavleBane(1, TavlePar([sp('a'), sp('b')]), TavlePar([sp('c'), sp('d')]))
      ]);
      final ny = op.byt(sp('a'), sp('d'));
      expect(ny.baner[0].par1.spillere.map((s) => s.id), ['d', 'b']);
      expect(ny.baner[0].par2.spillere.map((s) => s.id), ['c', 'a']);
      // Den oprindelige må ikke være rørt.
      expect(op.baner[0].par1.spillere.map((s) => s.id), ['a', 'b']);
    });

    test('bænken serialiseres med tom bane og par', () {
      final op = Opstilling(
        baner: [
          TavleBane(1, TavlePar([sp('a'), sp('b')]), const TavlePar.tom())
        ],
        baenk: [sp('c')],
      );
      final r = op.tilRaekker('runde-1');
      expect(r.length, 3);
      final over = r.firstWhere((x) => x['user_id'] == 'c');
      expect(over['bane'], isNull);
      expect(over['par'], isNull);
    });
  });
}
