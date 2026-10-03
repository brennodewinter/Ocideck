// De redactiesleutel, vanuit de Inbox (FORM_INTAKE.md §5.9): zichtbaar aanmaken, de
// herstelsleutel opschrijven en terugtypen, herstellen, als age-bestand bewaren, wissen.
//
// Elke stap zegt wat er gebeurt en wat er verloren kan gaan: de sleutel is onvervangbaar
// ([FormKeyService]), en de herstelsleutel is het enige wat er na een kapotte computer van
// over is. Daarom staat de herstelsleutel op een eigen scherm, met het terugtypen erbij —
// niet in een melding die weg is voor iemand hem heeft opgeschreven.

import 'dart:io';

import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ocideck_form_core/ocideck_form_core.dart';

import '../../l10n/app_localizations.dart';
import '../../platform/platform_features.dart';
import '../../services/file_service.dart' show pickDocumentExportDestination;
import '../../services/form/form_key_file.dart';
import '../../services/form/form_keys.dart';
import '../../state/form_keys_provider.dart';

/// Het opslaan van het age-sleutelbestand. Een naad voor de test: het opslagvenster van het
/// systeem en een bestand met beperkte rechten zijn niet te toetsen in een widgettest.
///
/// Geeft het pad terug waar het naartoe is geschreven, of `null` als de gebruiker annuleerde;
/// werpt [FileSystemException] als het schrijven mislukte.
typedef FormKeyFileSaver =
    Future<String?> Function(String dialogTitle, String fileName, String text);

/// Het systeemvenster, en daarna [writeSecretFile].
Future<String?> saveFormKeyFile(
  String dialogTitle,
  String fileName,
  String text,
) async {
  if (!supportsLocalProjectFolders) return null;
  final path = await pickDocumentExportDestination(
    dialogTitle: dialogTitle,
    fileName: fileName,
  );
  if (path == null) return null;
  await writeSecretFile(path, text);
  return path;
}

Future<void> showFormKeysDialog(
  BuildContext context, {
  FormKeyService? service,
  FormKeyFileSaver? saveFile,
}) => showDialog<void>(
  context: context,
  builder: (_) => FormKeysDialog(service: service, saveFile: saveFile),
);

class FormKeysDialog extends ConsumerStatefulWidget {
  const FormKeysDialog({super.key, this.service, this.saveFile});

  final FormKeyService? service;
  final FormKeyFileSaver? saveFile;

  @override
  ConsumerState<FormKeysDialog> createState() => _FormKeysDialogState();
}

enum _Step { overview, recovery, restore, card }

class _FormKeysDialogState extends ConsumerState<FormKeysDialog> {
  final TextEditingController _typed = TextEditingController();
  final TextEditingController _cardName = TextEditingController();
  FormEditorCard? _card;
  FormKeyState? _state;
  _Step _step = _Step.overview;
  String? _recoveryText;
  String? _message;
  bool _busy = false;

  FormKeyService get _service =>
      widget.service ?? ref.read(formKeyServiceProvider);

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _typed.dispose();
    _cardName.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final state = await _service.read();
    if (!mounted) return;
    setState(() => _state = state);
  }

  Future<void> _create() async {
    final l10n = context.l10n;
    setState(() {
      _busy = true;
      _message = null;
    });
    final result = await _service.create();
    if (!mounted) return;
    if (result is FormKeyWritten) {
      final text = await _service.recoveryKey();
      if (!mounted) return;
      setState(() {
        _busy = false;
        _state = FormKeyPresent(result.key, result.info);
        _recoveryText = text;
        _typed.clear();
        _step = _Step.recovery;
        _message = l10n.d(
          'Redactiesleutel aangemaakt. Schrijf nu de herstelsleutel op.',
        );
      });
      return;
    }
    await _refresh();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _message = switch (result) {
        FormKeyNotWritten(:final state) => _notWritten(l10n, state),
        _ => l10n.d(
          'De sleutelhanger nam de sleutel niet aan. Er is niets aangemaakt.',
        ),
      };
    });
  }

  String _notWritten(
    AppLocalizations l10n,
    FormKeyState state,
  ) => switch (state) {
    FormKeyPresent() => l10n.d(
      'Er is al een redactiesleutel. Die is niet aangeraakt.',
    ),
    FormKeyUnreadable() => l10n.d(
      'De sleutelhanger kon niet worden gelezen. Er is niets aangenomen en niets aangemaakt.',
    ),
    FormKeyDamaged() => l10n.d(
      'Er staat iets in de sleutelhanger dat geen redactiesleutel is. Het is niet overschreven.',
    ),
    _ => l10n.d('Dit platform heeft geen sleutelhanger.'),
  };

  /// Naar de kaartstap: een lege naam en nog geen kaart.
  void _openCard() => setState(() {
    _card = null;
    _cardName.clear();
    _message = null;
    _step = _Step.card;
  });

  void _makeCard(FormKeyPresent present) {
    final name = _cardName.text.trim();
    if (!isValidEditorName(name)) {
      setState(
        () =>
            _message = context.l10n.d('Vul een naam in van hooguit 80 tekens.'),
      );
      return;
    }
    setState(() {
      _message = null;
      _card = editorCardOf(present.info, name);
    });
  }

  Future<void> _showRecovery() async {
    final text = await _service.recoveryKey();
    if (!mounted) return;
    setState(() {
      _recoveryText = text;
      _typed.clear();
      _message = null;
      _step = _Step.recovery;
    });
  }

  Future<void> _verify() async {
    final l10n = context.l10n;
    final result = await _service.verifyRecovery(_typed.text);
    if (!mounted) return;
    if (result is FormKeyVerified) {
      await _refresh();
      if (!mounted) return;
      setState(() {
        _message = l10n.d('Klopt: de herstelsleutel is gecontroleerd.');
        _step = _Step.overview;
        _recoveryText = null;
        _typed.clear();
      });
      return;
    }
    setState(() {
      _message = switch (result) {
        FormKeyDifferent() => l10n.d(
          'Dit is een geldige herstelsleutel, maar niet die van deze redactiesleutel.',
        ),
        FormKeyUnreadableRecovery(:final issue) => _recoveryIssue(l10n, issue),
        FormKeyVerifyNotSaved() => l10n.d(
          'De herstelsleutel klopt, maar dat kon niet worden bewaard.',
        ),
        _ => l10n.d('Er is geen redactiesleutel om tegen te controleren.'),
      };
    });
  }

  String _recoveryIssue(AppLocalizations l10n, FormRecoveryIssue issue) =>
      switch (issue) {
        FormRecoveryIssue.format => l10n.d(
          'Dit is geen herstelsleutel van een redactiesleutel.',
        ),
        FormRecoveryIssue.checksum => l10n.d(
          'Er zit een typefout in: de controlesom klopt niet.',
        ),
        FormRecoveryIssue.version => l10n.d(
          'Deze herstelsleutel komt uit een nieuwere versie van OciDeck.',
        ),
        FormRecoveryIssue.purpose => l10n.d(
          'Deze herstelsleutel is voor iets anders gemaakt.',
        ),
      };

  Future<void> _restore() async {
    final l10n = context.l10n;
    setState(() => _busy = true);
    final result = await _service.restore(_typed.text);
    if (!mounted) return;
    if (result is FormKeyWritten) {
      await _refresh();
      if (!mounted) return;
      setState(() {
        _busy = false;
        _message = l10n.d('Hersteld uit de herstelsleutel.');
        _step = _Step.overview;
        _typed.clear();
      });
      return;
    }
    setState(() {
      _busy = false;
      _message = switch (result) {
        FormKeyRestoreRefused(:final issue) => _recoveryIssue(l10n, issue),
        FormKeyNotWritten(:final state) => _notWritten(l10n, state),
        _ => l10n.d(
          'De sleutelhanger nam de sleutel niet aan. Er is niets hersteld.',
        ),
      };
    });
  }

  Future<void> _export(FormKeyPresent present) async {
    final l10n = context.l10n;
    final text = _service.identityFileText(present.key, present.info);
    String? path;
    var failed = false;
    try {
      path = await (widget.saveFile ?? saveFormKeyFile)(
        l10n.d('Redactiesleutel opslaan als age-sleutelbestand'),
        'ocideck-redactiesleutel.txt',
        text,
      );
    } on FileSystemException {
      failed = true;
    }
    if (!mounted) return;
    setState(() {
      _message = failed
          ? l10n.d('Het bestand kon niet worden opgeslagen.')
          : path == null
          ? null
          : l10n
                .d(
                  'Opgeslagen als {pad}. Wie dit bestand heeft, kan alles openen.',
                )
                .replaceAll('{pad}', path);
    });
  }

  Future<void> _delete() async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => const _DeleteKeyDialog(),
    );
    if (confirmed != true) return;
    await _service.delete();
    await _refresh();
    if (!mounted) return;
    setState(() {
      _message = l10n.d('Redactiesleutel verwijderd.');
      _step = _Step.overview;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 700),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Semantics(
                        header: true,
                        child: Text(
                          l10n.d('Redactiesleutel'),
                          style: theme.textTheme.titleLarge,
                        ),
                      ),
                      const SizedBox(height: 12),
                      ..._body(l10n, theme),
                    ],
                  ),
                ),
              ),
              if (_message != null) ...[
                const SizedBox(height: 16),
                Semantics(liveRegion: true, child: Text(_message!)),
              ],
              const SizedBox(height: 20),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(l10n.d('Sluiten')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _body(AppLocalizations l10n, ThemeData theme) {
    final state = _state;
    if (state == null) return const [LinearProgressIndicator()];
    return switch (_step) {
      _Step.recovery => _recoveryStep(l10n, theme),
      _Step.restore => _restoreStep(l10n),
      _Step.card =>
        state is FormKeyPresent
            ? _cardStep(l10n, theme, state)
            : _overview(l10n, theme, state),
      _Step.overview => _overview(l10n, theme, state),
    };
  }

  List<Widget> _overview(
    AppLocalizations l10n,
    ThemeData theme,
    FormKeyState state,
  ) => switch (state) {
    FormKeyUnavailable() => [
      Text(
        l10n.d(
          'Dit platform heeft geen sleutelhanger. De redactiesleutel kan hier niet worden bewaard; gebruik de desktopapp.',
        ),
      ),
    ],
    FormKeyUnreadable() => [
      Text(
        l10n.d(
          'De sleutelhanger kon niet worden gelezen (vergrendeld, of toegang geweigerd). Er is niets aangenomen en niets aangemaakt.',
        ),
      ),
      const SizedBox(height: 12),
      OutlinedButton(
        onPressed: _refresh,
        child: Text(l10n.d('Opnieuw proberen')),
      ),
    ],
    FormKeyDamaged() => [
      Text(
        l10n.d(
          'Er staat iets in de sleutelhanger dat geen redactiesleutel is. Het is niet overschreven. Verwijder het en herstel de sleutel uit je herstelsleutel.',
        ),
      ),
      const SizedBox(height: 12),
      OutlinedButton(
        onPressed: _delete,
        child: Text(l10n.d('Redactiesleutel verwijderen…')),
      ),
    ],
    FormKeyAbsent() => [
      Text(
        l10n.d(
          'Een redactiesleutel opent de verzegelde inzendingen en ondertekent de bundels van je formulieren. Hij staat in de sleutelhanger van dit besturingssysteem. Verlies je alle sleutels van de redactie, dan zijn alle nog niet binnengehaalde inzendingen onleesbaar: dat is de prijs van een server die niets kan lezen.',
        ),
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          FilledButton(
            onPressed: _busy ? null : _create,
            child: Text(l10n.d('Redactiesleutel aanmaken')),
          ),
          OutlinedButton(
            onPressed: _busy
                ? null
                : () => setState(() {
                    _typed.clear();
                    _message = null;
                    _step = _Step.restore;
                  }),
            child: Text(l10n.d('Herstellen uit herstelsleutel…')),
          ),
        ],
      ),
    ],
    FormKeyPresent() => _present(l10n, theme, state),
  };

  List<Widget> _present(
    AppLocalizations l10n,
    ThemeData theme,
    FormKeyPresent present,
  ) {
    final info = present.info;
    return [
      Text(l10n.d('Vingerafdruk'), style: theme.textTheme.titleSmall),
      SelectableText(
        formatFingerprint(info.fingerprint),
        style: const TextStyle(fontFamily: 'monospace'),
      ),
      const SizedBox(height: 8),
      Text(l10n.d('Ontvanger (age)'), style: theme.textTheme.titleSmall),
      SelectableText(
        info.recipient,
        style: const TextStyle(fontFamily: 'monospace'),
      ),
      const SizedBox(height: 8),
      Text(
        l10n.d('Aangemaakt op {datum}.').replaceAll('{datum}', info.created),
      ),
      Text(
        info.recoveryVerified
            ? l10n.d('De herstelsleutel is gecontroleerd.')
            : l10n.d(
                'De herstelsleutel is nog niet gecontroleerd: schrijf hem op en typ hem terug.',
              ),
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          OutlinedButton(
            onPressed: _showRecovery,
            child: Text(l10n.d('Herstelsleutel tonen…')),
          ),
          OutlinedButton(
            onPressed: () => Clipboard.setData(
              ClipboardData(text: formatFingerprint(info.fingerprint)),
            ),
            child: Text(l10n.d('Vingerafdruk kopiëren')),
          ),
          OutlinedButton(
            onPressed: () => _export(present),
            child: Text(l10n.d('Exporteren als age-sleutelbestand…')),
          ),
          OutlinedButton(
            onPressed: _openCard,
            child: Text(l10n.d('Redacteurskaart maken…')),
          ),
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: theme.colorScheme.error,
            ),
            onPressed: _delete,
            child: Text(l10n.d('Redactiesleutel verwijderen…')),
          ),
        ],
      ),
    ];
  }

  List<Widget> _recoveryStep(AppLocalizations l10n, ThemeData theme) => [
    Text(
      l10n.d(
        'Schrijf deze herstelsleutel op en bewaar hem op een veilige plek, buiten dit apparaat. Wie hem heeft, kan alle inzendingen openen en in jullie naam bundels ondertekenen. Raak je dit apparaat kwijt, dan is hij alles wat overblijft.',
      ),
    ),
    const SizedBox(height: 12),
    SelectableText(
      _recoveryText ?? '',
      style: const TextStyle(fontFamily: 'monospace'),
    ),
    const SizedBox(height: 16),
    TextField(
      controller: _typed,
      autocorrect: false,
      enableSuggestions: false,
      decoration: InputDecoration(
        labelText: l10n.d('Typ de herstelsleutel hier opnieuw in'),
      ),
    ),
    const SizedBox(height: 12),
    Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        FilledButton(
          onPressed: _verify,
          child: Text(l10n.d('Herstelsleutel controleren')),
        ),
        TextButton(
          onPressed: () => setState(() {
            _step = _Step.overview;
            _recoveryText = null;
            _typed.clear();
          }),
          child: Text(l10n.d('Later')),
        ),
      ],
    ),
  ];

  List<Widget> _cardStep(
    AppLocalizations l10n,
    ThemeData theme,
    FormKeyPresent present,
  ) {
    final card = _card;
    return [
      Text(
        l10n.d(
          'Met een redacteurskaart voegt de eigenaar van een formulier jou toe aan de bundel, zodat ook jij de inzendingen kunt openen. De kaart mag per mail.',
        ),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _cardName,
        enabled: card == null,
        decoration: InputDecoration(labelText: l10n.d('Jouw naam op de kaart')),
        onSubmitted: (_) => _makeCard(present),
      ),
      const SizedBox(height: 12),
      if (card != null) ...[
        SelectableText(
          card.toText(),
          style: const TextStyle(fontFamily: 'monospace'),
        ),
        const SizedBox(height: 12),
        Text(
          l10n.d('Vingerafdruk van de kaart'),
          style: theme.textTheme.titleSmall,
        ),
        SelectableText(
          formatFingerprint(card.fingerprint),
          style: const TextStyle(fontFamily: 'monospace'),
        ),
        const SizedBox(height: 8),
        Text(
          l10n.d(
            'Geef de eigenaar deze vingerafdruk langs een andere weg dan de kaart, bijvoorbeeld aan de telefoon. Hij typt hem terug voordat hij je toevoegt.',
          ),
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
      ],
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          if (card == null)
            FilledButton(
              onPressed: () => _makeCard(present),
              child: Text(l10n.d('Kaart maken')),
            )
          else
            OutlinedButton(
              onPressed: () =>
                  Clipboard.setData(ClipboardData(text: card.toText())),
              child: Text(l10n.d('Kaart kopiëren')),
            ),
          TextButton(
            onPressed: () => setState(() {
              _step = _Step.overview;
              _message = null;
            }),
            child: Text(l10n.d('Terug')),
          ),
        ],
      ),
    ];
  }

  List<Widget> _restoreStep(AppLocalizations l10n) => [
    Text(
      l10n.d(
        'Typ of plak de herstelsleutel. Wat je ingeeft wordt als redactiesleutel in de sleutelhanger gezet; er wordt niets overschreven.',
      ),
    ),
    const SizedBox(height: 12),
    TextField(
      controller: _typed,
      autocorrect: false,
      enableSuggestions: false,
      decoration: InputDecoration(labelText: l10n.d('Herstelsleutel')),
    ),
    const SizedBox(height: 12),
    Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        FilledButton(
          onPressed: _busy ? null : _restore,
          child: Text(l10n.d('Herstellen')),
        ),
        TextButton(
          onPressed: () => setState(() {
            _step = _Step.overview;
            _typed.clear();
          }),
          child: Text(l10n.d('Terug')),
        ),
      ],
    ),
  ];
}

/// Zegt wat het wissen van de sleutel doet voordat het gebeurt.
class _DeleteKeyDialog extends StatelessWidget {
  const _DeleteKeyDialog();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text(l10n.d('Redactiesleutel verwijderen')),
      content: Text(
        l10n.d(
          'De sleutel wordt uit de sleutelhanger gewist en kan alleen terugkomen uit de herstelsleutel. Heb je die niet, dan zijn inzendingen die alleen voor deze sleutel zijn verzegeld voorgoed onleesbaar.',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.d('Annuleren')),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: scheme.error,
            foregroundColor: scheme.onError,
          ),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l10n.d('Verwijderen')),
        ),
      ],
    );
  }
}
