// De uitbreiding Formulieren en inzendingen (FORM_INTAKE.md §7): de organisatorkant
// van een formulier — inzendingen binnenhalen, tegen het gepubliceerde formulier
// houden en bijhouden in een register. Standaard uit.
//
// Een formulier invullen is geen module: een document met een formulier opent
// gewoon op het tabblad Invullen, ook als deze schakelaar uit staat. De module gaat
// over wat een organisator doet met wat binnenkomt.
//
// De werkmap is wat de organisator gekozen heeft: gewone bestanden op schijf
// (§7.1). Zodra er een gekozen is, blijft de functie zichtbaar ook als de
// schakelaar uitgaat — de module-afspraak: uitzetten maakt bestaand werk nooit
// onbereikbaar.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/log.dart';
import 'module_toggle.dart';

const formsEnabledKey = 'formsModuleEnabled';

/// De sleutel van de gekozen werkmap.
const formsWorkspaceKey = 'formsWorkspacePath';

final formsProvider = NotifierProvider<FormsNotifier, ModuleToggleState>(
  FormsNotifier.new,
);

final formsEnabledProvider = Provider<bool>((ref) {
  return ref.watch(formsProvider.select((s) => s.enabled));
});

/// De werkmap die de organisator koos, of `null`.
final formsWorkspaceProvider =
    NotifierProvider<FormsWorkspaceNotifier, String?>(
      FormsWorkspaceNotifier.new,
    );

/// Zichtbaar zodra de schakelaar aan staat óf er een werkmap is gekozen.
final formsRevealProvider = Provider<bool>((ref) {
  return ref.watch(formsEnabledProvider) ||
      ref.watch(formsWorkspaceProvider) != null;
});

class FormsNotifier extends ModuleToggleNotifier {
  FormsNotifier() : super(formsEnabledKey);
}

class FormsWorkspaceNotifier extends Notifier<String?> {
  @override
  String? build() {
    _load();
    return null;
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final path = prefs.getString(formsWorkspaceKey);
      if (path != null && path.isNotEmpty) state = path;
    } catch (e, s) {
      logError('FormsWorkspaceNotifier: voorkeur lezen', e, s);
    }
  }

  Future<void> choose(String path) async {
    state = path;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(formsWorkspaceKey, path);
    } catch (e, s) {
      logError('FormsWorkspaceNotifier: voorkeur schrijven', e, s);
    }
  }
}
