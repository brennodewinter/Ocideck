part of 'tabs_provider.dart';

/// Het uitpak-pad van een `.ocideck`-pakket dat in het geheugen is geopend
/// (web, of een import zonder projectmap): de leden naast de hoofd-markdown
/// worden teruggezet in het deck. Apart bestand omdat `tabs_provider` tegen de
/// regelratchet aan zit; de extensie zit in dezelfde library, dus de private
/// helpers blijven bereikbaar.
///
/// Elk type lid heeft zijn eigen route: afbeeldingen gaan naar de
/// [WebAssetStore] en de slidepaden worden naar `mem:` herschreven,
/// grafiekdata wordt inline in de spec gezet, en de sidecars worden als losse
/// lagen op het deck teruggelegd. Wat ze delen is de insluiting: een
/// verwijzing die met `../` buiten de pakketwortel wijst wordt niet gevolgd.
///
/// Hier woont ook [_warnUnfilledChartData], dat beide bytes-paden (los `.md` en
/// pakket) delen: het hoort bij dezelfde vraag — wat kon er zonder projectmap
/// niet worden ingevuld.
extension _TabsPackageAssets on TabsNotifier {
  /// Zet de afbeeldings-leden van een pakket in de [WebAssetStore] en
  /// herschrijf de slidepaden die ernaar verwijzen naar hun mem:-pad.
  /// Verwijzingen zijn relatief aan de hoofd-markdown ([mdName]). Alleen
  /// leden die de afbeeldingsvalidatie (magic bytes + cap) doorstaan doen mee.
  Deck _attachPackageAssets(
    Deck deck,
    List<PackageEntry> entries,
    String mdName,
  ) => attachPackageAssetsToMem(deck, entries, mdName);

  /// Vul chart-slides die hun data via `source` koppelen aan uit de `data/`-
  /// leden van het pakket — het tegenhangertje van `_hydrateCharts` op schijf.
  ///
  /// Anders dan afbeeldingen gaat dit *niet* via de [WebAssetStore]: de data is
  /// tekst die in de spec zelf hoort, en er is op web geen projectmap waar een
  /// los databestand naast kan blijven liggen. Zonder deze stap komt een deck
  /// met gekoppelde grafieken binnen met lege plots.
  Deck _attachPackageChartData(
    Deck deck,
    List<PackageEntry> entries,
    String mdName,
  ) {
    final mdDir = p.posix.dirname(mdName);
    final byName = {
      for (final e in entries) p.posix.normalize(e.name): e.bytes,
    };
    var changed = false;
    final slides = <Slide>[];
    for (final s in deck.slides) {
      final spec = s.type == SlideType.chart
          ? ChartSpec.parse(s.customMarkdown)
          : null;
      final source = spec?.source;
      if (spec == null || source == null || spec.hasInlineData) {
        slides.add(s);
        continue;
      }
      // Zelfde insluiting als resolveProjectRelative op schijf: een `source`
      // als ../../geheim.csv mag niet buiten het pakket wijzen.
      final resolved = p.posix.normalize(
        mdDir == '.' ? source : p.posix.join(mdDir, source),
      );
      final bytes = resolved.startsWith('..') ? null : byName[resolved];
      if (bytes == null ||
          bytes.isEmpty ||
          bytes.length > FileService.maxDeckMarkdownBytes) {
        slides.add(s);
        continue;
      }
      try {
        slides.add(
          s.copyWith(
            // Op de extensie, net als elk ander laadpad ([ChartSpec.withData]):
            // nieuwe databestanden zijn JSON, en die als CSV lezen levert een
            // lege plot zonder één melding.
            customMarkdown: spec
                .withData(utf8.decode(bytes), path: resolved)
                .toBlock(),
          ),
        );
        changed = true;
      } on FormatException catch (e) {
        logWarning('TabsNotifier._attachPackageChartData: data not UTF-8', e);
        slides.add(s);
      }
    }
    return changed ? deck.copyWith(slides: slides) : deck;
  }

  /// Meld de grafieken die met een `source` binnenkomen maar zonder cijfers.
  ///
  /// Van beide bytes-paden (los `.md` én pakket), want geen van beide heeft een
  /// projectmap: een `data/…`-verwijzing valt hier niet op te lossen, dus een
  /// deck dat op schijf is opgeslagen — waar de cijfers juist naar `data/`
  /// verhuizen — tekent hier lege plots. Dat is een grens van het pad, geen
  /// fout; zwijgen erover is er wel een, want een lege plot is niet te
  /// onderscheiden van een grafiek waar nog niets in staat. Zelfde melding als
  /// de schijfvariant in [FileService.openDeckDetailed].
  void _warnUnfilledChartData(Deck deck) {
    final sources = [
      for (final s in deck.slides)
        if (s.type == SlideType.chart)
          if (ChartSpec.parse(s.customMarkdown) case final spec)
            if (spec.source != null && !spec.hasInlineData) spec.source!,
    ];
    if (sources.isEmpty || !mounted) return;
    _ref.read(chartDataWarningProvider.notifier).state = ChartDataWarning(
      sources,
    );
  }

  /// Herstel de sidecar-lagen (ink-annotaties en sprekersnotities) uit de
  /// pakket-leden naast de hoofd-markdown — dezelfde bestandsnamen als de
  /// schijfvariant in [FileService.openDeckDetailed].
  Deck _attachPackageSidecars(
    Deck deck,
    List<PackageEntry> entries,
    String mdName,
  ) {
    final base = mdName.replaceAll(RegExp(r'\.md$', caseSensitive: false), '');
    String? textFor(String memberName) {
      for (final e in entries) {
        if (p.posix.normalize(e.name) == p.posix.normalize(memberName)) {
          try {
            return utf8.decode(e.bytes);
          } on FormatException catch (err) {
            logWarning(
              'TabsNotifier._attachPackageSidecars: sidecar not UTF-8',
              err,
            );
            return null;
          }
        }
      }
      return null;
    }

    var result = deck;
    final ink = textFor('$base.ink.json');
    if (ink != null) {
      try {
        final map = AnnotationCodec.decode(ink, result.slides);
        if (map.isNotEmpty) result = result.copyWith(annotations: map);
      } catch (e) {
        // Een kapotte sidecar mag het openen nooit blokkeren.
        logWarning('TabsNotifier._attachPackageSidecars: ink unreadable', e);
      }
    }
    final notes = textFor('$base.user-notes.json');
    if (notes != null) {
      try {
        final map = UserNotesCodec.decode(notes, result.slides);
        if (map.isNotEmpty) result = result.copyWith(userNotes: map);
      } catch (e) {
        logWarning('TabsNotifier._attachPackageSidecars: notes unreadable', e);
      }
    }
    final miauw = textFor('$base.miauw.json');
    if (miauw != null) {
      try {
        final d = MiauwCodec.decode(miauw);
        if (!d.isEmpty) {
          result = result.copyWith(miauw: d);
        }
      } catch (e) {
        logWarning('TabsNotifier._attachPackageSidecars: MIAUW unreadable', e);
      }
    }
    final seal = textFor('$base.seal.json');
    if (seal != null) {
      try {
        final record = SealCodec.decode(seal);
        if (record != null) result = record.applyTo(result);
      } catch (e) {
        logWarning('TabsNotifier._attachPackageSidecars: seal unreadable', e);
      }
    }
    return result;
  }
}

/// Pak een `.ocideck`/zip-pakket volledig in het geheugen uit en open het:
/// de hoofd-markdown gaat door dezelfde security-gate als elk bytes-open,
/// afbeeldings-leden gaan (na de pickImage-validatie) de [WebAssetStore] in
/// en de slidepaden worden naar hun mem:-pad herschreven, en de sidecars
/// (annotaties, sprekersnotities) reizen mee. Er raakt geen bestandssysteem
/// aan te pas, dus dit werkt ook in de webversie.
Future<OpenResult> _openPackageFromBytes(
  TabsNotifier notifier,
  Uint8List bytes,
  String name, {
  String? remoteOrigin,
}) async {
  // Versleuteld pakket: vraag (met retry) het wachtwoord vóór het decoderen.
  String? password;
  if (FileService.isEncryptedPackage(bytes)) {
    final resolver = notifier.packagePasswordResolver;
    if (resolver == null) return OpenResult.passwordCancelled;
    var retry = false;
    while (true) {
      final pw = await resolver(retry: retry);
      if (pw == null || !notifier.mounted) return OpenResult.passwordCancelled;
      if (notifier._file.canDecodePackage(bytes, pw)) {
        password = pw;
        break;
      }
      retry = true;
    }
  }
  final entries = notifier._file.decodePackageEntries(
    bytes,
    password: password,
  );
  if (entries == null) return OpenResult.unreadable;
  final mdEntry = FileService.mainMarkdownEntry(entries);
  if (mdEntry == null) return OpenResult.notAPresentation;
  final String raw;
  try {
    raw = utf8.decode(mdEntry.bytes);
  } on FormatException catch (e) {
    logWarning('TabsNotifier._openPackageFromBytes: md not UTF-8', e);
    return OpenResult.unreadable;
  }
  final gated = notifier._gateAndParseContent(
    raw,
    sourceName: '$name → ${mdEntry.name}',
  );
  var deck = gated.deck;
  if (deck == null) return gated.failure;

  try {
    deck = notifier._attachPackageAssets(deck, entries, mdEntry.name);
  } on WebAssetBudgetExceeded catch (e) {
    logWarning('TabsNotifier._openPackageFromBytes: webgeheugen vol', e);
    return _failOpen(
      notifier._ref,
      notifier.mounted,
      OpenFailure.memoryBudgetExceeded,
    );
  }
  deck = notifier._attachPackageChartData(deck, entries, mdEntry.name);
  deck = notifier._attachPackageSidecars(deck, entries, mdEntry.name);
  if (!notifier.mounted) return OpenResult.unreadable;
  // Ná het aanhaken: wat het pakket wél meebracht is nu ingevuld, dus wat
  // hier nog leeg is, ontbrak echt.
  notifier._warnUnfilledChartData(deck);
  notifier._placeDeckInTab(deck, remoteOrigin: remoteOrigin);
  return OpenResult.opened;
}
