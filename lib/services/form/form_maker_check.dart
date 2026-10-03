// De controle door de maker (FORM_INTAKE.md §7.4), de kant die met bestanden werkt: het
// hoofdstuk van één inzending, zoals het in het boek komt, en het adres waaraan de
// organisator het stuurt.
//
// De controle is een **integriteitscontrole**, geen beleefdheid: een anonieme inzender is
// niet te authenticeren (§5.7), en alleen een antwoord vanaf het adres dat de inzending
// opgaf bevestigt dat de bijdrage van die persoon is. Het hoofdstuk wordt daarom gemaakt
// met dezelfde samensteller als het boek (`compileFormBook`, met één inzending): wat de
// maker ziet is wat er in het boek komt, niet een tweede opmaak die kan afwijken.
//
// Het document zelf verlaat OciDeck niet: de organisator opent het, exporteert het als
// pdf met de gewone export (die het privacyprofiel, de classificatie en de lettertypen al
// kent) en voegt het toe aan de mail. Alleen de mail wordt hier voorbereid.
library;

import 'dart:io';

import 'package:ocideck_form_core/ocideck_form_core.dart';
import 'package:path/path.dart' as p;

import 'form_book.dart';
import 'form_workspace.dart';

/// De uitkomst van [prepareMakerCheck].
sealed class FormMakerCheckOutcome {
  const FormMakerCheckOutcome();
}

/// Het controledocument staat klaar.
class FormMakerCheckReady extends FormMakerCheckOutcome {
  const FormMakerCheckReady({required this.path, required this.address});

  /// Het pad van het document (`book/check-<begin van het nummer>.md`).
  final String path;

  /// Het adres dat de maker opgaf, of `null` als het formulier er geen vroeg of de
  /// maker het leeg liet.
  final String? address;
}

/// De inzending is niet te lezen: verwijderd, kapot of van een formulier dat er niet is.
class FormMakerCheckUnavailable extends FormMakerCheckOutcome {
  const FormMakerCheckUnavailable();
}

/// Het hoofdstuk kon niet worden gemaakt; [outcome] zegt waarom.
class FormMakerCheckRefused extends FormMakerCheckOutcome {
  const FormMakerCheckRefused(this.outcome);

  final FormBookOutcome outcome;
}

/// Het hoogste volgnummer van een controledocument voor dezelfde inzending.
const int _maxCheckDocuments = 99;

/// Maakt het controledocument van inzending [sid] met hoofdstuksjabloon [template].
///
/// Het document krijgt een nieuwe naam — `check-<de eerste acht tekens van het nummer>`,
/// zo nodig met `-2`, `-3`, … — en overschrijft nooit een eerder: een eerste controle
/// kan al verstuurd zijn, en een verbeterde inzending krijgt een nieuw hoofdstuk.
Future<FormMakerCheckOutcome> prepareMakerCheck(
  FormWorkspace workspace, {
  required String sid,
  required String template,
  required DateTime now,
}) async {
  final stored = await workspace.reviewStored(sid);
  final review = stored is FormStoredReview ? stored.review : null;
  final spec = review?.spec;
  final answers = review?.answers;
  if (spec == null || answers == null) {
    return const FormMakerCheckUnavailable();
  }
  // Een nummer is altijd lang genoeg: `submissionPath` weigert al wat dat niet is.
  final base = 'check-${sid.substring(0, 8)}';
  final bookDir = p.join(workspace.root, 'book');
  var name = base;
  for (var n = 2; n <= _maxCheckDocuments; n++) {
    if (!await File(p.join(bookDir, '$name.md')).exists()) break;
    name = '$base-$n';
  }
  final outcome = await compileFormBook(
    workspace,
    form: spec,
    template: template,
    states: const {},
    name: name,
    now: now,
    onlySid: sid,
  );
  return outcome is FormBookWritten
      ? FormMakerCheckReady(
          path: outcome.path,
          address: makerAddressOf(spec, answers),
        )
      : FormMakerCheckRefused(outcome);
}

/// Het adres van de maker, voor een inzending die te lezen is; anders `null`.
Future<String?> makerAddressOfSubmission(
  FormWorkspace workspace,
  String sid,
) async {
  final stored = await workspace.reviewStored(sid);
  if (stored is! FormStoredReview) return null;
  final review = stored.review;
  final spec = review.spec;
  final answers = review.answers;
  return spec == null || answers == null ? null : makerAddressOf(spec, answers);
}
