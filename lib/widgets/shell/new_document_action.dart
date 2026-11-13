// Nieuw-document-actie: vraagt op desktop eerst naam en map
// (new_document_dialog.dart, #2177) en maakt het bestand daar meteen aan —
// de document-tegenhanger van `_createDeckFromDialog` voor presentaties.
// "Nog niet opslaan" of web levert een klad-tabblad in het geheugen; de
// eerste opslaan vraagt dan alsnog om een pad via 'Opslaan als…'.

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../l10n/app_localizations.dart';
import '../../models/document_template.dart';
import '../../services/document_template_service.dart';
import '../../state/settings_provider.dart';
import '../../state/tabs_provider.dart';
import '../../utils/error_snackbar.dart';
import '../../utils/safe_filename.dart';
import '../dialogs/cpe_issue_dialog.dart';
import '../dialogs/new_document_dialog.dart';

/// Testhaak voor de aanmaak-aanroep achter de dialoog — zelfde reden als
/// `debugImportTaskRunner` in document_import_action.dart: echte schijf-IO
/// (de exclusieve `File.create` in `newDocument`) beantwoordt de fake klok
/// van `flutter test` niet, dus een widgettest vervangt deze stap.
Future<bool> Function(String? filePath)? debugNewDocumentRunner;

/// Maakt een document aan met een optioneel sjabloon. Op desktop kiest de
/// gebruiker naam en map; op web blijft het document een klad. Leest
/// de providers zelf via de container, zoals [importDocument], zodat de
/// aanroepplekken — welkomstscherm, menubalk — geen `ref` hoeven door te
/// geven.
Future<void> newDocumentFromDialog(BuildContext context) async {
  final container = ProviderScope.containerOf(context);
  final choice = await NewDocumentDialog.show(
    context,
    libraries: container.read(settingsProvider).libraries,
  );
  if (choice == null || !context.mounted) return;
  bool created;
  var completed = 0;
  var total = 1;
  String? attemptedPath;
  try {
    final source = await DocumentTemplateService().load(
      choice.template,
      choice.language,
    );
    var documents = [(path: choice.path, source: source)];
    if (choice.template == DocumentTemplate.cpe) {
      if (!context.mounted) return;
      final certificates =
          await showDialog<List<({String name, String source})>>(
            context: context,
            barrierDismissible: false,
            builder: (_) => CpeIssueDialog(
              template: source,
              language: choice.language,
              projectPath: choice.path == null ? null : p.dirname(choice.path!),
            ),
          );
      if (certificates == null) return;
      documents = [
        for (var i = 0; i < certificates.length; i++)
          (
            path: choice.path == null
                ? null
                : p.join(
                    p.dirname(choice.path!),
                    '${p.basenameWithoutExtension(choice.path!)}_${i + 1}_${sanitizeFilename(certificates[i].name, fallback: 'participant')}.md',
                  ),
            source: certificates[i].source,
          ),
      ];
    }
    created = true;
    total = documents.length;
    for (final document in documents) {
      attemptedPath = document.path;
      final success = debugNewDocumentRunner != null
          ? await debugNewDocumentRunner!(document.path)
          : await container
                .read(tabsProvider.notifier)
                .newDocument(filePath: document.path, source: document.source);
      if (!success) {
        created = false;
        break;
      }
      completed++;
    }
  } on Object {
    created = false;
  }
  // `false` = het bestand kon niet aangemaakt worden (naamconflict dat de
  // dialoog-voorshow miste, of een schijffout). Bij groepsuitgifte vermeldt
  // de melding hoeveel documenten al gemaakt zijn en welk pad mislukte.
  if (!created && context.mounted) {
    showErrorSnackBar(
      ScaffoldMessenger.of(context),
      context.l10n,
      '${context.l10n.d('Kon het bestand niet aanmaken.')}'
      '${total > 1 ? ' ($completed/$total)' : ''}'
      '${total <= 1 || attemptedPath == null ? '' : '\n$attemptedPath'}',
    );
  }
}
