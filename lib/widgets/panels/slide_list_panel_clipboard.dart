// Part of the slide_list_panel library — see ../slide_list_panel.dart.
// Split out for navigability (kopieer-slide-als-afbeelding, kopieer-naar-
// ander-deck); alle imports leven in het hoofdbestand.
part of 'slide_list_panel.dart';

/// Kopieer [slides] naar een ander open deck (keuze via dialoog).
///
/// De dia's kunnen uit een projectmap komen die niet die van het doel is: hun
/// paden worden absoluut gemaakt tegen [sourceProjectPath] en de bestanden
/// gaan de doelmap in (#2104). Top-level, niet als `extension … on`
/// _SlideListPanelState: zo'n extension telt mee voor het klasse-plafond,
/// en deze route drukt daadwerkelijk gedrag uit de klasse.
Future<void> _copySlidesToOtherDeck(
  WidgetRef ref,
  BuildContext context,
  List<Slide> slides,
  String? sourceProjectPath,
) async {
  if (slides.isEmpty) return;

  final tabs = ref.read(tabsProvider);
  final currentId = tabs.current?.id;
  final targets = tabs.tabs
      .where((t) => t.id != currentId && t.isOpen)
      .toList();

  final messenger = ScaffoldMessenger.of(context);
  if (targets.isEmpty) {
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          context.l10n.d('Geen ander deck open. Open eerst een ander tabblad.'),
        ),
      ),
    );
    return;
  }

  final target = await showDialog<TabInfo>(
    context: context,
    builder: (ctx) {
      final l10n = ctx.l10n;
      return SimpleDialog(
        title: Text(
          slides.length == 1
              ? l10n.d('1 slide kopiëren naar…')
              : '${slides.length} ${l10n.d('slides kopiëren naar…')}',
        ),
        children: [
          for (final t in targets)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, t),
              child: Row(
                children: [
                  const Icon(Icons.slideshow_outlined, size: 16),
                  const SizedBox(width: 8),
                  Expanded(child: Text(t.label)),
                ],
              ),
            ),
        ],
      );
    },
  );
  if (target == null || !context.mounted) return;

  // Een documenttabblad heeft geen deck; die kan geen slides opnemen.
  final targetDeck = target.deckNotifierOrNull;
  if (targetDeck == null) return;

  final adopted = await ref.read(imageServiceProvider).adoptSlideAssets([
    for (final s in slides) absolutizeSlideAssetPaths(s, sourceProjectPath),
  ], targetDeck.currentState.deck?.projectPath);
  if (!context.mounted) return;

  final at = targetDeck.insertSlides(adopted);
  if (at >= 0) target.editorNotifier.select(at);

  final targetIndex = tabs.tabs.indexWhere((t) => t.id == target.id);
  if (targetIndex >= 0) {
    ref.read(tabsProvider.notifier).selectTab(targetIndex);
  }

  if (!context.mounted) return;
  messenger.showSnackBar(
    SnackBar(
      content: Text(
        at >= 0
            ? '${slides.length} ${context.l10n.d('slide(s) gekopieerd naar')} “${target.label}”.'
            : context.l10n.d('Kopiëren mislukt.'),
      ),
    ),
  );
}

/// Rasteren-naar-klembord.
///
/// Functioneel een export: het levert een volledige render van (mogelijk
/// geclassificeerde, mogelijk persoonsgegevens bevattende) slide-inhoud af op het
/// systeemklembord. Daarom loopt het langs dezelfde twee poorten als een echte
/// export — de classificatie-gate en de privacyprojectie.
extension _SlideClipboardExport on _SlideListPanelState {
  /// Render de hele slide naar een afbeelding en kopieer 'm naar het klembord,
  /// zodat je 'm elders kunt plakken.
  /// Fail-closed classificatie-gate voor egress-paden buiten [ExportService].
  /// Rasteren-naar-klembord is functioneel een export: het levert een volledige
  /// render van (mogelijk geclassificeerde) slide-inhoud af op het systeem-
  /// klembord. Zonder deze check zou het vrijgaveplafond omzeild kunnen worden.
  /// Retourneert true als de actie door mag; toont anders de weigerreden.
  ///
  /// Getoetst wordt de strengste van dek en dia. Op `deck.tlp` alleen glipte
  /// een TLP:RED-dia in een TLP:GREEN-dek zo naar het klembord: de dia die
  /// juist de strengste markering droeg was de dia die vertrok.
  bool _classificationAllowsEgress(
    Deck deck,
    Slide slide,
    ScaffoldMessengerState messenger,
  ) {
    final policy = ClassificationEnforcementPolicy.fromAppSettings(
      ref.read(settingsProvider),
    );
    final tlp = effectiveTlp(deckTlp: deck.tlp, slideTlp: slide.tlp);
    final why = exportBlockMessage(context.l10n, policy.evaluate(tlp));
    if (why == null) return true;
    messenger.showSnackBar(SnackBar(content: Text(why)));
    return false;
  }

  Future<void> _copySlideAsImage(Slide slide) async {
    final deck = ref.read(deckProvider).deck;
    if (deck == null) return;
    final messenger = ScaffoldMessenger.of(context);
    if (!_classificationAllowsEgress(deck, slide, messenger)) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(context.l10n.d('Slide renderen…')),
        duration: const Duration(milliseconds: 700),
      ),
    );
    Uint8List? bytes;
    try {
      // Rasteren-naar-klembord is een ontvangend oppervlak: de projectie hoort
      // er dus net zo goed voor te staan als bij een echte export.
      final images = await SlideRasterizer.rasterize(
        context: context,
        audience: PrivacyProjection.forAudience(
          deck.copyWith(slides: [slide]),
          disabledRules: ref.read(settingsProvider).privacyDisabledRules,
          regions: ref.read(settingsProvider).privacyRegions,
          ownIdentity: OwnIdentity.fromLines(
            ref.read(settingsProvider).privacyOwnIdentity,
          ),
        ),
        cockpitColorScheme: ref.read(settingsProvider).cockpitColorScheme,
        showClassificationWatermark: ref
            .read(settingsProvider)
            .classificationWatermarkEnabled,
      );
      if (images.isNotEmpty) bytes = images.first;
    } catch (e) {
      logWarning('_SlideListPanelState._copySlideAsImage: rasterize slide', e);
    }
    if (!mounted) return;
    final ok =
        bytes != null && await ImageService().copyImageBytesToClipboard(bytes);
    if (!mounted) return;
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? context.l10n.d('Slide gekopieerd naar klembord.')
              : context.l10n.d('Kopiëren mislukt.'),
        ),
      ),
    );
  }
}
