// Verklaart, ná een omgevallen testsuite, de ene fout die naar de verkeerde
// plek wijst: een bestand dat niet GELADEN kon worden.
//
// #798 meldde dit tweemaal op één dag:
//
//     Failed to load "test/<wisselend>_test.dart":
//     type '_Map<String, dynamic>' is not a subtype of type 'List<dynamic>' in type cast
//
// De genoemde test was los gedraaid groen. Wie dat niet weet gaat hem debuggen,
// en dat is de kostenpost — niet de storing zelf.
//
// **Waarom een rapport en geen filter over de uitvoer.** De terminaluitvoer van
// `flutter test` blijft onaangeraakt: er wordt niets afgevangen, onderdrukt of
// herschreven, en de afloop blijft die van de suite. Dat is geen scrupule maar
// noodzaak — een pipe kost `flutter test` zijn voortgangsregel en maakt er
// duizenden regels van. In plaats daarvan schrijft elke suiteaanroep náást het
// scherm een machineleesbaar rapport (`--file-reporter json:…`), en dit leest
// dat. Een zijkanaal kan per definitie niets wegpoetsen.
//
// **Waarom het onderscheid maakt.** Een laadfout kan óók gewoon jouw fout zijn:
// een bestand dat niet compileert, of zonder `main`. Die wordt hier niet
// gesust maar juist benoemd, mét de zin die er anders bij inschiet — dat de
// tests in dat bestand niet gedraaid hebben, en de suite dus minder heeft
// getoetst dan het aantal suggereert.
import 'dart:convert';
import 'dart:io';

/// De handtekening van de storing uit #798.
///
/// Hij komt uit `stream_channel`: `MultiChannel` leest zijn verbinding met
/// `stream.cast<List>()` (multi_channel.dart:143), want elk frame hoort een
/// `[id, inhoud]`-lijst te zijn. Kwam er een JSON-object langs, dan is dat geen
/// frame — en de kale `List` in die cast leest de VM voor als `List<dynamic>`.
/// Vandaar precies deze tekst.
const kChannelFramingSignature =
    "is not a subtype of type 'List<dynamic>' in type cast";

/// Eén bestand dat niet geladen kon worden, met de reden zoals de suite die gaf.
class LoadFailure {
  final String path;
  final String reason;

  const LoadFailure(this.path, this.reason);

  /// Is dit de bekende storing in het kanaal, of een echte laadfout?
  ///
  /// Bij twijfel: een echte. Iets ten onrechte "bekend" noemen kost een
  /// gemiste bug; iets ten onrechte echt noemen kost één keer nakijken.
  bool get isKnownTransient => reason.contains(kChannelFramingSignature);
}

/// Leest de laadfouten uit een regelgescheiden JSON-testrapport.
///
/// Een laadfout is in dat rapport een `error` op een test wiens naam met
/// `loading ` begint — de pseudotest die package:test aanmaakt om het laden
/// zelf te kunnen melden. Een gewoon rode test heeft `isFailure: true` en een
/// eigen naam, en hoort hier dus niet bij.
List<LoadFailure> loadFailuresFrom(String report) {
  final loadingTests = <int, String>{};
  final failures = <LoadFailure>[];

  for (final line in const LineSplitter().convert(report)) {
    if (line.isEmpty) {
      continue;
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(line);
    } on FormatException {
      // Een half weggeschreven laatste regel is normaal wanneer de suite
      // midden in een run omvalt. De rest van het rapport blijft bruikbaar.
      continue;
    }
    if (decoded is! Map<String, Object?>) {
      continue;
    }

    switch (decoded['type']) {
      case 'testStart':
        final test = decoded['test'];
        if (test is Map<String, Object?>) {
          final name = test['name'];
          final id = test['id'];
          if (name is String && id is int && name.startsWith('loading ')) {
            loadingTests[id] = name.substring('loading '.length);
          }
        }
      case 'error':
        final id = decoded['testID'];
        final error = decoded['error'];
        final path = id is int ? loadingTests[id] : null;
        if (path != null && error is String) {
          failures.add(LoadFailure(path, error));
        }
    }
  }

  return failures;
}

/// Kort de padnaam in tot iets wat in een terminal te lezen is.
String _relative(String path) {
  final root = '${Directory.current.path}${Platform.pathSeparator}';
  return path.startsWith(root) ? path.substring(root.length) : path;
}

/// De reden zonder het `Failed to load "…": `-voorvoegsel, dat het pad herhaalt.
String _bareReason(String reason) {
  final marker = '": ';
  final at = reason.indexOf(marker);
  final bare = at == -1 ? reason : reason.substring(at + marker.length);
  return bare.split('\n').first.trim();
}

void _report(List<LoadFailure> failures) {
  final out = StringBuffer()
    ..writeln()
    ..writeln(
      '── De suite viel om, en dit deel gaat niet over een test die faalde ───────────',
    )
    ..writeln(
      '   Deze bestanden konden niet worden GELADEN — de tests erin hebben dus',
    )
    ..writeln('   niet gedraaid, en tellen ook niet mee in het aantal:');
  for (final f in failures) {
    out.writeln('     ${_relative(f.path)}');
    out.writeln('       ${_bareReason(f.reason)}');
  }
  out.writeln();

  if (failures.every((f) => f.isKnownTransient)) {
    out
      ..writeln(
        '   Dit is de bekende storing uit #798, in de verbinding tussen `flutter test`',
      )
      ..writeln(
        '   en het testproces — niet in dat bestand. Los gedraaid is die test groen.',
      )
      ..writeln(
        '   Draai opnieuw. Blijft hij staan: `make clean-test-cache`, en lees dan',
      )
      ..writeln('   docs/CHECKS.md, want dan weten we iets nieuws.');
  } else {
    out
      ..writeln(
        '   Dit is een échte laadfout: het bestand compileert niet, of het heeft geen',
      )
      ..writeln(
        '   `main`. Repareer die eerst — zolang hij staat, toetst de suite minder dan',
      )
      ..writeln('   het lijkt.');
  }
  out.writeln(
    '──────────────────────────────────────────────────────────────────────────────',
  );

  stderr.write(out);
}

void main(List<String> args) {
  // Nooit zelf de poort laten vallen: de Makefile bewaart de afloop van de
  // suite en deze verklaring mag daar niets aan veranderen.
  try {
    final report = File(args.isEmpty ? '' : args.first);
    if (!report.existsSync()) {
      return;
    }
    final failures = loadFailuresFrom(report.readAsStringSync());
    if (failures.isEmpty) {
      return;
    }
    _report(failures);
  } on Object {
    return;
  }
}
