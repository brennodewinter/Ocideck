import 'dart:convert';
import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/app.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/git_settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/models/storage_connection.dart';
import 'package:ocideck/services/git/git_forge.dart';
import 'package:ocideck/state/git_provider.dart';
import 'package:ocideck/state/tabs_provider.dart';
import 'package:ocideck/widgets/app_shell.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'git_forge_fake.dart';

/// "Afbeeldingen in de repository…" (§9.3): het overzicht van de gedeelde pool
/// met per afbeelding wie hem aanhaalt, plus de opruim-kandidaten.
/// `lib/widgets/shell/shell_actions_git_assets.dart` stond op nul uitgevoerde
/// regels, en dat is precies het verkeerde scherm om onbeproefd te laten: het
/// stelt weggooien voor, en weggooien is onomkeerbaar (P2).
///
/// De naad is de forge: [FakeForge] over een [FakeRepo] die de test zelf
/// samenstelt. De handler, de index en het scherm zijn echte code.
///
/// Wat dit bestand NIET dekt: het opruimen zelf — dat bestaat nog niet. Het
/// scherm doet een voorstel en niets meer.
void main() {
  const connectionId = 'git-verbinding';

  const repoConfig = GitRepoConfig(
    baseUrl: 'https://git.example.org',
    owner: 'acme',
    repo: 'decks',
    provider: GitProvider.gitea,
    defaultBranch: 'main',
    trustedInternal: true,
  );

  /// Drie assets met een echte poolvorm (sha256 + extensie); alleen zó telt de
  /// index ze mee.
  final shaA = 'a' * 64;
  final shaB = 'b' * 64;
  final shaC = 'c' * 64;
  String refOf(String sha, [String ext = 'png']) =>
      GitRepoLayout.assetRef(sha, ext)!;

  Uint8List bytes(String s, [int pad = 0]) =>
      Uint8List.fromList([...utf8.encode(s), ...List.filled(pad, 0x20)]);

  late FakeRepo repo;

  setUp(() {
    AppLocalizations.setActiveLanguageCode('nl');
    repo = FakeRepo(
      branches: {'main': 'commit-main'},
      files: {
        // Alfa gebruikt A, bèta gebruikt B; C wordt nergens aangehaald.
        'decks/alfa/deck.md': bytes('# Alfa\n\n![](${refOf(shaA)})\n'),
        'decks/beta/deck.md': bytes('# Beta\n\n![](${refOf(shaB)})\n'),
        'assets/$shaA.png': bytes('A', 400),
        'assets/$shaB.png': bytes('B', 4000),
        'assets/$shaC.png': bytes('C', 3 * 1024 * 1024),
      },
    );
    SharedPreferences.setMockInitialValues({
      'app_consent_accepted': true,
      'storageConnections': jsonEncode([
        GitConnection(
          id: connectionId,
          name: 'Klant A – repo',
          repo: repoConfig,
        ).toJson(),
      ]),
    });
  });

  Finder appBarIcon(IconData icon) =>
      find.descendant(of: find.byType(AppBar), matching: find.byIcon(icon));
  Finder menuItemIcon(IconData icon) => find.descendant(
    of: find.byWidgetPredicate((w) => w is PopupMenuItem),
    matching: find.byIcon(icon),
  );

  /// Pompt de app met [forge] achter de git-verbinding en opent het
  /// pool-overzicht uit het overloopmenu.
  Future<void> openAssetOverview(WidgetTester tester, {GitForge? forge}) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          // De forge rechtstreeks overschrijven houdt de sleutelbos erbuiten:
          // die bestaat niet onder `flutter test`, en zonder stub blijft het
          // token-lezen hangen.
          gitForgeProvider(connectionId).overrideWith((ref) async => forge),
        ],
        child: const OciDeckApp(),
      ),
    );
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(AppShell)),
    );
    container
        .read(tabsProvider)
        .current!
        .deckNotifier
        .loadDeck(
          Deck(
            title: 'Testrapport',
            slides: [
              Slide.create(SlideType.title).copyWith(title: 'Testrapport'),
            ],
          ),
        );
    await tester.pumpAndSettle();

    await tester.tap(appBarIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(menuItemIcon(Icons.photo_library_outlined));
    await tester.pumpAndSettle();
  }

  /// De ingekorte weergave van een verwijzing, zoals het scherm hem toont.
  /// Een sha256-naam is altijd langer dan veertien tekens, dus altijd ingekort.
  String shortOf(String sha, [String ext = 'png']) =>
      '${sha.substring(0, 10)}….$ext';

  testWidgets('het overzicht noemt per afbeelding wie hem aanhaalt', (
    tester,
  ) async {
    await openAssetOverview(tester, forge: FakeForge(repo));

    expect(find.text('Afbeeldingen in de repository'), findsOneWidget);
    expect(find.text('3 afbeeldingen in de gedeelde pool'), findsOneWidget);

    // De naam is ingekort tot iets wat een mens kan vergelijken — kop plus
    // extensie, want de extensie is vaak het enige verschil.
    expect(find.text(shortOf(shaA)), findsOneWidget);
    expect(find.text(shortOf(shaB)), findsOneWidget);
    expect(find.text(shortOf(shaC)), findsOneWidget);

    // En wie hem gebruikt staat eronder, op deknaam.
    expect(find.text('alfa'), findsOneWidget);
    expect(find.text('beta'), findsOneWidget);
    expect(find.text('nergens meer gevonden'), findsOneWidget);
  });

  testWidgets('de grootte staat er in leesbare eenheden bij', (tester) async {
    await openAssetOverview(tester, forge: FakeForge(repo));

    // Drie ordes van grootte, drie vormen: bytes, kilobytes, megabytes. Zonder
    // die omrekening staat er een getal van zeven cijfers en zegt de kolom
    // niets meer.
    expect(find.text('401 B'), findsOneWidget);
    expect(find.text('4 kB'), findsOneWidget);
    expect(find.text('3.0 MB'), findsOneWidget);
  });

  testWidgets('een ongebruikte afbeelding komt als opruim-voorstel terug', (
    tester,
  ) async {
    await openAssetOverview(tester, forge: FakeForge(repo));

    expect(
      find.textContaining('1 afbeeldingen worden nergens meer aangehaald'),
      findsOneWidget,
    );
    // Het blijft een voorstel: op een andere branch kan hij nog in gebruik zijn.
    expect(
      find.textContaining('Dit is een voorstel, geen oordeel'),
      findsOneWidget,
    );
  });

  testWidgets('is alles in gebruik, dan staat dát er — geen lege lijst', (
    tester,
  ) async {
    repo.files.remove('assets/$shaC.png');
    await openAssetOverview(tester, forge: FakeForge(repo));

    expect(find.text('Elke afbeelding wordt ergens gebruikt.'), findsOneWidget);
    expect(find.textContaining('worden nergens meer aangehaald'), findsNothing);
  });

  testWidgets('een onleesbaar deck onderdrukt élk opruim-voorstel', (
    tester,
  ) async {
    // Dit is de kern van het scherm: "niemand gebruikt dit" is een bewering die
    // je niet mag doen op grond van een deck dat je niet hebt kunnen lezen.
    // Weggooien is onomkeerbaar, dus fail-closed — geen lijst, maar de reden.
    await openAssetOverview(
      tester,
      forge: _BrokenDeckForge(repo, 'decks/beta'),
    );

    expect(
      find.textContaining('Niet te zeggen wat ongebruikt is'),
      findsOneWidget,
    );
    expect(find.textContaining('beta'), findsWidgets);
    expect(
      find.textContaining('worden nergens meer aangehaald'),
      findsNothing,
      reason: 'een onvolledige ronde mag geen kandidaat noemen',
    );
    // De lijst zelf staat er nog wél: wat we wél weten blijft bruikbaar.
    expect(find.text('3 afbeeldingen in de gedeelde pool'), findsOneWidget);
  });

  testWidgets('een afbeelding die alleen nog in een release zit is geen '
      'kandidaat', (tester) async {
    // Uit de huidige tekst gehaald, maar de versie van vorig kwartaal gebruikt
    // hem nog. Die versie moet blijven kloppen, dus dit is géén opruimwerk —
    // en het scherm zegt precies waarom.
    repo.tags['decks/alfa/v1.0'] = 'commit-main';
    await openAssetOverview(
      tester,
      forge: _TaggedForge(repo, {
        'decks/alfa/v1.0': '# Alfa v1\n\n![](${refOf(shaC)})\n',
      }),
    );

    expect(
      find.textContaining('alleen nog in een uitgebrachte versie:'),
      findsOneWidget,
    );
    expect(find.textContaining('decks/alfa/v1.0'), findsOneWidget);
    expect(
      find.textContaining('worden nergens meer aangehaald'),
      findsNothing,
      reason: 'een uitgebrachte versie telt als gebruiker',
    );
  });

  testWidgets('een lege pool zegt dat hij leeg is', (tester) async {
    repo.files
      ..remove('assets/$shaA.png')
      ..remove('assets/$shaB.png')
      ..remove('assets/$shaC.png');
    await openAssetOverview(tester, forge: FakeForge(repo));

    expect(find.text('De pool is nog leeg.'), findsOneWidget);
    expect(find.text('0 afbeeldingen in de gedeelde pool'), findsOneWidget);
  });

  testWidgets('sluiten laat het scherm verdwijnen', (tester) async {
    await openAssetOverview(tester, forge: FakeForge(repo));

    await tester.tap(find.widgetWithText(TextButton, 'Sluiten'));
    await tester.pumpAndSettle();

    expect(find.text('Afbeeldingen in de repository'), findsNothing);
  });

  testWidgets('een forge die niet antwoordt meldt dat, zonder scherm', (
    tester,
  ) async {
    await openAssetOverview(tester, forge: _FailingForge(repo));

    expect(find.text('Afbeeldingen in de repository'), findsNothing);
    expect(find.byType(SnackBar), findsOneWidget);
  });

  testWidgets('zonder bruikbare repo komt het scherm er niet', (tester) async {
    // De verbinding staat er (het menu-item dus ook), maar de forge is niet te
    // bouwen. Dan hoort de melding te komen die naar de instellingen wijst.
    await openAssetOverview(tester, forge: null);

    expect(find.text('Afbeeldingen in de repository'), findsNothing);
    expect(
      find.text('Stel eerst een git-repository in bij Instellingen → Opslag.'),
      findsOneWidget,
    );
  });
}

/// Een forge waarvan één deck niet te lezen valt — de onvolledige ronde.
class _BrokenDeckForge extends FakeForge {
  _BrokenDeckForge(super.repo, this.brokenDeckDir);

  final String brokenDeckDir;

  @override
  Future<Uint8List> readBlob(String ref, String path) {
    if (path.startsWith('$brokenDeckDir/')) {
      throw const GitForgeException(GitForgeError.server, 'stuk');
    }
    return super.readBlob(ref, path);
  }
}

/// Een forge waarin een release-tag ándere deck-inhoud draagt dan de branch.
/// [FakeRepo] deelt één bestandsboom, dus zonder dit zou een tag de huidige
/// tekst teruglezen en was het hele verschil onzichtbaar.
class _TaggedForge extends FakeForge {
  _TaggedForge(super.repo, this.atTag);

  /// tag → de `deck.md` op die tag.
  final Map<String, String> atTag;

  @override
  Future<Uint8List> readBlob(String ref, String path) async {
    final markdown = atTag[ref.trim()];
    if (markdown != null) return Uint8List.fromList(utf8.encode(markdown));
    return super.readBlob(ref, path);
  }
}

/// Een forge die er niet is.
class _FailingForge extends FakeForge {
  _FailingForge(super.repo);

  @override
  Future<List<RepoEntry>> listTree(
    String ref,
    String path, {
    bool recursive = false,
  }) async =>
      throw const GitForgeException(GitForgeError.network, 'Geen verbinding');
}
