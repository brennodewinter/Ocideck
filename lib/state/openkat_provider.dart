// De koppeling met OpenKAT (#767, #772, #1158): of de integratie aan staat, en
// de map waarin de OpenKAT-exports staan.
//
// **Waarom de schakelaar hier woont, en niet meer bij de module Importeren.**
// Tot #1158 had OpenKAT bewust geen eigen schakelaar (#772, besluit B1): de
// aan/uit zat in de module Importeren, die ook de presentatie-import dekt. Maar
// #1158 wil integraties elk los kunnen in- en uitschakelen, en dan is één
// gedeelde moduleschakelaar het verkeerde handvat — "OpenKAT uit" zou dan ook
// de presentatie-import doven. OpenKAT is daarom losgemaakt tot een
// eerste-klas integratie met een eigen schakelaar; de module Importeren gaat
// sindsdien alleen nog over presentatie-import.
//
// De scheiding binnen dít bestand blijft langs dezelfde vraag lopen als
// voorheen: [enabled] beantwoordt "hoort deze koppeling bij mijn werk",
// [reportDirectory] "waar staan mijn OpenKAT-bestanden".
//
// [openKatHasContentProvider] is wat de reveal-regel van de integratie inbrengt:
// een aangewezen map is inhoud, en inhoud blijft bereikbaar ook als de
// koppeling uit gaat (de vaste projectregel: uitzetten maakt bestaand werk
// nooit onbereikbaar).
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/openkat/openkat_wizard_models.dart';
import '../platform/platform_features.dart';
import '../utils/log.dart';

/// De voorkeursleutel van de map. Hernoemen mag nooit: dan is de aangewezen map
/// weg.
const _directoryKey = 'openkatReportDirectory';

/// De voorkeursleutel van de schakelaar (#1158). Harde standaard uit; hernoemen
/// mag hierna niet meer, dan staat de koppeling bij een bestaande installatie
/// stil weer uit.
const _enabledKey = 'openkatIntegrationEnabled';

final openKatProvider = NotifierProvider<OpenKatNotifier, OpenKatState>(
  OpenKatNotifier.new,
);

/// De aangewezen map met OpenKAT-exports, of null wanneer er geen staat.
final openKatDirectoryProvider = Provider<String?>((ref) {
  return ref.watch(openKatProvider.select((s) => s.reportDirectory));
});

/// Of de OpenKAT-koppeling aan staat (de bewaarde stand). Harde standaard uit.
final openKatIntegrationEnabledProvider = Provider<bool>((ref) {
  return ref.watch(openKatProvider.select((s) => s.enabled));
});

/// Of OpenKAT op dit platform überhaupt te gebruiken is: de koppeling leest een
/// map van schijf, en die mapkiezer bestaat alleen op desktop (op web geeft
/// `getDirectoryPath` stil null terug, #150). Als provider verpakt zodat het
/// integratieregister er net zo op kan kijken als op elke andere poort.
final openKatAvailableProvider = Provider<bool>((ref) {
  return supportsLocalProjectFolders;
});

/// Wat OpenKAT als "inhoud" inbrengt.
///
/// Een aangewezen rapportagemap betekent dat iemand hier al mee werkt. Zonder
/// deze provider zou de koppeling uitzetten een bestaand OpenKAT-deck
/// onbijwerkbaar maken, en zou de enige weg terug het opnieuw aanwijzen zijn
/// van een map waarvan de app al wist waar hij stond.
final openKatHasContentProvider = Provider<bool>((ref) {
  return ref.watch(openKatDirectoryProvider) != null;
});

/// De poort waar het tabblad, de menu-items en het openscherm op kijken: de
/// koppeling staat aan, óf er is al inhoud. Altijd minstens zo ruim als
/// [openKatIntegrationEnabledProvider].
final openKatIntegrationRevealProvider = Provider<bool>((ref) {
  return ref.watch(openKatIntegrationEnabledProvider) ||
      ref.watch(openKatHasContentProvider);
});

class OpenKatState {
  /// Of de koppeling aan staat (#1158). Standaard uit.
  final bool enabled;

  /// De map met OpenKAT-exports; null zolang er geen gekozen is.
  final String? reportDirectory;

  /// Voorkeuren worden nog geladen bij de eerste opbouw.
  final bool loading;

  /// Recept en bron per open deck. De sleutel is de stabiele recovery-id van
  /// het tabblad, niet "het laatst gebruikte rapport": twee OpenKAT-decks
  /// kunnen zo in dezelfde sessie ieder naar hun eigen bron terug.
  final Map<String, OpenKatDeckSession> deckSessions;

  const OpenKatState({
    this.enabled = false,
    this.reportDirectory,
    this.loading = true,
    this.deckSessions = const {},
  });

  OpenKatState copyWith({
    bool? enabled,
    String? reportDirectory,
    bool clearReportDirectory = false,
    bool? loading,
    Map<String, OpenKatDeckSession>? deckSessions,
  }) => OpenKatState(
    enabled: enabled ?? this.enabled,
    reportDirectory: clearReportDirectory
        ? null
        : (reportDirectory ?? this.reportDirectory),
    loading: loading ?? this.loading,
    deckSessions: deckSessions ?? this.deckSessions,
  );
}

class OpenKatDeckSession {
  final String directory;
  final OpenKatWizardRecipe recipe;

  const OpenKatDeckSession({required this.directory, required this.recipe});
}

class OpenKatNotifier extends Notifier<OpenKatState> {
  bool _directoryChanged = false;
  bool _enabledChanged = false;

  @override
  OpenKatState build() {
    _initialize();
    return const OpenKatState();
  }

  Future<void> _initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final directory = prefs.getString(_directoryKey);
      final storedEnabled = prefs.getBool(_enabledKey) ?? false;
      // Wat de gebruiker in deze sessie al omzette wint van de opgeslagen
      // waarde: het laden mag een net gemaakte keuze niet terugdraaien.
      final directoryHasContent = directory != null && directory.isNotEmpty;
      state = state.copyWith(
        enabled: _enabledChanged ? null : storedEnabled,
        reportDirectory: _directoryChanged || !directoryHasContent
            ? null
            : directory,
        clearReportDirectory: !_directoryChanged && !directoryHasContent,
        loading: false,
      );
    } catch (e, s) {
      // Onleesbare voorkeuren: geen map en uit — de veilige kant — maar het
      // laden stopt wél, anders blijft het tabblad hangen.
      logError('OpenKatNotifier._initialize: read integration state', e, s);
      state = state.copyWith(loading: false);
    }
  }

  /// Zet de koppeling aan of uit en bewaart de keuze.
  Future<void> setEnabled(bool value) async {
    _enabledChanged = true;
    state = state.copyWith(enabled: value, loading: false);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_enabledKey, value);
    } catch (e, s) {
      // De stand voor deze sessie staat al; alleen het bewaren ging mis.
      logError('OpenKatNotifier: prefs-schrijf mislukt (schakelaar)', e, s);
    }
  }

  /// Wijst de map met OpenKAT-exports aan, of wist hem met null.
  Future<void> setReportDirectory(String? directory) async {
    _directoryChanged = true;
    final trimmed = directory?.trim();
    final value = (trimmed == null || trimmed.isEmpty) ? null : trimmed;
    state = state.copyWith(
      reportDirectory: value,
      clearReportDirectory: value == null,
      loading: false,
    );
    try {
      final prefs = await SharedPreferences.getInstance();
      if (value == null) {
        await prefs.remove(_directoryKey);
      } else {
        await prefs.setString(_directoryKey, value);
      }
    } catch (e, s) {
      // De stand voor deze sessie staat al; alleen het bewaren ging mis.
      logError('OpenKatNotifier: prefs-schrijf mislukt', e, s);
    }
  }

  OpenKatDeckSession? sessionForDeck(String deckId) =>
      state.deckSessions[deckId];

  /// Bindt de bron en het recept aan één open deck.
  ///
  /// Dit blijft bewust sessiestaat. De directoryvoorkeur mag op schijf, maar
  /// een opgeslagen deck bevat geen verifieerbare koppeling met die directory;
  /// na herstart vraagt bijwerken daarom opnieuw om de bron.
  void rememberDeckSession({
    required String deckId,
    required String directory,
    required OpenKatWizardRecipe recipe,
  }) {
    state = state.copyWith(
      deckSessions: Map.unmodifiable({
        ...state.deckSessions,
        deckId: OpenKatDeckSession(directory: directory, recipe: recipe),
      }),
    );
  }
}
