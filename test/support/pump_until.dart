import 'package:flutter_test/flutter_test.dart';

/// Wacht tot [ready] waar is, in plaats van tot de klok een gok heeft ingehaald.
///
/// ── Waarom dit bestaat ──
///
/// Een widgettest draait op nep-tijd: `pump` zet de klok vooruit zonder dat er
/// echte tijd verstrijkt. Werk dat de echte gebeurtenislus nodig heeft —
/// `Picture.toImage`, PNG-codering, een maplezing — komt daar niet vooruit. Daar
/// is [WidgetTester.runAsync] voor: binnen die callback loopt de echte lus wél.
///
/// De valkuil zit in wat er dan meestal staat: `runAsync(() => Future.delayed(
/// const Duration(milliseconds: 80)))`. Die 80 is een gok op hoe lang echt werk
/// duurt op deze machine. Onder de volle suite — meerdere sessies tegelijk op
/// één machine — is de gok soms te krap, en dan faalt de test op iets wat een
/// paar milliseconden later wél klaar was. Het getal verhogen verplaatst de gok
/// alleen: te ruim is elke groene draai trager, te krap is af en toe rood.
///
/// Deze hulp draait de vraag om. Ze wisselt korte stapjes echte tijd af met een
/// `pump`, en kijkt na elke stap of het resultaat er ís. Klaar na 5 ms? Dan
/// duurt de test 5 ms. Duurt het onder belasting 3 seconden? Dan wacht ze 3
/// seconden. De bovengrens is er alleen om een vastloper te laten falen met een
/// leesbare melding in plaats van met een time-out van het testframework.
///
/// ── Gebruik ──
///
/// ```dart
/// await tester.tap(find.text('Klaar'));
/// await pumpUntil(tester, () => result != null, reason: 'de dialoog gaf niets terug');
/// ```
///
/// [ready] wordt ná een `pump` aangeroepen, dus een voorwaarde over de
/// widgetboom (`find.byType(X).evaluate().isNotEmpty`) mag ook.
///
/// De `pump` ná elke stap echte tijd is geen bijzaak: het werk komt vooruit in
/// [WidgetTester.runAsync], maar wat erop volgt — een `Navigator.pop`, een
/// `setState`, de voortzetting achter een `await` in de aanroeper — heeft een
/// frame nodig om zichtbaar te worden. Alleen `runAsync` en dan meten ziet het
/// resultaat dus nét niet.
///
/// `pumpAndSettle` is hier geen alternatief: een knipperende tekstcursor
/// (autofocus) of een voortgangsindicator laat de framewachtrij nooit
/// leeglopen, en dan loopt die af op een time-out. Losse frames hebben daar
/// geen last van.
///
/// ── Wacht op de uitkomst die je bewéért ──
///
/// Kies als [ready] de voorwaarde waar de test daarna op controleert, niet een
/// voorwaarde die er ongeveer op lijkt. In `duplicate_cleanup_dialog_test` bleek
/// dat het verschil te maken: het bestand was al van schijf en de rij al uit de
/// lijst, terwijl de knop nog even actief bleef. Precies dat gat kocht de vaste
/// wachttijd die daar stond.
///
/// ── Waar dit bewust níét gebruikt wordt ──
///
/// * `media_lifecycle_test` en `media_previews_video_coverage_test` wachten met
///   20 ms tot een stream-subscription van een *nep* videoplatform sluit. Dat is
///   een wachtrij die leegloopt, geen zwaar werk dat traag kan zijn, en er is
///   geen gedeelde waarneembare uitkomst om op te wachten — elke aanroepplek
///   verwacht andere `calls`. Een vaste flush is daar de eerlijke vorm.
/// * `image_carousel_picker_smoke_test.settle` na een klik of een zoekterm: daar
///   valt niets aan te wijzen dat "klaar" betekent; het is tot rust laten komen.
///   De initiële mapscan in dezelfde test wacht wél op de indicator.
/// * `shell_webdav_actions_test` en `shell_s3_actions_test` doen dit al met de
///   hand, en anders: daar moet de *handeling zelf* binnen [runAsync] beginnen
///   omdat een isolate die daarbuiten start in een testproces hangt na de eerste
///   keer. Die volgorde omdraaien zou die tests stukmaken.
Future<void> pumpUntil(
  WidgetTester tester,
  bool Function() ready, {
  Duration timeout = const Duration(seconds: 10),
  Duration step = const Duration(milliseconds: 20),
  String? reason,
}) async {
  if (ready()) return;
  final clock = Stopwatch()..start();
  while (clock.elapsed < timeout) {
    // Echte tijd: hier komt het werk vooruit dat de echte gebeurtenislus nodig
    // heeft. Kort, zodat we er niet langer in blijven dan nodig.
    await tester.runAsync(() => Future<void>.delayed(step));
    // Nep-tijd: één frame, zodat het gevolg van dat werk de boom bereikt.
    await tester.pump(step);
    if (ready()) return;
  }
  fail(
    'pumpUntil gaf het op na ${timeout.inMilliseconds} ms'
    '${reason == null ? '' : ': $reason'}. '
    'Verhoog de bovengrens niet zomaar — dit betekent meestal dat de '
    'voorwaarde nooit waar wordt, niet dat de machine traag is.',
  );
}
