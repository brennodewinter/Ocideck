// Een uitnodiging openen als handeling (FORM_INTAKE.md §6.6): het venster laten kiezen, de
// pins bewaren, het formulier onthouden en het sjabloon als nieuw document openen.
//
// Het geopende document is een gewoon formulierdocument: het opent op het tabblad Invullen en
// de invulpagina doet de rest. Wat de uitnodiging al heeft aangetoond — het gepubliceerde sjabloon,
// de bundel en de vingerafdruk — staat in het geheugen van de invulpagina, zodat het opslaan
// van de inzending er niet opnieuw om vraagt: die gegevens kwamen langs de weg waar ze voor zijn.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../l10n/app_localizations.dart';
import '../../services/form/intake/intake_client.dart';
import '../../services/form/intake/intake_http_factory.dart';
import '../../state/tabs_provider.dart';
import 'form_export_picker.dart';
import 'form_invitation_dialog.dart';

/// Opent het formulier van een uitnodiging die de invuller plakt. [client], [now] en
/// [initialLink] zijn de testhaken: een testserver, een vaste klok en een link zonder klembord.
Future<void> openFormInvitation(
  BuildContext context, {
  IntakeClient? client,
  DateTime Function()? now,
  String? initialLink,
}) async {
  final container = ProviderScope.containerOf(context);
  final messenger = ScaffoldMessenger.of(context);
  final l10n = context.l10n;
  final choice = await showFormInvitationDialog(
    context,
    client: client ?? IntakeClient(createIntakeHttp()),
    readPins: readFormBundlePins,
    now: now,
    initialLink: initialLink,
  );
  if (choice == null) return;
  final variant = choice.variant;
  // De pins gaan mee zodra de invuller het formulier opent: wat hij zag beschermt hem tegen een
  // oudere bundel die iemand hem later nog eens voorlegt.
  await writeFormBundlePins(choice.opened.pins);
  rememberInvitedForm(
    spec: variant.spec,
    template: variant.template,
    bundleText: variant.bundleText,
    fingerprint: variant.verified.fingerprint,
    invite: choice.opened.invite,
  );
  container
      .read(tabsProvider.notifier)
      .newDocumentFromMarkdown(variant.template);
  messenger.showSnackBar(SnackBar(content: Text(l10n.d('Formulier geopend.'))));
}
