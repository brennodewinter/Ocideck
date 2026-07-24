import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/checklist_spec.dart';
import 'package:ocideck/models/cockpit.dart';
import 'package:ocideck/models/scope_matrix_spec.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/models/timeline.dart';
import 'package:ocideck/widgets/slides/slide_preview.dart';

/// Een dia-preview die op nulbreedte wordt gemeten, hoort niets te tekenen —
/// niet te ontploffen.
///
/// Dit is dezelfde foutklasse als #714: `clamp` gooit `ArgumentError` zodra de
/// bovengrens onder de ondergrens zakt, en in een `LayoutBuilder` ís die
/// bovengrens de layout-constraint. `(outerW - padding).clamp(1.0, outerW)`
/// viel om met `Invalid argument(s): 1.0` bij elke breedte onder 1,0.
///
/// **Waarom dit een echte eis is en geen onzin-invoer.** Flutter meet een
/// widget vaker dan hij hem tekent: een inklappend paneel, een rij zonder
/// resterende ruimte, een animatie die bij nul begint. Geen van die drie is
/// bijzonder, en alle drie leveren ze precies deze constraint.
///
/// Een gebruikerspad naar deze breedte is in de huidige app níét aangetoond —
/// het venster heeft een ondergrens van 1000×650 en de panelen hebben hun eigen
/// vloer. Dit is dus een hardening met een reproductie, geen gerapporteerde
/// storing. Zie de reactie bij #714 voor de drie andere manieren waarop een
/// preview op nulbreedte omvalt; die hebben andere oorzaken en staan apart.
void main() {
  /// Een overloop van een paar pixels is bij deze breedtes de juiste uitkomst,
  /// geen gebrek: twee kolommen passen nu eenmaal niet in één pixel, en Flutter
  /// meldt dat in debug. Wat hier bewaakt wordt is het verschil tussen "past
  /// niet" en "valt om" — een `ArgumentError` of een gefaalde assertie is het
  /// tweede, en dat is wat deze toets rood moet maken.
  bool isHardFailure(Object? error) =>
      error != null &&
      !(error is FlutterError && '$error'.contains('overflowed by'));

  void expectNoHardFailure(Object? error, {required String what}) {
    expect(
      isHardFailure(error),
      isFalse,
      reason: '$what viel om in plaats van simpelweg niet te passen: $error',
    );
  }

  Future<Object?> renderAt(
    WidgetTester tester,
    double width,
    Slide slide,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: width,
              height: 200,
              child: SlidePreviewWidget(slide: slide),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return tester.takeException();
  }

  final bullets = Slide.create(
    SlideType.bullets,
  ).copyWith(title: 'Titel', bullets: const ['Een punt', 'Nog een punt']);

  final tweeKolommen = Slide.create(SlideType.twoBullets).copyWith(
    title: 'Titel',
    bullets: const ['Links een'],
    bullets2: const ['Rechts een'],
  );

  // Nul is de echte grens; 0,5 zit ertussen (boven de `<= 0`-guard, onder de
  // ondergrens 1,0) en is precies het gat dat de bestaande guards lieten staan.
  for (final width in const [0.0, 0.5, 1.0]) {
    testWidgets('bullets overleeft breedte $width', (tester) async {
      expectNoHardFailure(
        await renderAt(tester, width, bullets),
        what: 'bullets op $width',
      );
    });

    testWidgets('twee kolommen overleven breedte $width', (tester) async {
      expectNoHardFailure(
        await renderAt(tester, width, tweeKolommen),
        what: 'twee kolommen op $width',
      );
    });
  }

  testWidgets('een checklist met voortgangsgrafiek overleeft nulbreedte', (
    tester,
  ) async {
    // De voortgangskolom trekt eigen breedtes af van de contentbreedte, en dat
    // was het tweede clamp-paar in dit bestand.
    final checklist = Slide.create(SlideType.bullets).copyWith(
      title: 'Checklist',
      bullets: const ['[x] Een', '[ ] Twee'],
      listStyle: ListStyle.checklist,
      showChecklistProgress: true,
    );
    expectNoHardFailure(
      await renderAt(tester, 0, checklist),
      what: 'checklist met voortgang op 0',
    );
  });

  testWidgets('een checklist-dia overleeft nulbreedte', (tester) async {
    // De voortgangsbalk geeft `LinearProgressIndicator` een `minHeight` die van
    // de breedte is afgeleid, en die eist er een boven nul.
    final checklist = Slide.create(SlideType.checklist).copyWith(
      title: 'Checklist',
      tableRows: const ChecklistSpec(
        standardLabel: 'Checklist',
        rows: [
          ChecklistRow(id: 'A-1', test: 'Een', status: ChecklistStatus.tested),
          ChecklistRow(id: 'A-2', test: 'Twee'),
        ],
      ).toTableRows(),
    );
    expectNoHardFailure(
      await renderAt(tester, 0, checklist),
      what: 'checklist-dia op 0',
    );
  });

  testWidgets('een scopematrix overleeft nulbreedte', (tester) async {
    // Dezelfde voortgangsbalk, tweede vindplaats.
    final scope = Slide.create(SlideType.scopeMatrix).copyWith(
      title: 'Scope',
      tableRows: const ScopeMatrixSpec(
        title: 'Scope',
        rows: [
          ScopeRow(object: 'https://app.example', type: ScopeObjectType.web),
        ],
      ).toTableRows(),
    );
    expectNoHardFailure(
      await renderAt(tester, 0, scope),
      what: 'scopematrix op 0',
    );
  });

  // Nul alleen was hier niet genoeg. De rail verdeelt zijn verdiepingen met een
  // deling waarvan de deler van de breedte is afgeleid — die levert op nul
  // Infinity of NaN en het afronden daarvan gooit — maar de clamp van de
  // verbindingslijn viel pas ómhoog om, bij een kaart die smaller is dan haar
  // eigen marge. Elke breedte in deze lijst ving iets wat de andere lieten
  // staan, dus ze blijven alle vier staan.
  for (final layout in TimelineLayout.values) {
    for (final width in const [0.0, 0.5, 1.0, 4.0]) {
      testWidgets('tijdlijn ${layout.name} overleeft breedte $width', (
        tester,
      ) async {
        expectNoHardFailure(
          await renderAt(
            tester,
            width,
            Slide.create(SlideType.timeline).copyWith(timelineLayout: layout),
          ),
          what: 'tijdlijn ${layout.name} op $width',
        );
      });
    }
  }

  // De instrumentrand is één schilder die elk metertype doorloopt, en daar zat
  // de fout: de hoekstraal is van de metergrootte afgeleid terwijl de randdikte
  // een vaste pixel als vloer heeft, dus op een korte meter werd het verschil
  // negatief en dat weigert `RRect`. Eén meter zou volstaan om dat te vangen;
  // alle zeven staan er omdat de rand voor elk type opnieuw wordt getekend en
  // een type dat straks zijn eigen rand meebrengt hier hoort af te gaan.
  for (final type in CockpitMeterType.values) {
    testWidgets('cockpitmeter ${type.name} overleeft nulbreedte', (
      tester,
    ) async {
      final slide = Slide.create(SlideType.cockpit).copyWith(
        customMarkdown: CockpitSpec(
          meters: [CockpitMeterSpec(type: type)],
        ).toBlock(),
      );
      expectNoHardFailure(
        await renderAt(tester, 0, slide),
        what: 'cockpitmeter ${type.name} op 0',
      );
    });
  }

  // De lege cockpit valt terug op de voorbeeldmeters en zet er vier naast
  // elkaar; dat is het geval waarin één meter al kort wordt zonder dat de dia
  // zelf ontaard is.
  for (final width in const [0.0, 0.5, 1.0, 4.0]) {
    testWidgets('een lege cockpit overleeft breedte $width', (tester) async {
      expectNoHardFailure(
        await renderAt(tester, width, Slide.create(SlideType.cockpit)),
        what: 'lege cockpit op $width',
      );
    });
  }

  // Het vangnet onder de vier toetsen hierboven. Die noemen elk hun eigen
  // oorzaak en zetten er de inhoud bij die hem uitlokt; deze doet het omgekeerde
  // en loopt met de standaardinhoud van `Slide.create` alle types langs. Wat hij
  // vangt is niet een oorzaak maar een verzuim: het volgende slidetype dat erbij
  // komt en dezelfde deling of clamp opnieuw uitschrijft.
  //
  // Bewust één toets en geen 24, met alle omgevallen types in de melding: wie
  // een type toevoegt wil weten wát er omvalt, niet 24 losse regels waarvan er
  // één rood is.
  testWidgets('geen enkel slidetype valt om op een ontaarde breedte', (
    tester,
  ) async {
    final omgevallen = <String>[];
    for (final type in SlideType.values) {
      for (final width in const [0.0, 0.5, 1.0, 4.0]) {
        final error = await renderAt(tester, width, Slide.create(type));
        if (isHardFailure(error)) {
          omgevallen.add('${type.name} op $width: $error');
        }
      }
    }
    expect(omgevallen, isEmpty, reason: omgevallen.join('\n'));
  });

  testWidgets('op een gewone breedte verandert er niets', (tester) async {
    // Het vangnet onder de reparatie: de grenzen mogen alleen het ontaarde
    // geval raken, niet de maatvoering van een echte dia.
    expect(await renderAt(tester, 640, bullets), isNull);
    expect(find.text('Titel'), findsWidgets);
  });
}
