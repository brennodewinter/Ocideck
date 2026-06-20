import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'platform/native_window.dart';
import 'widgets/presentation/audience_window.dart';

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!kIsWeb && args.isNotEmpty && args.first == 'multi_window') {
    final raw = args.length >= 3 ? args[2] : '';
    final parsed = raw.isEmpty ? const {} : jsonDecode(raw);
    final map = Map<String, dynamic>.from(parsed as Map);
    runApp(AudienceWindowApp(args: map));
    return;
  }

  await configureNativeWindow();

  runApp(const ProviderScope(child: OciDeckApp()));
}
