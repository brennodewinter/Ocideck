import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/models/video_source.dart';
import 'package:ocideck/services/media/youtube_reference.dart';

void main() {
  test(
    'one parser recognises canonical, short, embed, mobile and live URLs',
    () {
      for (final url in [
        'https://www.youtube.com/watch?v=M7lc1UVf-VE&list=other&index=3',
        'https://youtu.be/M7lc1UVf-VE?si=tracking',
        'https://m.youtube.com/watch?v=M7lc1UVf-VE',
        'https://www.youtube-nocookie.com/embed/M7lc1UVf-VE',
        'https://www.youtube.com/shorts/M7lc1UVf-VE',
        'https://www.youtube.com/live/M7lc1UVf-VE',
      ]) {
        expect(VideoSource.parse(url).kind, VideoSourceKind.youtube);
        final result = YoutubeReference.parse(url)!;
        expect(result.videoId, 'M7lc1UVf-VE');
        expect(
          result.canonicalUrl.toString(),
          'https://www.youtube.com/watch?v=M7lc1UVf-VE',
        );
      }
    },
  );

  test('wrong hosts, credentials and malformed IDs cannot become jobs', () {
    for (final url in [
      'https://youtube.com.evil.test/watch?v=M7lc1UVf-VE',
      'https://evil.test/youtube.com/watch?v=M7lc1UVf-VE',
      'https://user:secret@youtube.com/watch?v=M7lc1UVf-VE',
      'https://youtube.com/watch?v=short1',
      'https://youtube.com/watch?v=toolong1234567890',
      'https://youtube.com/playlist?list=M7lc1UVf-VE',
      'file:///youtube.com/watch?v=M7lc1UVf-VE',
      'https://youtube.com/watch',
      'https://youtube.com/watch?v=%FF',
    ]) {
      expect(YoutubeReference.parse(url), isNull, reason: url);
    }
  });

  test(
    'time hints remain proposals and links retain the original video clock',
    () {
      final hinted = YoutubeReference.parse(
        'https://youtu.be/M7lc1UVf-VE?t=1h2m3s&end=4000',
      )!;
      expect(hinted.proposedStartMs, 3723000);
      expect(hinted.proposedEndMs, 4000000);
      expect(hinted.canonicalUrl.queryParameters, {'v': 'M7lc1UVf-VE'});
      expect(hinted.sourceLink(const Duration(seconds: 3800)).queryParameters, {
        'v': 'M7lc1UVf-VE',
        't': '3800',
      });
      expect(
        YoutubeReference.parse(
          'https://youtu.be/M7lc1UVf-VE#t=12',
        )!.proposedStartMs,
        12000,
      );
      expect(
        YoutubeReference.parse('https://youtu.be/M7lc1UVf-VE?start=20&end=10'),
        isNull,
      );
      expect(
        YoutubeReference.parse(
          'https://youtu.be/M7lc1UVf-VE?t=20',
          startMs: 0,
        )!.proposedStartMs,
        0,
      );
    },
  );

  test(
    'deck discovery retains slide references and distinguishes fragments',
    () {
      final slides = [
        Slide(
          id: 'a',
          type: SlideType.video,
          videoPath: 'https://youtu.be/M7lc1UVf-VE',
        ),
        Slide(
          id: 'b',
          type: SlideType.bullets,
          customMarkdown:
              '[First](https://youtube.com/watch?v=M7lc1UVf-VE&list=x) '
              '[Again](https://youtu.be/M7lc1UVf-VE) '
              '[Other](https://youtu.be/aqz-KE-bpKQ)',
        ),
        Slide(
          id: 'c',
          type: SlideType.video,
          videoPath: 'https://youtu.be/M7lc1UVf-VE',
          videoStartMs: 10000,
          videoEndMs: 20000,
        ),
        Slide(
          id: 'd',
          type: SlideType.bullets,
          bullets: ['<https://youtu.be/M7lc1UVf-VE?t=10&end=20>'],
        ),
      ];
      final found = findDeckYoutubeReferences(slides);
      expect(found, hasLength(3));
      expect(found[0].slideNumbers, [1, 2]);
      expect(found[1].reference.videoId, 'aqz-KE-bpKQ');
      expect(found[2].slideNumbers, [3, 4]);
      expect(found[2].reference.proposedStartMs, 10000);
      expect(slides[2].videoStartMs, 10000);
    },
  );
}
