// Part of the settings-dialog library — see ../settings_dialog.dart.
//
// De opsommingsteken-keuze van een stijlprofiel (stip, pootje of eigen SVG):
// de segmentknop plus de bestandskiezer voor de eigen marker. Eigen part omdat
// settings_dialog_colors.dart er anders over het regelplafond heen groeit;
// top-level hulp in plaats van een extensie, zodat de regels óók niet meer bij
// de klasse tellen.
part of '../settings_dialog.dart';

/// De instelrij voor [ThemeProfile.bulletMarker]: segmentknop, en bij
/// [BulletMarker.customSvg] de knoppen om een SVG te kiezen of te verwijderen.
Widget _bulletMarkerField(
  BuildContext context, {
  required ThemeProfile profile,
  required ValueChanged<ThemeProfile> onChanged,
}) {
  final l10n = context.l10n;
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _settingFieldRow(
        context,
        label: Text(
          l10n.d('Opsommingsteken'),
          style: const TextStyle(fontSize: 13),
        ),
        control: SegmentedButton<BulletMarker>(
          segments: [
            ButtonSegment(
              value: BulletMarker.dot,
              icon: const Icon(Icons.fiber_manual_record, size: 12),
              label: Text(l10n.d('Stip')),
            ),
            ButtonSegment(
              value: BulletMarker.paw,
              icon: const Icon(Icons.pets, size: 16),
              label: Text(l10n.d('Pootje')),
            ),
            ButtonSegment(
              value: BulletMarker.customSvg,
              icon: const Icon(Icons.image_outlined, size: 16),
              label: Text(l10n.d('SVG')),
            ),
          ],
          selected: {profile.bulletMarker},
          showSelectedIcon: false,
          style: const ButtonStyle(visualDensity: VisualDensity.compact),
          onSelectionChanged: (selection) =>
              onChanged(profile.copyWith(bulletMarker: selection.first)),
        ),
      ),
      if (profile.bulletMarker == BulletMarker.customSvg) ...[
        const SizedBox(height: 8),
        Row(
          children: [
            OutlinedButton.icon(
              key: const Key('custom-bullet-svg-picker'),
              onPressed: () async {
                final svg = await _pickCustomBulletSvgFile(context);
                if (svg != null && context.mounted) {
                  onChanged(profile.copyWith(customBulletSvg: svg));
                }
              },
              icon: const Icon(Icons.upload_file, size: 18),
              label: Text(
                l10n.d(
                  profile.customBulletSvg == null
                      ? 'Bestand kiezen'
                      : 'Vervangen',
                ),
              ),
            ),
            if (profile.customBulletSvg != null) ...[
              const SizedBox(width: 8),
              TextButton(
                onPressed: () =>
                    onChanged(profile.copyWith(clearCustomBulletSvg: true)),
                child: Text(l10n.d('Verwijder')),
              ),
            ],
          ],
        ),
      ],
    ],
  );
}

/// Laat de gebruiker een `.svg` kiezen en geef de gesanitiseerde inhoud terug,
/// of `null` bij annuleren, overschrijding van de limiet of onleesbare invoer —
/// de melding aan de gebruiker zit hier al bij.
Future<String?> _pickCustomBulletSvgFile(BuildContext context) async {
  final file = await FilePicker.pickFile(
    dialogTitle: context.l10n.d('Bestand kiezen'),
    type: FileType.custom,
    allowedExtensions: const ['svg'],
  );
  if (file == null || !context.mounted) return null;

  void reject(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(context.l10n.d(message))));

  final length = await file.length();
  if (!context.mounted) return null;
  if (length == null || length > kMaxCustomBulletSvgChars) {
    reject('Dit bestand is te groot om te openen.');
    return null;
  }

  final String source;
  try {
    source = utf8.decode(await file.readAsBytes());
  } on FormatException {
    if (context.mounted) reject('Het bestand kon niet worden gelezen.');
    return null;
  }
  final sanitised = sanitizeCustomBulletSvg(source);
  if (sanitised == null && context.mounted) {
    reject('Het bestand kon niet worden gelezen.');
  }
  return sanitised;
}
