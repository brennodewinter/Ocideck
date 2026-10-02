// Een formulier met een e-mailveld en een inzending die erin landt: de grondstof van de
// tests voor de controle door de maker (FORM_INTAKE.md §7.4).

import 'package:ocideck/services/form/form_import.dart';
import 'package:ocideck/services/form/form_submission_actions.dart';
import 'package:ocideck/services/form/form_workspace.dart';
import 'package:ocideck_form_core/ocideck_form_core.dart';

const String kookWithMail =
    '''<!-- form id=kook version=1 states="received|maker-check-sent|maker-approved" overview="naam" -->
# Inzending

<!-- field id=naam type=text required -->
**Naam**
<!-- answer -->
<!-- /field id=naam -->

<!-- field id=mail type=text pattern=email -->
**E-mail**
<!-- answer -->
<!-- /field id=mail -->

<!-- field id=akkoord type=consent required -->
Ik ga akkoord.
<!-- answer -->
- [ ]
<!-- /field id=akkoord -->
''';

const List<String> kookStates = [
  'received',
  'maker-check-sent',
  'maker-approved',
];

String sidOf(int n) => 'abcdefghijklmnopqrstuvwxy${'abcdefg'[n]}';

/// Laat inzending [n] in de werkmap landen, met [status] als ze die nog niet heeft.
Future<void> landKook(
  FormWorkspace workspace,
  int n, {
  String form = kookWithMail,
  String naam = 'Sari',
  String mail = 'sari@example.nl',
  String status = 'received',
  bool withdrawn = false,
}) async {
  final text = form
      .replaceFirst(
        '<!-- answer -->\n<!-- /field id=naam',
        '<!-- answer -->\n$naam\n<!-- /field id=naam',
      )
      .replaceFirst(
        '<!-- answer -->\n<!-- /field id=mail',
        '<!-- answer -->\n$mail\n<!-- /field id=mail',
      )
      .replaceFirst(
        '- [ ]\n<!-- /field id=akkoord',
        '- [x]\n<!-- /field id=akkoord',
      );
  await importFormPackage(
    workspace,
    buildFormPackage(
      submission: text,
      template: form,
      spec: (parseForm(form) as ParsedForm).spec,
      images: const {},
      submissionId: sidOf(n),
      created: DateTime.utc(2026, 10, 4),
      clientRules: kFormRulesVersion,
    ),
    now: DateTime.utc(2026, 10, 6),
  );
  if (status != 'received') {
    await setSubmissionStatus(workspace, sidOf(n), status, kookStates);
  }
  if (withdrawn) {
    await setSubmissionWithdrawal(workspace, sidOf(n), '2026-11-02');
  }
}
