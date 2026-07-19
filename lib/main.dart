import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'theme/app_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'platform/launch_files.dart';
import 'platform/native_window.dart';
import 'services/asset_staging.dart';
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

    // Bepaal de wachtkamer voor media vóór de eerste frame: de UI moet
    // synchroon kunnen zien of een afbeelding daar staat (zie AssetStaging).
    await AssetStaging.initialize();

    await configureNativeWindow();

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
