import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/latex/markdown_to_latex.dart';
import 'package:ocideck/services/marp_html_service.dart';

Future<String> _diskLoader(String asset) => File(asset).readAsString();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const source = '''<!-- timeline -->
| Tijd | Gebeurtenis | Status |
| --- | --- | --- |
| 12:02 | Eerste melding | Gemeld |
| 13:41 | Herstelclaim **weerlegd** | Vastgesteld |''';

  test('LaTeX projecteert de tijdlijn zonder gewone tabular', () {
    final latex = markdownToLatex(source);
    expect(latex, contains(r'\begin{description}'));
    expect(latex, contains('12:02'));
    expect(latex, contains(r'Herstelclaim \textbf{weerlegd}'));
    expect(latex, contains('Status: Vastgesteld'));
    expect(latex, isNot(contains(r'\begin{tabular}')));
  });

  test(
    'continue HTML draagt tijdlijnstructuur en printveilige kaarten',
    () async {
      final html = await MarpHtmlService(
        loadAsset: _diskLoader,
      ).build(source, continuous: true);
      expect(html, contains('ocideck-timeline-marker'));
      expect(html, contains("list.className='ocideck-timeline'"));
      expect(html, contains('break-inside:avoid'));
      expect(html, contains('13:41'));
    },
  );
}
