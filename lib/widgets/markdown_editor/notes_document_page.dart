import 'package:material_ui/material_ui.dart';

import 'markdown_editor_theme.dart';

/// Het gecentreerde schrijfblad rond de visuele of broneditor.
class NotesDocumentPage extends StatelessWidget {
  const NotesDocumentPage({
    super.key,
    required this.theme,
    required this.child,
    this.maxWidth,
  });

  final MarkdownEditorTheme theme;
  final Widget child;
  final double? maxWidth;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(6, 12, 6, 6),
    child: Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth ?? double.infinity),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: theme.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: theme.border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.10),
                blurRadius: 12,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: child,
        ),
      ),
    ),
  );
}
