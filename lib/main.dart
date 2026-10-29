import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'theme/app_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'platform/launch_files.dart';
import 'platform/native_window.dart';
import 'services/bundled_licenses.dart';
import 'services/privacy/privacy_bulk_lexicon.dart';
import 'services/shared_preferences_atomic.dart';
import 'services/asset_staging.dart';
import 'services/disk_traces.dart';
import 'services/single_instance.dart';
import 'utils/log.dart';
import 'widgets/presentation/audience_window.dart';

void main(List<String> args) {
  // Run the whole app inside a guarded zone so that no uncaught error — from a
  // build, a platform callback, or an async gap — can disappear without a trace
  // or leave the UI wedged mid-presentation. Everything is logged via the
  // existing dart:developer sink (quiet in release).
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    _installErrorHandlers();

    // Op Windows/Linux schrijft shared_preferences alles in één JSON-bestand
    // met een niet-atomare write — een afgebroken schrijfbeurt liet elke
    // volgende start op een FormatException vallen (#2628). De atomaire
    // variant schrijft via rename en zet een onleesbaar bestand in
    // quarantaine in plaats van opnieuw te falen. Vóór de eerste
    // getInstance() registreren; op macOS/web is dit een no-op.
    registerAtomicFilePreferences();

    // De fonts, het gezichtsmodel en de gebundelde JavaScript zijn geen
    // Dart-pakketten, dus Flutter's eigen NOTICES-asset kent ze niet. Ze hier
    // aanmelden zorgt dat de licentiepagina ze wél toont — OFL-1.1 §2 laat een
    // lettertype alleen meereizen mét zijn licentie.
    BundledLicenses.register();

    if (!kIsWeb && args.isNotEmpty && args.first == 'multi_window') {
      final raw = args.length >= 3 ? args[2] : '';
      final parsed = raw.isEmpty ? const <String, dynamic>{} : jsonDecode(raw);
      final map = Map<String, dynamic>.from(parsed as Map);
      runApp(AudienceWindowApp(args: map));
      return;
    }

    // Windows/Linux: een bestandsassociatie start de app met het pad als
    // argument. Bewaar het; de shell opent het bij de eerste frame (macOS
    // levert open-events via het ocideck/open_file-kanaal, niet via args).
    if (!kIsWeb) {
      pendingLaunchFiles.addAll(args.where(looksLikeDeckLaunchArg));
    }

    // Linux enkel-exemplaar (#2656): een tweede starter stuurt zijn paden via
    // de Unix-socket naar de primaire en stopt hier, vóór elk zwaar werk —
    // het venster verschijnt pas bij het eerste frame, dus vroeg genoeg is
    // dit helemaal onzichtbaar. (Windows doet dit natief in de runner; macOS
    // regelt exemplaren via het besturingssysteem.)
    if (!kIsWeb && Platform.isLinux) {
      final guard = SingleInstanceGuard();
      if (await guard.forwardToPrimary(pendingLaunchFiles)) {
        // De primaire opent de paden; dit proces bezit niets om op te ruimen.
        exit(0);
      }
      await guard.becomePrimary();
      activeSingleInstance = guard;
    }

    // De opstartwaakhond (#2626): op Windows toont het venster pas bij het
    // eerste frame, dus alles wat daarvoor op de UI-isolate gebeurt is
    // onzichtbaar wachten — onmiskenbaar van een crash. Loopt het eerste
    // frame langer dan tien seconden op zich wachten, dan blijft er ten
    // minste een spoor van waar het stopte.
    final startupWatchdog = Timer(const Duration(seconds: 10), () {
      logWarning('opstart: nog geen eerste frame na 10 s');
    });

    // Het gebundelde gezondheidslexicon start meteen: laden en ontleden
    // (deels in een eigen isolate) is de langste opstartstap, en mag daarom
    // niet op zijn beurt wachten. De `await` komt pas vlak vóór [runApp],
    // zodat de garantie blijft dat de privacyscan nooit zonder lexicon
    // draait (zie de toelichting hieronder).
    final lexiconReady = PrivacyBulkLexicon.instance.ensureLoaded();

    // Bepaal de stagingmap voor media vóór de eerste frame: de UI moet
    // synchroon kunnen zien of een afbeelding daar staat (zie AssetStaging).
    await AssetStaging.initialize();

    await configureNativeWindow();

    // Huishouding start pas ná het eerste frame — het venster is dan
    // zichtbaar en dit werk mag de event loop nooit ononderbroken bezetten.
    // pruneStale zelf is sinds #2626 volledig async; de git-zandbak en de
    // rechtenbeperking zijn eveneens best-effort.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      startupWatchdog.cancel();
      // Oude sessiemappen opruimen.
      unawaited(AssetStaging.pruneStale());
      // De zandbak waarin `git` draait (lege HOME, geen hooks van de
      // gebruiker) bleef na afloop staan met wat git er zelf in achterliet.
      unawaited(DiskTraces().clearGitSandbox());
      // Op Linux leunt de herstelbestand-bescherming op de
      // accountbescherming van het OS (docs/PRIVACY.md).
      unawaited(DiskTraces().restrictToOwner());
    });

    // Het gebundelde gezondheidslexicon vóór de eerste frame, en bewust met
    // `await`. De privacyscan is synchroon en memoiseert per slide; zou dit
    // lexicon halverwege binnenkomen, dan zou dezelfde slide vóór en ná het
    // laden een ander antwoord geven en het gememoiseerde antwoord het oude
    // blijven. Eén keer wachten op een asset van twee megabyte is goedkoper dan
    // die klasse bugs.
    //
    // Faalt het laden, dan draait de scanner op de ingebakken vloer verder —
    // zie PrivacyBulkLexicon.
    await lexiconReady;

    runApp(const ProviderScope(child: OciDeckApp()));
  }, (error, stack) => logError('Uncaught zone error', error, stack));
}

/// Route framework- and platform-level errors through [logError] while keeping
/// the default debug presentation, and show a neutral placeholder instead of a
/// red error box when a widget fails to build in release.
void _installErrorHandlers() {
  final previousOnError = FlutterError.onError;
  FlutterError.onError = (details) {
    logError(
      'FlutterError: ${details.context?.toString() ?? 'widget build'}',
      details.exception,
      details.stack,
    );
    // Preserve the default behaviour (red screen / console dump in debug).
    previousOnError?.call(details);
  };

  // Errors that escape the widget layer (e.g. platform-channel callbacks).
  WidgetsBinding.instance.platformDispatcher.onError = (error, stack) {
    logError('PlatformDispatcher uncaught', error, stack);
    return true; // handled: do not crash the isolate
  };

  // In release, a build failure should not paint a glaring red box over a live
  // presentation; show a quiet placeholder instead. Debug keeps the red box so
  // problems stay obvious during development.
  if (kReleaseMode) {
    ErrorWidget.builder = (details) => const ColoredBox(
      color: AppTheme.darkInk,
      child: Center(
        child: Icon(Icons.warning_amber_rounded, color: AppTheme.gray550),
      ),
    );
  }
}
