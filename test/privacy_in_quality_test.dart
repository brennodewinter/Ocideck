import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/l10n/slide_quality_localization.dart';
import 'package:ocideck/models/privacy_disposition.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/state/deck_provider.dart';
import 'package:ocideck/state/privacy_provider.dart';
import 'package:ocideck/widgets/slides/slide_thumbnail.dart';

const _l10n = AppLocalizations(Locale('nl'));

/// Een geldig, niet-voorbeeld NL-IBAN (mod-97 klopt) — levert een zekere
/// bevinding, en die vertaalt de bridge naar een waarschuwing.
const _iban = 'Rekening NL18RABO0123459876';

void main() {
  setUp(() => AppLocalizations.setActiveLanguageCode('nl'));

  group('uitgevoerde controles', () {
    test('noemt de privacycontrole als die aanstaat', () {
      final checks = slideQualityPerformedChecks(_l10n, privacyEnabled: true);
      expect(
        checks.map((c) => c.title),
        contains(
          'Persoonsgegevens, bijzondere gegevens en geheimen in de tekst',
        ),
      );
      // De belofte die dit product overal herhaalt, hoort ook hier te staan.
      final privacy = checks.firstWhere((c) => c.title.startsWith('Persoons'));
      expect(
        privacy.params,
        contains('garandeert niet dat alles wordt gevonden'),
      );
    });

    test('noemt de privacycontrole niet als die uitstaat', () {
      // "Uitgevoerde controles" is een feitelijke kop. Een controle die niet
      // draaide, hoort er niet onder te staan — dat zou een groene balk laten
      // liegen.
      final checks = slideQualityPerformedChecks(_l10n, privacyEnabled: false);
      expect(
        checks.map((c) => c.title).where((t) => t.startsWith('Persoons')),
        isEmpty,
      );
      // De andere vier blijven staan.
      expect(checks, hasLength(4));
    });
  });

  group('thumbnail-badge', () {
    Future<void> pumpRail(
      WidgetTester tester,
      ProviderContainer container,
    ) async {
      final slide = container.read(deckProvider).deck!.slides.first;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            localizationsDelegates: const [AppLocalizations.delegate],
            home: Scaffold(
              body: SizedBox(
                width: 240,
                height: 260,
                child: SlideThumbnail(
                  slide: slide,
                  index: 0,
                  onTap: () {},
                  onDuplicate: () {},
                  onDelete: () {},
                  onToggleSkip: () {},
                  onCopyImage: () {},
                  onSplit: () {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('een slide met alleen een privacybevinding krijgt een badge', (
      tester,
    ) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(deckProvider.notifier);
      notifier.newDeck('Test');
      final slide = container.read(deckProvider).deck!.slides.single;
      notifier.updateSlide(0, slide.copyWith(bullets: [_iban]));

      // De bevinding bestaat.
      expect(
        container.read(privacyQualityIssuesProvider),
        isNotEmpty,
        reason: 'het IBAN hoort een privacybevinding op te leveren',
      );

      await pumpRail(tester, container);

      // Vóór deze fix keek de badge alleen naar deckQualityProvider en bleef een
      // slide waarvan het énige probleem een IBAN is, ongemarkeerd.
      //
      // De markering zégt sindsdien ook waar ze over gaat. Zolang privacy in de
      // kwaliteitsbadge gevouwen zat, kon hetzelfde oranje bolletje contrast,
      // tekstdichtheid óf een IBAN betekenen — en dan weet je van geen enkele
      // slide waar je naar kijkt.
      expect(find.byTooltip('Persoonsgegevens gevonden'), findsOneWidget);
      expect(find.byTooltip('Kwaliteitsproblemen'), findsNothing);
    });

    testWidgets('een schone slide krijgt geen badge', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(deckProvider.notifier);
      notifier.newDeck('Test');
      final slide = container.read(deckProvider).deck!.slides.single;
      notifier.updateSlide(
        0,
        slide.copyWith(type: SlideType.section, bullets: const []),
      );

      await pumpRail(tester, container);

      expect(find.byTooltip('Kwaliteitsproblemen'), findsNothing);
      expect(
        find.byTooltip('Kwaliteitsproblemen (inclusief ernstige)'),
        findsNothing,
      );
      expect(find.byTooltip('Persoonsgegevens gevonden'), findsNothing);
    });

    testWidgets('een geaccepteerde slide houdt een grijze badge', (
      tester,
    ) async {
      // Dit is de klacht waar deze badge uit voortkomt. Wie een bevinding
      // accepteerde, zag daarna nérgens meer dat er iets gevonden wás: de
      // melding verdween uit het paneel én de badge van de thumbnail, en de
      // slide zag er daarna precies zo uit als een slide waarop niets staat.
      //
      // Accepteren mag niet hetzelfde worden als verbergen. De badge blijft dus
      // staan en wordt grijs — hij zegt "hier is iets, en jij weet ervan".
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(deckProvider.notifier);
      notifier.newDeck('Test');
      final slide = container.read(deckProvider).deck!.slides.single;
      notifier.updateSlide(
        0,
        slide.copyWith(bullets: [_iban], privacy: PrivacyDisposition.accept),
      );

      // Het paneel is stil — daar hoort een afgehandelde beslissing niet meer
      // te zeuren.
      expect(container.read(privacyQualityIssuesProvider), isEmpty);

      await pumpRail(tester, container);

      // Maar de slide is niet stilletjes schoon geworden.
      expect(find.byTooltip('Persoonsgegevens geaccepteerd'), findsOneWidget);
      expect(find.byTooltip('Persoonsgegevens gevonden'), findsNothing);
    });
  });
}
