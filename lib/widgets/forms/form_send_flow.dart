// De weg van "Versturen…" (FORM_INTAKE.md §6.6): het pakket verzegelen voor de organisatoren van de
// bundel uit de uitnodiging, de invuller laten bevestigen en versturen.
//
// Het verzegelen gaat eerst en is lokaal: pas als de bundel met de vingerafdruk uit de uitnodiging
// klopt — én voor het adres is ondertekend waar de inzending heen gaat — staat er in het venster
// naar wie. Wat de bundel zelf zegt (gesloten, te groot) komt als zin, niet als "doorgaan".

import 'package:flutter/widgets.dart';
import 'package:ocideck_form_core/ocideck_form_core.dart';

import '../../l10n/app_localizations.dart';
import '../../services/form/form_submission_export.dart';
import '../../services/form/form_submission_seal.dart';
import 'form_export_support.dart';
import 'form_seal_outcome_text.dart';
import 'form_send_dialog.dart';

/// Stuurt [built] naar de server waar het formulier van [spec] vandaan kwam. Geeft de zin die de
/// invuller te lezen krijgt als het niet eens tot het venster kwam, anders `null`: wat er daarna
/// gebeurt zegt het venster zelf.
Future<String?> sendFormSubmission(
  BuildContext context, {
  required FormExportSupport support,
  required FormSpec spec,
  required FormSubmissionBuilt built,
  required String published,
  required DateTime now,
  required FormSaveFile saveFile,
}) async {
  final l10n = context.l10n;
  final send = support.send;
  final seal = support.seal;
  final invite = send?.recall(spec);
  final known = seal?.recall(spec);
  // Alleen een formulier dat via een uitnodiging kwam heeft een server; de knop staat er daarom ook
  // niet zonder. Dit is de laatste controle, niet een weg die de invuller kan nemen.
  if (send == null || seal == null || invite == null || known == null) {
    return l10n.d('De inzending kon niet worden verzegeld.');
  }
  final outcome = await sealFormSubmission(
    built: built,
    bundleText: known.bundle,
    published: published,
    fingerprintText: known.fingerprint,
    pins: await seal.readPins(),
    now: now,
    expectedApiHost: invite.apiHost,
  );
  if (outcome is! FormSubmissionSealed) {
    // Een bundel die niet werkt wordt niet onthouden; een gesloten formulier of een te grote
    // inzending zegt niets over de bundel.
    if (outcome is FormSealBadFingerprint || outcome is FormSealBundleRefused) {
      seal.forget(spec);
    }
    return formSealOutcomeText(l10n, outcome);
  }
  await seal.writePins(outcome.pins);
  if (!context.mounted) return null;
  await showFormSendDialog(
    context,
    invite: invite,
    client: send.client,
    built: built,
    sealed: outcome,
    fingerprint: known.fingerprint,
    saveFile: saveFile,
  );
  return null;
}
