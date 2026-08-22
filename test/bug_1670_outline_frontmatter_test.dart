import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/markdown_document.dart';
import 'package:ocideck/utils/doc_link.dart';
import 'package:ocideck/widgets/reader/document_markdown_view.dart';

void main() {
  test(
    'headingBlockIndex op body wijst naar de juiste kop bij frontmatter (#1670)',
    () {
      const source =
          '---\n'
          'theme: vigilant\n'
          'papersize: a4\n'
          '---\n\n'
          '# Eerste kop\n\n'
          'Inhoud.\n\n'
          '## Tweede kop\n\n'
          'Meer inhoud.\n';

      final doc = MarkdownDocument.parse(source);

      // De preview rendert de body, niet de source. headingBlockIndex op de
      // body moet de kop vinden op de juiste plek.
      final bodyIndex = DocumentMarkdownView.headingBlockIndex(
        doc.body,
        headingSlug('Tweede kop'),
      );
      expect(bodyIndex, greaterThanOrEqualTo(0));

      // headingBlockIndex op de source (frontmatter + body) geeft een
      // ander index — dat is de bug: de frontmatter-blokken schuiven het
      // index op.
      final sourceIndex = DocumentMarkdownView.headingBlockIndex(
        doc.source,
        headingSlug('Tweede kop'),
      );
      // De body-index moet anders zijn dan de source-index: frontmatter
      // voegt blokken toe (thematische ---, sleutelregels als alinea's).
      expect(bodyIndex, isNot(sourceIndex));
    },
  );
}
