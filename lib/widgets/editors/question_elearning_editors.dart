import 'package:material_ui/material_ui.dart';

import '../../l10n/app_localizations.dart';
import '../../models/question.dart';
import '../../services/image_service.dart';
import '../../theme/app_theme.dart';
import '_editor_field.dart';

/// Editor voor het matching-vraagtype. Aparte widget zodat _QuestionEditorState
/// onder de 1000-regel klasseplafond blijft — de eLearning-kinds hebben genoeg
/// eigen state om een eigen widget te rechtvaardigen.
class MatchingKindEditor extends StatelessWidget {
  final List<MatchPair> pairs;
  final List<String> distractors;
  final int answerLimit;
  final ValueChanged<List<MatchPair>> onPairsChanged;
  final ValueChanged<List<String>> onDistractorsChanged;

  const MatchingKindEditor({
    super.key,
    required this.pairs,
    required this.distractors,
    required this.answerLimit,
    required this.onPairsChanged,
    required this.onDistractorsChanged,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final filled = pairs.where((p) => p.isFilled).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionLabel('Paren'),
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            l10n.d(
              'De kijker koppelt links aan rechts. Paar i heeft links[i] als juiste antwoord bij rechts[i]. De rechterkolom wordt geschud bij presenteren.',
            ),
            style: TextStyle(fontSize: 12, color: AppTheme.slate500),
          ),
        ),
        for (var i = 0; i < pairs.length; i++) ...[
          _pairRow(l10n, i),
          const SizedBox(height: 8),
        ],
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: pairs.length < answerLimit
                ? () => onPairsChanged([...pairs, const MatchPair()])
                : null,
            icon: const Icon(Icons.add, size: 16),
            label: Text(l10n.d('Paar toevoegen')),
          ),
        ),
        const SizedBox(height: 12),
        const SectionLabel('Afleiders (optioneel)'),
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            l10n.d(
              'Extra rechteritems zonder correcte partner. Ze maken de vraag moeilijker.',
            ),
            style: TextStyle(fontSize: 12, color: AppTheme.slate500),
          ),
        ),
        for (var i = 0; i < distractors.length; i++) ...[
          _distractorRow(l10n, i),
          const SizedBox(height: 6),
        ],
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: distractors.length < answerLimit
                ? () => onDistractorsChanged([...distractors, ''])
                : null,
            icon: const Icon(Icons.add, size: 16),
            label: Text(l10n.d('Afleider toevoegen')),
          ),
        ),
        if (filled < 2)
          _warningRow(l10n.d('Maak minstens twee gevulde paren.')),
      ],
    );
  }

  Widget _pairRow(AppLocalizations l10n, int i) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _LabeledField(
            label: '${l10n.d('Links')} ${i + 1}',
            value: pairs[i].left,
            onChanged: (v) {
              final next = [...pairs];
              next[i] = pairs[i].copyWith(left: v);
              onPairsChanged(next);
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 32),
          child: Icon(Icons.arrow_forward, size: 18, color: AppTheme.slate400),
        ),
        Expanded(
          child: _LabeledField(
            label: '${l10n.d('Rechts')} ${i + 1}',
            value: pairs[i].right,
            onChanged: (v) {
              final next = [...pairs];
              next[i] = pairs[i].copyWith(right: v);
              onPairsChanged(next);
            },
          ),
        ),
        IconButton(
          icon: const Icon(Icons.remove_circle_outline, size: 20),
          onPressed: pairs.length > 2
              ? () {
                  final next = [...pairs]..removeAt(i);
                  onPairsChanged(next);
                }
              : null,
          tooltip: l10n.d('Paar verwijderen'),
        ),
      ],
    );
  }

  Widget _distractorRow(AppLocalizations l10n, int i) {
    return Row(
      children: [
        Expanded(
          child: _LabeledField(
            label: '${l10n.d('Afleider')} ${i + 1}',
            value: distractors[i],
            onChanged: (v) {
              final next = [...distractors];
              next[i] = v;
              onDistractorsChanged(next);
            },
          ),
        ),
        IconButton(
          icon: const Icon(Icons.remove_circle_outline, size: 20),
          onPressed: () {
            final next = [...distractors]..removeAt(i);
            onDistractorsChanged(next);
          },
          tooltip: l10n.d('Afleider verwijderen'),
        ),
      ],
    );
  }

  Widget _warningRow(String message) => Padding(
    padding: const EdgeInsets.only(top: 4),
    child: Row(
      children: [
        const Icon(
          Icons.warning_amber_rounded,
          size: 16,
          color: AppTheme.amber700,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            message,
            style: const TextStyle(fontSize: 12, color: AppTheme.amber700),
          ),
        ),
      ],
    ),
  );
}

/// Editor voor het invulvraag-type.
class FillInKindEditor extends StatelessWidget {
  final List<FillField> fields;
  final int answerLimit;
  final ValueChanged<List<FillField>> onFieldsChanged;

  const FillInKindEditor({
    super.key,
    required this.fields,
    required this.answerLimit,
    required this.onFieldsChanged,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final filled = fields.where((f) => f.accepted.isNotEmpty).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionLabel('Invulvelden'),
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            l10n.d(
              'De kijker typt het antwoord in elk veld. Elk veld heeft een of meer aanvaarde antwoorden en een evaluatiestrategie.',
            ),
            style: TextStyle(fontSize: 12, color: AppTheme.slate500),
          ),
        ),
        for (var i = 0; i < fields.length; i++) ...[
          _fieldRow(l10n, i),
          const SizedBox(height: 12),
        ],
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: fields.length < answerLimit
                ? () => onFieldsChanged([...fields, const FillField()])
                : null,
            icon: const Icon(Icons.add, size: 16),
            label: Text(l10n.d('Veld toevoegen')),
          ),
        ),
        if (filled == 0)
          _warningRow(
            l10n.d('Voeg minstens één veld toe met een aanvaard antwoord.'),
          ),
      ],
    );
  }

  Widget _fieldRow(AppLocalizations l10n, int i) {
    final field = fields[i];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              '${l10n.d('Veld')} ${i + 1}',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.remove_circle_outline, size: 20),
              onPressed: fields.length > 1
                  ? () {
                      final next = [...fields]..removeAt(i);
                      onFieldsChanged(next);
                    }
                  : null,
              tooltip: l10n.d('Veld verwijderen'),
            ),
          ],
        ),
        _LabeledField(
          label: l10n.d('Aanvaarde antwoorden (komma-gescheiden)'),
          value: field.accepted.join(', '),
          onChanged: (value) {
            final next = [...fields];
            next[i] = field.copyWith(
              accepted: value
                  .split(',')
                  .map((s) => s.trim())
                  .where((s) => s.isNotEmpty)
                  .toList(),
            );
            onFieldsChanged(next);
          },
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<FillMatchMode>(
                initialValue: field.matchMode,
                decoration: InputDecoration(
                  labelText: l10n.d('Evaluatiestrategie'),
                  isDense: true,
                ),
                items: [
                  DropdownMenuItem(
                    value: FillMatchMode.exact,
                    child: Text(l10n.d('Exacte overeenkomst')),
                  ),
                  DropdownMenuItem(
                    value: FillMatchMode.contains,
                    child: Text(l10n.d('Bevat het antwoord')),
                  ),
                  DropdownMenuItem(
                    value: FillMatchMode.similar,
                    child: Text(l10n.d('Tikfout toegestaan')),
                  ),
                  DropdownMenuItem(
                    value: FillMatchMode.numericRange,
                    child: Text(l10n.d('Getal in bereik')),
                  ),
                ],
                onChanged: (mode) {
                  if (mode == null) return;
                  final next = [...fields];
                  next[i] = field.copyWith(matchMode: mode);
                  onFieldsChanged(next);
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _LabeledField(
                label: l10n.d('Placeholder'),
                value: field.placeholder,
                onChanged: (value) {
                  final next = [...fields];
                  next[i] = field.copyWith(placeholder: value);
                  onFieldsChanged(next);
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _warningRow(String message) => Padding(
    padding: const EdgeInsets.only(top: 4),
    child: Row(
      children: [
        const Icon(
          Icons.warning_amber_rounded,
          size: 16,
          color: AppTheme.amber700,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            message,
            style: const TextStyle(fontSize: 12, color: AppTheme.amber700),
          ),
        ),
      ],
    ),
  );
}

/// Editor voor het hotspot-vraagtype.
class HotspotKindEditor extends StatelessWidget {
  final String hotspotImage;
  final List<HotspotRegion> regions;
  final bool multiSelect;
  final int answerLimit;
  final List<String> searchPaths;
  final String? captionBasePath;
  final ImageService imageService;
  final ValueChanged<String> onImageChanged;
  final ValueChanged<List<HotspotRegion>> onRegionsChanged;
  final ValueChanged<bool> onMultiSelectChanged;

  const HotspotKindEditor({
    super.key,
    required this.hotspotImage,
    required this.regions,
    required this.multiSelect,
    required this.answerLimit,
    required this.searchPaths,
    required this.captionBasePath,
    required this.imageService,
    required this.onImageChanged,
    required this.onRegionsChanged,
    required this.onMultiSelectChanged,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final hasCorrect = regions.any((r) => r.correct && r.coords.isNotEmpty);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionLabel('Afbeelding'),
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            l10n.d(
              'De kijker wijst één of meerdere gebieden op de afbeelding aan. Coördinaten zijn genormaliseerd (0–1).',
            ),
            style: TextStyle(fontSize: 12, color: AppTheme.slate500),
          ),
        ),
        ImagePickerBar(
          imagePath: hotspotImage,
          searchPaths: searchPaths,
          captionBasePath: captionBasePath,
          onPicked: (path, _) => onImageChanged(path),
          onBrowse: () async {
            final path = await pickImageWithFeedback(
              context,
              imageService,
              projectPath: captionBasePath,
            );
            if (path != null) onImageChanged(path);
          },
          onPaste: () async {
            final path = await pasteImageWithFeedback(
              context,
              imageService,
              projectPath: captionBasePath,
            );
            if (path != null) onImageChanged(path);
          },
          onClear: hotspotImage.isNotEmpty ? () => onImageChanged('') : null,
        ),
        const SizedBox(height: 16),
        const SectionLabel('Gebieden'),
        for (var i = 0; i < regions.length; i++) ...[
          _regionRow(l10n, i),
          const SizedBox(height: 8),
        ],
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: regions.length < answerLimit
                ? () => onRegionsChanged([...regions, const HotspotRegion()])
                : null,
            icon: const Icon(Icons.add, size: 16),
            label: Text(l10n.d('Gebied toevoegen')),
          ),
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          title: Text(l10n.d('Meerdere gebieden selecteerbaar')),
          value: multiSelect,
          onChanged: onMultiSelectChanged,
        ),
        if (hotspotImage.isEmpty || !hasCorrect)
          _warningRow(
            l10n.d('Kies een afbeelding en markeer minstens één juist gebied.'),
          ),
      ],
    );
  }

  Widget _regionRow(AppLocalizations l10n, int i) {
    final region = regions[i];
    final coordsText = region.coords.isEmpty
        ? '0.1, 0.1, 0.3, 0.3'
        : region.coords.map((c) => c.toStringAsFixed(2)).join(', ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              '${l10n.d('Gebied')} ${i + 1}',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.remove_circle_outline, size: 20),
              onPressed: regions.length > 1
                  ? () {
                      final next = [...regions]..removeAt(i);
                      onRegionsChanged(next);
                    }
                  : null,
              tooltip: l10n.d('Gebied verwijderen'),
            ),
          ],
        ),
        _LabeledField(
          label: l10n.d('Coördinaten (x, y, w, h — genormaliseerd 0–1)'),
          value: coordsText,
          onChanged: (value) {
            final parsed = value
                .split(',')
                .map((s) => double.tryParse(s.trim()))
                .where((v) => v != null)
                .cast<double>()
                .toList();
            final next = [...regions];
            next[i] = region.copyWith(coords: parsed);
            onRegionsChanged(next);
          },
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: _LabeledField(
                label: l10n.d('Label (optioneel)'),
                value: region.label,
                onChanged: (value) {
                  final next = [...regions];
                  next[i] = region.copyWith(label: value);
                  onRegionsChanged(next);
                },
              ),
            ),
            const SizedBox(width: 12),
            SegmentedButton<bool>(
              segments: [
                ButtonSegment(value: true, label: Text(l10n.d('Juist'))),
                ButtonSegment(value: false, label: Text(l10n.d('Afleider'))),
              ],
              selected: {region.correct},
              showSelectedIcon: false,
              onSelectionChanged: (selection) {
                final next = [...regions];
                next[i] = region.copyWith(correct: selection.first);
                onRegionsChanged(next);
              },
            ),
          ],
        ),
      ],
    );
  }

  Widget _warningRow(String message) => Padding(
    padding: const EdgeInsets.only(top: 4),
    child: Row(
      children: [
        const Icon(
          Icons.warning_amber_rounded,
          size: 16,
          color: AppTheme.amber700,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            message,
            style: const TextStyle(fontSize: 12, color: AppTheme.amber700),
          ),
        ),
      ],
    ),
  );
}

/// Een eenvoudig gelabeld tekstveld met onChanged.
class _LabeledField extends StatelessWidget {
  final String label;
  final String value;
  final ValueChanged<String> onChanged;

  const _LabeledField({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppTheme.slate500,
          ),
        ),
        const SizedBox(height: 5),
        TextField(
          controller: TextEditingController(text: value),
          onChanged: onChanged,
          maxLines: 1,
        ),
      ],
    );
  }
}
