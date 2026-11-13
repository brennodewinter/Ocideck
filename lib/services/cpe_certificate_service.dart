import 'package:ocideck_form_core/ocideck_form_core.dart';

import '../models/markdown_document.dart';

/// Shared course data stays in a single form; individual attendance never does.
class CpeCertificateService {
  static String groupForm(String template, String language) {
    var body = MarkdownDocument.parse(template).body.replaceFirst(
      'overview="naam,programma,uren"',
      'overview="programma"',
    );
    for (final id in ['naam', 'mail', 'uren']) {
      body = body.replaceFirst(
        RegExp('<!-- field id=$id .*?<!-- /field id=$id -->\\n*', dotAll: true),
        '',
      );
    }
    final nl = language == 'nl';
    final columns = nl
        ? 'Naam|E-mailadres|PE-uren|Afwijkende aanwezigheid (optioneel)'
        : 'Name|Email address|CPE hours|Attendance exceptions (optional)';
    return '$body\n<!-- field id=deelnemers type=table columns="$columns" rows=1.. required -->\n'
        '**${nl ? 'Deelnemers' : 'Participants'}**\n'
        '> ${nl ? 'Eén rij per persoon. Vul netto uren per deelnemer in, exclusief pauzes. Vermeld gemiste sessies of afwijkende tijden in de laatste kolom.' : 'One row per person. Enter net hours for each participant, excluding breaks. Note missed sessions or different times in the last column.'}\n'
        '<!-- answer -->\n<!-- /field id=deelnemers -->\n';
  }

  /// Throws before creating any documents if any participant is invalid.
  static List<({String name, String source})> issue(
    String template,
    FormFill group,
    String language,
  ) {
    if (!group.canSend) throw const FormatException('Incomplete course data');
    final rows = group.answerOf('deelnemers').value.rows;
    final certificates = <({String name, String source})>[];
    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      if (row.length != 4) throw const FormatException('Invalid participant');
      var individual =
          (FormFill.open(
                    MarkdownDocument.parse(template).body,
                    imageFacts: group.imageFacts,
                  )
                  as FormFillReady)
              .fill;
      for (final field in individual.spec.fields) {
        final value = switch (field.id) {
          'naam' => FormAnswerValue(text: row[0].trim()),
          'mail' => FormAnswerValue(text: row[1].trim()),
          'uren' => FormAnswerValue(text: row[2].trim()),
          _ => group.answerOf(field.id).value,
        };
        final step = individual.setAnswer(field.id, value);
        if (step is! FormFillChanged) {
          throw const FormatException('Invalid answer');
        }
        individual = step.fill;
      }
      if (!individual.canSend) {
        throw FormatException(
          'Invalid participant name, email or hours',
          null,
          i + 1,
        );
      }
      certificates.add((
        name: row[0].trim(),
        source: _certificate(individual, row[3], language),
      ));
    }
    return certificates;
  }

  static String _certificate(
    FormFill fill,
    String attendance,
    String language,
  ) {
    final nl = language == 'nl';
    String answer(String id) => fill.answerOf(id).raw.trim();
    String cell(String text) =>
        text.replaceAll('|', r'\|').replaceAll('\n', ' ');
    String label(String id) {
      final region = fill.fieldOf(id).label;
      return fill.text
          .substring(region.start, region.end)
          .split('\n')
          .first
          .replaceAll('**', '')
          .trim();
    }

    final out =
        StringBuffer(
            '---\npapersize: a4\ngeometry: top=18mm,bottom=18mm,left=22mm,right=22mm\n---\n\n',
          )
          ..writeln(
            '![ISACA Netherlands Chapter](asset:assets/images/isaca-netherlands-chapter.png)\n',
          )
          ..writeln(
            '# ${nl ? 'Bewijs van deelname' : 'Certificate of attendance'}\n',
          )
          ..writeln('**CONTINUING PROFESSIONAL EDUCATION · PE / CPE**\n')
          ..writeln('## ${answer('naam')}\n')
          ..writeln('${answer('mail')}\n')
          ..writeln(nl ? 'Heeft deelgenomen aan:' : 'Has attended:')
          ..writeln('\n**${answer('programma')}**\n')
          ..writeln('### ${answer('uren')} ${nl ? 'PE-uren' : 'CPE hours'}\n')
          ..writeln(answer('sessies'))
          ..writeln();
    if (attendance.trim().isNotEmpty) {
      // Treat attendance as plain text, never as document structure.
      out.writeln(
        '**${nl ? 'Afwijkende aanwezigheid' : 'Attendance exceptions'}:** ${cell(attendance)}\n',
      );
    }
    out.writeln(
      '| ${nl ? 'Opleidingsgegevens' : 'Course details'} | |\n| --- | --- |',
    );
    for (final id in ['locatie', 'docent', 'uitgever', 'datum']) {
      out.writeln('| ${label(id)} | ${cell(answer(id))} |');
    }
    out.writeln('\n${answer('logo')}\n');
    out.writeln('**${nl ? 'Bevestigd door' : 'Confirmed by'}**\n');
    out.writeln('${answer('ondertekenaar')}\n');
    out.writeln(answer('handtekening'));
    return out.toString();
  }
}
