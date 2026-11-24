import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../l10n/app_localizations.dart';
import '../../models/deck.dart';
import '../../models/slide_style.dart';
import '../../state/settings_provider.dart';
import '../../theme/app_theme.dart';
import 'new_deck_dialog.dart' show ThemeProfileSwatch;
import 'settings_dialog.dart';

/// De stijlprofielkeuze in de presentatie-eigenschappen — veel gebruikers
/// zoeken "de look" daar, niet in instellingen. De beheerknop opent het
/// instellingen-tabblad Presentatiestijl.
///
/// De keuze wijzigt alleen de standaardstijl (#3143): een dia met een eigen
/// stijlmarkering (`Slide.styleName`, #2996) behoudt die. Daarom staat eronder
/// hoeveel dia's de keuze níet overnemen, met als expliciete optie "Toepassen
/// op alle dia's" die de markeringen mee wist.
///
/// Een eigen widget, net als [SlideSizePicker]: de dialoog zit aan zijn
/// regelplafond.
class StyleProfilePicker extends ConsumerWidget {
  const StyleProfilePicker({
    super.key,
    required this.deck,
    required this.profileName,
    required this.applyToAll,
    required this.onProfileChanged,
    required this.onApplyToAllChanged,
  });

  /// Het deck waar de tellingen over gaan — `null` behandelen we niet apart:
  /// zonder dia's is er gewoon niets afwijkends.
  final Deck deck;

  /// De nu gekozen profielnaam in het dialoog.
  final String profileName;

  /// Of "Toepassen op alle dia's" aanstaat.
  final bool applyToAll;

  final ValueChanged<String> onProfileChanged;
  final ValueChanged<bool> onApplyToAllChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final profiles = ref.watch(settingsProvider.select((s) => s.themeProfiles));
    final value = profiles.any((p) => p.name == profileName)
        ? profileName
        : profiles.first.name;
    final slides = deck.slides;
    final markerCount = slides.where((s) => s.styleName.isNotEmpty).length;
    var deviating = 0;
    for (var i = 0; i < slides.length; i++) {
      final active = slideStyleNameAt(slides, i);
      if (active != null && active != profileName) deviating++;
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: l10n.t('styleProfile'),
                  isDense: true,
                  prefixIcon: const Icon(Icons.palette_outlined, size: 18),
                  border: const OutlineInputBorder(),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: value,
                    isExpanded: true,
                    isDense: true,
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
                    onChanged: (name) {
                      if (name != null) onProfileChanged(name);
                    },
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: l10n.d('Stijlprofielen beheren…'),
              icon: const Icon(Icons.tune, size: 18),
              onPressed: () => SettingsDialog.show(
                context,
                initialSection: SettingsSection.presentation,
              ),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            l10n.d(
              'Dit is de standaardstijl: dia\'s met een eigen stijlwissel behouden die.',
            ),
            style: TextStyle(fontSize: 11, color: AppTheme.slate400),
          ),
        ),
        if (deviating > 0)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              l10n
                  .d('{n} van de {m} dia\'s houden een afwijkende stijl.')
                  .replaceAll('{n}', '$deviating')
                  .replaceAll('{m}', '${slides.length}'),
              style: TextStyle(fontSize: 11, color: AppTheme.slate400),
            ),
          ),
        if (markerCount > 0)
          CheckboxListTile(
            key: const ValueKey('style-apply-to-all-slides'),
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: Text(l10n.d('Toepassen op alle dia\'s')),
            subtitle: Text(
              l10n
                  .d(
                    'Verwijdert de {n} stijlmarkering(en); elke dia krijgt de gekozen stijl.',
                  )
                  .replaceAll('{n}', '$markerCount'),
              style: const TextStyle(fontSize: 11),
            ),
            value: applyToAll,
            onChanged: (v) => onApplyToAllChanged(v ?? false),
          ),
      ],
    );
  }
}
