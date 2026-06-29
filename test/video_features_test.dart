import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/models/video_source.dart';
import 'package:ocideck/services/file_service.dart';
import 'package:ocideck/services/image_service.dart';
import 'package:ocideck/services/markdown_service.dart';
import 'package:ocideck/state/deck_provider.dart';
import 'package:ocideck/utils/net_guard.dart';

DeckNotifier _notifier() {
  final md = MarkdownService();
  final file = FileService(md, ImageService(), () => const ThemeProfile());
  return DeckNotifier(md, file);
}

Slide _roundTrip(Slide slide) {
  final service = MarkdownService();
  final markdown = service.generateDeck(Deck(title: 'Demo', slides: [slide]));
  final deck = service.parseDeck(markdown);
  expect(deck, isNotNull, reason: 'parseDeck returned null for:\n$markdown');
  expect(deck!.slides, hasLength(1));
  return deck.slides.single;
}

void main() {
  group('VideoSource.parse', () {
    test('classifies local paths and empty', () {
      expect(VideoSource.parse('').kind, VideoSourceKind.none);
      expect(
        VideoSource.parse('media/clip.mp4').kind,
        VideoSourceKind.localFile,
      );
      expect(
        VideoSource.parse('/abs/path/clip.mov').kind,
        VideoSourceKind.localFile,
      );
    });

    test('classifies remote direct files', () {
      final s = VideoSource.parse('https://example.com/path/clip.mp4');
      expect(s.kind, VideoSourceKind.remoteFile);
      expect(s.isRemote, isTrue);
      expect(s.isEmbed, isFalse);
    });

    test('recognises YouTube in all common URL shapes', () {
      for (final url in [
        'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
        'https://youtu.be/dQw4w9WgXcQ',
        'https://www.youtube.com/embed/dQw4w9WgXcQ',
        'https://m.youtube.com/watch?v=dQw4w9WgXcQ',
        'https://www.youtube.com/shorts/dQw4w9WgXcQ',
      ]) {
        final s = VideoSource.parse(url);
        expect(s.kind, VideoSourceKind.youtube, reason: url);
        expect(s.embedId, 'dQw4w9WgXcQ', reason: url);
      }
    });

    test('recognises Vimeo URL shapes', () {
      for (final url in [
        'https://vimeo.com/123456789',
        'https://player.vimeo.com/video/123456789',
        'https://vimeo.com/channels/staffpicks/123456789',
      ]) {
        final s = VideoSource.parse(url);
        expect(s.kind, VideoSourceKind.vimeo, reason: url);
        expect(s.embedId, '123456789', reason: url);
      }
    });

    test('embedUri folds trim and autoplay into provider params', () {
      final yt = VideoSource.parse('https://youtu.be/dQw4w9WgXcQ');
      final uri = yt.embedUri(startMs: 12000, endMs: 40000, autoplay: true)!;
      expect(uri.host, 'www.youtube-nocookie.com');
      expect(uri.path, '/embed/dQw4w9WgXcQ');
      expect(uri.queryParameters['start'], '12');
      expect(uri.queryParameters['end'], '40');
      expect(uri.queryParameters['autoplay'], '1');

      final vimeo = VideoSource.parse('https://vimeo.com/123456789');
      final vUri = vimeo.embedUri(startMs: 5000, endMs: 0, autoplay: false)!;
      expect(vUri.host, 'player.vimeo.com');
      expect(vUri.fragment, 't=5s');
    });
  });

  group('NetGuard media URL gate', () {
    test('rejects non-web schemes and blocked hosts', () {
      expect(NetGuard.isAllowedMediaUrl('ftp://example.com/x.mp4'), isFalse);
      expect(NetGuard.isAllowedMediaUrl('file:///etc/passwd'), isFalse);
      expect(NetGuard.isAllowedMediaUrl('http://localhost/x.mp4'), isFalse);
      expect(NetGuard.isAllowedMediaUrl('http://127.0.0.1/x.mp4'), isFalse);
      expect(NetGuard.isAllowedMediaUrl('http://192.168.1.10/x.mp4'), isFalse);
      expect(NetGuard.isAllowedMediaUrl('http://169.254.169.254/x'), isFalse);
    });

    test('allows public https URLs', () {
      expect(
        NetGuard.isAllowedMediaUrl('https://example.com/clip.mp4'),
        isTrue,
      );
    });
  });

  group('markdown round-trip with trim and embeds', () {
    test('local video keeps the trim window via #t fragment', () {
      final out = _roundTrip(
        Slide.create(SlideType.video).copyWith(
          videoPath: 'media/clip.mp4',
          videoStartMs: 5000,
          videoEndMs: 12000,
          videoAutoplay: true,
        ),
      );
      expect(out.type, SlideType.video);
      expect(out.videoPath, 'media/clip.mp4');
      expect(out.videoStartMs, 5000);
      expect(out.videoEndMs, 12000);
      expect(out.videoAutoplay, isTrue);
    });

    test('remote direct video URL round-trips', () {
      final out = _roundTrip(
        Slide.create(
          SlideType.video,
        ).copyWith(videoPath: 'https://example.com/clip.mp4'),
      );
      expect(VideoSource.parse(out.videoPath).kind, VideoSourceKind.remoteFile);
      expect(out.videoPath, 'https://example.com/clip.mp4');
    });

    test('YouTube embed round-trips source and trim', () {
      final out = _roundTrip(
        Slide.create(SlideType.video).copyWith(
          videoPath: 'https://youtu.be/dQw4w9WgXcQ',
          videoStartMs: 10000,
          videoEndMs: 30000,
        ),
      );
      expect(out.type, SlideType.video);
      expect(out.videoPath, 'https://youtu.be/dQw4w9WgXcQ');
      expect(VideoSource.parse(out.videoPath).kind, VideoSourceKind.youtube);
      expect(out.videoStartMs, 10000);
      expect(out.videoEndMs, 30000);
    });

    test('Vimeo embed round-trips source', () {
      final out = _roundTrip(
        Slide.create(SlideType.video).copyWith(
          videoPath: 'https://vimeo.com/123456789',
          videoStartMs: 8000,
        ),
      );
      expect(VideoSource.parse(out.videoPath).kind, VideoSourceKind.vimeo);
      expect(out.videoPath, 'https://vimeo.com/123456789');
      expect(out.videoStartMs, 8000);
    });
  });

  group('DeckNotifier.splitVideoSlide', () {
    test('splits the segment and inserts a continuation slide', () {
      final n = _notifier();
      n.newDeck('Deck');
      n.addSlide(SlideType.video, afterIndex: 0);
      n.updateSlide(
        1,
        n.state.deck!.slides[1].copyWith(
          videoPath: 'media/clip.mp4',
          videoEndMs: 20000,
        ),
      );

      n.splitVideoSlide(1, 8000);

      final slides = n.state.deck!.slides;
      expect(slides, hasLength(3));
      final first = slides[1];
      final second = slides[2];
      expect(first.videoEndMs, 8000);
      expect(second.videoStartMs, 8000);
      expect(second.videoEndMs, 20000);
      expect(second.videoPath, 'media/clip.mp4');
      expect(second.id, isNot(first.id));
    });

    test('ignores a cut outside the current segment', () {
      final n = _notifier();
      n.newDeck('Deck');
      n.addSlide(SlideType.video, afterIndex: 0);
      n.updateSlide(
        1,
        n.state.deck!.slides[1].copyWith(
          videoPath: 'media/clip.mp4',
          videoStartMs: 5000,
          videoEndMs: 10000,
        ),
      );

      n.splitVideoSlide(1, 4000); // before start
      n.splitVideoSlide(1, 10000); // at/after end
      expect(n.state.deck!.slides, hasLength(2));
    });
  });
}
