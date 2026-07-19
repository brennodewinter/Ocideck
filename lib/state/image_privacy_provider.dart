// De beeldcontrole als kwaliteitsmelding.
//
// Waarom dit een eigen, asynchrone provider is en niet een regel in
// `PrivacyScanner`: de tekstscan is puur, synchroon en microseconden snel, en
// daar hangt de hele UI aan. Een afbeelding decoderen en er een neuraal netwerk
// overheen halen is orden van grootte duurder en raakt de schijf. Dat hoort niet
// in het pad dat bij elke toetsaanslag draait.
//
// Dit is dus de duurste stap van de hele controle, en hij staat daarom achteraan
// en apart — precies zoals `imageContrastIssuesProvider`, die om dezelfde reden
// bestaat.

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/markdown_validation.dart';
import '../models/privacy_finding.dart';
import '../models/slide.dart';
import '../models/slide_quality.dart';
import '../services/privacy/image_face_scan.dart';
import 'deck_provider.dart';
import 'settings_provider.dart';

/// Het pad van het gebundelde YuNet-model.
const String kFaceModelAsset =
    'assets/models/face_detection_yunet_2023mar.onnx';

/// De scanner voor deze sessie: één keer gebouwd, want het model laden en de
/// detector opzetten kost meer dan de detectie zelf.
final imageFaceScannerProvider = Provider<Future<ImageFaceScanner>>((
  ref,
) async {
  final model = await rootBundle.load(kFaceModelAsset);
  final scanner = createImageFaceScanner(model.buffer.asUint8List());
  ref.onDispose(scanner.dispose);
  return scanner;
});

/// De beeldbevindingen van het huidige deck, als kwaliteitsmeldingen.
final imagePrivacyIssuesProvider = FutureProvider<List<SlideQualityIssue>>(
  computeImagePrivacyIssues,
);

/// Top-level, zodat `AppShell` dezelfde berekening per tab kan overriden — zie
/// `provider_scope_test.dart`.
Future<List<SlideQualityIssue>> computeImagePrivacyIssues(Ref ref) async {
  final enabled = ref.watch(
    settingsProvider.select(
      (s) => s.privacyChecksEnabled && s.privacyImageFaceDetection,
    ),
  );
  if (!enabled) return const [];

  final deck = ref.watch(deckProvider.select((s) => s.deck));
  if (deck == null) return const [];

  final scanner = await ref.watch(imageFaceScannerProvider);
  // Draait de native laag niet (web, of een build zonder OpenCV), dan melden we
  // niets — en het paneel met uitgevoerde controles laat de beeldcontrole weg,
  // zodat een lege uitslag niet als "niets gevonden" leest.
  if (!scanner.isSupported) return const [];

  final images = _imagesOf(deck.slides);
  if (images.isEmpty) return const [];

  final service = ref.read(imageServiceProvider);
  final issues = <SlideQualityIssue>[];
  for (final image in images) {
    // Bewust serieel. Parallel decoderen van twintig foto's tegelijk piekt het
    // geheugen van een presentatietool zonder dat iemand op de uitslag wacht:
    // dit is een achtergrondcontrole, geen renderpad.
    final bytes = await service.readSlideImageBytes(
      image.path,
      projectPath: deck.projectPath,
    );
    if (bytes == null) continue;
    final faces = await scanner.countFaces(bytes);
    if (faces <= 0) continue;
    issues.add(_issueFor(image, faces));
  }
  return issues;
}

typedef _SlideImage = ({int slideIndex, String field, String path});

/// Elke afbeelding die werkelijk getoond wordt. Overgeslagen slides tellen niet
/// mee — die worden ook niet geëxporteerd.
List<_SlideImage> _imagesOf(List<Slide> slides) {
  final out = <_SlideImage>[];
  for (var i = 0; i < slides.length; i++) {
    final slide = slides[i];
    if (slide.skipped) continue;
    if (slide.imagePath.isNotEmpty) {
      out.add((slideIndex: i, field: 'imagePath', path: slide.imagePath));
    }
    if (slide.imagePath2.isNotEmpty) {
      out.add((slideIndex: i, field: 'imagePath2', path: slide.imagePath2));
    }
  }
  return out;
}

SlideQualityIssue _issueFor(_SlideImage image, int faces) => SlideQualityIssue(
  slideIndex: image.slideIndex,
  kind: SlideQualityIssueKind.privacyImage,
  category: SlideQualityCategory.privacy,
  // Een herkenbaar gezicht maakt iemand identificeerbaar, dus dit is een
  // persoonsgegeven — maar of het er werkelijk één is hangt af van de context,
  // en dat kan een detector niet zien. Waarschuwing, geen fout.
  severity: MarkdownValidationSeverity.warning,
  field: image.field,
  args: {
    'rule': 'image.face',
    // Geen gemaskeerde waarde maar een aantal: bij een afbeelding valt er niets
    // te maskeren, en het getal zelf verraadt niemand.
    'sample': '$faces',
  },
);

/// De familie waar deze melding onder valt, voor de badge en het paneel.
const PrivacyFamily kImagePrivacyFamily = PrivacyFamily.image;
