// Part of the slide_list_panel library — see ../slide_list_panel.dart.
// Split out for navigability (kopieer-slide-als-afbeelding); alle imports leven in
// het hoofdbestand. Verhuisd zonder gedragswijziging.
part of 'slide_list_panel.dart';

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
    final decision = policy.evaluate(
      effectiveTlp(deckTlp: deck.tlp, slideTlp: slide.tlp),
    );
    if (!decision.allowed) {
      messenger.showSnackBar(SnackBar(content: Text(decision.reason!)));
      return false;
    }
    return true;
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
