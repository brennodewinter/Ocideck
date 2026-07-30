// Part of the app_shell library — see ../app_shell.dart.
// Split out for navigability; all imports live in the main library file.
//
// De ontdekkingsbanieren van de optionele modules: een presentatie bevat
// onderdelen van Informatieveiligheid of Procesverbetering terwijl die module
// uit staat, en dan doet OciDeck een aanbod in plaats van de slide stil te
// laten. Eén onderwerp, twee modules, hetzelfde patroon — en samen groot genoeg
// om `app_shell.dart` mee te laten krimpen.
//
// Een extensie en geen aparte klasse: de banier hoort bij de levensduur van de
// schil en houdt zijn toestand in twee velden van [_AppShellState]
// (`_securityPromptTabId`, `_improvementPromptTabId`), want een banier die een
// tabwissel overleeft, beweert iets over de verkeerde presentatie.
part of '../app_shell.dart';

extension _ModulePrompts on _AppShellState {
  /// Een zojuist geopende presentatie bevat Informatieveiligheid-slidetypes
  /// terwijl de module uit staat: bied aan de module aan te zetten (puur
  /// discovery — de slides renderen sowieso gewoon, MODUS-REGEL). De state-laag
  /// seint dit alleen bij het OPENEN; edits raken dit pad nooit, dus de melding
  /// komt precies één keer per open. De module-stand toetsen we hier, op het
  /// verse moment: nog aan het laden of al aan → niets tonen.
  ///
  /// Bewust een [MaterialBanner] en geen snackbar: de gebruiker heeft hier drie
  /// antwoorden — eerst kijken, aanzetten, of wegklikken — en een snackbar
  /// draagt er maar één. Hij verdwijnt ook niet vanzelf na een paar tellen,
  /// want een aanbod dat wegtikt terwijl je nog aan het kijken bent is geen
  /// aanbod. Wegblijven doet hij op precies twee manieren: de gebruiker kiest
  /// iets, of de presentatie waar het over gaat verdwijnt uit beeld.
  void _listenSecurityModulePrompt(BuildContext context) {
    ref.listen<SecurityModulePrompt?>(securityModulePromptProvider, (
      _,
      prompt,
    ) {
      if (prompt == null) return;
      ref.read(securityModulePromptProvider.notifier).state = null;
      final sec = ref.read(infoSafetyProvider);
      if (sec.loading || sec.enabled) return;
      final l10n = context.l10n;
      final messenger = ScaffoldMessenger.of(context);
      // Een tweede open zet de vorige balk opzij in plaats van erachter in de
      // rij: die ging over een presentatie die niet meer voorgrond is.
      messenger.hideCurrentMaterialBanner();
      _securityPromptTabId = prompt.tabId;
      messenger.showMaterialBanner(
        MaterialBanner(
          content: Text(
            l10n.d(
              'Deze presentatie bevat onderdelen van de Informatieveiligheidsmodule. Zet de module aan om ze te bewerken.',
            ),
          ),
          actions: [
            // Sluit de melding niet: je gaat kijken om te beslissen, dus het
            // aanbod moet er nog staan als je terugkomt.
            TextButton(
              onPressed: _showSecuritySlide,
              child: Text(l10n.d('Naar de slide')),
            ),
            TextButton(
              onPressed: () {
                _hideSecurityBanner();
                ref.read(infoSafetyProvider.notifier).enable();
              },
              child: Text(l10n.d('Inschakelen')),
            ),
            IconButton(
              tooltip: l10n.d('Sluiten'),
              icon: const Icon(Icons.close),
              onPressed: _hideSecurityBanner,
            ),
          ],
        ),
      );
    });
  }

  /// Spring naar de eerste Informatieveiligheid-slide, zodat de gebruiker de
  /// bewering van de melding kan controleren vóórdat hij de module aanzet.
  /// Alleen als het bijbehorende tabblad nog vóór staat — anders zou de sprong
  /// in een andere presentatie landen.
  ///
  /// De index wordt hier opnieuw uit het deck gelezen en niet bij het openen
  /// onthouden: tussen de melding en de klik kan de gebruiker slides hebben
  /// verwijderd of verplaatst, en dan wijst een oude index de verkeerde slide
  /// aan.
  void _showSecuritySlide() {
    final tab = ref.read(tabsProvider).current;
    if (tab == null || tab.id != _securityPromptTabId) return;
    if (!tab.deckNotifier.mounted) return;
    final index =
        tab.deckNotifier.currentState.deck?.firstSecuritySlideIndex ?? -1;
    if (index < 0) return;
    tab.editorNotifier.select(index);
  }

  void _hideSecurityBanner() {
    if (_securityPromptTabId == null) return;
    _securityPromptTabId = null;
    ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
  }

  /// Discovery banner for Procesverbetering — same shape as
  /// [_listenSecurityModulePrompt]. Fires when a deck already carries
  /// engine slides (`matrix`, …) while the module is off.
  void _listenImprovementModulePrompt(BuildContext context) {
    ref.listen<ImprovementModulePrompt?>(improvementModulePromptProvider, (
      _,
      prompt,
    ) {
      if (prompt == null) return;
      ref.read(improvementModulePromptProvider.notifier).state = null;
      final mod = ref.read(procesverbeteringProvider);
      if (mod.loading || mod.enabled) return;
      final l10n = context.l10n;
      final messenger = ScaffoldMessenger.of(context);
      messenger.hideCurrentMaterialBanner();
      _improvementPromptTabId = prompt.tabId;
      messenger.showMaterialBanner(
        MaterialBanner(
          content: Text(
            l10n.d(
              'Deze presentatie bevat onderdelen van de Procesverbetering-module. Zet de module aan om ze te bewerken.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: _showImprovementSlide,
              child: Text(l10n.d('Naar de slide')),
            ),
            TextButton(
              onPressed: () {
                _hideImprovementBanner();
                ref.read(procesverbeteringProvider.notifier).enable();
              },
              child: Text(l10n.d('Inschakelen')),
            ),
            IconButton(
              tooltip: l10n.d('Sluiten'),
              icon: const Icon(Icons.close),
              onPressed: _hideImprovementBanner,
            ),
          ],
        ),
      );
    });
  }

  void _showImprovementSlide() {
    final tab = ref.read(tabsProvider).current;
    if (tab == null || tab.id != _improvementPromptTabId) return;
    if (!tab.deckNotifier.mounted) return;
    final index =
        tab.deckNotifier.currentState.deck?.firstImprovementSlideIndex ?? -1;
    if (index < 0) return;
    tab.editorNotifier.select(index);
  }

  void _hideImprovementBanner() {
    if (_improvementPromptTabId == null) return;
    _improvementPromptTabId = null;
    ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
  }

  void _syncImprovementBannerWithTabs(TabsState tabs) {
    if (_improvementPromptTabId == null) return;
    final current = tabs.current;
    if (current == null ||
        current.id != _improvementPromptTabId ||
        !current.isOpen ||
        !current.deckNotifier.mounted) {
      _hideImprovementBanner();
      return;
    }
    final deck = current.deckNotifier.currentState.deck;
    if (deck == null || !deck.hasImprovementSlides) _hideImprovementBanner();
  }

  /// Haal de melding weg zodra ze niet meer waar is. Dat gebeurt op twee
  /// manieren, en allebei laten ze een blijvende balk iets beweren dat niet
  /// klopt:
  ///
  /// 1. De presentatie staat niet meer vóór — een andere tab gekozen, het
  ///    tabblad gesloten, of het deck dichtgeklapt. De balk zou dan over de
  ///    volgende presentatie hangen.
  /// 2. De laatste Informatieveiligheid-slide is weggehaald. De balk zegt dat
  ///    deze presentatie module-onderdelen bevat; verwijder je ze, dan is dat
  ///    simpelweg niet meer zo, en biedt hij aan iets aan te zetten waar niets
  ///    meer voor te bewerken valt.
  ///
  /// Dit draait op elke wijziging van [tabsProvider], en die volgt ook de
  /// deck-stream — een verwijderde slide komt hier dus vanzelf langs.
  void _syncSecurityBannerWithTabs(TabsState tabs) {
    if (_securityPromptTabId == null) return;
    final current = tabs.current;
    if (current == null ||
        current.id != _securityPromptTabId ||
        !current.isOpen ||
        !current.deckNotifier.mounted) {
      _hideSecurityBanner();
      return;
    }
    final deck = current.deckNotifier.currentState.deck;
    if (deck == null || !deck.hasSecuritySlides) _hideSecurityBanner();
  }
}
