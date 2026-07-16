import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/git_settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/markdown_service.dart';

const _sha = '3f9a1c8e5b2d4f6a8c0e1d3b5a7f9e2c4d6b8a0f2e4c6d8b0a2f4e6c8d0b2a4f';

void main() {
  group('GitRepoLayout.assetRef', () {
    test('builds the pool reference', () {
      expect(GitRepoLayout.assetRef(_sha, 'png'), 'repo:assets/$_sha.png');
    });

    test('normalises case and a leading dot on the extension', () {
      expect(
        GitRepoLayout.assetRef(_sha.toUpperCase(), '.PNG'),
        GitRepoLayout.assetRef(_sha, 'png'),
      );
    });

    test('refuses anything that is not a sha-256', () {
      for (final hash in [
        '',
        'abc',
        '${_sha}0', // te lang
        _sha.substring(1), // te kort
        _sha.replaceFirst('3', 'g'), // geen hex
        '../etc/passwd',
      ]) {
        expect(GitRepoLayout.assetRef(hash, 'png'), isNull, reason: hash);
      }
    });

    test('refuses an extension that would not be a path segment', () {
      for (final ext in ['', '.', '..', 'p/g', 'p.g', 'toolongextension']) {
        expect(GitRepoLayout.assetRef(_sha, ext), isNull, reason: ext);
      }
    });

    test('trims stray whitespace, like the other name guards do', () {
      expect(
        GitRepoLayout.assetRef('  $_sha  ', ' png '),
        GitRepoLayout.assetRef(_sha, 'png'),
      );
    });
  });

  group('GitRepoLayout.assetPathOf', () {
    test('unwraps the scheme to a repo path', () {
      expect(
        GitRepoLayout.assetPathOf('repo:assets/$_sha.png'),
        'assets/$_sha.png',
      );
    });

    test('round-trips assetRef', () {
      final ref = GitRepoLayout.assetRef(_sha, 'webp')!;
      expect(GitRepoLayout.assetPathOf(ref), 'assets/$_sha.webp');
    });

    test('is null for the other schemes and for a plain path', () {
      for (final ref in [
        'mem:abc-123',
        'asset:assets/images/logo.png',
        'images/foto.png',
        '',
      ]) {
        expect(GitRepoLayout.assetPathOf(ref), isNull, reason: ref);
      }
    });

    test('refuses a reference that climbs out of the pool', () {
      // The guard §6.1 asks for: a repo: target must stay under assets/.
      for (final ref in [
        'repo:assets/../decks/kwartaalcijfers/deck.md',
        'repo:../assets/x.png',
        'repo:decks/kwartaalcijfers/deck.md',
        'repo:/etc/passwd',
        'repo:assets/../../etc/passwd',
        'repo:',
        'repo:assets',
      ]) {
        expect(GitRepoLayout.assetPathOf(ref), isNull, reason: ref);
      }
    });

    test('a traversal that lands back inside the pool is allowed', () {
      expect(
        GitRepoLayout.assetPathOf('repo:assets/sub/../$_sha.png'),
        'assets/$_sha.png',
      );
    });

    test('isRepoAsset only claims its own scheme', () {
      expect(GitRepoLayout.isRepoAsset('repo:assets/x.png'), isTrue);
      expect(GitRepoLayout.isRepoAsset('mem:x'), isFalse);
      expect(GitRepoLayout.isRepoAsset('repository/x.png'), isFalse);
    });
  });

  group('repo: survives the markdown round-trip', () {
    // Load-bearing: the whole asset pool assumes a repo: reference written into
    // deck.md comes back byte-identical. markdown_service needs no knowledge of
    // the scheme — a path is opaque to it — but nothing *keeps* that true, so
    // this pins it. If a future serialiser change starts touching paths, this
    // fails here rather than silently turning every pooled image into a broken
    // link.
    Slide imageSlide(String path, {String caption = ''}) => Slide(
      id: 's1',
      type: SlideType.image,
      title: 'Slide',
      imagePath: path,
      imageCaption: caption,
    );

    String? roundTrip(Slide slide) {
      final svc = MarkdownService();
      final markdown = svc.generateDeck(Deck(title: 'T', slides: [slide]));
      return svc.parseDeck(markdown)?.slides.first.imagePath;
    }

    test('a pool reference comes back unchanged', () {
      final ref = GitRepoLayout.assetRef(_sha, 'png')!;
      expect(roundTrip(imageSlide(ref)), ref);
    });

    test('and does so beside a caption carrying the pipe sentinel', () {
      // The caption escaping is one of the edge cases the design flagged; if it
      // ever bled into the path, this catches it.
      final ref = GitRepoLayout.assetRef(_sha, 'jpg')!;
      final slide = imageSlide(ref, caption: 'Kwartaal | cijfers');
      final svc = MarkdownService();
      final markdown = svc.generateDeck(Deck(title: 'T', slides: [slide]));
      final back = svc.parseDeck(markdown)!.slides.first;

      expect(back.imagePath, ref);
      expect(back.imageCaption, 'Kwartaal | cijfers');
    });

    test('the reference appears literally in the markdown', () {
      final ref = GitRepoLayout.assetRef(_sha, 'png')!;
      final markdown = MarkdownService().generateDeck(
        Deck(title: 'T', slides: [imageSlide(ref)]),
      );
      expect(markdown, contains(ref));
    });

    test('the existing schemes still round-trip beside it', () {
      for (final path in ['images/foto.png', 'mem:abc-123']) {
        expect(roundTrip(imageSlide(path)), path, reason: path);
      }
    });
  });
}
