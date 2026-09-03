import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/services/marp_html_service.dart';

/// Exercises the cockpit-instrument SVG renderer that backs the static HTML
/// export (marp_html/marp_html_service_cockpit.dart). The public entry point is the
/// static [MarpHtmlService.renderCockpitBlocks], which parses a ```cockpit
/// fenced JSON block and replaces it with an inline `<svg>` — reaching every
/// private meter renderer without a WebView or any bundled asset.
void main() {
  /// Wrap a cockpit spec map in the fenced block the renderer looks for.
  String block(Map<String, dynamic> spec) =>
      '```cockpit\n${jsonEncode(spec)}\n```';

  String renderMeters(
    List<Map<String, dynamic>> meters, {
    ThemeProfile? theme,
    CockpitColorScheme scheme = CockpitColorScheme.standard,
  }) => MarpHtmlService.renderCockpitBlocks(
    block({'meters': meters}),
    theme: theme,
    scheme: scheme,
  );

  const customScheme = CockpitColorScheme(
    name: 'Test',
    good: '#101010',
    warning: '#202020',
    critical: '#303030',
    cold: '#404040',
    sky: '#505050',
    ground: '#606060',
  );

  test('empty meters fall back to the sample preset', () {
    // CockpitSpec.parse of `{}` yields no meters, so _cockpitSvg substitutes
    // the built-in preset (four instruments).
    final svg = MarpHtmlService.renderCockpitBlocks('```cockpit\n{}\n```');
    expect(svg, contains('<div class="cockpit">'));
    expect(svg, contains('<svg'));
    expect(svg, contains('</svg>'));
    // De hardgecodeerde Engelse header is uit de export gehaald (stond niet in
    // de app-render); de export volgt nu het dia-thema.
    expect(svg, isNot(contains('COCKPIT VIEW')));
    // Preset carries a "Capacity used" speedometer — domain-neutral since
    // #646, because this fallback also reaches the exported HTML.
    expect(svg, contains('Capacity used'));
  });

  test('arc gauge renders both zone orderings (green-low and green-high)', () {
    // Speedometer: redFrom (70) >= greenFrom (0) → green-low "else" branch.
    final speed = renderMeters([
      {
        'type': 'speedometer',
        'label': 'Speed',
        'unit': '%',
        'min': 0,
        'max': 100,
        'greenFrom': 0,
        'greenTo': 40,
        'redFrom': 70,
        'value': 78,
      },
    ], scheme: customScheme);
    expect(speed, contains('Speed'));
    // Getal en korte eenheid staan als aparte tekstknopen in het venster.
    expect(speed, contains('>78<tspan'));
    expect(speed, contains('>%</tspan>'));
    expect(speed, contains('#101010')); // good zone
    expect(speed, contains('#303030')); // critical zone
    // Schaalcijfers op volle dekking: met 0,85 alfa bleven ze in de lichte
    // export op 4,05:1, onder AA.
    expect(speed, isNot(contains('fill-opacity=".85"')));

    // Voltmeter: redFrom (50) < greenFrom (75) → green-high "if" branch.
    final volt = renderMeters([
      {
        'type': 'voltmeter',
        'label': 'Volt',
        'unit': 'V',
        'min': 0,
        'max': 100,
        'greenFrom': 75,
        'greenTo': 100,
        'redFrom': 50,
        'value': 92,
      },
    ], scheme: customScheme);
    expect(volt, contains('>92<tspan'));
    expect(volt, contains('>V</tspan>'));
    expect(volt, contains('#101010')); // good zone
    expect(volt, contains('#303030')); // critical zone

    // Altimeter is a third arc-gauge type.
    final alt = renderMeters([
      {
        'type': 'altimeter',
        'label': 'Alt',
        'unit': 'ft',
        'min': 0,
        'max': 5000,
        'greenFrom': 0,
        'greenTo': 2000,
        'redFrom': 4000,
        'value': 3200,
      },
    ]);
    expect(alt, contains('>3200<tspan'));
    expect(alt, contains('>ft</tspan>'));
    expect(alt, contains('<svg'));
  });

  group('thermometer colour branches', () {
    Map<String, dynamic> thermo(double value) => {
      'type': 'thermometer',
      'label': 'Heat',
      'unit': '/10',
      'min': 0,
      'max': 100,
      'greenFrom': 20,
      'greenTo': 60,
      'redFrom': 80,
      'value': value,
    };

    test('value >= redFrom uses the critical colour', () {
      final svg = renderMeters([thermo(90)], scheme: customScheme);
      expect(svg, contains('#303030'));
    });

    test('value in the warning band uses the warning colour', () {
      final svg = renderMeters([thermo(70)], scheme: customScheme);
      expect(svg, contains('#202020'));
    });

    test('value below greenFrom uses the cold colour', () {
      final svg = renderMeters([thermo(10)], scheme: customScheme);
      expect(svg, contains('#404040'));
    });

    test('value in the green band uses the good colour', () {
      final svg = renderMeters([thermo(40)], scheme: customScheme);
      expect(svg, contains('#101010'));
    });
  });

  test('climb/descent shows a + prefix for a positive value', () {
    final up = renderMeters([
      {
        'type': 'climbDescent',
        'label': 'Trend',
        'unit': '',
        'min': -20,
        'max': 20,
        'value': 12,
      },
    ]);
    expect(up, contains('+12'));

    final down = renderMeters([
      {
        'type': 'climbDescent',
        'label': 'Trend',
        'unit': '',
        'min': -20,
        'max': 20,
        'value': -8,
      },
    ]);
    // No leading + for a non-positive value; a real minus sign (U+2212)
    // beside the plus, not a hyphen.
    expect(down, contains('\u22128'));
    expect(down, isNot(contains('-8')));
  });

  test('cells keep their translate when the power-on animation scales', () {
    // De cockpitPowerOn-keyframes zetten `transform:scale()` als CSS op
    // `.cockpit-meter`; een transform-attribuut op datzelfde element werd
    // overschreven en alle meters vielen op cel 0. De verplaatsing staat
    // daarom op een eigen buitenste <g>.
    final svg = renderMeters([
      {'type': 'speedometer', 'label': 'A', 'value': 10},
      {'type': 'speedometer', 'label': 'B', 'value': 20},
    ]);
    final translated = RegExp(
      r'<g transform="translate\([^"]+\)"><g class="cockpit-meter"',
    );
    expect(translated.allMatches(svg), hasLength(2));
    expect(
      svg,
      isNot(
        contains('class="cockpit-meter" style="--meter-index:0" transform='),
      ),
    );
  });

  test('horizon renders sky/ground bands and a clip path', () {
    final svg = renderMeters([
      {'type': 'horizon', 'label': 'Attitude', 'pitch': 20, 'bank': 15},
    ], scheme: customScheme);
    expect(svg, contains('#505050')); // sky
    expect(svg, contains('#606060')); // ground
    // Het clip-id draagt een suffix per SVG: meerdere cockpit-dia's delen
    // één HTML-document en één id-namespace.
    expect(svg, contains('cockpit-horizon-0-'));
    // Pitch en bank staan als twee regels in het uitleesvenster, niet meer
    // op de grond van de horizon.
    expect(svg, contains('>P 20<'));
    expect(svg, contains('>B 15<'));
  });

  test('horizon clamps extreme pitch and bank', () {
    // pitch 60 → clamped to 45, bank -80 → clamped to -60 (in normalized()).
    final svg = renderMeters([
      {'type': 'horizon', 'label': 'Att', 'pitch': 60, 'bank': -80},
    ]);
    expect(svg, contains('>P 45<'));
    expect(svg, contains('>B \u221260<'));
  });

  test('heading renders compass, actual/target and a marker label', () {
    final svg = renderMeters([
      {
        'type': 'heading',
        'label': 'HDG',
        'value': 90,
        'heading': 180,
        'markerLabel': 'RWY27',
      },
    ]);
    expect(svg, contains('ACT 090'));
    expect(svg, contains('TGT 180'));
    expect(svg, contains('RWY27'));
    // Compass rose letters.
    for (final letter in ['N', 'E', 'S', 'W']) {
      expect(svg, contains('>$letter<'));
    }
  });

  test('heading without a marker label omits the marker text', () {
    final svg = renderMeters([
      {'type': 'heading', 'label': 'HDG', 'value': 0, 'heading': 0},
    ]);
    expect(svg, contains('ACT 000'));
    expect(svg, isNot(contains('RWY27')));
  });

  test('an empty meter label falls back to a numbered placeholder', () {
    final svg = renderMeters([
      {'type': 'speedometer', 'label': '', 'value': 30},
    ]);
    expect(svg, contains('Meter 1'));
  });

  test('theme accent colour is threaded into the gauge, default otherwise', () {
    // Authentiek draagt het accent op de kompasmarker, net als de app; de
    // naald is inkt en het horizonsymbool is wit met een donkere rand.
    final themed = renderMeters([
      {'type': 'heading', 'label': 'S', 'value': 0, 'heading': 90},
    ], theme: const ThemeProfile(accentColor: '#123456'));
    expect(themed, contains('#123456'));

    final plain = renderMeters([
      {'type': 'heading', 'label': 'S', 'value': 0, 'heading': 90},
    ]);
    // Falls back to the built-in accent when no theme is supplied.
    expect(plain, contains('#38BDF8'));
  });

  test('column layout scales with meter count (1, 4 and 6 meters)', () {
    Map<String, dynamic> m(int i) => {
      'type': 'speedometer',
      'label': 'M$i',
      'value': 10 * i,
    };

    final one = renderMeters([m(1)]);
    expect(one, contains('M1'));

    final four = renderMeters([for (var i = 1; i <= 4; i++) m(i)]);
    expect(four, contains('M4'));

    // Seven requested, but the renderer caps at cockpitMaxMeters (6).
    final many = renderMeters([for (var i = 1; i <= 7; i++) m(i)]);
    expect(many, contains('M6'));
    expect(many, isNot(contains('>M7<')));
  });

  test('a cockpit with no fenced block is returned unchanged', () {
    const plain = 'Just some **markdown**, no cockpit here.';
    expect(MarpHtmlService.renderCockpitBlocks(plain), plain);
  });
}
