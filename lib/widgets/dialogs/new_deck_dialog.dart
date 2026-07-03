import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../l10n/app_localizations.dart';
import '../../models/settings.dart';
import '../../state/settings_provider.dart';

/// Uitkomst van de nieuwe-presentatie-dialoog: titel plus het gekozen
/// stijlprofiel. Het profiel staat hier bewust naast de titel — veel
/// gebruikers denken in vormen ("een nette briefing"), niet in een
/// instellingenscherm.
class NewDeckChoice {
  final String title;
  final String profileName;

  const NewDeckChoice({required this.title, required this.profileName});
}

class NewDeckDialog extends ConsumerStatefulWidget {
  const NewDeckDialog({super.key});

  static Future<NewDeckChoice?> show(BuildContext context) {
    return showDialog<NewDeckChoice>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const NewDeckDialog(),
    );
  }

  @override
  ConsumerState<NewDeckDialog> createState() => _NewDeckDialogState();
}

class _NewDeckDialogState extends ConsumerState<NewDeckDialog> {
  final _ctrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  String? _profileName;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final settings = ref.watch(settingsProvider);
    final profiles = settings.themeProfiles;
    final selected = _profileName ?? settings.selectedThemeProfileName;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.pop(context),
      },
      child: AlertDialog(
        title: Text(l10n.d('Nieuwe presentatie')),
        content: Form(
          key: _formKey,
          child: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  controller: _ctrl,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: l10n.d('Titel'),
                    hintText: l10n.d('Bijv. Kwartaalupdate Q4'),
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? l10n.d('Vul een titel in')
                      : null,
                  onFieldSubmitted: (_) => _submit(),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: profiles.any((p) => p.name == selected)
                      ? selected
                      : profiles.first.name,
                  decoration: InputDecoration(
                    labelText: l10n.t('styleProfile'),
                  ),
                  items: [
                    for (final profile in profiles)
                      DropdownMenuItem(
                        value: profile.name,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ThemeProfileSwatch(profile: profile),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                profile.name,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                  onChanged: (name) => setState(() => _profileName = name),
                ),
                const SizedBox(height: 6),
                Text(
                  l10n.d(
                    'Bepaalt kleuren, lettertype en logo. Later aan te passen via de presentatie-eigenschappen of instellingen.',
                  ),
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.t('cancel')),
          ),
          ElevatedButton(onPressed: _submit, child: Text(l10n.d('Aanmaken'))),
        ],
      ),
    );
  }

  void _submit() {
    if (_formKey.currentState!.validate()) {
      final settings = ref.read(settingsProvider);
      Navigator.pop(
        context,
        NewDeckChoice(
          title: _ctrl.text.trim(),
          profileName: _profileName ?? settings.selectedThemeProfileName,
        ),
      );
    }
  }
}

/// Mini-voorproef van een stijlprofiel: titelbalk-, accent- en
/// achtergrondkleur als drie blokjes. Genoeg om profielen op gevoel uit
/// elkaar te houden zonder de dialoog te verzwaren.
class ThemeProfileSwatch extends StatelessWidget {
  final ThemeProfile profile;

  const ThemeProfileSwatch({super.key, required this.profile});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final hex in [
          profile.titleBackgroundColor,
          profile.accentColor,
          profile.slideBackgroundColor,
        ])
          Container(
            width: 12,
            height: 12,
            margin: const EdgeInsets.only(right: 2),
            decoration: BoxDecoration(
              color: _parseHexColor(hex),
              borderRadius: BorderRadius.circular(2),
              border: Border.all(color: Colors.black26, width: 0.5),
            ),
          ),
      ],
    );
  }
}

Color _parseHexColor(String hex) {
  final cleaned = hex.replaceFirst('#', '');
  final value = int.tryParse(cleaned, radix: 16) ?? 0xFFFFFF;
  return Color(0xFF000000 | value);
}
