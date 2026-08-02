import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/improvement_y01.dart';

/// Collects the optional Y-01 metadata after an improvement-project template
/// has been chosen. The method itself belongs in the template catalogue; this
/// dialog therefore contains no second, competing framework picker.
class ImprovementProjectSetupDialog extends StatefulWidget {
  const ImprovementProjectSetupDialog({super.key});

  static Future<ImprovementY01Metric?> show(BuildContext context) {
    return showDialog<ImprovementY01Metric>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const ImprovementProjectSetupDialog(),
    );
  }

  @override
  State<ImprovementProjectSetupDialog> createState() =>
      _ImprovementProjectSetupDialogState();
}

class _ImprovementProjectSetupDialogState
    extends State<ImprovementProjectSetupDialog> {
  final _y01Ctrl = TextEditingController();
  final _uslCtrl = TextEditingController();
  final _lslCtrl = TextEditingController();
  final _unitCtrl = TextEditingController();
  final _targetCtrl = TextEditingController();
  final _baselineCtrl = TextEditingController();
  final _goalCtrl = TextEditingController();
  bool _noLimitsYet = true;

  @override
  void dispose() {
    _y01Ctrl.dispose();
    _uslCtrl.dispose();
    _lslCtrl.dispose();
    _unitCtrl.dispose();
    _targetCtrl.dispose();
    _baselineCtrl.dispose();
    _goalCtrl.dispose();
    super.dispose();
  }

  double? _parseOptional(String raw) {
    final text = raw.trim().replaceAll(',', '.');
    return text.isEmpty ? null : double.tryParse(text);
  }

  void _finish() {
    Navigator.of(context).pop(
      ImprovementY01Metric(
        name: _y01Ctrl.text.trim(),
        unit: _unitCtrl.text.trim(),
        usl: _noLimitsYet ? null : _parseOptional(_uslCtrl.text),
        lsl: _noLimitsYet ? null : _parseOptional(_lslCtrl.text),
        target: _parseOptional(_targetCtrl.text),
        baseline: _parseOptional(_baselineCtrl.text),
        goal: _parseOptional(_goalCtrl.text),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.d('Primaire Y-metriek (Y-01)')),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                key: const ValueKey('improvementY01Name'),
                controller: _y01Ctrl,
                decoration: InputDecoration(
                  labelText: l10n.d('Primaire Y-metriek (Y-01)'),
                  hintText: l10n.d(
                    'Bijvoorbeeld: doorlooptijd orderintake in werkdagen',
                  ),
                ),
                maxLines: 2,
                autofocus: true,
              ),
              const SizedBox(height: 12),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.d('Nog geen specificatielimiet')),
                value: _noLimitsYet,
                onChanged: (value) {
                  setState(() {
                    _noLimitsYet = value ?? true;
                    if (_noLimitsYet) {
                      _uslCtrl.clear();
                      _lslCtrl.clear();
                    }
                  });
                },
              ),
              if (!_noLimitsYet)
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _uslCtrl,
                        decoration: InputDecoration(
                          labelText: l10n.d('USL (bovengrens)'),
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _lslCtrl,
                        decoration: InputDecoration(
                          labelText: l10n.d('LSL (ondergrens)'),
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                      ),
                    ),
                  ],
                ),
              ExpansionTile(
                title: Text(l10n.d('Optionele Y-01-velden')),
                children: [
                  TextField(
                    controller: _unitCtrl,
                    decoration: InputDecoration(labelText: l10n.d('Eenheid')),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _targetCtrl,
                    decoration: InputDecoration(
                      labelText: l10n.d('Procesdoel (target)'),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _baselineCtrl,
                    decoration: InputDecoration(labelText: l10n.d('Baseline')),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _goalCtrl,
                    decoration: InputDecoration(labelText: l10n.d('Doel')),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.t('cancel')),
        ),
        FilledButton(
          key: const ValueKey('improvementProjectStart'),
          onPressed: _finish,
          child: Text(l10n.d('Project starten')),
        ),
      ],
    );
  }
}
