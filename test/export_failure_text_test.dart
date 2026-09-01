import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/services/download_delivery.dart';
import 'package:ocideck/services/export_result.dart';
import 'package:ocideck/widgets/dialogs/export_failure_text.dart';

/// De tekst bij een mislukte export (#714).
///
/// Wat hier bewaakt wordt is niet de bewoording maar de drie eigenschappen die
/// de melding bruikbaar maken: hij noemt de stap, hij zegt iets anders per stap,
/// en de ruwe uitzondering blijft leesbaar staan. Die laatste is het enige waar
/// een oorzaak uit te herleiden valt — `Invalid argument(s): 1` was in #714
/// nietszeggend als hele melding, maar wél de enige aanwijzing die er was.
void main() {
  const l10n = AppLocalizations(Locale('nl'));

  test('elke stap krijgt zijn eigen zin', () {
    final texts = {
      for (final stage in ExportStage.values)
        stage: exportFailureText(l10n, stage, 'x'),
    };
    expect(texts.values.toSet(), hasLength(ExportStage.values.length));
  });

  test('een gestrand render wijst naar de HTML-export', () {
    // Alleen PDF en PPTX renderen; HTML komt daar niet langs. Dat is precies de
    // omweg die de gebruiker in #714 zelf had gevonden en die de melding hem
    // niet vertelde.
    final text = exportFailureText(l10n, ExportStage.rendering, 'x');
    expect(text, contains('HTML'));
  });

  test('de technische melding blijft staan, maar niet als hele boodschap', () {
    final text = exportFailureText(l10n, ExportStage.writing, ArgumentError(1));
    expect(text, contains('Invalid argument(s): 1'));
    // Er staat een menselijke zin vóór de technische regel, anders is er niets
    // gewonnen ten opzichte van de kale uitzondering.
    expect(text.indexOf('Invalid argument(s)'), greaterThan(40));
  });

  test('de webversie zegt "aangeboden", niet "geëxporteerd naar"', () {
    // Op web weet de pagina niet of het bestand in de downloadmap aankwam. Het
    // kopje mag dus niet hetzelfde zijn als op schijf (#1902).
    final opSchijf = exportDeliveryLabel(l10n);
    debugDeliversByDownload = true;
    addTearDown(() => debugDeliversByDownload = null);
    final inDeBrowser = exportDeliveryLabel(l10n);

    expect(opSchijf, isNot(inDeBrowser));
    expect(opSchijf, contains('Geëxporteerd'));
    expect(inDeBrowser, contains('download'));
  });

  test(
    'een geweigerde download krijgt een zin, geen lege technische regel',
    () {
      final text = exportFailureReasonText(
        l10n,
        ExportFailure.downloadNotStarted,
      );
      expect(text, contains('mislukt'));
      expect(text, contains('downloads'));
      // Geen kopje "Technische melding:" met niets erachter: er ís geen
      // uitzondering, en een leeg kopje leest als een weggevallen fout.
      expect(text, isNot(contains('Technische melding')));
    },
  );
}
