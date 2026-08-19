import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/document_chrome_template.dart';
import 'package:ocideck/utils/document_front_matter.dart';

void main() {
  test('vervangt bekende velden en laat onbekende placeholders staan', () {
    expect(
      resolveDocumentChromeTemplate(
        '{title} · {project-id} · {missing}',
        const {'title': 'Audit', 'project-id': 'P-42'},
      ),
      r'Audit · P\-42 · {missing}',
    );
  });

  test('veldwaarden kunnen geen Markdown of HTML in de band injecteren', () {
    const value = '**Beheerder** [open](javascript:alert(1)) <script>';

    final resolved = resolveDocumentChromeTemplate('Auteur: {author}', const {
      'author': value,
    });

    expect(resolved, isNot(contains('**Beheerder**')));
    expect(resolved, isNot(contains('[open](')));
    expect(resolved, isNot(contains('<script>')));
    expect(
      resolved,
      r'Auteur: \*\*Beheerder\*\* \[open\]\(javascript\:alert\(1\)\) \<script\>',
    );
  });

  test('raw-uitvoer laat escaping bewust aan de ontvangende renderer', () {
    const value = r'R&D_100% {intern}';

    expect(
      resolveDocumentChromeTemplate('{label}', const {
        'label': value,
      }, escapeMarkdownValues: false),
      value,
    );
  });

  test('begrensd resultaat voorkomt vermenigvuldiging per pagina', () {
    final value = 'x' * (kMaxDocumentFieldValueLength + 100);
    final resolved = resolveDocumentChromeTemplate(
      '{author} {author} {author} {author} {author}',
      {'author': value},
    );

    expect(resolved.length, kMaxResolvedDocumentChromeChars);
    expect(resolved, endsWith('…'));
  });

  test('veel placeholdermatches bouwen nooit eerst de volledige uitvoer', () {
    final template = List.filled(50000, '{author}').join();
    final value = '*' * kMaxDocumentFieldValueLength;

    final resolved = resolveDocumentChromeTemplate(template, {'author': value});

    expect(resolved.length, kMaxResolvedDocumentChromeChars);
    expect(resolved, startsWith(r'\*\*\*'));
    expect(resolved, endsWith('…'));
  });
}
