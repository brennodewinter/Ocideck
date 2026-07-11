import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/deck.dart';
import '../../l10n/app_localizations.dart';
import '../../state/settings_provider.dart';
import '../../theme/app_theme.dart';
import 'new_deck_dialog.dart' show ThemeProfileSwatch;
import 'settings_dialog.dart';

/// The editable general metadata of a presentation.
class PresentationInfo {
  final String title;
  final String author;
  final String organization;
  final String version;
  final String date;
  final String description;
  final String keywords;
  final int presentationTargetSeconds;
  final bool showRehearsalSummary;

  /// 'Alleen afspelen'-vergrendeling. Zie [Deck.playOnly].
  final bool playOnly;

  /// Naam van het gekozen stijlprofiel (null = ongewijzigd laten).
  final String? styleProfileName;

  const PresentationInfo({
    required this.title,
    required this.author,
    required this.organization,
    required this.version,
    required this.date,
    required this.description,
    required this.keywords,
    this.presentationTargetSeconds = 0,
    this.showRehearsalSummary = true,
    this.playOnly = false,
    this.styleProfileName,
  });
}

/// Dialog to view and edit a presentation's general metadata (author, version,
/// organization, date, description, keywords). These are stored in the
/// markdown front matter and are therefore also full-text searchable.
class PresentationInfoDialog extends ConsumerStatefulWidget {
  final Deck deck;

  const PresentationInfoDialog({super.key, required this.deck});

  static Future<PresentationInfo?> show(BuildContext context, Deck deck) {
    return showDialog<PresentationInfo>(
      context: context,
      builder: (_) => PresentationInfoDialog(deck: deck),
    );
  }

  @override
  ConsumerState<PresentationInfoDialog> createState() =>
      _PresentationInfoDialogState();
}

class _PresentationInfoDialogState
    extends ConsumerState<PresentationInfoDialog> {
  static const _targetSteps = [
    0,
    300,
    600,
    900,
    1200,
    1500,
    1800,
    2700,
    3600,
    5400,
    7200,
  ];

  /// Sentinel dropdown value for the "custom time" option. When selected the
  /// number of seconds comes from [_customMinutes] instead of a fixed preset.
  static const _customTargetValue = -1;

  late final TextEditingController _title;
  late final TextEditingController _author;
  late final TextEditingController _organization;
  late final TextEditingController _version;
  late final TextEditingController _date;
  late final TextEditingController _description;
  late final TextEditingController _keywords;
  late int _presentationTargetSeconds;
  late bool _useCustomTarget;
  late final TextEditingController _customMinutes;
  late bool _showRehearsalSummary;
  late bool _playOnly;
  late String _profileName;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.deck.title);
    _author = TextEditingController(text: widget.deck.author);
    _organization = TextEditingController(text: widget.deck.organization);
    _version = TextEditingController(text: widget.deck.version);
    _date = TextEditingController(text: widget.deck.date);
    _description = TextEditingController(text: widget.deck.description);
    _keywords = TextEditingController(text: widget.deck.keywords);
    _presentationTargetSeconds = widget.deck.presentationTargetSeconds;
    _useCustomTarget =
        _presentationTargetSeconds > 0 &&
        !_targetSteps.contains(_presentationTargetSeconds);
    _customMinutes = TextEditingController(
      text: _useCustomTarget ? '${_presentationTargetSeconds ~/ 60}' : '',
    );
    _showRehearsalSummary = widget.deck.showRehearsalSummary;
    _playOnly = widget.deck.playOnly;
    _profileName = widget.deck.themeProfile.name;
  }

  @override
  void dispose() {
    _title.dispose();
    _author.dispose();
    _organization.dispose();
    _version.dispose();
    _date.dispose();
    _description.dispose();
    _keywords.dispose();
    _customMinutes.dispose();
    super.dispose();
  }

  void _save() {
    Navigator.pop(
      context,
      PresentationInfo(
        title: _title.text.trim(),
        author: _author.text.trim(),
        organization: _organization.text.trim(),
        version: _version.text.trim(),
        date: _date.text.trim(),
        description: _description.text.trim(),
        keywords: _keywords.text.trim(),
        presentationTargetSeconds: _presentationTargetSeconds,
        showRehearsalSummary: _showRehearsalSummary,
        playOnly: _playOnly,
        styleProfileName: _profileName,
      ),
    );
  }

  void _setCurrentDate() {
    final now = DateTime.now();
    String twoDigits(int value) => value.toString().padLeft(2, '0');
    _date.text = '${now.year}-${twoDigits(now.month)}-${twoDigits(now.day)}';
    _date.selection = TextSelection.collapsed(offset: _date.text.length);
  }

  int get _targetDropdownValue =>
      _useCustomTarget ? _customTargetValue : _presentationTargetSeconds;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.pop(context),
      },
      child: AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.info_outline, size: 20),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                l10n.d('Presentatie-eigenschappen'),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _metadataFields(),
                const SizedBox(height: 16),
                _styleProfileControl(l10n),
                const SizedBox(height: 16),
                _targetTimeControl(l10n),
                const SizedBox(height: 16),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  secondary: const Icon(Icons.timeline_outlined, size: 20),
                  title: Text(l10n.d('Tijden-overzicht tonen na afloop')),
                  subtitle: Text(
                    l10n.d(
                      'De tijd per slide wordt altijd gemeten; dit bepaalt alleen of het overzicht na deze presentatie verschijnt.',
                    ),
                    style: const TextStyle(fontSize: 11),
                  ),
                  value: _showRehearsalSummary,
                  onChanged: (v) => setState(() => _showRehearsalSummary = v),
                ),
                const SizedBox(height: 4),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  secondary: const Icon(Icons.lock_outline, size: 20),
                  title: Text(l10n.d('Alleen afspelen (vergrendeld)')),
                  subtitle: Text(
                    l10n.d(
                      'Vergrendelt het deck tot presenteren: de editor, menu\'s en export zijn niet beschikbaar. Uitzetten kan daarna alleen door de sleutel uit het markdown-bestand te halen.',
                    ),
                    style: const TextStyle(fontSize: 11),
                  ),
                  value: _playOnly,
                  onChanged: (v) => setState(() => _playOnly = v),
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.d(
                    'Deze gegevens worden in de markdown opgeslagen en zijn doorzoekbaar bij het openen.',
                  ),
                  style: TextStyle(fontSize: 11, color: AppTheme.slate400),
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
          ElevatedButton(onPressed: _save, child: Text(l10n.t('save'))),
        ],
      ),
    );
  }

  /// De metadata-invoervelden (titel t/m trefwoorden) van het dialoog.
  Widget _metadataFields() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _field(_title, 'Titel', 'Titel van de presentatie'),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _field(_author, 'Auteur', 'Bijv. Jan Jansen')),
            const SizedBox(width: 12),
            SizedBox(
              width: 120,
              child: _field(_version, 'Versie', 'Bijv. 1.0'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _field(_organization, 'Organisatie', 'Bijv. Vigilis'),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 120,
              child: _field(
                _date,
                'Datum',
                'Bijv. 2026-05-30',
                onDoubleTap: _setCurrentDate,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _field(
          _description,
          'Beschrijving',
          'Korte omschrijving van de presentatie',
          maxLines: 3,
        ),
        const SizedBox(height: 12),
        _field(
          _keywords,
          'Trefwoorden',
          'Komma-gescheiden, bijv. kwartaal, cijfers, 2026',
        ),
      ],
    );
  }

  /// Stijlprofielkeuze, hier zichtbaar naast de metadata: veel gebruikers
  /// zoeken "de look" bij de presentatie-eigenschappen, niet in instellingen.
  /// De beheerknop opent het instellingen-tabblad Presentatiestijl.
  Widget _styleProfileControl(AppLocalizations l10n) {
    final profiles = ref.watch(settingsProvider.select((s) => s.themeProfiles));
    final value = profiles.any((p) => p.name == _profileName)
        ? _profileName
        : profiles.first.name;
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
                      if (name != null) setState(() => _profileName = name);
                    },
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Tooltip(
              message: l10n.d('Stijlprofielen beheren…'),
              child: IconButton(
                icon: const Icon(Icons.tune, size: 18),
                onPressed: () => SettingsDialog.show(context, initialTab: 2),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// De doeltijd-dropdown met toelichting (aftelling in de presenter).
  Widget _targetTimeControl(AppLocalizations l10n) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InputDecorator(
          decoration: InputDecoration(
            labelText: l10n.d('Doeltijd (aftellen)'),
            isDense: true,
            prefixIcon: const Icon(Icons.timer_outlined, size: 18),
            border: const OutlineInputBorder(),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<int>(
              value: _targetDropdownValue,
              isExpanded: true,
              isDense: true,
              items: [
                for (final step in _targetSteps)
                  DropdownMenuItem(
                    value: step,
                    child: Text(
                      step == 0
                          ? l10n.d('Geen aftelling')
                          : '${step ~/ 60} min',
                    ),
                  ),
                DropdownMenuItem(
                  value: _customTargetValue,
                  child: Text(l10n.d('Aangepast…')),
                ),
              ],
              onChanged: (seconds) {
                if (seconds == null) return;
                setState(() {
                  if (seconds == _customTargetValue) {
                    _useCustomTarget = true;
                    // Seed the field from the current value for a smooth switch.
                    final minutes = _presentationTargetSeconds ~/ 60;
                    _customMinutes.text = minutes > 0 ? '$minutes' : '';
                  } else {
                    _useCustomTarget = false;
                    _presentationTargetSeconds = seconds;
                  }
                });
              },
            ),
          ),
        ),
        if (_useCustomTarget)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: SizedBox(
              width: 200,
              child: TextField(
                controller: _customMinutes,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(4),
                ],
                decoration: InputDecoration(
                  labelText: l10n.d('Aangepaste tijd'),
                  suffixText: 'min',
                  isDense: true,
                  prefixIcon: const Icon(Icons.edit_outlined, size: 18),
                  border: const OutlineInputBorder(),
                ),
                onChanged: (value) {
                  final minutes = int.tryParse(value) ?? 0;
                  setState(
                    () => _presentationTargetSeconds = (minutes * 60).clamp(
                      0,
                      86400,
                    ),
                  );
                },
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            l10n.d(
              'Doeltijd voor de aftelling in de presenter. Tijdens presenteren fijn af te stellen met de toets K.',
            ),
            style: TextStyle(fontSize: 11, color: AppTheme.slate400),
          ),
        ),
      ],
    );
  }

  Widget _field(
    TextEditingController controller,
    String label,
    String hint, {
    int maxLines = 1,
    VoidCallback? onDoubleTap,
  }) {
    final l10n = context.l10n;
    final field = TextField(
      controller: controller,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: l10n.d(label),
        hintText: l10n.d(hint),
        isDense: true,
        border: const OutlineInputBorder(),
      ),
    );
    if (onDoubleTap == null) return field;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onDoubleTap: onDoubleTap,
      child: field,
    );
  }
}
