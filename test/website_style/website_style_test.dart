import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/feeds/feed_fetch.dart';
import 'package:ocideck/services/website_style/website_style_proposal.dart';
import 'package:ocideck/services/website_style/website_style_source.dart';

void main() {
  test('publieke website-invoer wordt een HTTPS-URL zonder fragment', () {
    expect(
      websiteStyleUrl(' example.org/over#team ')?.toString(),
      'https://example.org/over',
    );
    expect(websiteStyleUrl('https://user:secret@example.org'), isNull);
    expect(websiteStyleUrl('http://example.org'), isNull);
    expect(websiteStyleUrl('https://example.org:8443'), isNull);
    expect(websiteStyleUrl('file:///somewhere'), isNull);
  });

  test(
    'snapshot behoudt CSS-volgorde en maakt HTML en lokale verwijzingen inert',
    () async {
      final origin = Uri.parse('https://example.org/page');
      final resources = {
        '/page': '''
        <base href="/static/"><link rel="stylesheet" href="main.css">
        <style>h1 { color: #123456 }</style>
        <script>window.shouldNeverRun = true;</script>
        <main onload="window.shouldNeverRun = true">
          <h1>Onze huisstijl</h1><p>Lees ons nieuws.</p>
          <img class="logo" src="logo.png" onerror="window.shouldNeverRun = true">
          <iframe src="file:///private.txt"></iframe>
        </main>''',
        '/static/main.css': '''
        @import 'colors.css';
        .hero { background-image: url('../hero.jpg'); }
        p { color: #222222; } /* </style><script>bad</script> */
        ''',
        '/static/colors.css': ':root { --brand-primary: #3658A5; }',
      };
      final requests = <String>[];
      final snapshot = await loadWebsiteStyleSnapshot(
        origin,
        fetch: (url, {required maxBytes}) async {
          requests.add(url.path);
          return FeedFetchResult.ok(
            statusCode: 200,
            finalUrl: url,
            bytes: Uint8List.fromList(utf8.encode(resources[url.path]!)),
          );
        },
      );

      expect(requests, ['/page', '/static/main.css', '/static/colors.css']);
      expect(snapshot.incompleteStylesheets, isFalse);
      expect(snapshot.html, contains("default-src 'none'"));
      expect(snapshot.html, contains('--brand-primary: #3658A5'));
      expect(snapshot.html, contains('https://example.org/hero.jpg'));
      expect(
        snapshot.html,
        contains('data-ocideck-image="https://example.org/static/logo.png"'),
      );
      expect(snapshot.html, isNot(contains('shouldNeverRun')));
      expect(snapshot.html, isNot(contains('file:///private.txt')));
      expect(snapshot.html, isNot(contains('</style><script>')));
      expect(
        snapshot.html.indexOf('p { color: #222222'),
        lessThan(snapshot.html.indexOf('h1 { color: #123456')),
      );
    },
  );

  test(
    'profiel bewaart de actieve kleuren en maakt lettertypevervanging expliciet',
    () {
      final response = jsonEncode(
        jsonEncode({
          'hasText': true,
          'accent': {
            'value': '#4472c4',
            'token': '--brand-primary',
            'roles': ['buttons', 'links'],
          },
          'textColor': '#222222',
          'titleTextColor': '#ffffff',
          'titleBackgroundColor': '#162342',
          'backgroundColor': '#fffefd',
          'fontFamily': '"Brand Sans", Georgia, Arial, sans-serif',
          'titleImage': 'https://cdn.example.org/cover.jpg',
          'logo': 'file:///private.png',
        }),
      );
      final proposal = WebsiteStyleProposal.fromProbe(
        response,
        Uri.parse('https://example.org'),
      );
      expect(proposal.profile.accentColor, '#4472C4');
      expect(proposal.profile.titleTextColor, '#FFFFFF');
      expect(proposal.profile.titleBackgroundColor, '#162342');
      expect(proposal.profile.slideBackgroundColor, '#FFFEFD');
      expect(proposal.profile.fontFamily, 'Georgia');
      expect(proposal.profile.preferredFontFamily, 'Brand Sans');
      expect(proposal.accentToken, '--brand-primary');
      expect(proposal.accentRoles, {'buttons', 'links'});
      expect(proposal.images, {
        WebsiteStyleImage.title: Uri.parse('https://cdn.example.org/cover.jpg'),
      });
    },
  );
}
