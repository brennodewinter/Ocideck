import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';
import 'app.dart';
import 'widgets/presentation/audience_window.dart';

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  // Secondary windows (e.g. the audience/beamer slide window) are launched by
  // desktop_multi_window with these entrypoint arguments. They run a minimal app
  // and must not touch the main window's window_manager setup.
  if (args.isNotEmpty && args.first == 'multi_window') {
    final raw = args.length >= 3 ? args[2] : '';
    final parsed = raw.isEmpty ? const {} : jsonDecode(raw);
    final map = Map<String, dynamic>.from(parsed as Map);
    runApp(AudienceWindowApp(args: map));
    return;
  }

  if (!kIsWeb && (Platform.isMacOS || Platform.isWindows || Platform.isLinux)) {
    await windowManager.ensureInitialized();
    const options = WindowOptions(
      minimumSize: Size(1000, 650),
      title: 'OciDeck',
    );
    windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.show();
      await windowManager.focus();
      await windowManager.setPreventClose(true);
    });
  }

  runApp(const ProviderScope(child: OciDeckApp()));
}
