import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/settings.dart' show ThemeProfile;
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/file_service.dart';
import 'package:ocideck/services/image_service.dart';
import 'package:ocideck/services/markdown_service.dart';
import 'package:ocideck/state/deck_provider.dart';
import 'package:path/path.dart' as p;

/// #1909: "Opgeslagen, maar het bestand kon niet opnieuw worden gelezen".
///
/// Een presentatie waarvan de enige dia nog leeg is, serialiseert naar front
/// matter zónder body — dat is precies wat OciDeck zelf wegschrijft. De
/// truncatie-controle in het open-pad las die vorm als "afgekapt bestand" en
/// weigerde hem, waarna het opslaan zijn eigen zojuist geschreven bestand niet
/// meer terug kon lezen en de gebruiker een schrikmelding kreeg over een
/// bestand waar niets mis mee was.
///
/// De maatlat hier is de invariant die daaronder ligt: **wat OciDeck schrijft,
/// moet OciDeck kunnen teruglezen** — op elk van de drie routes (schijf,
/// inhoud-uit-de-hand, en de opslaan-en-herlees-lus zelf).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  FileService service({String? saveTo}) => FileService(
    MarkdownService(),
    ImageService(),
    () => const ThemeProfile(),
    saveDestination: ({dialogTitle, fileName, initialDirectory}) async =>
        saveTo,
  );

  /// Een presentatie zoals die er staat vlak nadat je hem hebt aangemaakt en de
  /// dia nog niet hebt ingevuld.
  Deck emptyDeck() =>
      Deck(title: 'test2', slides: [Slide.create(SlideType.bullets)]);

  late Directory temp;
  setUp(() => temp = Directory.systemTemp.createTempSync('bug1909_'));
  tearDown(() {
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  });

  test('een lege presentatie opent weer van schijf', () async {
    final path = p.join(temp.path, 'test2.md');
    final file = service();
    await file.saveDeck(emptyDeck(), path);

    final reopened = await file.openDeckDetailed(path);

    expect(reopened.failure, isNull);
    expect(reopened.deck, isNotNull);
  });

  test('en ook via de inhoud-route (download, git, WebDAV)', () {
    final raw = MarkdownService().generateDeck(emptyDeck());

    final opened = service().openDeckFromContent(raw);

    expect(opened.failure, isNull);
    expect(opened.deck, isNotNull);
  });

  test('opslaan meldt geen fout over zijn eigen bestand', () async {
    final path = p.join(temp.path, 'test2.md');
    final md = MarkdownService();
    final notifier = DeckNotifier(md, service(saveTo: path));
    notifier.newDeck('test2', slides: [Slide.create(SlideType.bullets)]);

    final saved = await notifier.save();

    expect(saved, isTrue);
    expect(notifier.state.error, isNull, reason: 'de schrikmelding uit #1909');
    expect(notifier.state.filePath, path);
    expect(notifier.state.isDirty, isFalse);
  });

  test('een bestand dat geen presentatie is, wordt nog steeds geweigerd', () {
    final opened = service().openDeckFromContent('# Zomaar een notitie\n');

    expect(opened.failure, OpenFailure.notPresentation);
    expect(opened.deck, isNull);
  });
}
