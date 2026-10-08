import 'package:material_ui/material_ui.dart';
import '../../l10n/app_localizations.dart';

/// Eén optie in een [ChoicePicker]: de waarde die terugkomt plus wat er op de
/// rij staat.
typedef PickerOption<T> = ({T value, IconData icon, String label});

/// De tweede stap achter een gegroepeerd menu-item: kies één optie, dan pas
/// volgt de afhandelroute met haar eigen vragen.
///
/// Zelfde vorm als [StorageConnectionPicker]: een titel, een rij met
/// pictogram en label, en een annuleerknop. De lijst scrolt wanneer hij niet
/// past, zodat lange vertalingen en smalle vensters hem niet afknippen.
class ChoicePicker<T> extends StatelessWidget {
  const ChoicePicker({super.key, required this.title, required this.options});

  final String title;
  final List<PickerOption<T>> options;

  /// Toon de keuze en lever de aangeklikte waarde; `null` bij annuleren en bij
  /// een lege lijst (dan is er niets te kiezen).
  static Future<T?> show<T>(
    BuildContext context, {
    required String title,
    required List<PickerOption<T>> options,
  }) {
    if (options.isEmpty) return Future<T?>.value();
    return showDialog<T>(
      context: context,
      builder: (_) => ChoicePicker<T>(title: title, options: options),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 420,
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final option in options)
              ListTile(
                leading: Icon(option.icon),
                title: Text(option.label),
                onTap: () => Navigator.of(context).pop(option.value),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.t('cancel')),
        ),
      ],
    );
  }
}
