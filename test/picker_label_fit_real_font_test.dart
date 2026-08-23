import 'dart:io';
import 'package:flutter/rendering.dart';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/widgets/dialogs/add_slide_dialog.dart';

/// Breekt een diatype-label ergens midden in een woord? Gemeten in het font
/// waarin de app het werkelijk tekent.
///
/// De melding in #646 was Duits: "Abschnittsüberschri / ft" in de diatypekiezer.
/// Er stond al een toets naast deze — "every registered type label fits its
/// card" — maar die bewees niets. Twee redenen, en ze versterken elkaar:
///
///  1. Ze eiste `fittedFontSize(...) >= minFontSize`, en die functie stopt zélf
///     bij die vloer. De assertie was altijd waar.
///  2. Een widgettest tekent in Ahem, waar elk teken een vierkant em is. Daar
///     zit twaalf van de vierentwintig Nederlandse labels al op de vloer, dus
///     ook een echte toets zou daar niets kunnen onderscheiden.
///
/// Deze toets laadt daarom `Roboto-Variable.ttf` — het gebundelde
/// interfacefont — en meet daarin. Daarmee is de vraag beslisbaar in plaats van
/// een kwestie van vertrouwen, en gaat ze over álle 31 talen en niet alleen de
/// Nederlandse bron: de melding gíng over een vertaling.
void main() {
  const cardLabelWidth = 84.0;
  const roboto = TextStyle(fontFamily: 'Roboto');

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final bytes = File('assets/fonts/Roboto-Variable.ttf').readAsBytesSync();
    await (FontLoader('Roboto')..addFont(
          Future.value(ByteData.view(Uint8List.fromList(bytes).buffer)),
        ))
        .load();
  });

  double widthOf(String text, double fontSize) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: roboto.merge(TextStyle(fontSize: fontSize, height: 1.15)),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    return painter.width;
  }

  /// De stukken waarin de regelafbreker het label mág knippen: op witruimte en
  /// ná een koppelteken. Spiegelt [FittedTypeLabel] — daar staat waarom.
  Iterable<String> pieces(String label) =>
      label.split(RegExp(r'(?<=-)|\s+')).where((p) => p.isNotEmpty);

  test('geen enkel type-label breekt midden in een woord, in geen taal', () {
    final breekt = <String>[];
    for (final entry in slideTypeMeta.entries) {
      for (final code in AppLocalizations.languageNames.keys) {
        final label = AppLocalizations.sourceFor(code, entry.value.label);
        final size = FittedTypeLabel.fittedFontSize(
          label,
          cardLabelWidth,
          TextDirection.ltr,
          base: roboto,
        );
        for (final piece in pieces(label)) {
          final w = widthOf(piece, size);
          if (w > cardLabelWidth) {
            breekt.add(
              '$code ${entry.key.name}: "$piece" is ${w.toStringAsFixed(1)}px '
              'op ${size}pt, kaart is ${cardLabelWidth}px',
            );
          }
        }
      }
    }
    expect(
      breekt,
      isEmpty,
      reason:
          'Een stuk dat breder is dan de kaart wordt door Flutter middenin '
          'gebroken, en dat leest als een typefout in plaats van als een '
          'regelovergang. Kort het label in die taal in, of verlaag de vloer '
          'in FittedTypeLabel — maar weet dat 8pt al klein is.\n'
          '${breekt.join('\n')}',
    );
  });

  test('een koppelwoord hoeft niet te krimpen, want daar mag het breken', () {
    // Het Zweedse "Cockpit-instrumentpanel" is 87,3px op 8pt — breder dan de
    // kaart als je het als één woord telt, en dat deed de meting eerst. Flutter
    // breekt er wél: "Cockpit-" / "instrumentpanel", allebei binnen de kaart.
    // Zonder deze regel kromp de kaart naar de vloer voor een label dat op de
    // volle grootte prima leest.
    const zweeds = 'Cockpit-instrumentpanel';
    expect(widthOf(zweeds, FittedTypeLabel.minFontSize), greaterThan(84.0));
    expect(
      FittedTypeLabel.fittedFontSize(
        zweeds,
        cardLabelWidth,
        TextDirection.ltr,
        base: roboto,
      ),
      FittedTypeLabel.baseFontSize,
    );
  });

  testWidgets('en de renderer breekt inderdaad op het koppelteken', (
    tester,
  ) async {
    // De regel hierboven leunt op een aanname over Flutters regelafbreker.
    // Deze toets controleert hem in plaats van hem te geloven: twee regels,
    // allebei smaller dan de kaart, geen afkapping.
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: cardLabelWidth,
              child: FittedTypeLabel(label: 'Cockpit-instrumentpanel'),
            ),
          ),
        ),
      ),
    );

    final paragraph =
        tester.renderObject(find.byType(RichText)) as RenderParagraph;
    final boxes = paragraph.getBoxesForSelection(
      const TextSelection(baseOffset: 0, extentOffset: 23),
    );
    final lines = <int, List<TextBox>>{};
    for (final b in boxes) {
      lines.putIfAbsent(b.top.round(), () => []).add(b);
    }
    expect(lines, hasLength(2), reason: 'hoort op het koppelteken te breken');
    for (final line in lines.values) {
      expect(line.last.right - line.first.left, lessThan(cardLabelWidth));
    }
  });
}
