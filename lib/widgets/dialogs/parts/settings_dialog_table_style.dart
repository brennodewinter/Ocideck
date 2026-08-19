// Part of the settings-dialog library — see ../settings_dialog.dart.
//
// De tabelstijl-controls van een documentstijlprofiel: randstijl, randkleur,
// zebrastrepen en -kleur, celopvulling en de accentlijn onder de koprij. Eigen
// part omdat settings_dialog_colors.dart er anders over het regelplafond heen
// groeit; dezelfde extension op _SettingsDialogState, dus de aanroep in het
// kleurenpaneel verandert niet.
part of '../settings_dialog.dart';

extension _SettingsTableStyle on _SettingsDialogState {
  Widget _tableStyleControls(AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.d('Tabelstijl'),
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        // Randstijl: lined / boxed / none
        DropdownButtonFormField<TableBorderStyle>(
          // Uitgeklapt, want "Omrand (volledig)" past niet naast het pijltje
          // wanneer het paneel smal staat — dan liep de regel over de rand.
          isExpanded: true,
          initialValue: _themeProfile.tableBorderStyle,
          decoration: InputDecoration(
            labelText: l10n.d('Randstijl'),
            border: const OutlineInputBorder(),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 8,
            ),
          ),
          items: [
            DropdownMenuItem(
              value: TableBorderStyle.lined,
              child: Text(l10n.d('Lijnen (horizontaal)')),
            ),
            DropdownMenuItem(
              value: TableBorderStyle.boxed,
              child: Text(l10n.d('Omrand (volledig)')),
            ),
            DropdownMenuItem(
              value: TableBorderStyle.none,
              child: Text(l10n.d('Geen randen')),
            ),
          ],
          onChanged: (v) {
            if (v != null) {
              _rebuild(() {
                _themeProfile = _themeProfile.copyWith(tableBorderStyle: v);
                _profileTouched = true;
              });
            }
          },
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          value: _themeProfile.tableZebraStriped,
          onChanged: (v) => _rebuild(() {
            _themeProfile = _themeProfile.copyWith(tableZebraStriped: v);
            _profileTouched = true;
          }),
          title: Text(
            l10n.d('Zebrastrepen (om en om)'),
            style: const TextStyle(fontSize: 13),
          ),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          value: _themeProfile.tableAccentHeaderBorder,
          onChanged: (v) => _rebuild(() {
            _themeProfile = _themeProfile.copyWith(tableAccentHeaderBorder: v);
            _profileTouched = true;
          }),
          title: Text(
            l10n.d('Accentlijn onder koprij'),
            style: const TextStyle(fontSize: 13),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          // Placeholder, geen interpolatie in de bronsleutel: een string mét
          // ingebakken waarde is per definitie onvertaalbaar — elke waarde zou
          // een eigen sleutel worden.
          l10n
              .d('Celopvulling: {px} px')
              .replaceAll(
                '{px}',
                _themeProfile.tableCellPaddingPx.toStringAsFixed(1),
              ),
          style: const TextStyle(fontSize: 12),
        ),
        Slider(
          value: _themeProfile.tableCellPaddingPx,
          min: 2.0,
          max: 20.0,
          divisions: 18,
          onChanged: (v) => _rebuild(() {
            _themeProfile = _themeProfile.copyWith(tableCellPaddingPx: v);
            _profileTouched = true;
          }),
        ),
      ],
    );
  }
}
