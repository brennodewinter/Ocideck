import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/marp_style.dart';
import '../../models/slide.dart';
import '../../state/deck_provider.dart';
import '_editor_field.dart';

/// Decoratieve achtergrond, onafhankelijk van de inhoudsafbeeldingen.
class SlideBackgroundEditor extends ConsumerWidget {
  final Slide slide;
  final ValueChanged<Slide> onUpdate;
  final String? projectPath;

  const SlideBackgroundEditor({
    super.key,
    required this.slide,
    required this.onUpdate,
    this.projectPath,
  });

  void _setPath(String path) => onUpdate(
    slide.copyWith(
      marpStyle: slide.marpStyle.copyWith(
        backgroundImage: path.isEmpty ? 'none' : 'url("$path")',
      ),
    ),
  );

  Future<void> _pick(BuildContext context, WidgetRef ref, bool paste) async {
    final service = ref.read(imageServiceProvider);
    final path = await (paste
        ? pasteImageWithFeedback(context, service, projectPath: projectPath)
        : pickImageWithFeedback(context, service, projectPath: projectPath));
    if (context.mounted && path != null) _setPath(path);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) => ImagePickerBar(
    imagePath: marpBackgroundAssetPath(slide.marpStyle.backgroundImage),
    searchPaths: [?projectPath],
    captionBasePath: projectPath,
    onPicked: (path, _) => _setPath(path),
    onBrowse: () => _pick(context, ref, false),
    onPaste: () => _pick(context, ref, true),
    onClear: slide.marpStyle.hasBackgroundImage ? () => _setPath('') : null,
    label: 'Geen achtergrondafbeelding',
  );
}
