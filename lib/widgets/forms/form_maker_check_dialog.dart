// De controle door de maker, vanuit de Inbox (FORM_INTAKE.md §7.4): het hoofdstuk van één
// inzending maken, de mail voorbereiden waarmee de maker het controleert, en de status
// op `maker-check-sent` zetten zodra die mail is verstuurd.
//
// Drie losse stappen in plaats van één reeks: het document opent in een tabblad (de Inbox
// sluit), de pdf maakt de organisator met de gewone export, en de mail en de status
// volgen daarna. Elke stap kan op zichzelf, ook na een bezoek aan de Inbox.

import 'package:material_ui/material_ui.dart';
import 'package:ocideck_form_core/ocideck_form_core.dart';

import '../../l10n/app_localizations.dart';
import '../../services/form/form_book.dart';
import '../../services/form/form_maker_check.dart';
import '../../services/form/form_submission_actions.dart';
import '../../services/form/form_workspace.dart';
import '../../utils/url_launcher_util.dart';
import 'form_book_dialog.dart' show FormTemplatePick, pickFormTemplateFile;
import 'form_inbox_actions.dart' show formActionFailedMessage;

/// Wat het dialoogvenster de Inbox meegeeft.
sealed class FormMakerCheckResult {
  const FormMakerCheckResult();
}

/// Het controledocument is gemaakt: de Inbox opent het.
class FormMakerCheckOpened extends FormMakerCheckResult {
  const FormMakerCheckOpened(this.path);

  final String path;
}

/// De status is gezet: de Inbox leest zich opnieuw en toont de zin.
class FormMakerCheckStatusSet extends FormMakerCheckResult {
  const FormMakerCheckStatusSet(this.message);

  final String message;
}

/// De status die de organisator zet zodra de mail is verstuurd.
const String kMakerCheckSent = 'maker-check-sent';

/// Het aantal dagen dat de maker standaard krijgt om te antwoorden.
const int kMakerCheckDays = 14;

/// Opent een `mailto:`-link in het mailprogramma. Een naad voor de test.
typedef FormMailOpener = Future<void> Function(String link);

/// Zoekt het adres dat de maker opgaf. Een naad voor de test: dat wat de organisator al
/// typte nooit wordt overschreven is alleen te bewijzen als het zoeken pas klaar is
/// nadat er getypt is.
typedef FormAddressLoader =
    Future<String?> Function(FormWorkspace workspace, String sid);

Future<FormMakerCheckResult?> showFormMakerCheckDialog(
  BuildContext context, {
  required FormWorkspace workspace,
  required String sid,
  required FormSpec spec,
  FormTemplatePick? pickTemplate,
  FormMailOpener? openMail,
  FormAddressLoader? loadAddress,
  DateTime Function()? now,
}) => showDialog<FormMakerCheckResult>(
  context: context,
  builder: (_) => FormMakerCheckDialog(
    workspace: workspace,
    sid: sid,
    spec: spec,
    pickTemplate: pickTemplate,
    openMail: openMail,
    loadAddress: loadAddress,
    now: now,
  ),
);

class FormMakerCheckDialog extends StatefulWidget {
  const FormMakerCheckDialog({
    super.key,
    required this.workspace,
    required this.sid,
    required this.spec,
    this.pickTemplate,
    this.openMail,
    this.loadAddress,
    this.now,
  });

  final FormWorkspace workspace;
  final String sid;

  /// Het formulier waartegen de inzending is beoordeeld: de statuslijst komt eruit.
  final FormSpec spec;
  final FormTemplatePick? pickTemplate;
  final FormMailOpener? openMail;
  final FormAddressLoader? loadAddress;
  final DateTime Function()? now;

  @override
  State<FormMakerCheckDialog> createState() => _FormMakerCheckDialogState();
}

class _FormMakerCheckDialogState extends State<FormMakerCheckDialog> {
  late final DateTime _today = (widget.now ?? DateTime.now)();
  late final TextEditingController _address = TextEditingController()
    ..addListener(() => setState(() {}));
  late final TextEditingController _deadline = TextEditingController(
    text: formDay(_today.add(const Duration(days: kMakerCheckDays))),
  )..addListener(() => setState(() {}));
  String? _templateName;
  String? _template;
  bool _busy = false;
  String? _message;

  bool get _canSetStatus => formStatesOf(widget.spec).contains(kMakerCheckSent);
  bool get _addressOk => isMailableAddress(_address.text.trim());
  bool get _deadlineOk => isValidCalendarDate(_deadline.text.trim());

  @override
  void initState() {
    super.initState();
    _prefillAddress();
  }

  @override
  void dispose() {
    _address.dispose();
    _deadline.dispose();
    super.dispose();
  }

  /// Het adres dat de maker opgaf, tenzij de organisator al iets typte.
  Future<void> _prefillAddress() async {
    final found = await (widget.loadAddress ?? makerAddressOfSubmission)(
      widget.workspace,
      widget.sid,
    );
    if (!mounted || found == null || _address.text.isNotEmpty) return;
    _address.text = found;
  }

  Future<void> _chooseTemplate() async {
    final l10n = context.l10n;
    final picked = await (widget.pickTemplate ?? pickFormTemplateFile)(
      l10n.d('Kies het hoofdstuksjabloon'),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _templateName = picked.name;
      _template = picked.text;
    });
  }

  Future<void> _createDocument() async {
    final l10n = context.l10n;
    final template = _template;
    if (template == null) {
      setState(() => _message = l10n.d('Kies eerst een hoofdstuksjabloon.'));
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    final outcome = await prepareMakerCheck(
      widget.workspace,
      sid: widget.sid,
      template: template,
      now: _today,
    );
    if (!mounted) return;
    if (outcome is FormMakerCheckReady) {
      Navigator.of(context).pop(FormMakerCheckOpened(outcome.path));
      return;
    }
    setState(() {
      _busy = false;
      _message = _refusal(l10n, outcome);
    });
  }

  String _refusal(
    AppLocalizations l10n,
    FormMakerCheckOutcome outcome,
  ) => switch (outcome) {
    FormMakerCheckRefused(outcome: FormBookEmpty(:final withdrawn))
        when withdrawn > 0 =>
      l10n.d(
        'Deze inzending is ingetrokken en komt dus in geen enkel hoofdstuk.',
      ),
    FormMakerCheckRefused(outcome: FormBookUnknownFields(:final ids)) =>
      l10n
          .d(
            'Het sjabloon noemt velden die het formulier niet heeft: {velden}.',
          )
          .replaceAll('{velden}', ids.join(', ')),
    FormMakerCheckRefused(outcome: FormBookRegisterDamaged()) => l10n.d(
      'Het register kan niet worden gelezen. Herstel overview.md.',
    ),
    FormMakerCheckRefused(outcome: FormBookEmpty()) => l10n.d(
      'Deze inzending staat niet in het register. Herstel overview.md en probeer het opnieuw.',
    ),
    FormMakerCheckUnavailable() => l10n.d(
      'Deze inzending is niet te lezen, of het formulier waarvoor ze is ingediend staat niet in de werkmap.',
    ),
    _ => l10n.d('Het controledocument kon niet worden geschreven.'),
  };

  Future<void> _writeMail() async {
    final l10n = context.l10n;
    final link = makerCheckMailLink(
      address: _address.text.trim(),
      subject: l10n.d('Je bijdrage voor het boek: graag even controleren'),
      body: l10n
          .d(
            'Hierbij je bijdrage zoals die in het boek komt (zie de bijlage). Klopt alles? Antwoord ‘akkoord’ of met je correcties vóór {datum}.',
          )
          .replaceAll('{datum}', _deadline.text.trim()),
    );
    await (widget.openMail ?? openExternalUrl)(link);
    if (!mounted) return;
    setState(
      () => _message = l10n.d(
        'De mail staat klaar in je mailprogramma. Voeg de pdf toe en verstuur hem.',
      ),
    );
  }

  Future<void> _markSent() async {
    final l10n = context.l10n;
    setState(() {
      _busy = true;
      _message = null;
    });
    final outcome = await setSubmissionStatus(
      widget.workspace,
      widget.sid,
      kMakerCheckSent,
      formStatesOf(widget.spec),
    );
    if (!mounted) return;
    if (outcome == FormActionOutcome.done) {
      Navigator.of(context).pop(
        FormMakerCheckStatusSet(
          l10n
              .d('Status gewijzigd naar {status}.')
              .replaceAll('{status}', kMakerCheckSent),
        ),
      );
      return;
    }
    setState(() {
      _busy = false;
      _message = formActionFailedMessage(l10n, outcome);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final address = _address.text.trim();
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
                          l10n.d('Controle door de maker…'),
                          style: theme.textTheme.titleLarge,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        l10n.d(
                          'Het controledocument is het hoofdstuk van deze ene inzending. Exporteer het als pdf (kies het volledige profiel), voeg de pdf toe aan de mail en verstuur die. Antwoordt de maker ‘akkoord’, zet de status dan zelf op maker-approved: dat antwoord is ook de bevestiging dat de bijdrage echt van deze persoon komt.',
                        ),
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _templateName ?? l10n.d('Nog geen sjabloon gekozen.'),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton(
                        onPressed: _chooseTemplate,
                        child: Text(l10n.d('Hoofdstuksjabloon kiezen…')),
                      ),
                      const SizedBox(height: 8),
                      FilledButton(
                        onPressed: _busy ? null : _createDocument,
                        child: Text(l10n.d('Controledocument maken en openen')),
                      ),
                      const SizedBox(height: 20),
                      TextField(
                        controller: _address,
                        decoration: InputDecoration(
                          labelText: l10n.d('E-mailadres van de maker'),
                          errorText: address.isNotEmpty && !_addressOk
                              ? l10n.d('Dit is geen geldig e-mailadres.')
                              : null,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _deadline,
                        decoration: InputDecoration(
                          labelText: l10n.d('Antwoord vóór (jjjj-mm-dd)'),
                          errorText: !_deadlineOk
                              ? l10n
                                    .d(
                                      'Ongeldige dag. Gebruik jaar-maand-dag, bijvoorbeeld {voorbeeld}.',
                                    )
                                    .replaceAll('{voorbeeld}', formDay(_today))
                              : null,
                        ),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton(
                        onPressed: !_addressOk || !_deadlineOk
                            ? null
                            : _writeMail,
                        child: Text(l10n.d('Mail schrijven')),
                      ),
                      const SizedBox(height: 20),
                      if (!_canSetStatus)
                        Text(
                          l10n.d(
                            'Dit formulier kent de status maker-check-sent niet; die kan hier dus niet worden gezet.',
                          ),
                          style: theme.textTheme.bodySmall,
                        ),
                      OutlinedButton(
                        onPressed: _busy || !_canSetStatus ? null : _markSent,
                        child: Text(l10n.d('Controle verstuurd')),
                      ),
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
}
