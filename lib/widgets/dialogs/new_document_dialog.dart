import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import '../../l10n/app_localizations.dart';
import '../../models/library_folder.dart';
import '../../platform/platform_features.dart';
import '../../theme/app_theme.dart';
import '../../utils/safe_filename.dart';

/// Uitkomst van de aanmaakdialoog: het volledige pad van het nieuwe bestand,
/// of `null` wanneer de gebruiker "Nog niet opslaan" koos — dan krijgt het
/// tabblad geen bestand en blijft het een klad in het geheugen. `null` uit
/// [NewDocumentDialog.show] zelf betekent dat de dialoog geannuleerd is.
class NewDocumentChoice {
  final String? path;
  const NewDocumentChoice(this.path);
}

/// Aanmaakdialoog voor een nieuw document (#2177): vraagt een naam — zoals de
/// nieuwe-presentatie-wizard dat doet — én de map waar het `.md` meteen op
/// schijf komt. Zo landt een document niet ongevraagd als `document N.md` in
/// de eerste bibliotheek maar op de plek die de gebruiker bedoelde.
///
/// De opties zijn de bibliotheken, een eigen map via "Andere map…" en "Nog
/// niet opslaan" voor wie een klad wil zonder bestand. De naam wordt de
/// bestandsnaam — een document kent verder geen titelveld; het tabblad toont
/// de bestandsnaam.
class NewDocumentDialog extends StatefulWidget {
  final List<LibraryFolder> libraries;

  const NewDocumentDialog({super.key, required this.libraries});

  static Future<NewDocumentChoice?> show(
    BuildContext context, {
    required List<LibraryFolder> libraries,
  }) {
    return showDialog<NewDocumentChoice>(
      context: context,
      builder: (_) => NewDocumentDialog(libraries: libraries),
    );
  }

  @override
  State<NewDocumentDialog> createState() => _NewDocumentDialogState();
}

class _NewDocumentDialogState extends State<NewDocumentDialog> {
  final _nameCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  /// De gekozen doelmap. Start op de eerste bibliotheek; `null` betekent dat
  /// er geen map is — samen met [_noSave] de enige geldige toestand zonder
  /// bibliotheek.
  String? _dir;

  /// Een via "Andere map…" gekozen map die niet in de bibliotheken zit — als
  /// aparte optie getoond zodat de keuze zichtbaar blijft.
  String? _customDir;

  /// "Nog niet opslaan": het document blijft een klad in het geheugen. De
  /// keuze is een bestemming als de andere — daarom een optie in dezelfde
  /// lijst en geen derde knop in de actiebalk.
  bool _noSave = false;

  @override
  void initState() {
    super.initState();
    _dir = widget.libraries.isEmpty ? null : widget.libraries.first.path;
    _noSave = widget.libraries.isEmpty;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  /// De bestandsnaam die de getypte naam wordt: een eventueel meegetypte
  /// `.md` eraf (die voegen we zelf toe), de rest gezuiverd tot een veilige
  /// stam — hetzelfde recept dat de presentatie voor haar voorgestelde
  /// bestandsnaam gebruikt.
  String _fileName(AppLocalizations l10n) {
    var raw = _nameCtrl.text.trim();
    if (raw.toLowerCase().endsWith('.md')) {
      raw = raw.substring(0, raw.length - 3).trim();
    }
    return '${sanitizeFilename(raw, fallback: l10n.d('document'))}.md';
  }

  /// Waar het bestand komt te staan, of `null` bij "Nog niet opslaan" of
  /// wanneer er nog geen map is. Live bijgewerkt tijdens het typen zodat de
  /// gebruiker ziet wat "Aanmaken" straks doet.
  String? _targetPath(AppLocalizations l10n) {
    final dir = _dir;
    if (_noSave || dir == null) return null;
    return p.join(dir, _fileName(l10n));
  }

  Future<void> _pickCustom() async {
    // Zelfde poort als elders: op web bestaat getDirectoryPath niet en geeft
    // het stil null terug — dan doet de knop niets zonder uitleg (#150).
    if (!supportsLocalProjectFolders) return;
    final result = await FilePicker.getDirectoryPath(
      dialogTitle: context.l10n.d('Map kiezen'),
      initialDirectory: _dir,
    );
    if (!mounted || result == null) return;
    setState(() {
      _customDir = result;
      _dir = result;
      _noSave = false;
    });
  }

  void _submit() {
    final l10n = context.l10n;
    if (_noSave) {
      Navigator.pop(context, const NewDocumentChoice(null));
      return;
    }
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final path = _targetPath(l10n);
    // Kan alleen null zijn als er geen map is — met een bibliotheek of een
    // eigen map staat er altijd een keuze, dus dan is _dir gezet.
    if (path == null) return;
    Navigator.pop(context, NewDocumentChoice(path));
  }

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
            const Icon(Icons.description_outlined, size: 20),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                l10n.d('Nieuw document'),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: Form(
          key: _formKey,
          child: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.d('Kies een naam en waar het document komt te staan.'),
                    style: TextStyle(fontSize: 12, color: AppTheme.slate500),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _nameCtrl,
                    autofocus: true,
                    enabled: !_noSave,
                    autovalidateMode: AutovalidateMode.onUserInteraction,
                    decoration: InputDecoration(
                      labelText: l10n.d('Naam'),
                      hintText: l10n.d('Bijv. Vergadernotities'),
                    ),
                    validator: _validateName,
                    onFieldSubmitted: (_) => _submit(),
                  ),
                  const SizedBox(height: 16),
                  for (final lib in widget.libraries)
                    _option(lib.name, lib.path),
                  if (_customDir != null)
                    _option(p.basename(_customDir!), _customDir!),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: _pickCustom,
                      icon: const Icon(Icons.folder_open_outlined, size: 16),
                      label: Text(l10n.d('Andere map…')),
                    ),
                  ),
                  _option(
                    l10n.d('Nog niet opslaan'),
                    null,
                    subtitle: l10n.d(
                      'Alleen in het geheugen, tot je het zelf opslaat.',
                    ),
                    noSave: true,
                  ),
                  const SizedBox(height: 8),
                  _preview(l10n),
                ],
              ),
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

  String? _validateName(String? value) {
    final l10n = context.l10n;
    if (_noSave) return null;
    if (value == null || value.trim().isEmpty) {
      return l10n.d('Vul een naam in');
    }
    final path = _targetPath(l10n);
    // Bestaat de naam al, dan mag de gebruiker een andere kiezen — een nieuw
    // (leeg) document over een bestaand bestand heen is dataverlies. De
    // aanmaak zelf claimt het pad later nog exclusief; dit is de
    // gebruiksvriendelijke voormelding, geen veiligheidsgrens.
    if (path != null && File(path).existsSync()) {
      return l10n.d('Er bestaat al een bestand met deze naam in deze map.');
    }
    return null;
  }

  /// Eén bestemmingsoptie: een bibliotheek, de eigen map, of "Nog niet
  /// opslaan" ([path] is dan `null`). Zelfde vorm als de
  /// presentatie-bestemmingsdialoog — radio, naam, pad — zodat de twee
  /// aanmaakflows er hetzelfde uitzien.
  Widget _option(
    String name,
    String? path, {
    String? subtitle,
    bool noSave = false,
  }) {
    final selected = noSave ? _noSave : (!_noSave && _dir == path);
    return Semantics(
      button: true,
      selected: selected,
      label: name,
      child: InkWell(
        onTap: () => setState(() {
          if (noSave) {
            _noSave = true;
          } else {
            _noSave = false;
            _dir = path;
          }
        }),
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
                      name,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (path != null || subtitle != null)
                      Text(
                        path ?? subtitle!,
                        style: TextStyle(
                          fontSize: 11,
                          color: AppTheme.slate400,
                        ),
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

  /// Het volledige doelpad, live meebewegend met de getypte naam — de
  /// gebruiker ziet wat "Aanmaken" doet vóórdat hij klikt. Bij "Nog niet
  /// opslaan" zegt het vak wat er dan gebeurt.
  Widget _preview(AppLocalizations l10n) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: _nameCtrl,
      builder: (context, _, _) {
        final path = _targetPath(l10n);
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppTheme.slate50,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppTheme.slate200),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                path == null ? Icons.edit_note_outlined : Icons.save_outlined,
                size: 15,
                color: AppTheme.slate400,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  path ??
                      l10n.d(
                        'Het bestand wordt niet opgeslagen; het document blijft een klad.',
                      ),
                  style: TextStyle(fontSize: 12, color: AppTheme.slate600),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
