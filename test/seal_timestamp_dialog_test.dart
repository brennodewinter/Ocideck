import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/file_service.dart';
import 'package:ocideck/services/image_service.dart';
import 'package:ocideck/services/markdown_service.dart';
import 'package:ocideck/state/deck_provider.dart';
import 'package:ocideck/widgets/dialogs/seal_timestamp_dialog.dart';

import 'rfc3161_token_fixture.dart';

/// Bewijsmateriaal-gereedschap: het scherm waarmee een tester een RFC
/// 3161-tijdstempel over de zegel-hash aanvraagt en de teruggekregen token
/// inleest. Wat hier getoetst wordt is wat de gebruiker eruit afleidt — of het
/// deck getijdstempeld is, of de token bij *dit* zegel hoort, en dat het scherm
/// nooit meer belooft dan er gecontroleerd is (de TSA-handtekening wordt
/// bewust niet geverifieerd, §8-A3).
///
/// De bestandskiezer zelf blijft buiten beeld: die is platformspul. De
/// beslissingen eromheen — een kapotte zegel-hash levert geen verzoek op, een
/// niet-passende token wordt niet als bewijs gepresenteerd — zitten hier wel in.
void main() {
  setUp(() => AppLocalizations.setActiveLanguageCode('nl'));

  DeckNotifier notifier() {
    final md = MarkdownService();
    return DeckNotifier(
      md,
      FileService(md, ImageService(), () => const ThemeProfile()),
    );
  }

  final digest = sampleSealDigest();
  final sealHash = hexOf(digest);

  Deck sealedDeck({String hash = '', String token = ''}) => Deck(
    title: 'Pentestrapport',
    slides: [Slide.create(SlideType.title)],
    sealHash: hash,
    sealTimestampToken: token,
  );

  Future<DeckNotifier> pumpDialog(WidgetTester tester, Deck deck) async {
    final n = notifier()..loadDeck(deck);
    addTearDown(n.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: SealTimestampDialog(notifier: n)),
      ),
    );
    await tester.pumpAndSettle();
    return n;
  }

  testWidgets('een onverzegeld deck krijgt geen knoppen, maar een opdracht', (
    tester,
  ) async {
    await pumpDialog(tester, sealedDeck());

    expect(find.text('Verzegel het deck eerst.'), findsOneWidget);
    // Zonder zegel valt er niets te stempelen; de knoppen horen weg te zijn.
    expect(
      find.widgetWithText(OutlinedButton, 'Verzoek (.tsq) exporteren'),
      findsNothing,
    );
    expect(
      find.widgetWithText(OutlinedButton, 'Token (.tsr) importeren'),
      findsNothing,
    );
  });

  testWidgets('een verzegeld deck zonder token zegt dat met zoveel woorden', (
    tester,
  ) async {
    await pumpDialog(tester, sealedDeck(hash: sealHash));

    expect(find.text('Nog geen tijdstempel'), findsOneWidget);
    // De hash staat afgekort in beeld, zodat de tester kan vergelijken met wat
    // hij naar de TSA stuurt.
    expect(find.textContaining(sealHash.substring(0, 24)), findsOneWidget);
    expect(
      find.widgetWithText(OutlinedButton, 'Verzoek (.tsq) exporteren'),
      findsOneWidget,
    );
  });

  testWidgets('een passende token toont het tijdstip én het voorbehoud', (
    tester,
  ) async {
    final token = fakeTimeStampToken(digest, '20260712120000Z');
    await pumpDialog(
      tester,
      sealedDeck(hash: sealHash, token: base64Url.encode(token)),
    );

    expect(find.textContaining('2026-07-12T12:00:00'), findsOneWidget);
    // Nooit een groen "geverifieerd"-vinkje: alleen de hash is gecontroleerd.
    expect(
      find.text(
        'De TSA-handtekening is niet in-app geverifieerd; alleen de hash komt overeen.',
      ),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.schedule), findsOneWidget);
    expect(find.byIcon(Icons.error_outline), findsNothing);
  });

  testWidgets('een token over een ánder document wordt afgekeurd', (
    tester,
  ) async {
    // Zelfde vorm, andere imprint: precies het geval waarin een tijdstempel
    // niets bewijst over dit deck.
    final other = fakeTimeStampToken(
      List.generate(64, (i) => 255 - i),
      '20260712120000Z',
    );
    await pumpDialog(
      tester,
      sealedDeck(hash: sealHash, token: base64Url.encode(other)),
    );

    expect(
      find.text('Tijdstempel komt niet overeen met de seal-hash'),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.error_outline), findsOneWidget);
    expect(find.textContaining('2026-07-12'), findsNothing);
  });

  testWidgets('een onleesbare token wordt afgekeurd, niet genegeerd', (
    tester,
  ) async {
    // Geen geldige base64url: het veld is beschadigd geraakt. Ook dan mag het
    // scherm geen tijdstip verzinnen.
    await pumpDialog(
      tester,
      sealedDeck(hash: sealHash, token: 'dit is geen base64!!'),
    );

    expect(
      find.text('Tijdstempel komt niet overeen met de seal-hash'),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.error_outline), findsOneWidget);
  });

  testWidgets('een kapotte zegel-hash levert geen verzoek op', (tester) async {
    // Een halve hex-hash: eerder werd die half ingelezen en werd er alsnog een
    // .tsq geëxporteerd — dan laat je een TSA een document stempelen dat niet
    // bestaat. De export moet stoppen vóór de bestandskiezer.
    await pumpDialog(tester, sealedDeck(hash: 'abc'));

    // Het scherm zelf mag er ook niet op stukgaan: substring(0, 24) op een
    // kortere hash gaf een RangeError en er kwam geen dialoog in beeld.
    expect(find.textContaining('SHA-512: abc'), findsOneWidget);

    await tester.tap(
      find.widgetWithText(OutlinedButton, 'Verzoek (.tsq) exporteren'),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      find.descendant(
        of: find.byType(SnackBar),
        matching: find.text('Tijdstempel komt niet overeen met de seal-hash'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('de status volgt de notifier zonder heropenen', (tester) async {
    final n = await pumpDialog(tester, sealedDeck(hash: sealHash));
    expect(find.text('Nog geen tijdstempel'), findsOneWidget);

    // Wat een geslaagde import doet: de token op het deck zetten. Het scherm
    // luistert mee, dus het moet meteen bijdraaien.
    n.setSealTimestampToken(
      base64Url.encode(fakeTimeStampToken(digest, '20260712120000Z')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Nog geen tijdstempel'), findsNothing);
    expect(find.textContaining('2026-07-12T12:00:00'), findsOneWidget);
  });

  testWidgets('sluiten haalt het scherm weg', (tester) async {
    final n = notifier()..loadDeck(sealedDeck(hash: sealHash));
    addTearDown(n.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => SealTimestampDialog.show(context, n),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(SealTimestampDialog), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Sluiten'));
    await tester.pumpAndSettle();
    expect(find.byType(SealTimestampDialog), findsNothing);
  });
}
