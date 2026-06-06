import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/slide.dart';
import '../../theme/app_theme.dart';
import '../../l10n/app_localizations.dart';

class AddSlideDialog extends StatelessWidget {
  const AddSlideDialog({super.key});

  static Future<SlideType?> show(BuildContext context) {
    return showDialog<SlideType>(
      context: context,
      builder: (_) => const AddSlideDialog(),
    );
  }

  static const _types = [
    (SlideType.title, Icons.title, 'Titelpagina'),
    (SlideType.section, Icons.bookmark_outline, 'Tussentitel'),
    (SlideType.bullets, Icons.format_list_bulleted, 'Alleen Bullets'),
    (SlideType.twoBullets, Icons.view_column_outlined, 'Twee Bulletkolommen'),
    (
      SlideType.bulletsImage,
      Icons.view_agenda_outlined,
      'Bullets + Afbeelding',
    ),
    (SlideType.twoImages, Icons.auto_stories_outlined, 'Twee Afbeeldingen'),
    (SlideType.image, Icons.image_outlined, 'Grote Afbeelding'),
    (SlideType.video, Icons.movie_outlined, 'Video'),
    (SlideType.quote, Icons.format_quote_outlined, 'Quote'),
    (SlideType.table, Icons.table_chart_outlined, 'Tabel'),
    (SlideType.code, Icons.terminal, 'Broncode'),
    (SlideType.freeMarkdown, Icons.code, 'Vrije Markdown'),
  ];

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.pop(context),
      },
      child: Focus(
        autofocus: true,
        child: AlertDialog(
          title: Text(l10n.d('Slide type kiezen')),
          content: SizedBox(
            width: 400,
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: _types.map((entry) {
                final (type, icon, label) = entry;
                return _TypeCard(
                  icon: icon,
                  label: l10n.d(label),
                  onTap: () => Navigator.pop(context, type),
                );
              }).toList(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(l10n.t('cancel')),
            ),
          ],
        ),
      ),
    );
  }
}

class _TypeCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _TypeCard({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 110,
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFFCBD5E1)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 28, color: AppTheme.navy),
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}
