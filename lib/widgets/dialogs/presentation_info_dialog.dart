import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/deck.dart';

/// The editable general metadata of a presentation.
class PresentationInfo {
  final String author;
  final String organization;
  final String version;
  final String date;
  final String description;
  final String keywords;

  const PresentationInfo({
    required this.author,
    required this.organization,
    required this.version,
    required this.date,
    required this.description,
    required this.keywords,
  });
}

/// Dialog to view and edit a presentation's general metadata (author, version,
/// organization, date, description, keywords). These are stored in the
/// markdown front matter and are therefore also full-text searchable.
class PresentationInfoDialog extends StatefulWidget {
  final Deck deck;

  const PresentationInfoDialog({super.key, required this.deck});

  static Future<PresentationInfo?> show(BuildContext context, Deck deck) {
    return showDialog<PresentationInfo>(
      context: context,
      builder: (_) => PresentationInfoDialog(deck: deck),
    );
  }

  @override
  State<PresentationInfoDialog> createState() => _PresentationInfoDialogState();
}

class _PresentationInfoDialogState extends State<PresentationInfoDialog> {
  late final TextEditingController _author;
  late final TextEditingController _organization;
  late final TextEditingController _version;
  late final TextEditingController _date;
  late final TextEditingController _description;
  late final TextEditingController _keywords;

  @override
  void initState() {
    super.initState();
    _author = TextEditingController(text: widget.deck.author);
    _organization = TextEditingController(text: widget.deck.organization);
    _version = TextEditingController(text: widget.deck.version);
    _date = TextEditingController(text: widget.deck.date);
    _description = TextEditingController(text: widget.deck.description);
    _keywords = TextEditingController(text: widget.deck.keywords);
  }

  @override
  void dispose() {
    _author.dispose();
    _organization.dispose();
    _version.dispose();
    _date.dispose();
    _description.dispose();
    _keywords.dispose();
    super.dispose();
  }

  void _save() {
    Navigator.pop(
      context,
      PresentationInfo(
        author: _author.text.trim(),
        organization: _organization.text.trim(),
        version: _version.text.trim(),
        date: _date.text.trim(),
        description: _description.text.trim(),
        keywords: _keywords.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.pop(context),
      },
      child: AlertDialog(
        title: Row(
          children: const [
            Icon(Icons.info_outline, size: 20),
            SizedBox(width: 8),
            Text('Presentatie-eigenschappen'),
          ],
        ),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.deck.title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF64748B),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _field(_author, 'Auteur', 'Bijv. Jan Jansen'),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 120,
                      child: _field(_version, 'Versie', 'Bijv. 1.0'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _field(
                        _organization,
                        'Organisatie',
                        'Bijv. Vigilis',
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 120,
                      child: _field(_date, 'Datum', 'Bijv. 2026-05-30'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _field(
                  _description,
                  'Beschrijving',
                  'Korte omschrijving van de presentatie',
                  maxLines: 3,
                ),
                const SizedBox(height: 12),
                _field(
                  _keywords,
                  'Trefwoorden',
                  'Komma-gescheiden, bijv. kwartaal, cijfers, 2026',
                ),
                const SizedBox(height: 8),
                const Text(
                  'Deze gegevens worden in de markdown opgeslagen en zijn '
                  'doorzoekbaar bij het openen.',
                  style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuleren'),
          ),
          ElevatedButton(onPressed: _save, child: const Text('Opslaan')),
        ],
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label,
    String hint, {
    int maxLines = 1,
  }) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        isDense: true,
        border: const OutlineInputBorder(),
      ),
    );
  }
}
