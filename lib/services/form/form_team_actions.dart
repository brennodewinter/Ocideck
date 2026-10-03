// Het team van de redactie bijhouden (FORM_INTAKE.md §7.6): een redacteur toevoegen met zijn kaart,
// en weer verwijderen.
//
// Toevoegen is de plek waar vertrouwen ontstaat, en daarom gaat het in één vaste volgorde: de kaart
// wordt gelezen, en pas als de eigenaar de vingerafdruk van die kaart heeft teruggetypt — die hij
// langs een andere weg kreeg dan de kaart — wordt de redacteur in het team gezet. Wat het scherm
// al van de kaart liet zien telt hier niet: deze functie leest de tekst zelf.
//
// Het team zelf staat in `team.json` in de werkmap; wat daar niet te lezen is wordt niet overschreven.
library;

import 'package:ocideck_form_core/ocideck_form_core.dart';

import 'form_keys.dart';
import 'form_workspace.dart';

/// Wat een wijziging van het team opleverde.
sealed class FormTeamEdit {
  const FormTeamEdit();
}

/// De redacteur staat in het team.
class FormEditorAdded extends FormTeamEdit {
  const FormEditorAdded(this.team, this.card);

  final FormTeam team;
  final FormEditorCard card;
}

/// De redacteur is uit het team gehaald.
class FormEditorRemoved extends FormTeamEdit {
  const FormEditorRemoved(this.team, this.card);

  final FormTeam team;
  final FormEditorCard card;
}

/// De eigenaar heeft zelf geen bruikbare redactiesleutel: dan is er geen team om aan te vullen
/// (de eigenaar is wie de sleutel op dit apparaat heeft).
class FormTeamNeedsKey extends FormTeamEdit {
  const FormTeamNeedsKey(this.problem);

  final FormKeyProblem problem;
}

/// `team.json` in de werkmap is niet te lezen: er is niets aangepast.
class FormTeamUnreadable extends FormTeamEdit {
  const FormTeamUnreadable();
}

/// De geplakte tekst is geen redacteurskaart, om [issue].
class FormTeamCardRefused extends FormTeamEdit {
  const FormTeamCardRefused(this.issue);

  final FormEditorCardIssue issue;
}

/// Wat is ingetikt is geen vingerafdruk.
class FormTeamBadFingerprint extends FormTeamEdit {
  const FormTeamBadFingerprint();
}

/// De ingetikte vingerafdruk is niet die van deze kaart: de kaart is veranderd, of hoort bij iemand
/// anders dan degene die de vingerafdruk gaf.
class FormTeamFingerprintWrong extends FormTeamEdit {
  const FormTeamFingerprintWrong();
}

/// De kaart is in orde, maar de redacteur kan er niet bij: zie [issue].
class FormTeamNotAdded extends FormTeamEdit {
  const FormTeamNotAdded(this.issue);

  final FormTeamAddIssue issue;
}

/// Er is geen redacteur met deze `kid` in het team.
class FormEditorUnknown extends FormTeamEdit {
  const FormEditorUnknown();
}

/// Het team kon niet worden bewaard.
class FormTeamNotSaved extends FormTeamEdit {
  const FormTeamNotSaved();
}

/// Zet de redacteur met de kaart [cardText] in het team van [workspace], als [fingerprintText] de
/// vingerafdruk van die kaart is. De eigenaar is de sleutel uit [keys].
Future<FormTeamEdit> addFormEditor(
  FormWorkspace workspace,
  FormKeyService keys, {
  required String cardText,
  required String fingerprintText,
}) async {
  final state = await keys.read();
  final problem = keyProblemOf(state);
  if (problem != null) return FormTeamNeedsKey(problem);
  final owner = (state as FormKeyPresent).info;

  final stored = await workspace.readTeam();
  if (stored is! FormTeamStored) return const FormTeamUnreadable();

  final parsed = parseFormEditorCard(cardText);
  if (parsed is FormEditorCardRefused) return FormTeamCardRefused(parsed.issue);
  final card = (parsed as FormEditorCardParsed).card;

  final typed = normalizeFingerprint(fingerprintText);
  if (typed == null) return const FormTeamBadFingerprint();
  if (typed != card.fingerprint) return const FormTeamFingerprintWrong();

  final added = stored.team.withEditor(
    card,
    ownerAge: owner.recipient,
    ownerSign: owner.signPublicKey,
  );
  if (added is FormTeamAddRefused) return FormTeamNotAdded(added.issue);
  final team = (added as FormTeamAdded).team;
  if (!await workspace.saveTeam(team)) return const FormTeamNotSaved();
  return FormEditorAdded(team, card);
}

/// Haalt de redacteur met key id [kid] uit het team van [workspace]. Bundels die al zijn gepubliceerd
/// blijven zoals ze zijn tot de eigenaar opnieuw publiceert.
Future<FormTeamEdit> removeFormEditor(
  FormWorkspace workspace,
  String kid,
) async {
  final stored = await workspace.readTeam();
  if (stored is! FormTeamStored) return const FormTeamUnreadable();
  final matches = stored.team.editors.where((e) => e.kid == kid);
  if (matches.isEmpty) return const FormEditorUnknown();
  final team = stored.team.without(kid);
  if (!await workspace.saveTeam(team)) return const FormTeamNotSaved();
  return FormEditorRemoved(team, matches.first);
}
