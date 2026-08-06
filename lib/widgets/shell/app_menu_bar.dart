import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';

/// De handelingen die niet van een open presentatie afhangen.
@immutable
class AppMenuActions {
  final VoidCallback newDeck;
  final VoidCallback newDocument;
  final VoidCallback open;
  final VoidCallback settings;
  final VoidCallback userGuide;
  final VoidCallback shortcuts;

  const AppMenuActions({
    required this.newDeck,
    required this.newDocument,
    required this.open,
    required this.settings,
    required this.userGuide,
    required this.shortcuts,
  });
}

/// De macOS-menubalk van OciDeck.
///
/// Er was er geen. Ongedaan maken en opnieuw bestonden alleen als twee kleine
/// icoontjes in de werkbalk, en de rest van wat de app kan zat verspreid over
/// een `…`-menu, een statusbalk en een commandopalet dat je moet kennen om te
/// vinden. Op macOS is de menubalk de plek waar iemand ontdekt wát een
/// programma kan — en het enige oppervlak dat een schermlezer systematisch
/// afloopt.
///
/// Alleen op macOS. Elders levert deze widget zijn kind ongewijzigd af: Windows
/// en Linux krijgen hun menu van de vensterbeheerder, en op web bestaat er geen.
/// [PlatformProvidedMenuItem] gooit daar bovendien in debug een `ArgumentError`,
/// dus de menu's worden buiten macOS niet eens opgebouwd.
///
/// Knippen, kopiëren, plakken en alles selecteren lopen via
/// [PlatformMenuItem.onSelectedIntent]: die dispatcht naar het veld dat focus
/// heeft, precies zoals de sneltoetsen. Ze staan er omdat ze in het
/// standaard-Xib-menu stonden dat deze balk vervangt — een menubalk toevoegen
/// mag geen tekstbewerking wegnemen.
class AppPlatformMenuBar extends StatelessWidget {
  final AppMenuActions actions;

  /// De handelingen van de werkruimte, of `null` zolang er geen presentatie
  /// open is. Dan blijven de items staan maar uitgeschakeld.
  final AppDeckMenuActions? deckActions;

  final Widget child;

  const AppPlatformMenuBar({
    super.key,
    required this.actions,
    required this.deckActions,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    if (defaultTargetPlatform != TargetPlatform.macOS || kIsWeb) return child;
    return PlatformMenuBar(
      menus: buildAppMenus(context.l10n, actions, deckActions),
      child: child,
    );
  }
}

/// De deck-afhankelijke helft van de menubalk, losgekoppeld van Riverpod zodat
/// [buildAppMenus] puur en toetsbaar blijft.
@immutable
class AppDeckMenuActions {
  final VoidCallback save;
  final VoidCallback export;
  final VoidCallback present;
  final VoidCallback fullDeckPreview;
  final VoidCallback properties;
  final VoidCallback find;
  final VoidCallback findReplace;
  final VoidCallback commandPalette;
  final VoidCallback undo;
  final VoidCallback redo;
  final bool canExport;
  final bool canUndo;
  final bool canRedo;

  const AppDeckMenuActions({
    required this.save,
    required this.export,
    required this.present,
    required this.fullDeckPreview,
    required this.properties,
    required this.find,
    required this.findReplace,
    required this.commandPalette,
    required this.undo,
    required this.redo,
    required this.canExport,
    required this.canUndo,
    required this.canRedo,
  });
}

/// De menustructuur. Publiek en puur: een test kan zo nalopen dat elk menu-item
/// een label, een sneltoets en een werkende handeling heeft, zonder een venster
/// te openen.
///
/// `null` als handeling betekent "uitgeschakeld"; dat is wat [PlatformMenuItem]
/// ervan maakt.
List<PlatformMenuItem> buildAppMenus(
  AppLocalizations l10n,
  AppMenuActions actions,
  AppDeckMenuActions? deck,
) => [
  _appMenu(l10n, actions),
  _fileMenu(l10n, actions, deck),
  _editMenu(l10n, deck),
  _presentationMenu(l10n, deck),
  _windowMenu(l10n),
  _helpMenu(l10n, actions),
];

/// Het applicatiemenu. macOS geeft het de naam van de app; het label hier is
/// wat de tests eraan herkennen.
PlatformMenu _appMenu(AppLocalizations l10n, AppMenuActions actions) =>
    PlatformMenu(
      // Op macOS wordt het eerste menu het applicatiemenu en draagt het de naam
      // van de app; het label hier is wat de tests eraan herkennen.
      label: l10n.d('OciDeck'),
      menus: [
        const PlatformMenuItemGroup(
          members: [
            PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.about),
          ],
        ),
        PlatformMenuItemGroup(
          members: [
            PlatformMenuItem(
              label: l10n.t('settings'),
              shortcut: const SingleActivator(
                LogicalKeyboardKey.comma,
                meta: true,
              ),
              onSelected: actions.settings,
            ),
          ],
        ),
        const PlatformMenuItemGroup(
          members: [
            PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.hide),
            PlatformProvidedMenuItem(
              type: PlatformProvidedMenuItemType.hideOtherApplications,
            ),
            PlatformProvidedMenuItem(
              type: PlatformProvidedMenuItemType.showAllApplications,
            ),
          ],
        ),
        const PlatformMenuItemGroup(
          members: [
            PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.quit),
          ],
        ),
      ],
    );

/// Wat je met het bestand doet: maken, openen, opslaan, exporteren en de
/// eigenschappen ervan.
PlatformMenu _fileMenu(
  AppLocalizations l10n,
  AppMenuActions actions,
  AppDeckMenuActions? deck,
) => PlatformMenu(
  label: l10n.d('Bestand'),
  menus: [
    PlatformMenuItemGroup(
      members: [
        PlatformMenuItem(
          label: l10n.t('newPresentation'),
          shortcut: const SingleActivator(LogicalKeyboardKey.keyN, meta: true),
          onSelected: actions.newDeck,
        ),
        PlatformMenuItem(
          label: l10n.d('Nieuw document'),
          onSelected: actions.newDocument,
        ),
        PlatformMenuItem(
          label: l10n.t('openEllipsis'),
          shortcut: const SingleActivator(LogicalKeyboardKey.keyO, meta: true),
          onSelected: actions.open,
        ),
      ],
    ),
    PlatformMenuItemGroup(
      members: [
        PlatformMenuItem(
          label: l10n.d('Opslaan'),
          shortcut: const SingleActivator(LogicalKeyboardKey.keyS, meta: true),
          onSelected: deck?.save,
        ),
        PlatformMenuItem(
          label: l10n.t('export'),
          onSelected: (deck != null && deck.canExport) ? deck.export : null,
        ),
      ],
    ),
    PlatformMenuItemGroup(
      members: [
        PlatformMenuItem(
          label: l10n.d('Eigenschappen'),
          onSelected: deck?.properties,
        ),
      ],
    ),
  ],
);

/// Ongedaan maken, tekstbewerking en zoeken.
///
/// De tekstbewerking staat er omdat deze balk het standaardmenu van macOS
/// vervangt: wat daar stond moet hier terugkomen, anders neemt een menubalk
/// toevoegen knippen en plakken wég bij wie met het menu werkt.
PlatformMenu _editMenu(
  AppLocalizations l10n,
  AppDeckMenuActions? deck,
) => PlatformMenu(
  label: l10n.d('Bewerken'),
  menus: [
    PlatformMenuItemGroup(
      members: [
        // De sneltoets staat in de kolom ernaast; hem óók in het label
        // zetten (zoals de werkbalktooltip doet) leest als een fout.
        PlatformMenuItem(
          label: l10n.d('Ongedaan maken'),
          shortcut: const SingleActivator(LogicalKeyboardKey.keyZ, meta: true),
          onSelected: (deck != null && deck.canUndo) ? deck.undo : null,
        ),
        PlatformMenuItem(
          label: l10n.d('Opnieuw'),
          shortcut: const SingleActivator(
            LogicalKeyboardKey.keyZ,
            meta: true,
            shift: true,
          ),
          onSelected: (deck != null && deck.canRedo) ? deck.redo : null,
        ),
      ],
    ),
    // Tekstbewerking. Deze balk vervangt het standaardmenu van macOS, dus
    // wat daar stond moet hier terugkomen — anders neemt een menubalk
    // toevoegen knippen en plakken wég bij wie met het menu werkt.
    PlatformMenuItemGroup(
      members: [
        PlatformMenuItem(
          label: l10n.d('Knippen'),
          shortcut: const SingleActivator(LogicalKeyboardKey.keyX, meta: true),
          onSelectedIntent: const CopySelectionTextIntent.cut(
            SelectionChangedCause.keyboard,
          ),
        ),
        PlatformMenuItem(
          label: l10n.d('Kopiëren'),
          shortcut: const SingleActivator(LogicalKeyboardKey.keyC, meta: true),
          onSelectedIntent: CopySelectionTextIntent.copy,
        ),
        PlatformMenuItem(
          label: l10n.d('Plakken'),
          shortcut: const SingleActivator(LogicalKeyboardKey.keyV, meta: true),
          onSelectedIntent: const PasteTextIntent(
            SelectionChangedCause.keyboard,
          ),
        ),
        PlatformMenuItem(
          label: l10n.d('Alles selecteren'),
          shortcut: const SingleActivator(LogicalKeyboardKey.keyA, meta: true),
          onSelectedIntent: const SelectAllTextIntent(
            SelectionChangedCause.keyboard,
          ),
        ),
      ],
    ),
    PlatformMenuItemGroup(
      members: [
        PlatformMenuItem(
          label: l10n.d('Zoeken'),
          shortcut: const SingleActivator(LogicalKeyboardKey.keyF, meta: true),
          onSelected: deck?.find,
        ),
        PlatformMenuItem(
          label: l10n.t('findReplace'),
          shortcut: const SingleActivator(LogicalKeyboardKey.keyH, meta: true),
          onSelected: deck?.findReplace,
        ),
      ],
    ),
  ],
);

/// Wat je met de presentatie zelf doet, plus het commandopalet — de plek waar
/// alles staat wat te weinig gebruikt wordt voor een eigen menu-item.
PlatformMenu _presentationMenu(
  AppLocalizations l10n,
  AppDeckMenuActions? deck,
) => PlatformMenu(
  label: l10n.d('Presentatie'),
  menus: [
    PlatformMenuItemGroup(
      members: [
        PlatformMenuItem(
          label: l10n.d('Presenteren'),
          onSelected: deck?.present,
        ),
        PlatformMenuItem(
          label: l10n.t('fullDeckPreview'),
          onSelected: deck?.fullDeckPreview,
        ),
      ],
    ),
    PlatformMenuItemGroup(
      members: [
        PlatformMenuItem(
          label: l10n.d('Opdrachten…'),
          shortcut: const SingleActivator(LogicalKeyboardKey.keyK, meta: true),
          onSelected: deck?.commandPalette,
        ),
      ],
    ),
  ],
);

/// Het vensterbeheer, geheel door het platform geleverd.
PlatformMenu _windowMenu(AppLocalizations l10n) => PlatformMenu(
  label: l10n.d('Venster'),
  menus: const [
    PlatformMenuItemGroup(
      members: [
        PlatformProvidedMenuItem(
          type: PlatformProvidedMenuItemType.minimizeWindow,
        ),
        PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.zoomWindow),
        PlatformProvidedMenuItem(
          type: PlatformProvidedMenuItemType.toggleFullScreen,
        ),
      ],
    ),
  ],
);

/// De gebundelde documentatie, zonder internet te hoeven raadplegen.
PlatformMenu _helpMenu(AppLocalizations l10n, AppMenuActions actions) =>
    PlatformMenu(
      label: l10n.d('Help'),
      menus: [
        PlatformMenuItemGroup(
          members: [
            PlatformMenuItem(
              label: l10n.d('Gebruikershandleiding'),
              onSelected: actions.userGuide,
            ),
            PlatformMenuItem(
              label: l10n.d('Sneltoetsen'),
              onSelected: actions.shortcuts,
            ),
          ],
        ),
      ],
    );
