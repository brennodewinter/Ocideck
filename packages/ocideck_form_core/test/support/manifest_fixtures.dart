import 'dart:convert';
import 'dart:typed_data';

import 'package:ocideck_form_core/ocideck_form_core.dart';

/// [p] with a different manifest: the consent record and/or the template hash
/// changed, everything else as received. The manifest bytes are written again, as
/// a package that really said so would carry them.
FormPackageOpened withManifest(
  FormPackageOpened p, {
  List<FormManifestConsent>? consent,
  String? templateSha256,
}) {
  final m = p.manifest;
  final manifest = FormPackageManifest(
    submissionId: m.submissionId,
    formId: m.formId,
    formVersion: m.formVersion,
    formRules: m.formRules,
    templateSha256: templateSha256 ?? m.templateSha256,
    created: m.created,
    clientName: m.clientName,
    clientVersion: m.clientVersion,
    clientRules: m.clientRules,
    files: m.files,
    consent: consent ?? m.consent,
  );
  return FormPackageOpened(
    manifest: manifest,
    manifestBytes: Uint8List.fromList(utf8.encode(manifest.toJsonText())),
    submission: p.submission,
    submissionBytes: p.submissionBytes,
    images: p.images,
  );
}
