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
      // Organisatie-thema's (#2429): alleen voor wie bewust verbonden is.
      if (ref.watch(ociServeProvider).authenticated)
        IconButton(
          tooltip: l10n.d('Thema’s van de organisatie'),
          onPressed: () => OciServeOrgThemes.show(
            context,
            current: _editedProfile(),
            onAdopt: _adoptProfile,
          ),
          icon: const Icon(Icons.groups_outlined, size: 18),
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
    if (_styleProfiles.length <= 1) return;
    final removing = _originalName;
    _styleProfiles = [
      for (final profile in _styleProfiles)
        if (profile.name != removing) profile,
    ];
    _adoptProfile(_styleProfiles.first);
  }

  Future<void> _createProfile() async {
    _commitEditedStyleProfile(this);
    final created = _themeProfile.copyWith(
      name: _uniqueStyleName(this, 'Nieuw profiel'),
    );
    _styleProfiles = [..._styleProfiles, created];
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
  Future<void> _exportProfile() => _exportStyleProfileAndReport(
    ref.read(fileServiceProvider),
    _editedProfile(),
    projectPath: _currentProjectPath,
    messenger: ScaffoldMessenger.of(context),
    l10n: context.l10n,
    stillMounted: () => mounted,
  );

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
    // De naam wordt uniek in de werkkopie. Opslaan schrijft de lijst pas weg;
    // tot dan mag Annuleren het geïmporteerde profiel weer laten vallen.
    final saved = imported.copyWith(
      name: _uniqueStyleName(this, imported.name),
    );
    _styleProfiles = [..._styleProfiles, saved];
    _adoptProfile(saved);

    final renamed = saved.name != imported.name;
    final message = [
      l10n.d('Stijlprofiel geïmporteerd'),
      if (renamed)
        '— ${l10n.d('die naam bestond al, bewaard als')} "${saved.name}"',
      if (outcome.logoOmitted)
        '— ${l10n.d('een ingesloten stijlafbeelding kon niet worden teruggezet')}',
    ].join(' ');
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }
}

/// Zet de editor terug in de werkkopie. Top-level: de dialoogklasse zit tegen
/// haar plafond, en dit is boekhouding van de lijst, geen widget.
void _commitEditedStyleProfile(_SettingsDialogState state) {
  final edited = state._editedProfile();
  final name = _uniqueStyleName(
    state,
    edited.name,
    except: state._originalName,
  );
  final stored = edited.copyWith(name: name);
  final index = state._styleProfiles.indexWhere(
    (p) => p.name == state._originalName,
  );
  if (index < 0) {
    state._styleProfiles = [...state._styleProfiles, stored];
  } else {
    state._styleProfiles = [
      for (var i = 0; i < state._styleProfiles.length; i++)
        if (i == index) stored else state._styleProfiles[i],
    ];
  }
  state._originalName = name;
  state._themeProfile = stored;
  state._profileName.text = name;
}

String _uniqueStyleName(
  _SettingsDialogState state,
  String raw, {
  String? except,
}) {
  final base = raw.trim().isEmpty ? 'Stijlprofiel' : raw.trim();
  final used = state._styleProfiles
      .map((profile) => profile.name)
      .where((name) => name != except)
      .toSet();
  if (!used.contains(base)) return base;
  var index = 2;
  while (used.contains('$base $index')) {
    index++;
  }
  return '$base $index';
}

Future<void> _pickPresentationLogo(_SettingsDialogState state) =>
    _pickStyleLogo(
      state,
      dialogTitle: state.context.l10n.d('Logo kiezen'),
      // Een geïmporteerde merkstrook bevat het oude logo. Bij een bewuste
      // wissel moet die strook weg, anders blijft het vorige merk staan.
      apply: (path) =>
          state._themeProfile.copyWith(logoPath: path, clearBrandStrip: true),
    );

Future<void> _pickDarkPresentationLogo(_SettingsDialogState state) =>
    _pickStyleLogo(
      state,
      dialogTitle: state.context.l10n.d('Donker logo kiezen'),
      apply: (path) => state._themeProfile.copyWith(logoDarkPath: path),
    );

Future<void> _pickDocumentLogo(_SettingsDialogState state) => _pickStyleLogo(
  state,
  dialogTitle: state.context.l10n.d('Logo kiezen'),
  apply: (path) => state._themeProfile.copyWith(documentLogoPath: path),
);

/// Desktop bewaart het pad. Web leest bytes: `PlatformFile.path` bestaat
/// daar niet en een blob-adres zou na herladen nergens heen wijzen.
/// [supportsLocalProjectFolders] is die grens.
Future<void> _pickStyleLogo(
  _SettingsDialogState state, {
  required String dialogTitle,
  required ThemeProfile Function(String path) apply,
}) async {
  final file = await FilePicker.pickFile(
    dialogTitle: dialogTitle,
    type: FileType.image,
  );
  if (!state.mounted || file == null) return;
  final length = await file.length();
  if (!state.mounted) return;
  if (length == null ||
      length <= 0 ||
      length > FileService.maxStyleProfileLogoBytes) {
    _reportRejectedStyleLogo(state);
    return;
  }
  final Uint8List bytes;
  try {
    bytes = await file.readAsBytes();
  } catch (e) {
    logWarning('SettingsDialog: logo lezen mislukt', e);
    if (state.mounted) _reportRejectedStyleLogo(state);
    return;
  }
  if (!state.mounted || styleLogoFromBytes(bytes) == null) {
    if (state.mounted) _reportRejectedStyleLogo(state);
    return;
  }
  final String path;
  if (!supportsLocalProjectFolders) {
    try {
      final name = file.name.trim().isEmpty ? 'logo.png' : file.name;
      path = WebAssetStore.put(bytes, name: name);
    } on WebAssetBudgetExceeded {
      if (state.mounted) _reportRejectedStyleLogo(state);
      return;
    }
  } else {
    final picked = file.path;
    if (picked == null) return;
    path = picked;
  }
  state._rebuild(() {
    state._themeProfile = apply(path);
    state._profileTouched = true;
    rememberStyleEditorMemoryPins(state._themeProfile);
  });
}

void _reportRejectedStyleLogo(_SettingsDialogState state) {
  final l10n = state.context.l10n;
  showErrorSnackBar(
    ScaffoldMessenger.of(state.context),
    l10n,
    l10n.d(
      'Het logo is geen afbeelding of groter dan 8 MB. Kies een kleiner PNG, JPEG, GIF of WebP.',
    ),
  );
}

/// Exporteert [profile] en meldt de uitkomst aan de gebruiker.
///
/// Top-level en niet in `_SettingsDialogState`: het gebruikt niets van de
/// dialoogtoestand behalve wat het meekrijgt, en die klasse zit tegen haar
/// plafond. [stillMounted] blijft nodig omdat het scherm tijdens het exporteren
/// kan sluiten — de melding hoort dan achterwege te blijven, net als voorheen.
Future<void> _exportStyleProfileAndReport(
  FileService fileService,
  ThemeProfile profile, {
  required String? projectPath,
  required ScaffoldMessengerState messenger,
  required AppLocalizations l10n,
  required bool Function() stillMounted,
}) async {
  try {
    final outcome = await fileService.exportStyleProfile(
      profile,
      projectPath: projectPath,
    );
    if (!stillMounted()) return;
    // Afbreken is stil; een geweigerde browserdownload niet — de gebruiker heeft
    // daar niets afgebroken en zou anders denken dat het bestand er is (#1902).
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
                  'Stijlprofiel geëxporteerd — een eigen stijlafbeelding kon niet worden meegenomen',
                )
              : l10n.d('Stijlprofiel geëxporteerd'),
        ),
      ),
    );
  } catch (e) {
    logWarning('SettingsDialog: stijlprofiel exporteren mislukt', e);
    if (!stillMounted()) return;
    showErrorSnackBar(
      messenger,
      l10n,
      l10n.d('Stijlprofiel exporteren mislukt'),
    );
  }
}
