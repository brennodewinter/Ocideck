// De instellingen van de OpenKAT-importeur (#767, #772): de map waarin de
// OpenKAT-exports staan.
//
// De schakelaar staat hier bewust níét. Die hoort bij de module "Importeren"
// (`import_module_provider.dart`), die meer importeurs dan alleen OpenKAT dekt —
// besluit B1 van #772. De scheiding loopt langs de vraag die de gebruiker
// stelt: de schakelaar beantwoordt "hoort importeren bij mijn werk", dit
// bestand beantwoordt "waar staan mijn OpenKAT-bestanden".
//
// [openKatHasContentProvider] is wat deze importeur in de reveal-lijst van de
// module inbrengt: een aangewezen map is inhoud, en inhoud blijft bereikbaar
// ook als de module uit gaat.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/openkat/openkat_wizard_models.dart';
import '../utils/log.dart';

/// De voorkeursleutel. Hernoemen mag nooit: dan is de aangewezen map weg.
const _directoryKey = 'openkatReportDirectory';

final openKatProvider = NotifierProvider<OpenKatNotifier, OpenKatState>(
  OpenKatNotifier.new,
);

/// De aangewezen map met OpenKAT-exports, of null wanneer er geen staat.
final openKatDirectoryProvider = Provider<String?>((ref) {
  return ref.watch(openKatProvider.select((s) => s.reportDirectory));
});

/// Wat OpenKAT als "inhoud" inbrengt bij de module Importeren.
///
/// Een aangewezen rapportagemap betekent dat iemand hier al mee werkt. Zonder
/// deze provider zou de module uitzetten een bestaand OpenKAT-deck
/// onbijwerkbaar maken, en zou de enige weg terug het opnieuw aanwijzen zijn
/// van een map waarvan de app al wist waar hij stond.
final openKatHasContentProvider = Provider<bool>((ref) {
  return ref.watch(openKatDirectoryProvider) != null;
});

class OpenKatState {
  /// De map met OpenKAT-exports; null zolang er geen gekozen is.
  final String? reportDirectory;

  /// Voorkeuren worden nog geladen bij de eerste opbouw.
  final bool loading;

  /// Recept en bron per open deck. De sleutel is de stabiele recovery-id van
  /// het tabblad, niet "het laatst gebruikte rapport": twee OpenKAT-decks
  /// kunnen zo in dezelfde sessie ieder naar hun eigen bron terug.
  final Map<String, OpenKatDeckSession> deckSessions;

  const OpenKatState({
    this.reportDirectory,
    this.loading = true,
    this.deckSessions = const {},
  });

  OpenKatState copyWith({
    String? reportDirectory,
    bool clearReportDirectory = false,
    bool? loading,
    Map<String, OpenKatDeckSession>? deckSessions,
  }) => OpenKatState(
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

  @override
  OpenKatState build() {
    _initialize();
    return const OpenKatState();
  }

  Future<void> _initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final directory = prefs.getString(_directoryKey);
      if (_directoryChanged) {
        state = state.copyWith(loading: false);
        return;
      }
      state = state.copyWith(
        reportDirectory: (directory != null && directory.isNotEmpty)
            ? directory
            : null,
        clearReportDirectory: directory == null || directory.isEmpty,
        loading: false,
      );
    } catch (e, s) {
      // Onleesbare voorkeuren: geen map — de veilige kant — maar het laden
      // stopt wél, anders blijft het tabblad hangen.
      logError('OpenKatNotifier._initialize: read report directory', e, s);
      state = state.copyWith(loading: false);
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
