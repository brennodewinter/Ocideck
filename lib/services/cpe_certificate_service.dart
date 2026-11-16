import 'package:ocideck_form_core/ocideck_form_core.dart';

import '../models/markdown_document.dart';
import '../utils/image_size_tokens.dart';

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
        '> ${nl ? 'Eén rij per persoon. Laat PE-uren leeg voor het totaal van de sessies — hoger dan dat totaal kan niet. Vermeld gemiste sessies of afwijkende tijden in de laatste kolom.' : 'One row per person. Leave CPE hours empty for the session total — more than that total is not possible. Note missed sessions or different times in the last column.'}\n'
        '<!-- answer -->\n<!-- /field id=deelnemers -->\n';
  }

  /// De lengte van één sessiecultuur in uren, uit de `Tijd`-kolom:
  /// tijdsblokken (`09:00 - 12:30`, meerdere per cel mogen) of een urenaantal
  /// (`6,5`, `6,5 uur`, `90 minuten`). Geeft `null` als niets ervan parseert.
  static double? sessionHours(String cell) {
    final text = cell.trim();
    if (text.isEmpty) return null;
    final blocks = RegExp(
      r'(\d{1,2})[:.](\d{2})\s*[-–—]+\s*(\d{1,2})[:.](\d{2})',
    ).allMatches(text);
    if (blocks.isNotEmpty) {
      var minutes = 0;
      for (final m in blocks) {
        final start = int.parse(m[1]!) * 60 + int.parse(m[2]!);
        var end = int.parse(m[3]!) * 60 + int.parse(m[4]!);
        // Een blok over middernacht ('22:00 - 02:00') loopt de dag door.
        if (end <= start) end += 24 * 60;
        minutes += end - start;
      }
      return minutes / 60;
    }
    final minutes = RegExp(
      r'(\d+)\s*(?:minuten|min)\b',
      caseSensitive: false,
    ).firstMatch(text);
    if (minutes != null) return int.parse(minutes[1]!) / 60;
    final hours =
        RegExp(
          r'(\d+(?:[.,]\d+)?)\s*(?:uur|uren|hours?|h)\b',
          caseSensitive: false,
        ).firstMatch(text) ??
        RegExp(r'^\s*(\d+(?:[.,]\d+)?)\s*$').firstMatch(text);
    if (hours == null) return null;
    return double.tryParse(hours[1]!.replaceAll(',', '.'));
  }

  /// Het PE-totaal van de sessietabel, of `null` als geen enkele tijdsopgave
  /// parseert — dan is er geen bovengrens om te bewaken.
  static double? sessionTotal(FormFill group) {
    var total = 0.0;
    var found = false;
    for (final row in group.answerOf('sessies').value.rows) {
      if (row.length < 3) continue;
      final hours = sessionHours(row[2]);
      if (hours == null) continue;
      total += hours;
      found = true;
    }
    return found ? total : null;
  }

  /// `8.0` → `8`, `6.5` → `6,5` (nl) — zoals de invuller het zelf zou schrijven.
  static String formatHours(double hours, {required bool nl}) {
    final text = hours.toStringAsFixed(2).replaceAll(RegExp(r'\.?0+$'), '');
    return nl ? text.replaceAll('.', ',') : text;
  }

  /// Throws before creating any documents if any participant is invalid.
  static List<({String name, String source})> issue(
    String template,
    FormFill group,
    String language,
  ) {
    if (!group.canSend) throw const FormatException('Incomplete course data');
    final rows = group.answerOf('deelnemers').value.rows;
    // Het sessietotaal is de standaard én het plafond: een lege urenkolom
    // krijgt het totaal, en meer PE-uren dan er sessietijd was kan niet.
    final total = sessionTotal(group);
    final certificates = <({String name, String source})>[];
    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      if (row.length != 4) throw const FormatException('Invalid participant');
      var hours = row[2].trim();
      if (hours.isEmpty && total != null) {
        hours = formatHours(total, nl: language == 'nl');
      }
      final given = double.tryParse(hours.replaceAll(',', '.'));
      if (total != null && given != null && given > total) {
        throw FormatException('Hours above session total', null, i + 1);
      }
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
          'uren' => FormAnswerValue(text: hours),
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
    // Een handtekening hoort een strook te zijn, geen plaat op kolombreedte:
    // `h:` begrenst de hoogte in lezer én export (image_size_tokens.dart).
    out.writeln(
      markdownImageWithSize(answer('handtekening'), (
        width: null,
        widthFraction: null,
        height: 96,
      )),
    );
    return out.toString();
  }
}
