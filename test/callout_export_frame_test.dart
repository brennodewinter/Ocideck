import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:material_ui/material_ui.dart';
import 'package:ocideck/models/image_callout.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/utils/image_limits.dart';
import 'package:ocideck/widgets/slides/previews/callout_overlay.dart';

/// De rasterexports (PDF, PPTX, ODP) laden de dia-afbeeldingen voor en vangen
/// dan een frame zodra de boom niet meer hoeft te verven. `CalloutOverlay`
/// tekent niets zolang de intrinsieke beeldmaat onbekend is — kwam die maat
/// altijd via een `setState`, dan was het frame al gevangen en ontbrak élke
/// markering in élke rasterexport. Dat was zo, en het was in de app niet te
/// zien: daar volgt vanzelf een volgend frame.
///
/// Deze toets legt de eis vast waar het misging: **is het beeld al gecachet,
/// dan staan de markeringen er in het éérste frame**.

String _writePng() {
  final dir = Directory.systemTemp.createTempSync('ocideck_exportframe');
  final file = File('${dir.path}/beeld.png');
  final image = img.Image(width: 200, height: 100);
  img.fill(image, color: img.ColorRgb8(180, 180, 180));
  file.writeAsBytesSync(Uint8List.fromList(img.encodePng(image)));
  return file.path;
}

/// Een gastheer die van dia wisselt via `setState` — precies wat de rasterizer
/// doet: één onzichtbare diahost die per pagina een andere dia krijgt.
class _Host extends StatefulWidget {
  const _Host({super.key, required this.eerste, required this.tweede});
  final Slide eerste;
  final Slide tweede;
  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  late Slide _slide = widget.eerste;

  void volgende() => setState(() => _slide = widget.tweede);

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Center(
      child: SizedBox(
        width: 400,
        height: 300,
        child: _slide.callouts.isEmpty
            ? const SizedBox.expand()
            : CalloutOverlay(
                slide: _slide,
                profile: const ThemeProfile(),
                slotWidth: 400,
                slotHeight: 300,
              ),
      ),
    ),
  );
}

void main() {
  testWidgets('een gecachet beeld levert zijn maat synchroon', (tester) async {
    // Twee bestanden: een koud beeld en een warm beeld. Eén bestand voor beide
    // kan niet — de koude peiling zet een nog-lopende decode in de cache, en
    // die komt onder de testklok nooit meer af.
    final koudPad = _writePng();
    final warmPad = _writePng();

    bool? koudSynchroon;
    resolveIntrinsicSize(cappedFileImage(File(koudPad)), (_, sync) {
      koudSynchroon = sync;
    });
    expect(
      koudSynchroon,
      isNull,
      reason: 'een ongedecodeerd beeld kan niet synchroon antwoorden',
    );

    // Voorladen, zoals de rasterizer doet vóór hij een frame vangt.
    final warmProvider = cappedFileImage(File(warmPad));
    await tester.runAsync(() async {
      final done = Completer<void>();
      final stream = warmProvider.resolve(ImageConfiguration.empty);
      late ImageStreamListener listener;
      listener = ImageStreamListener(
        (_, _) {
          if (!done.isCompleted) done.complete();
        },
        onError: (_, _) {
          if (!done.isCompleted) done.complete();
        },
      );
      stream.addListener(listener);
      await done.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw StateError('het beeld kwam niet in de cache'),
      );
      stream.removeListener(listener);
    });

    Size? warmeMaat;
    bool? warmSynchroon;
    resolveIntrinsicSize(warmProvider, (size, sync) {
      warmeMaat = size;
      warmSynchroon = sync;
    });
    expect(
      warmSynchroon,
      isTrue,
      reason:
          'staat het beeld in de cache, dan hoort de maat er te zijn vóór het '
          'volgende frame — anders vertrekt de rasterexport zonder markering',
    );
    expect(warmeMaat, const Size(200, 100));
  });

  testWidgets('voorgeladen beeld: markeringen staan er in het eerste frame', (
    tester,
  ) async {
    final path = _writePng();

    // Wat de rasterizer doet vóór hij een frame vangt.
    await tester.runAsync(() async {
      final stream = cappedFileImage(
        File(path),
      ).resolve(ImageConfiguration.empty);
      final done = Completer<void>();
      late ImageStreamListener listener;
      listener = ImageStreamListener(
        (_, _) {
          if (!done.isCompleted) done.complete();
        },
        onError: (_, _) {
          if (!done.isCompleted) done.complete();
        },
      );
      stream.addListener(listener);
      await done.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw StateError('het beeld kwam niet in de cache'),
      );
      stream.removeListener(listener);
    });

    final zonder = Slide(id: 'een', type: SlideType.bulletsImage);
    final met = Slide(
      id: 'twee',
      anchor: 'dia-2',
      type: SlideType.bulletsImage,
      imagePath: path,
      callouts: const [
        ImageCallout(
          reference: 'B',
          targets: [CalloutPoint(0.5, 0.5)],
          description: 'de meetkamer',
        ),
      ],
    );

    final key = GlobalKey<_HostState>();
    await tester.pumpWidget(_Host(key: key, eerste: zonder, tweede: met));

    // De overlay komt er nu bij tijdens een rebuild, niet bij de allereerste
    // opbouw — net als in de export, waar de diahost per pagina een andere dia
    // krijgt. Daarna precies één frame: de rasterizer wacht niet op een tweede.
    key.currentState!.volgende();
    await tester.pump();

    expect(
      find.text('B'),
      findsOneWidget,
      reason:
          'een gecachet beeld hoort de maat synchroon te leveren, zodat het '
          'frame dat de export vangt de markering al draagt',
    );
  });
}
