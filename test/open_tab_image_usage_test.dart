import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/markdown_document.dart';
import 'package:ocideck/state/document_provider.dart';
import 'package:ocideck/state/open_tab_image_usage.dart';
import 'package:ocideck/state/tabs_provider.dart';
import 'package:path/path.dart' as p;

void main() {
  test(
    'open document references follow a deduplicated image and can undo',
    () async {
      final project = p.join('tmp', 'project');
      final oldPath = p.join(project, 'images', 'copy.png');
      final keeper = p.join(project, 'images', 'keeper.png');
      final notifier = DocumentNotifier()
        ..loadDocument(
          MarkdownDocument.parse(
            '---\ntitle: Report\n---\n![Alt](images/copy.png)',
          ),
          filePath: p.join(project, 'report.md'),
          projectPath: project,
        );
      addTearDown(notifier.dispose);
      final tab = TabInfo(
        id: 1,
        recoveryId: 'document',
        content: DocumentTabContent(notifier),
      );

      expect(openTabImageUsages([tab], oldPath), ['report']);
      expect(openTabMarkdownFiles([tab]), [p.join(project, 'report.md')]);

      await replaceOpenTabImageUsages([tab], oldPath, keeper);

      expect(
        notifier.currentState.document!.source,
        '---\ntitle: Report\n---\n![Alt](images/keeper.png)',
      );
      expect(notifier.currentState.isDirty, isTrue);
      notifier.undo();
      expect(notifier.currentState.document!.body, '![Alt](images/copy.png)');
    },
  );
}
