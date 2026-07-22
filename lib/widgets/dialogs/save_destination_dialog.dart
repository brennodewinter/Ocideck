import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../../l10n/app_localizations.dart';
import '../../models/library_folder.dart';
import '../../theme/app_theme.dart';
import '../../platform/platform_features.dart';

/// Uitkomst van de bestemmingsdialoog: de gekozen doelmap (of null om op de
/// standaardlocatie te beginnen). `null` uit [SaveDestinationDialog.show] zelf
/// betekent dat de gebruiker annuleerde — dat is iets anders dan doorgaan
/// zonder een specifieke map.
class SaveDestinationChoice {
  final String? directory;
  const SaveDestinationChoice(this.directory);
}

/// Bestemmingsdialoog voor een nieuwe presentatie: kies een bibliotheek (of een
/// andere map) en zie precies waar de presentatie, afbeeldingen en media komen
/// te staan, vóórdat het systeem-opslaanvenster opent. Geeft de gekozen map
/// terug als startmap voor dat venster; annuleren geeft null.
class SaveDestinationDialog extends StatefulWidget {
  final List<LibraryFolder> libraries;
  final String deckTitle;

  const SaveDestinationDialog({
    super.key,
    required this.libraries,
    required this.deckTitle,
  });

  static Future<SaveDestinationChoice?> show(
    BuildContext context, {
    required List<LibraryFolder> libraries,
    required String deckTitle,
  }) {
    return showDialog<SaveDestinationChoice>(
      context: context,
      builder: (_) =>
          SaveDestinationDialog(libraries: libraries, deckTitle: deckTitle),
    );
  }

  @override
  State<SaveDestinationDialog> createState() => _SaveDestinationDialogState();
}

class _SaveDestinationDialogState extends State<SaveDestinationDialog> {
  /// De gekozen doelmap. Start op de eerste bibliotheek; null betekent dat het
  /// systeemvenster op de standaardlocatie opent.
  String? _selectedPath;

  /// Een via "Andere map…" gekozen map die niet in de bibliotheken zit — als
  /// aparte optie getoond zodat de keuze zichtbaar blijft.
  String? _customPath;

  @override
  void initState() {
    super.initState();
    _selectedPath = widget.libraries.isEmpty
        ? null
        : widget.libraries.first.path;
  }

  /// Bestandsnaam-voorbeeld — spiegelt `FileService.saveDeckAs` zodat de preview
  /// klopt met wat het systeemvenster voorinvult.
  String get _fileName {
    final safe = widget.deckTitle
        .replaceAll(RegExp(r'[^\w\s-]'), '')
        .replaceAll(' ', '_');
    return '${safe.isEmpty ? 'presentatie' : safe}.md';
  }

  Future<void> _pickCustom() async {
    // Ook hier, niet alleen bij de aanroeper in deck_provider.dart: op web
    // bestaat `getDirectoryPath` niet en geeft het stil null terug, en dan
    // doet de knop niets zonder één woord uitleg (#150). De poort bij de
    // aanroeper is vandaag correct, maar dit bestand kon dat niet zelf
    // bewijzen — en een garantie die elders staat, verdwijnt bij de
    // eerstvolgende nieuwe aanroeper.
    if (!supportsLocalProjectFolders) return;
    final result = await FilePicker.getDirectoryPath(
      dialogTitle: context.l10n.d('Map kiezen'),
      initialDirectory: _selectedPath,
    );
    if (!mounted || result == null) return;
    setState(() {
      _customPath = result;
      _selectedPath = result;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.save_outlined, size: 20),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              l10n.d('Presentatie opslaan'),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.libraries.isEmpty
                  ? l10n.d('Kies een map om de presentatie in te bewaren.')
                  : l10n.d('Kies in welke bibliotheek de presentatie komt.'),
              style: TextStyle(fontSize: 12, color: AppTheme.slate500),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final lib in widget.libraries)
                      _option(lib.name, lib.path),
                    if (_customPath != null)
                      _option(p.basename(_customPath!), _customPath!),
                  ],
                ),
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _pickCustom,
                icon: const Icon(Icons.folder_open_outlined, size: 16),
                label: Text(l10n.d('Andere map…')),
              ),
            ),
            const SizedBox(height: 8),
            _summary(l10n),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.t('cancel')),
        ),
        ElevatedButton.icon(
          onPressed: () =>
              Navigator.pop(context, SaveDestinationChoice(_selectedPath)),
          icon: const Icon(Icons.drive_file_rename_outline, size: 16),
          label: Text(l10n.d('Kies bestandsnaam…')),
        ),
      ],
    );
  }

  Widget _option(String name, String path) {
    final selected = _selectedPath == path;
    return Semantics(
      button: true,
      selected: selected,
      label: name.trim().isEmpty ? p.basename(path) : name,
      child: InkWell(
        onTap: () => setState(() => _selectedPath = path),
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
          child: Row(
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                size: 18,
                color: selected ? AppTheme.accentFg : AppTheme.slate400,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name.trim().isEmpty ? p.basename(path) : name,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      path,
                      style: TextStyle(fontSize: 11, color: AppTheme.slate400),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Samenvatting van waar de bestanden landen. Met een gekozen map de concrete
  /// paden; zonder map een uitleg van het model (submappen naast het bestand).
  Widget _summary(AppLocalizations l10n) {
    final folder = _selectedPath;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.slate50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.slate200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.d('Zo worden de bestanden bewaard'),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppTheme.slate500,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 8),
          if (folder == null)
            Text(
              l10n.d(
                'Je kiest de map en de naam in het volgende venster. De afbeeldingen komen in een submap images/ en media in media/, naast het presentatiebestand.',
              ),
              style: TextStyle(fontSize: 12, color: AppTheme.slate600),
            )
          else ...[
            _summaryRow(
              Icons.slideshow_outlined,
              l10n.d('Presentatie'),
              p.join(folder, _fileName),
            ),
            _summaryRow(
              Icons.image_outlined,
              l10n.d('Afbeeldingen'),
              '${p.join(folder, 'images')}${p.separator}',
            ),
            _summaryRow(
              Icons.movie_outlined,
              l10n.d('Media'),
              '${p.join(folder, 'media')}${p.separator}',
            ),
            const SizedBox(height: 6),
            Text(
              l10n.d(
                'Afbeeldingen en media worden gedeeld door presentaties in dezelfde map. De exacte naam kies je zo in het systeemvenster.',
              ),
              style: TextStyle(fontSize: 11, color: AppTheme.slate400),
            ),
          ],
        ],
      ),
    );
  }

  Widget _summaryRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: AppTheme.slate400),
          const SizedBox(width: 8),
          SizedBox(
            width: 84,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppTheme.slate600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(fontSize: 12, color: AppTheme.slate700),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
