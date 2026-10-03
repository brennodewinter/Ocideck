/// The team of a form's organisers (FORM_INTAKE.md §7.6): the editors, other than the owner, who
/// are listed in every bundle the owner signs so they can open the submissions too.
///
/// It is a list of [FormEditorCard]s the owner has accepted — each one after typing back the card's
/// fingerprint, which the editor gave by another road (§5.1, *the editor card*). The owner is not in it:
/// the owner is whoever holds the editorial key on this machine, and is added to the bundle from there.
///
/// This file holds the rules (who may be added, in what order, how it is written down); where the file
/// lives and when it is read or written is the workspace's business.
library;

import 'dart:convert';

import 'form_bundle.dart' show organiserKid;
import 'form_editor_card.dart';
import 'form_seal.dart';

/// The team file version this engine reads and writes.
const int kFormTeamVersion = 1;

/// The most editors besides the owner: a bundle may name [kFormMaxRecipients] organisers in all, and
/// a package is sealed to every one of them.
const int kFormMaxEditors = kFormMaxRecipients - 1;

/// Why [FormTeam.withEditor] did not add a card.
enum FormTeamAddIssue {
  /// The card is the owner's own: the keys on it are the ones this machine holds.
  owner,

  /// Someone in the team has this recipient, this signing key or this key id already.
  duplicate,

  /// The team is as large as a bundle can carry ([kFormMaxEditors]).
  full,
}

/// The outcome of [FormTeam.withEditor].
sealed class FormTeamAdd {
  const FormTeamAdd();
}

/// The card was added.
class FormTeamAdded extends FormTeamAdd {
  const FormTeamAdded(this.team);

  /// The team with the new editor last.
  final FormTeam team;
}

/// The card was not added.
class FormTeamAddRefused extends FormTeamAdd {
  const FormTeamAddRefused(this.issue);

  final FormTeamAddIssue issue;
}

/// The editors of a form besides its owner. Immutable.
class FormTeam {
  const FormTeam([this.editors = const []]);

  /// In the order they were added.
  final List<FormEditorCard> editors;

  /// Whether [a] and [b] clash: one organiser may not repeat another's recipient, key or key id —
  /// the same rule a bundle is verified by.
  static bool _same(FormEditorCard a, String age, String sign, String kid) =>
      a.age == age || a.sign == sign || a.kid == kid;

  /// This team with [card] added, unless it is the owner's ([ownerAge], [ownerSign]), repeats an editor,
  /// or the team is full.
  FormTeamAdd withEditor(
    FormEditorCard card, {
    required String ownerAge,
    required String ownerSign,
  }) {
    if (card.age == ownerAge ||
        card.sign == ownerSign ||
        card.kid == organiserKid(ownerAge)) {
      return const FormTeamAddRefused(FormTeamAddIssue.owner);
    }
    if (editors.any((e) => _same(e, card.age, card.sign, card.kid))) {
      return const FormTeamAddRefused(FormTeamAddIssue.duplicate);
    }
    if (editors.length >= kFormMaxEditors) {
      return const FormTeamAddRefused(FormTeamAddIssue.full);
    }
    return FormTeamAdded(FormTeam([...editors, card]));
  }

  /// This team without the editor whose key id is [kid]; the same team if there is none.
  FormTeam without(String kid) => FormTeam([
    for (final e in editors)
      if (e.kid != kid) e,
  ]);

  /// The team file's text: indented, one trailing newline.
  String toJsonText() =>
      '${const JsonEncoder.withIndent('  ').convert({
        'v': kFormTeamVersion,
        'editors': [for (final e in editors) e.toJson()],
      })}\n';
}

/// Why a team file was not read.
enum FormTeamIssue {
  /// Not JSON, not an object, or with a key a team file does not have.
  notATeam,

  /// `v` is not the version this engine reads.
  unsupportedVersion,

  /// An entry of `editors` is not an editor card (the card's own issue is in
  /// [FormTeamRefused.card]), or the list is not a list.
  badEditor,

  /// Two entries clash: the same recipient, signing key or key id.
  duplicate,

  /// More editors than [kFormMaxEditors].
  tooMany,
}

/// The outcome of [parseFormTeam].
sealed class FormTeamResult {
  const FormTeamResult();
}

/// A team file that is one.
class FormTeamParsed extends FormTeamResult {
  const FormTeamParsed(this.team);

  final FormTeam team;
}

/// A team file that is not, and why.
class FormTeamRefused extends FormTeamResult {
  const FormTeamRefused(this.issue, {this.card});

  final FormTeamIssue issue;

  /// With [FormTeamIssue.badEditor]: what is wrong with the entry, when it was an object.
  final FormEditorCardIssue? card;
}

/// Reads [text] as a team file. Never throws; every card in it is read as strictly as a card is.
FormTeamResult parseFormTeam(String text) {
  final Object? json;
  try {
    json = jsonDecode(text);
  } on FormatException {
    return const FormTeamRefused(FormTeamIssue.notATeam);
  }
  if (json is! Map || json.keys.any((k) => k != 'v' && k != 'editors')) {
    return const FormTeamRefused(FormTeamIssue.notATeam);
  }
  if (json['v'] != kFormTeamVersion) {
    return FormTeamRefused(
      json['v'] is int
          ? FormTeamIssue.unsupportedVersion
          : FormTeamIssue.notATeam,
    );
  }
  final list = json['editors'];
  if (list is! List) return const FormTeamRefused(FormTeamIssue.badEditor);
  if (list.length > kFormMaxEditors) {
    return const FormTeamRefused(FormTeamIssue.tooMany);
  }
  final editors = <FormEditorCard>[];
  for (final entry in list) {
    final result = parseFormEditorCard(jsonEncode(entry));
    if (result is! FormEditorCardParsed) {
      return FormTeamRefused(
        FormTeamIssue.badEditor,
        card: (result as FormEditorCardRefused).issue,
      );
    }
    final card = result.card;
    if (editors.any((e) => FormTeam._same(e, card.age, card.sign, card.kid))) {
      return const FormTeamRefused(FormTeamIssue.duplicate);
    }
    editors.add(card);
  }
  return FormTeamParsed(FormTeam(editors));
}
