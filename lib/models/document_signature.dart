/// A reusable, non-drawing visual signature block: who signed, in what role,
/// on what date, an optional statement they attest to, and the signature itself
/// as a typed name and/or an image path. Deliberately SIMPLE — no freehand
/// canvas — so it can be reused anywhere (the pentest sign-off slide is a later
/// consumer). Stored deck-level in the markdown front matter (see
/// `markdown_service`), so it round-trips as plain, human-readable text and is
/// covered by the document seal (see [DocumentIntegrity]).
class DocumentSignature {
  /// Name of the signer.
  final String name;

  /// Role or function of the signer (e.g. "Onderzoeker", "CISO").
  final String role;

  /// Signing date, free-form text (typically an ISO date like `2026-07-10`).
  final String date;

  /// The statement the signer attests to (e.g. a truthful-reporting clause).
  final String statement;

  /// The signature rendered as a typed name.
  final String typedSignature;

  /// Optional path to an image of the signature (relative to the deck folder or
  /// an embedded data URI). Empty when no image is used.
  final String imagePath;

  const DocumentSignature({
    this.name = '',
    this.role = '',
    this.date = '',
    this.statement = '',
    this.typedSignature = '',
    this.imagePath = '',
  });

  /// Whether every field is blank — i.e. there is effectively no signature. Used
  /// so an empty signature is neither serialised nor rendered.
  bool get isEmpty =>
      name.isEmpty &&
      role.isEmpty &&
      date.isEmpty &&
      statement.isEmpty &&
      typedSignature.isEmpty &&
      imagePath.isEmpty;

  bool get isNotEmpty => !isEmpty;

  DocumentSignature copyWith({
    String? name,
    String? role,
    String? date,
    String? statement,
    String? typedSignature,
    String? imagePath,
  }) {
    return DocumentSignature(
      name: name ?? this.name,
      role: role ?? this.role,
      date: date ?? this.date,
      statement: statement ?? this.statement,
      typedSignature: typedSignature ?? this.typedSignature,
      imagePath: imagePath ?? this.imagePath,
    );
  }
}
