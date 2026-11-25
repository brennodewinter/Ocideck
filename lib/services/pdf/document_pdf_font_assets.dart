import 'package:flutter/services.dart';

import '../font_substitution.dart';
import 'document_pdf_fonts.dart';

/// Use real regular, bold and italic outlines in Unicode document PDFs.
/// The static EB Garamond and Roboto faces are derived from the bundled OFL
/// variable fonts at weights 400 and 700, preserving all encoded glyphs.
/// Roboto Italic 3.015 comes from google/fonts commit
/// 6183fc0d26361f6ddfd6f6b7a736e1467c6d8a43 under the same Roboto OFL.
Future<DocumentPdfFonts> loadDocumentPdfTypefaces(
  String family, {
  String? headingFamily,
  List<ByteData> fallbackFonts = const [],
}) async {
  String assetFamily(String name) =>
      classifyFontFamily(name) == FontClass.serif ? 'EBGaramond' : 'Roboto';

  final body = assetFamily(family);
  final heading = assetFamily(headingFamily ?? family);
  try {
    final (bodyFace, headingFace, mono) = await (
      _loadTypeface(body),
      heading == body
          ? Future<DocumentPdfTypeface?>.value()
          : _loadTypeface(heading),
      Future.sync(
        () => rootBundle.load('assets/fonts/RobotoMono-Variable.ttf'),
      ),
    ).wait;
    return DocumentPdfFonts.embedded(
      body: bodyFace,
      heading: headingFace ?? bodyFace,
      mono: mono,
      fallbackFonts: fallbackFonts,
    );
  } on ParallelWaitError<Object?, Object?> {
    // Headless callers may run without a Flutter asset bundle.
    return DocumentPdfFonts.forFamily(
      family,
      headingFamily: headingFamily,
      fallbackFonts: fallbackFonts,
    );
  }
}

Future<DocumentPdfTypeface> _loadTypeface(String family) async {
  Future<ByteData> load(String style) =>
      Future.sync(() => rootBundle.load('assets/fonts/pdf/$family-$style.ttf'));
  final (regular, bold, italic, boldItalic) = await (
    load('Regular'),
    load('Bold'),
    load('Italic'),
    load('BoldItalic'),
  ).wait;
  return (regular: regular, bold: bold, italic: italic, boldItalic: boldItalic);
}
