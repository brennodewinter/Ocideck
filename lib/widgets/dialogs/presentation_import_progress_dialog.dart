import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../services/import/pipeline/import_task.dart';
import '../../services/import/presentation_import_service.dart';
import '../../theme/app_theme.dart';

/// Een klein annuleerbaar voortgangsvenster voor het importeren van één
/// presentatie (#875).
///
/// De enkelvoudige import las vroeger zonder venster: de UI wachtte af, en bij
/// een groot of vijandig bestand blokkeerde ze secondenlang zonder dat de
/// gebruiker kon zien of stoppen. Nu draait het lezen op een worker-isolate en
/// toont dit venster de voortgang met een **Stoppen**-knop. Stoppen cancelt de
/// [ImportCancelToken]; de worker breekt af, er is niets half af, en het venster
/// sluit met een geannuleerde uitkomst.
///
/// Het venster stuurt de taak zelf aan: het start [task] in `initState`, werkt
/// de balk bij op elke voortgangsstap, en sluit zichzelf met de uitkomst zodra
/// de taak klaar is — geslaagd, mislukt of geannuleerd.
class PresentationImportProgressDialog extends StatefulWidget {
  const PresentationImportProgressDialog._({
    required this.fileName,
    required this.task,
  });

  /// De naam van het bestand, als titel van het venster.
  final String fileName;

  /// De taak die het venster draait: krijgt een voortgangsrapporteur en de
  /// annuleertoken, en levert de voorbereide import (of een geannuleerde/mislukte
  /// uitkomst) terug.
  final Future<PreparedImportResult> Function(
    void Function(double fraction, String message) report,
    ImportCancelToken cancel,
  )
  task;

  /// Toon het venster en draai [task]. Het venster sluit zichzelf zodra de taak
  /// klaar is en levert die uitkomst terug; een venster dat toch wordt
  /// weggeklikt leest als een annulering (er is dan niets gebouwd).
  static Future<PreparedImportResult> run(
    BuildContext context, {
    required String fileName,
    required Future<PreparedImportResult> Function(
      void Function(double fraction, String message) report,
      ImportCancelToken cancel,
    )
    task,
  }) async {
    final result = await showDialog<PreparedImportResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          PresentationImportProgressDialog._(fileName: fileName, task: task),
    );
    return result ?? const PreparedImportResult.cancelled();
  }

  @override
  State<PresentationImportProgressDialog> createState() =>
      _PresentationImportProgressDialogState();
}

class _PresentationImportProgressDialogState
    extends State<PresentationImportProgressDialog> {
  final ImportCancelToken _cancel = ImportCancelToken();
  double _fraction = 0;
  String _message = '';
  bool _stopRequested = false;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    final result = await widget.task((fraction, message) {
      if (mounted) {
        setState(() {
          _fraction = fraction;
          _message = message;
        });
      }
    }, _cancel);
    if (mounted) Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return PopScope(
      // Niet weg te klikken: de taak bepaalt wanneer het venster sluit. Stoppen
      // gaat via de knop, die de worker netjes afbreekt.
      canPop: false,
      child: AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.slideshow_outlined, size: 20),
            const SizedBox(width: 8),
            Flexible(
              child: Text(widget.fileName, overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Onbepaald tot de eerste stap binnen is; daarna de echte breuk.
            LinearProgressIndicator(value: _fraction == 0 ? null : _fraction),
            if (_message.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                // `_message` is een vaste Nederlandse voortgangsstring uit de
                // servicelaag (die geen `BuildContext` heeft); `l10n.d` vertaalt
                // hem hier — dezelfde naad als de wachtrijdialoog.
                l10n.d(_message),
                style: TextStyle(fontSize: 12, color: AppTheme.slate500),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: _stopRequested
                ? null
                : () {
                    _cancel.cancel();
                    setState(() => _stopRequested = true);
                  },
            child: Text(l10n.d('Stoppen')),
          ),
        ],
      ),
    );
  }
}
