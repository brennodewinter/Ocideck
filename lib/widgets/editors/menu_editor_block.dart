// Part of the menu_editor library — see menu_editor.dart.
// Split out for navigability (de rij van één keuzeblok); all imports live in the
// main library file.
part of 'menu_editor.dart';

/// Eén keuzeblok in de editor: label, uitleg, doeldia, afbeelding en — als het
/// menu categorieën heeft — in welke categorie het blok staat.
///
/// Zelf zonder toestand: alle wijzigingen gaan als terugroep naar de editor, die
/// als enige de bullets van de dia schrijft.
class _MenuBlockRow extends StatelessWidget {
  final MenuBlock block;
  final TextEditingController label;
  final TextEditingController description;
  final List<MenuCategory> categories;
  final int categoryIndex;
  final List<Slide> slides;
  final int menuIndex;
  final ValueChanged<String> onLabel;
  final ValueChanged<String> onDescription;
  final ValueChanged<int?> onTarget;
  final ValueChanged<int> onCategory;
  final VoidCallback onPickImage;
  final VoidCallback onClearImage;
  final VoidCallback onRemove;

  const _MenuBlockRow({
    required this.block,
    required this.label,
    required this.description,
    required this.categories,
    required this.categoryIndex,
    required this.slides,
    required this.menuIndex,
    required this.onLabel,
    required this.onDescription,
    required this.onTarget,
    required this.onCategory,
    required this.onPickImage,
    required this.onClearImage,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppTheme.paper,
        border: Border.all(color: AppTheme.slate200),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: label,
                  onChanged: onLabel,
                  style: const TextStyle(fontSize: 13),
                  decoration: InputDecoration(
                    isDense: true,
                    labelText: l10n.d('Label'),
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
              IconButton(
                tooltip: l10n.d('Blok verwijderen'),
                icon: const Icon(Icons.delete_outline, size: 18),
                onPressed: onRemove,
              ),
            ],
          ),
          const SizedBox(height: 6),
          TextField(
            controller: description,
            onChanged: onDescription,
            style: const TextStyle(fontSize: 13),
            decoration: InputDecoration(
              isDense: true,
              labelText: l10n.d('Uitleg'),
              // Bewust géén `hintText`: met allebei ziet een leeg veld er anders
              // uit dan een gevuld — grotere letter, geen zwevend opschrift — en
              // dan lijken het twee soorten besturingselement (#1162,
              // beeldkeuring). De uitleg staat in de hulptekst bij het diatype.
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 6),
          _targetRow(context, l10n),
          const SizedBox(height: 6),
          _imageRow(context, l10n),
          if (categories.length > 1) ...[
            const SizedBox(height: 6),
            _categoryRow(context, l10n),
          ],
        ],
      ),
    );
  }

  Widget _targetRow(BuildContext context, AppLocalizations l10n) {
    // Welke dia is nu het doel (de index in het deck), of -1 bij geen sprong.
    final targetIndex = block.hasTarget
        ? slides.indexWhere((s) => s.anchor == block.targetAnchor)
        : -1;
    return _labelled(
      icon: Icons.alt_route,
      text: l10n.d('Springt naar'),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int?>(
          isDense: true,
          isExpanded: true,
          value: targetIndex < 0 ? null : targetIndex,
          style: TextStyle(fontSize: 12, color: AppTheme.ink),
          items: [
            DropdownMenuItem(value: null, child: Text(l10n.d('Geen sprong'))),
            for (var s = 0; s < slides.length; s++)
              if (s != menuIndex)
                DropdownMenuItem(
                  value: s,
                  child: Text(
                    '${s + 1}. ${_slideLabel(l10n, slides[s])}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
          ],
          onChanged: onTarget,
        ),
      ),
    );
  }

  Widget _categoryRow(BuildContext context, AppLocalizations l10n) => _labelled(
    icon: Icons.folder_outlined,
    text: l10n.d('Categorie'),
    child: DropdownButtonHideUnderline(
      child: DropdownButton<int>(
        isDense: true,
        isExpanded: true,
        value: categoryIndex,
        style: TextStyle(fontSize: 12, color: AppTheme.ink),
        items: [
          for (var c = 0; c < categories.length; c++)
            DropdownMenuItem(
              value: c,
              child: Text(
                categories[c].isNamed
                    ? categories[c].label
                    : l10n.d('Algemeen'),
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
        onChanged: (to) => to == null ? null : onCategory(to),
      ),
    ),
  );

  Widget _imageRow(BuildContext context, AppLocalizations l10n) => Row(
    children: [
      Icon(Icons.image_outlined, size: 15, color: AppTheme.slate500),
      const SizedBox(width: 6),
      Expanded(
        child: Text(
          block.hasImage
              ? block.imagePath.split(RegExp(r'[\\/]')).last
              : l10n.d('Geen afbeelding'),
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 12,
            color: block.hasImage ? AppTheme.slate600 : AppTheme.slate400,
          ),
        ),
      ),
      TextButton(
        onPressed: onPickImage,
        child: Text(
          block.hasImage ? l10n.d('Wijzigen') : l10n.d('Kiezen'),
          style: const TextStyle(fontSize: 12),
        ),
      ),
      if (block.hasImage)
        IconButton(
          tooltip: l10n.d('Afbeelding verwijderen'),
          icon: const Icon(Icons.clear, size: 16),
          onPressed: onClearImage,
        ),
    ],
  );

  /// Een regel met pictogram, opschrift en een keuzeveld erachter — de vorm die
  /// "springt naar" en "categorie" delen.
  Widget _labelled({
    required IconData icon,
    required String text,
    required Widget child,
  }) => Row(
    children: [
      Icon(icon, size: 15, color: AppTheme.slate500),
      const SizedBox(width: 6),
      Text(text, style: TextStyle(fontSize: 12, color: AppTheme.slate600)),
      const SizedBox(width: 8),
      Expanded(child: child),
    ],
  );

  String _slideLabel(AppLocalizations l10n, Slide s) {
    final title = stripInlineMarkdown(s.title).trim();
    return title.isEmpty ? l10n.d('Dia') : title;
  }
}
