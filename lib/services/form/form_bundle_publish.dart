// Een bundel maken en ondertekenen voor een gepubliceerd formulier (FORM_INTAKE.md §5.1, §7.6).
//
// De bundel is wat een invuller van de redactie gelooft: wie de organisatoren zijn, naar welke
// sleutels hij verzegelt, welke tekst van het formulier hoort bij deze bundel en tot wanneer. Hij
// wordt ondertekend met de sleutel van de eigenaar — de redactiesleutel (§5.9) — en naast de
// sjabloon bewaard, zodat hij samen met het formulier naar de invuller kan.
//
// Wat deze stap weigert, en waarom:
//
// * **Geen bruikbare sleutel**: er valt niets mee te ondertekenen.
// * **Een herstelsleutel die niet is teruggetypt** (§7.6): een bundel die verzegelt naar één sleutel
//   zonder herstelweg maakt elke inzending onleesbaar zodra dit apparaat stuk gaat. Het team telt
//   hier nog één sleutel; twee sleutels als alternatief komt met het team zelf.
// * **Een bundel die al in de werkmap staat en niet te lezen is**: het volgnummer (`bundle_seq`)
//   moet boven alles uitkomen wat al is uitgegeven, en dat is niet te weten. Een lager nummer
//   wordt door een invuller die de hogere ooit zag stilletjes geweigerd (§5.1: terugval).
// * **Een geldigheid die eindigt vóór de sluitingsdag**: de invuller zou de laatste dagen een
//   bundel zonder geloof hebben.
library;

import 'dart:convert';
import 'dart:math';

import 'package:ocideck_form_core/ocideck_form_core.dart';

import 'form_keys.dart';
import 'form_workspace.dart';

/// Wat [publishFormBundle] opleverde.
sealed class FormBundleOutcome {
  const FormBundleOutcome();
}

/// De bundel is gemaakt, gecontroleerd en bewaard.
class FormBundlePublished extends FormBundleOutcome {
  const FormBundlePublished({
    required this.bundle,
    required this.path,
    required this.fingerprint,
  });

  final FormBundle bundle;

  /// Waar het bundelbestand staat, naast de sjabloon.
  final String path;

  /// De vingerafdruk van de eigenaar, in groepjes van vier: wat de invuller langs een andere
  /// weg dan het bundelbestand krijgt (§5.1).
  final String fingerprint;
}

/// Er is geen redactiesleutel om mee te ondertekenen.
class FormBundleNeedsKey extends FormBundleOutcome {
  const FormBundleNeedsKey(this.problem);

  final FormKeyProblem problem;
}

/// De herstelsleutel is nog niet teruggetypt (§7.6).
class FormBundleRecoveryNotChecked extends FormBundleOutcome {
  const FormBundleRecoveryNotChecked();
}

/// Er staan bundels van dit formulier in de werkmap die niet te lezen zijn, of die
/// elkaar tegenspreken over het `fid`: het volgende volgnummer is dan niet te bepalen.
class FormBundleExistingUnreadable extends FormBundleOutcome {
  const FormBundleExistingUnreadable(this.paths);

  final List<String> paths;
}

/// Een ingevoerde waarde deugt niet.
class FormBundleBadInput extends FormBundleOutcome {
  const FormBundleBadInput(this.field);

  final FormBundleInputField field;
}

enum FormBundleInputField {
  /// De naam die de invuller te zien krijgt: niet leeg, hooguit 80 tekens, geen stuurtekens.
  name,

  /// Een datum `jjjj-mm-dd` die bestaat.
  expires,

  /// Een geldigheid die vóór de sluitingsdag van het formulier eindigt.
  expiresBeforeCloses,
}

/// De kern weigerde de bundel (`closes` of `retain-unused` van het formulier zelf zijn niet te
/// gebruiken, het formulier is geen formulier, …): [detail] noemt het veld.
class FormBundleRefusedByCore extends FormBundleOutcome {
  const FormBundleRefusedByCore(this.issue, this.detail);

  final FormBundleCreateIssue issue;
  final String? detail;
}

/// De bundel was goed, maar is niet te bewaren.
class FormBundleNotWritten extends FormBundleOutcome {
  const FormBundleNotWritten();
}

/// De geldigheid die [publishFormBundle] voorstelt: de sluitingsdag van het formulier, of een
/// jaar na [now] als er geen is.
String defaultBundleExpiry(DateTime now, String? closes) =>
    closes != null && isValidCalendarDate(closes)
    ? closes
    : formDay(DateTime.utc(now.year + 1, now.month, now.day));

/// De naam die de invuller te zien krijgt, als de redacteur er niets anders van maakt: wie het
/// formulier zegt te verwerken, of anders `Redactie`.
String defaultBundleOrganiserName(FormSpec spec) =>
    spec.controller?.trim() ?? 'Redactie';

/// Maakt en bewaart de bundel van [form] in [workspace], ondertekend met de redactiesleutel uit
/// [keys]. [organiserName] en [expires] zijn wat de redacteur invult; `closes` en `retain_unused`
/// komen uit het formulier zelf — één bron. [random] is de bron van een nieuw `fid`; [now] de dag.
Future<FormBundleOutcome> publishFormBundle(
  FormWorkspace workspace,
  PublishedForm form, {
  required FormKeyService keys,
  required String organiserName,
  required String expires,
  required DateTime now,
  Random? random,
}) async {
  final state = await keys.read();
  final problem = keyProblemOf(state);
  if (problem != null) return FormBundleNeedsKey(problem);
  final present = state as FormKeyPresent;
  if (!present.info.recoveryVerified) {
    return const FormBundleRecoveryNotChecked();
  }

  final name = organiserName.trim();
  if (!_nameOk(name)) {
    return const FormBundleBadInput(FormBundleInputField.name);
  }
  if (!isValidCalendarDate(expires)) {
    return const FormBundleBadInput(FormBundleInputField.expires);
  }
  final parsed = parseForm(form.text);
  if (parsed is! ParsedForm) {
    return const FormBundleRefusedByCore(FormBundleCreateIssue.notAForm, null);
  }
  final spec = parsed.spec;
  // De sluitingsdag is een datum: een formulier met een andere komt het parseren niet door.
  final closes = spec.closes;
  if (closes != null && expires.compareTo(closes) < 0) {
    return const FormBundleBadInput(FormBundleInputField.expiresBeforeCloses);
  }

  final existing = await _existing(workspace, form.id);
  if (existing.unreadable.isNotEmpty) {
    return FormBundleExistingUnreadable(existing.unreadable);
  }
  final fid = existing.fid ?? newFormId(random ?? Random.secure());

  final signing = await formSigningKeyFromSeed(present.key.signingSeed);
  final created = await createFormBundle(
    fid: fid,
    template: form.text,
    organisers: [
      FormBundleOrganiserInput(
        name: name,
        age: present.info.recipient,
        signPublicKey: signing.publicKey,
      ),
    ],
    owner: signing,
    bundleSeq: existing.highestSeq + 1,
    expires: expires,
    now: now,
    policy: FormBundlePolicy(closes: closes, retainUnused: spec.retainUnused),
  );
  if (created is FormBundleCreateRefused) {
    return FormBundleRefusedByCore(created.issue, created.detail);
  }
  final bundle = (created as FormBundleCreated).bundle;
  final path = workspace.bundlePathOf(form);
  if (!await workspace.writeBundle(form, created.text)) {
    return const FormBundleNotWritten();
  }
  return FormBundlePublished(
    bundle: bundle,
    path: path,
    fingerprint: formatFingerprint(signing.fingerprint),
  );
}

bool _nameOk(String name) =>
    name.isNotEmpty &&
    name.length <= 80 &&
    !name.codeUnits.any((c) => c < 0x20 || c == 0x7f);

/// Wat de werkmap al aan bundels van één formulier heeft: het `fid` waar ze het over eens zijn
/// (`null` als er nog geen bundel is), het hoogste volgnummer, en de paden van wat niet te lezen is
/// of het oneens is over het `fid` — daarmee is het volgende volgnummer niet te bepalen.
Future<({String? fid, int highestSeq, List<String> unreadable})> _existing(
  FormWorkspace workspace,
  String formId,
) async {
  final stored = await workspace.bundlesOf(formId);
  final unreadable = [...stored.unreadable];
  String? fid;
  var highest = 0;
  for (final bundle in stored.bundles) {
    final meta = _meta(bundle.text);
    if (meta == null || (fid != null && fid != meta.fid)) {
      unreadable.add(bundle.path);
      continue;
    }
    fid = meta.fid;
    if (meta.seq > highest) highest = meta.seq;
  }
  return (fid: fid, highestSeq: highest, unreadable: unreadable);
}

/// `fid` en `bundle_seq` van een bundel zoals de werkmap hem bewaart. Niet geverifieerd — het zijn
/// de eigen bestanden —, wel strikt: wat er niet uitziet als een bundel is geen bundel.
({String fid, int seq})? _meta(String text) {
  final Object? json;
  try {
    json = jsonDecode(text);
  } on FormatException {
    return null;
  }
  if (json is! Map) return null;
  final fid = json['fid'];
  final seq = json['bundle_seq'];
  if (fid is! String || !isValidFormId(fid) || seq is! int || seq < 1) {
    return null;
  }
  return (fid: fid, seq: seq);
}
