import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/improvement_y01.dart';
import '../../services/improvement/improvement_project_scaffold.dart';

/// Outcome of the process-improvement project wizard.
class ImprovementProjectChoice {
  final String title;
  final String framework;
  final ImprovementY01Metric y01;

  const ImprovementProjectChoice({
    required this.title,
    required this.framework,
    required this.y01,
  });

  /// Alias for [y01.name] — kept for call sites that only need the description.
  String get y01Description => y01.name;
}

/// Wizard for a new Lean Six Sigma / process-improvement project deck.
class ImprovementProjectWizard extends StatefulWidget {
  const ImprovementProjectWizard({super.key});

  static Future<ImprovementProjectChoice?> show(BuildContext context) {
    return showDialog<ImprovementProjectChoice>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const ImprovementProjectWizard(),
    );
  }

  @override
  State<ImprovementProjectWizard> createState() =>
      _ImprovementProjectWizardState();
}

class _ImprovementProjectWizardState extends State<ImprovementProjectWizard> {
  final _titleCtrl = TextEditingController();
  final _y01Ctrl = TextEditingController();
  final _uslCtrl = TextEditingController();
  final _lslCtrl = TextEditingController();
  final _unitCtrl = TextEditingController();
  final _targetCtrl = TextEditingController();
  final _baselineCtrl = TextEditingController();
  final _goalCtrl = TextEditingController();
  String _framework = kImprovementFrameworks.first;
  bool _noLimitsYet = true;

  @override
  void dispose() {
    _titleCtrl.dispose();
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
    if (text.isEmpty) return null;
    return double.tryParse(text);
  }

  void _finish() {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) return;
    final usl = _noLimitsYet ? null : _parseOptional(_uslCtrl.text);
    final lsl = _noLimitsYet ? null : _parseOptional(_lslCtrl.text);
    Navigator.of(context).pop(
      ImprovementProjectChoice(
        title: title,
        framework: _framework,
        y01: ImprovementY01Metric(
          name: _y01Ctrl.text.trim(),
          unit: _unitCtrl.text.trim(),
          usl: usl,
          lsl: lsl,
          target: _parseOptional(_targetCtrl.text),
          baseline: _parseOptional(_baselineCtrl.text),
          goal: _parseOptional(_goalCtrl.text),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.d('Nieuw verbeteringsproject')),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<String>(
                initialValue: _framework,
                decoration: InputDecoration(labelText: l10n.d('Kader')),
                items: [
                  for (final fw in kImprovementFrameworks)
                    DropdownMenuItem(value: fw, child: Text(fw.toUpperCase())),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  setState(() => _framework = v);
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _titleCtrl,
                decoration: InputDecoration(labelText: l10n.d('Projecttitel')),
                textInputAction: TextInputAction.next,
                autofocus: true,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _y01Ctrl,
                decoration: InputDecoration(
                  labelText: l10n.d('Primaire Y-metriek (Y-01)'),
                  hintText: l10n.d(
                    'Bijvoorbeeld: doorlooptijd orderintake in werkdagen',
                  ),
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 12),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.d('Nog geen specificatielimiet')),
                value: _noLimitsYet,
                onChanged: (v) {
                  setState(() {
                    _noLimitsYet = v ?? true;
                    if (_noLimitsYet) {
                      _uslCtrl.clear();
                      _lslCtrl.clear();
                    }
                  });
                },
              ),
              if (!_noLimitsYet) ...[
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
              ],
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
          onPressed: _titleCtrl.text.trim().isEmpty ? null : _finish,
          child: Text(l10n.d('Project starten')),
        ),
      ],
    );
  }
}
