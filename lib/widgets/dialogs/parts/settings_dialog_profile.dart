// Part of the settings_dialog library — see ../settings_dialog.dart.
// Split out for navigability (stijlprofiel kiezen/beheren + het los
// exporteren en importeren van een profiel); all imports live in the main
// library file. Instance methods relocate verbatim into an extension on
// _SettingsDialogState — same library, same members. Muteren gaat via
// _adoptProfile in de hoofdklasse: setState is protected en dus niet vanuit
// een extension aan te roepen.
part of '../settings_dialog.dart';

String _importFailureText(
  AppLocalizations l10n,
  StyleProfileImportFailure failure,
) => switch (failure) {
  StyleProfileImportFailure.tooLarge => l10n.d(
    'Dit bestand is te groot voor een stijlprofiel',
  ),
  StyleProfileImportFailure.unsupportedVersion => l10n.d(
    'Dit stijlprofiel komt uit een nieuwere versie van OciDeck',
  ),
  StyleProfileImportFailure.memoryBudgetExceeded => webAssetBudgetMessage(l10n),
  // cancelled komt hier nooit: dat handelt _importProfile stil af.
  _ => l10n.d('Dit is geen geldig stijlprofiel-bestand'),
};

extension _SettingsProfile on _SettingsDialogState {
  Widget _profileSelector(List<ThemeProfile> profiles) {
    final l10n = context.l10n;
    final nameField = TextField(
      controller: _profileName,
      textInputAction: TextInputAction.done,
      decoration: InputDecoration(
        labelText: l10n.d('Stijlprofiel'),
        hintText: l10n.d('Naam van het stijlprofiel'),
        isDense: true,
        prefixIcon: const Icon(Icons.style_outlined, size: 18),
        suffixIcon: PopupMenuButton<String>(
          tooltip: l10n.d('Ander profiel kiezen'),
          icon: const Icon(Icons.arrow_drop_down),
          onSelected: _selectProfile,
          itemBuilder: (context) => [
            for (final profile in profiles)
              PopupMenuItem(
                value: profile.name,
                child: Row(
                  children: [
                    if (profile.name == _originalName)
                      const Padding(
                        padding: EdgeInsets.only(right: 8),
                        child: Icon(Icons.check, size: 16),
                      ),
                    Expanded(child: Text(profile.name)),
                  ],
                ),
              ),
          ],
        ),
      ),
      onChanged: (value) {
        final name = value.trim();
        _themeProfile = _themeProfile.copyWith(
          name: name.isEmpty ? _themeProfile.name : name,
        );
        _profileTouched = true;
      },
    );
    final buttons = <Widget>[
      IconButton(
        tooltip: l10n.d('Nieuw profiel'),
        onPressed: _createProfile,
        icon: const Icon(Icons.add, size: 18),
      ),
      IconButton(
        tooltip: l10n.d('Standaardprofiel laden'),
        onPressed: _loadDefaultProfile,
        icon: const Icon(Icons.restart_alt, size: 18),
      ),
      IconButton(
        tooltip: l10n.d('Profiel exporteren'),
        onPressed: _exportProfile,
        icon: const Icon(Icons.file_download_outlined, size: 18),
      ),
      IconButton(
        tooltip: l10n.d('Profiel importeren'),
        onPressed: _importProfile,
        icon: const Icon(Icons.file_upload_outlined, size: 18),
      ),
      IconButton(
        tooltip: l10n.d('Profiel verwijderen'),
        onPressed: profiles.length <= 1 ? null : _deleteProfile,
        icon: const Icon(Icons.delete_outline, size: 18),
      ),
    ];
    // Op smal web (telefoonbreedte) passen vijf 48-px-knoppen niet naast het
    // tekstveld — de Row liep 4 px over (#1885). Onder 400 px gaan de knoppen
    // in een Wrap onder het veld; daarboven blijft de oorspronkelijke Row.
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 400) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              nameField,
              const SizedBox(height: 8),
              Wrap(spacing: 4, runSpacing: 4, children: buttons),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: nameField),
            const SizedBox(width: 8),
            ...buttons,
          ],
        );
      },
    );
  }

  void _loadDefaultProfile() {
    _adoptProfile(ref.read(settingsProvider).themeProfile);
  }

  void _deleteProfile() {
    ref.read(settingsProvider.notifier).deleteThemeProfile(_themeProfile.name);
    _adoptProfile(ref.read(settingsProvider).themeProfile);
  }

  Future<void> _createProfile() async {
    final created = await ref
        .read(settingsProvider.notifier)
        .createThemeProfile(base: _themeProfile);
    if (!mounted) return;
    _adoptProfile(created);
  }

  /// De projectmap van de presentatie die nu open staat — nodig om een
  /// projectrelatief logo (`logos/…`) te kunnen inlezen bij het exporteren.
  String? get _currentProjectPath => ref
      .read(tabsProvider)
      .current
      ?.deckNotifier
      .currentState
      .deck
      ?.projectPath;

  /// Schrijf het profiel zoals het in de editor staat weg als los bestand.
  /// Bewust het bewerkte profiel en niet het opgeslagene: je exporteert wat je
  /// ziet, ook zonder eerst op Opslaan te drukken.
  Future<void> _exportProfile() async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final outcome = await ref
          .read(fileServiceProvider)
          .exportStyleProfile(
            _editedProfile(),
            projectPath: _currentProjectPath,
          );
      if (!mounted) return;
      // Afbreken is stil; een geweigerde browserdownload niet — de gebruiker
      // heeft daar niets afgebroken en zou anders denken dat het bestand er is
      // (#1902).
      if (outcome.downloadRefused) {
        showErrorSnackBar(
          messenger,
          l10n,
          l10n.d(
            'De browser heeft de download niet aangenomen. Sta downloads voor deze site toe en probeer het opnieuw.',
          ),
        );
        return;
      }
      if (!outcome.saved) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            outcome.logoOmitted
                ? l10n.d(
                    'Stijlprofiel geëxporteerd — het eigen logo kon niet worden meegenomen',
                  )
                : l10n.d('Stijlprofiel geëxporteerd'),
          ),
        ),
      );
    } catch (e) {
      logWarning('SettingsDialog: stijlprofiel exporteren mislukt', e);
      if (!mounted) return;
      showErrorSnackBar(
        messenger,
        l10n,
        l10n.d('Stijlprofiel exporteren mislukt'),
      );
    }
  }

  /// Lees een los profielbestand in, bewaar het als nieuw profiel en zet het
  /// meteen in de editor. Opslaan gaat via saveThemeProfile, die de naam al
  /// uniek maakt — vandaar dat we de bewaarde naam daarna teruglezen.
  Future<void> _importProfile() async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final StyleProfileImportOutcome outcome;
    try {
      outcome = await ref.read(fileServiceProvider).importStyleProfile();
    } catch (e) {
      logWarning('SettingsDialog: stijlprofiel importeren mislukt', e);
      if (!mounted) return;
      showErrorSnackBar(
        messenger,
        l10n,
        l10n.d('Stijlprofiel importeren mislukt'),
      );
      return;
    }
    if (!mounted) return;

    final failure = outcome.failure;
    if (failure == StyleProfileImportFailure.cancelled) return;
    if (failure != null) {
      showErrorSnackBar(messenger, l10n, _importFailureText(l10n, failure));
      return;
    }

    final imported = outcome.profile!;
    // previousName matcht bewust geen bestaand profiel: het profiel wordt
    // toegevoegd (met een unieke naam) in plaats van er een te overschrijven.
    await ref
        .read(settingsProvider.notifier)
        .saveThemeProfile(imported, previousName: '');
    if (!mounted) return;

    final saved = ref.read(settingsProvider).themeProfile;
    _adoptProfile(saved);

    final renamed = saved.name != imported.name;
    final message = [
      l10n.d('Stijlprofiel geïmporteerd'),
      if (renamed)
        '— ${l10n.d('die naam bestond al, bewaard als')} "${saved.name}"',
      if (outcome.logoOmitted)
        '— ${l10n.d('het ingesloten logo kon niet worden teruggezet')}',
    ].join(' ');
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }
}
