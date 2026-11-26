import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/gallery_layout.dart';
import 'package:ocideck/models/image_callout.dart';
import 'package:ocideck/models/menu.dart';
import 'package:ocideck/models/marp_style.dart';
import 'package:ocideck/models/timeline.dart';
import 'package:ocideck/models/display_window_spec.dart';
import 'package:ocideck/models/privacy_disposition.dart';
import 'package:ocideck/models/quality_disposition.dart';
import 'package:ocideck/utils/sanitize_svg.dart';

/// The same case list supplies the inventory and the executable assertions.
/// Every fixture must change the named property from its baseline.
class FieldCase<T> {
  const FieldCase(this.base, this.input, this.read);
  final T base;
  final T input;
  final Object? Function(T) read;
}

FieldCase<Slide> slideCase(
  SlideType type,
  Slide Function(Slide) change,
  Object? Function(Slide) read,
) {
  var base = Slide.create(type).copyWith(title: 'Basis', findingId: 'F-10');
  if ({
    SlideType.title,
    SlideType.section,
    SlideType.quote,
    SlideType.image,
    SlideType.bulletsImage,
    SlideType.twoImages,
  }.contains(type)) {
    base = base.copyWith(imagePath: 'images/base.png');
  }
  if (type == SlideType.twoImages || type == SlideType.title) {
    base = base.copyWith(imagePath2: 'images/base2.png');
  }
  if (type == SlideType.video) {
    base = base.copyWith(videoPath: 'videos/base.mp4');
  }
  if (type == SlideType.bulletsImage) {
    base = base.copyWith(
      anchor: 'callout-probe',
      bullets: ['Punt (A)'],
      callouts: const [
        ImageCallout(reference: 'A', targets: [CalloutPoint(0.1, 0.2)]),
      ],
    );
  }
  return FieldCase(base, change(base), read);
}

FieldCase<ThemeProfile> themeCase(
  ThemeProfile Function(ThemeProfile) change,
  Object? Function(ThemeProfile) read,
) {
  const base = ThemeProfile();
  return FieldCase(base, change(base), read);
}

final slideRoundtripCases = <String, FieldCase<Slide>>{
  'type': slideCase(
    SlideType.bullets,
    (s) => s.copyWith(type: SlideType.section),
    (s) => s.type,
  ),
  'title': slideCase(
    SlideType.title,
    (s) => s.copyWith(title: 'Veldtitel'),
    (s) => s.title,
  ),
  'subtitle': slideCase(
    SlideType.title,
    (s) => s.copyWith(subtitle: 'Onderkop'),
    (s) => s.subtitle,
  ),
  'bullets': slideCase(
    SlideType.twoBullets,
    (s) => s.copyWith(bullets: ['Een', 'Twee']),
    (s) => s.bullets,
  ),
  'bullets2': slideCase(
    SlideType.twoBullets,
    (s) => s.copyWith(bullets2: ['Drie', 'Vier']),
    (s) => s.bullets2,
  ),
  'listStyle': slideCase(
    SlideType.bullets,
    (s) => s.copyWith(listStyle: ListStyle.checklist),
    (s) => s.listStyle,
  ),
  'showChecklistProgress': slideCase(
    SlideType.bullets,
    (s) => s.copyWith(showChecklistProgress: true),
    (s) => s.showChecklistProgress,
  ),
  'continueNumbering': slideCase(
    SlideType.bullets,
    (s) => s.copyWith(listStyle: ListStyle.numbered, continueNumbering: true),
    (s) => s.continueNumbering,
  ),
  'continuesSplit': slideCase(
    SlideType.bullets,
    (s) => s.copyWith(continuesSplit: true),
    (s) => s.continuesSplit,
  ),
  'columnTitle1': slideCase(
    SlideType.twoBullets,
    (s) => s.copyWith(columnTitle1: 'Kolom links'),
    (s) => s.columnTitle1,
  ),
  'columnTitle2': slideCase(
    SlideType.twoBullets,
    (s) => s.copyWith(columnTitle2: 'Kolom rechts'),
    (s) => s.columnTitle2,
  ),
  'imagePath': slideCase(
    SlideType.image,
    (s) => s.copyWith(imagePath: 'images/probe.png'),
    (s) => s.imagePath,
  ),
  'imagePath2': slideCase(
    SlideType.twoImages,
    (s) => s.copyWith(imagePath2: 'images/probe2.png'),
    (s) => s.imagePath2,
  ),
  'imageCaption': slideCase(
    SlideType.image,
    (s) => s.copyWith(imageCaption: 'Bijschrift'),
    (s) => s.imageCaption,
  ),
  'imageCaption2': slideCase(
    SlideType.twoImages,
    (s) => s.copyWith(imageCaption2: 'Tweede bijschrift'),
    (s) => s.imageCaption2,
  ),
  'imageAltText': slideCase(
    SlideType.image,
    (s) => s.copyWith(imageAltText: 'Beschrijving'),
    (s) => s.imageAltText,
  ),
  'imageAltText2': slideCase(
    SlideType.twoImages,
    (s) => s.copyWith(imageAltText2: 'Tweede beschrijving'),
    (s) => s.imageAltText2,
  ),
  'imageFocalX': slideCase(
    SlideType.image,
    (s) => s.copyWith(imageFocalX: 0.25),
    (s) => s.imageFocalX,
  ),
  'imageFocalY': slideCase(
    SlideType.image,
    (s) => s.copyWith(imageFocalY: 0.75),
    (s) => s.imageFocalY,
  ),
  'imageFocalX2': slideCase(
    SlideType.twoImages,
    (s) => s.copyWith(imageFocalX2: 0.2),
    (s) => s.imageFocalX2,
  ),
  'imageFocalY2': slideCase(
    SlideType.twoImages,
    (s) => s.copyWith(imageFocalY2: 0.8),
    (s) => s.imageFocalY2,
  ),
  'galleryImages': slideCase(
    SlideType.imageGallery,
    (s) => s.copyWith(
      galleryImages: ['![Een](images/een.png)', '![Twee](images/twee.png)'],
    ),
    (s) => s.galleryImages,
  ),
  'galleryLayout': slideCase(
    SlideType.imageGallery,
    (s) => s.copyWith(galleryLayout: GalleryLayout.stack),
    (s) => s.galleryLayout,
  ),
  'videoPath': slideCase(
    SlideType.video,
    (s) => s.copyWith(videoPath: 'videos/probe.mp4'),
    (s) => s.videoPath,
  ),
  'videoAutoplay': slideCase(
    SlideType.video,
    (s) => s.copyWith(videoAutoplay: true),
    (s) => s.videoAutoplay,
  ),
  'videoStartMs': slideCase(
    SlideType.video,
    (s) => s.copyWith(videoStartMs: 1500),
    (s) => s.videoStartMs,
  ),
  'videoEndMs': slideCase(
    SlideType.video,
    (s) => s.copyWith(videoEndMs: 9000),
    (s) => s.videoEndMs,
  ),
  'videoCaptions': slideCase(
    SlideType.video,
    (s) => s.copyWith(videoCaptions: 'captions/probe.vtt'),
    (s) => s.videoCaptions,
  ),
  'audioPath': slideCase(
    SlideType.bullets,
    (s) => s.copyWith(audioPath: 'audio/probe.mp3'),
    (s) => s.audioPath,
  ),
  'audioAutoplay': slideCase(
    SlideType.bullets,
    (s) => s.copyWith(audioPath: 'audio/base.mp3', audioAutoplay: true),
    (s) => s.audioAutoplay,
  ),
  'quote': slideCase(
    SlideType.quote,
    (s) => s.copyWith(quote: 'Een citaat'),
    (s) => s.quote,
  ),
  'quoteAuthor': slideCase(
    SlideType.quote,
    (s) => s.copyWith(quoteAuthor: 'Een auteur'),
    (s) => s.quoteAuthor,
  ),
  'customMarkdown': slideCase(
    SlideType.freeMarkdown,
    (s) => s.copyWith(customMarkdown: 'Een **vrije** tekst'),
    (s) => s.customMarkdown,
  ),
  'codeLanguage': slideCase(
    SlideType.code,
    (s) => s.copyWith(codeLanguage: 'dart'),
    (s) => s.codeLanguage,
  ),
  'cssClass': slideCase(
    SlideType.bullets,
    (s) => s.copyWith(cssClass: 'contract-class'),
    (s) => s.cssClass,
  ),
  'notes': slideCase(
    SlideType.bullets,
    (s) => s.copyWith(notes: 'Sprekersnotitie'),
    (s) => s.notes,
  ),
  'preservedMarpLines': slideCase(
    SlideType.bullets,
    (s) =>
        s.copyWith(preservedMarpLines: ['<!-- ocideck_future_probe: keep -->']),
    (s) => s.preservedMarpLines,
  ),
  'marpStyle': slideCase(
    SlideType.bullets,
    (s) => s.copyWith(
      marpStyle: const MarpStyle(color: '#123456', header: 'Kop'),
    ),
    (s) => s.marpStyle.toJson(),
  ),
  'advanceDuration': slideCase(
    SlideType.bullets,
    (s) => s.copyWith(advanceDuration: 8.5),
    (s) => s.advanceDuration,
  ),
  'imageSize': slideCase(
    SlideType.image,
    (s) => s.copyWith(imageSize: 65),
    (s) => s.imageSize,
  ),
  'splitImageOnLeft': slideCase(
    SlideType.bulletsImage,
    (s) => s.copyWith(splitImageOnLeft: true),
    (s) => s.splitImageOnLeft,
  ),
  'imageZoom': slideCase(
    SlideType.image,
    (s) => s.copyWith(imageZoom: 150),
    (s) => s.imageZoom,
  ),
  'twoImagesLayout': slideCase(
    SlideType.twoImages,
    (s) => s.copyWith(twoImagesLayout: TwoImagesLayout.equalHeight),
    (s) => s.twoImagesLayout,
  ),
  'titleImageOverlay': slideCase(
    SlideType.title,
    (s) => s.copyWith(titleImageOverlay: false),
    (s) => s.titleImageOverlay,
  ),
  'imageTitleAbove': slideCase(
    SlideType.image,
    (s) => s.copyWith(imageTitleAbove: true),
    (s) => s.imageTitleAbove,
  ),
  'titleTextColorOverride': slideCase(
    SlideType.title,
    (s) => s.copyWith(titleTextColorOverride: '#123456'),
    (s) => s.titleTextColorOverride,
  ),
  'titleColumnLayout': slideCase(
    SlideType.title,
    (s) => s.copyWith(titleColumnLayout: TitleColumnLayout.right),
    (s) => s.titleColumnLayout,
  ),
  'titleColumnWidth': slideCase(
    SlideType.title,
    (s) => s.copyWith(
      titleColumnLayout: TitleColumnLayout.left,
      titleColumnWidth: 35,
    ),
    (s) => s.titleColumnWidth,
  ),
  'bulletMarkerOverride': slideCase(
    SlideType.bullets,
    (s) => s.copyWith(bulletMarkerOverride: BulletMarker.paw),
    (s) => s.bulletMarkerOverride,
  ),
  'showLogo': slideCase(
    SlideType.bullets,
    (s) => s.copyWith(showLogo: false),
    (s) => s.showLogo,
  ),
  'showFooter': slideCase(
    SlideType.bullets,
    (s) => s.copyWith(showFooter: false),
    (s) => s.showFooter,
  ),
  'skipped': slideCase(
    SlideType.bullets,
    (s) => s.copyWith(skipped: true),
    (s) => s.skipped,
  ),
  'tlp': slideCase(
    SlideType.bullets,
    (s) => s.copyWith(tlp: TlpLevel.amber),
    (s) => s.tlp,
  ),
  'isDetail': slideCase(
    SlideType.bullets,
    (s) => s.copyWith(isDetail: true),
    (s) => s.isDetail,
  ),
  'privacy': slideCase(
    SlideType.bullets,
    (s) => s.copyWith(privacy: PrivacyDisposition.accept),
    (s) => s.privacy,
  ),
  'quality': slideCase(
    SlideType.bullets,
    (s) => s.copyWith(quality: QualityDisposition.accept),
    (s) => s.quality,
  ),
  'styleName': slideCase(
    SlideType.bullets,
    (s) => s.copyWith(styleName: 'Eigen stijl'),
    (s) => s.styleName,
  ),
  'tableRows': slideCase(
    SlideType.table,
    (s) => s.copyWith(
      tableRows: [
        ['Kop 1', 'Kop 2'],
        ['A', '42'],
      ],
    ),
    (s) => s.tableRows,
  ),
  'tableColumnAlignments': slideCase(
    SlideType.table,
    (s) => s.copyWith(
      tableColumnAlignments: [TableAlign.center, TableAlign.right],
    ),
    (s) => s.tableColumnAlignments,
  ),
  'tableNumberColumns': slideCase(
    SlideType.table,
    (s) => s.copyWith(tableNumberColumns: [false, true]),
    (s) => s.tableNumberColumns,
  ),
  'tableEditable': slideCase(
    SlideType.table,
    (s) => s.copyWith(tableEditable: true),
    (s) => s.tableEditable,
  ),
  'tableMarkOverdue': slideCase(
    SlideType.table,
    (s) => s.copyWith(tableMarkOverdue: true),
    (s) => s.tableMarkOverdue,
  ),
  'ganttScale': slideCase(
    SlideType.gantt,
    (s) => s.copyWith(ganttScale: 'day'),
    (s) => s.ganttScale,
  ),
  'ganttSections': slideCase(
    SlideType.gantt,
    (s) => s.copyWith(ganttSections: true),
    (s) => s.ganttSections,
  ),
  'viewLimit': slideCase(
    SlideType.bullets,
    (s) => s.copyWith(
      viewLimit: const DisplayWindowSpec(
        limit: 1,
        mode: DisplayWindowMode.last,
        showCount: false,
      ),
    ),
    (s) => s.viewLimit?.toComments(),
  ),
  'menuLayout': slideCase(
    SlideType.menu,
    (s) => s.copyWith(menuLayout: MenuLayout.circle),
    (s) => s.menuLayout,
  ),
  'timelineLayout': slideCase(
    SlideType.timeline,
    (s) => s.copyWith(timelineLayout: TimelineLayout.vertical),
    (s) => s.timelineLayout,
  ),
  'timelineReveal': slideCase(
    SlideType.timeline,
    (s) => s.copyWith(timelineReveal: TimelineReveal.steps),
    (s) => s.timelineReveal,
  ),
  'timelineAnimationMs': slideCase(
    SlideType.timeline,
    (s) => s.copyWith(timelineAnimationMs: 1200),
    (s) => s.timelineAnimationMs,
  ),
  'timelineCurrentIndex': slideCase(
    SlideType.timeline,
    (s) => s.copyWith(timelineCurrentIndex: 1),
    (s) => s.timelineCurrentIndex,
  ),
  'findingId': slideCase(
    SlideType.checklist,
    (s) => s.copyWith(findingId: 'F-42'),
    (s) => s.findingId,
  ),
  'findingRole': slideCase(
    SlideType.checklist,
    (s) => s.copyWith(findingRole: FindingRole.evidence),
    (s) => s.findingRole,
  ),
  'aiAssistedFields': slideCase(
    SlideType.checklist,
    (s) => s.copyWith(aiAssistedFields: ['title']),
    (s) => s.aiAssistedFields,
  ),
  'checklistScope': slideCase(
    SlideType.checklist,
    (s) => s.copyWith(checklistScope: 'https://scope.example/login'),
    (s) => s.checklistScope,
  ),
  'improvementTemplateId': slideCase(
    SlideType.matrix,
    (s) => s.copyWith(improvementTemplateId: 'contract-template'),
    (s) => s.improvementTemplateId,
  ),
  'improvementLayout': slideCase(
    SlideType.tree,
    (s) => s.copyWith(improvementLayout: 'fishbone'),
    (s) => s.improvementLayout,
  ),
  'anchor': slideCase(
    SlideType.bullets,
    (s) => s.copyWith(anchor: 'doel-anker'),
    (s) => s.anchor,
  ),
  'nextAnchor': slideCase(
    SlideType.bullets,
    (s) => s.copyWith(nextAnchor: 'volgend-anker'),
    (s) => s.nextAnchor,
  ),
  'callouts': slideCase(
    SlideType.bulletsImage,
    (s) => s.copyWith(
      callouts: const [
        ImageCallout(
          reference: 'A',
          targets: [CalloutPoint(0.3, 0.4)],
          description: 'Doel',
        ),
      ],
    ),
    (s) => s.callouts,
  ),
  'calloutPresentation': slideCase(
    SlideType.bulletsImage,
    (s) => s.copyWith(calloutPresentation: CalloutPresentation.region),
    (s) => s.calloutPresentation,
  ),
  'calloutReveal': slideCase(
    SlideType.bulletsImage,
    (s) => s.copyWith(calloutReveal: BulletRevealMode.steps),
    (s) => s.calloutReveal,
  ),
};

final themeRoundtripCases = <String, FieldCase<ThemeProfile>>{
  'name': themeCase((s) => s.copyWith(name: 'Rondgangprofiel'), (s) => s.name),
  'slideBackgroundColor': themeCase(
    (s) => s.copyWith(slideBackgroundColor: '#123456'),
    (s) => s.slideBackgroundColor,
  ),
  'textColor': themeCase(
    (s) => s.copyWith(textColor: '#123456'),
    (s) => s.textColor,
  ),
  'accentColor': themeCase(
    (s) => s.copyWith(accentColor: '#123456'),
    (s) => s.accentColor,
  ),
  'checklistCheckedColor': themeCase(
    (s) => s.copyWith(checklistCheckedColor: '#123456'),
    (s) => s.checklistCheckedColor,
  ),
  'checklistUncheckedColor': themeCase(
    (s) => s.copyWith(checklistUncheckedColor: '#123456'),
    (s) => s.checklistUncheckedColor,
  ),
  'checklistStrikeThrough': themeCase(
    (s) => s.copyWith(checklistStrikeThrough: false),
    (s) => s.checklistStrikeThrough,
  ),
  'bulletMarker': themeCase(
    (s) => s.copyWith(bulletMarker: BulletMarker.paw),
    (s) => s.bulletMarker,
  ),
  'customBulletSvg': themeCase(
    (s) => s.copyWith(
      customBulletSvg: sanitizeCustomBulletSvg(
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10"><circle cx="5" cy="5" r="3"/></svg>',
      )!,
    ),
    (s) => s.customBulletSvg,
  ),
  'tableTextColor': themeCase(
    (s) => s.copyWith(tableTextColor: '#123456'),
    (s) => s.tableTextColor,
  ),
  'tableHeaderTextColor': themeCase(
    (s) => s.copyWith(tableHeaderTextColor: '#123456'),
    (s) => s.tableHeaderTextColor,
  ),
  'tableHeaderBackgroundColor': themeCase(
    (s) => s.copyWith(tableHeaderBackgroundColor: '#123456'),
    (s) => s.tableHeaderBackgroundColor,
  ),
  'tableZebraStriped': themeCase(
    (s) => s.copyWith(tableZebraStriped: true),
    (s) => s.tableZebraStriped,
  ),
  'tableZebraColor': themeCase(
    (s) => s.copyWith(tableZebraColor: '#123456'),
    (s) => s.tableZebraColor,
  ),
  'tableBorderStyle': themeCase(
    (s) => s.copyWith(tableBorderStyle: TableBorderStyle.lined),
    (s) => s.tableBorderStyle,
  ),
  'tableBorderColor': themeCase(
    (s) => s.copyWith(tableBorderColor: '#123456'),
    (s) => s.tableBorderColor,
  ),
  'tableCellPaddingPx': themeCase(
    (s) => s.copyWith(tableCellPaddingPx: 13.0),
    (s) => s.tableCellPaddingPx,
  ),
  'tableAccentHeaderBorder': themeCase(
    (s) => s.copyWith(tableAccentHeaderBorder: true),
    (s) => s.tableAccentHeaderBorder,
  ),
  'titleBackgroundColor': themeCase(
    (s) => s.copyWith(titleBackgroundColor: '#123456'),
    (s) => s.titleBackgroundColor,
  ),
  'titleTextColor': themeCase(
    (s) => s.copyWith(titleTextColor: '#123456'),
    (s) => s.titleTextColor,
  ),
  'sectionBackgroundColor': themeCase(
    (s) => s.copyWith(sectionBackgroundColor: '#123456'),
    (s) => s.sectionBackgroundColor,
  ),
  'codeBackgroundColor': themeCase(
    (s) => s.copyWith(codeBackgroundColor: '#123456'),
    (s) => s.codeBackgroundColor,
  ),
  'codeTextColor': themeCase(
    (s) => s.copyWith(codeTextColor: '#123456'),
    (s) => s.codeTextColor,
  ),
  'codeHighlightSyntax': themeCase(
    (s) => s.copyWith(codeHighlightSyntax: false),
    (s) => s.codeHighlightSyntax,
  ),
  'codeFontFamily': themeCase(
    (s) => s.copyWith(codeFontFamily: 'Courier New'),
    (s) => s.codeFontFamily,
  ),
  'logoPath': themeCase(
    (s) => s.copyWith(logoPath: 'asset:assets/images/librekat-logo.png'),
    (s) => s.logoPath,
  ),
  'logoPosition': themeCase(
    (s) => s.copyWith(logoPosition: 'top-left'),
    (s) => s.logoPosition,
  ),
  'logoSize': themeCase((s) => s.copyWith(logoSize: 120), (s) => s.logoSize),
  'brandStripPath': themeCase(
    (s) => s.copyWith(brandStripPath: 'asset:assets/images/librekat-logo.png'),
    (s) => s.brandStripPath,
  ),
  'slideBackgroundImages': themeCase(
    (s) => s.copyWith(
      slideBackgroundImages: const {
        'content': 'asset:assets/images/librekat-logo.png',
        'title': 'asset:assets/images/librekat-logo.png',
      },
    ),
    (s) => s.slideBackgroundImages,
  ),
  'brandStripHeight': themeCase(
    (s) => s.copyWith(brandStripHeight: 0.15),
    (s) => s.brandStripHeight,
  ),
  'titleSubtitleInBrandStrip': themeCase(
    (s) => s.copyWith(titleSubtitleInBrandStrip: true),
    (s) => s.titleSubtitleInBrandStrip,
  ),
  'logoDarkPath': themeCase(
    (s) => s.copyWith(logoDarkPath: 'asset:assets/images/librekat-logo.png'),
    (s) => s.logoDarkPath,
  ),
  'documentLogoPath': themeCase(
    (s) =>
        s.copyWith(documentLogoPath: 'asset:assets/images/librekat-logo.png'),
    (s) => s.documentLogoPath,
  ),
  'documentLogoPosition': themeCase(
    (s) => s.copyWith(documentLogoPosition: 'bottom-left'),
    (s) => s.documentLogoPosition,
  ),
  'documentLogoSize': themeCase(
    (s) => s.copyWith(documentLogoSize: 140),
    (s) => s.documentLogoSize,
  ),
  'documentBodyFontSize': themeCase(
    (s) => s.copyWith(documentBodyFontSize: 18.0),
    (s) => s.documentBodyFontSize,
  ),
  'documentHeaderText': themeCase(
    (s) => s.copyWith(documentHeaderText: 'Kop: {title}'),
    (s) => s.documentHeaderText,
  ),
  'documentFooterText': themeCase(
    (s) => s.copyWith(documentFooterText: 'Voet: {page}'),
    (s) => s.documentFooterText,
  ),
  'documentHeaderFontSize': themeCase(
    (s) => s.copyWith(documentHeaderFontSize: 13.0),
    (s) => s.documentHeaderFontSize,
  ),
  'documentFooterFontSize': themeCase(
    (s) => s.copyWith(documentFooterFontSize: 14.0),
    (s) => s.documentFooterFontSize,
  ),
  'documentHeadingColor': themeCase(
    (s) => s.copyWith(documentHeadingColor: '#123456'),
    (s) => s.documentHeadingColor,
  ),
  'documentBandTextColor': themeCase(
    (s) => s.copyWith(documentBandTextColor: '#123456'),
    (s) => s.documentBandTextColor,
  ),
  'documentBandBackgroundColor': themeCase(
    (s) => s.copyWith(documentBandBackgroundColor: '#123456'),
    (s) => s.documentBandBackgroundColor,
  ),
  'documentShowPageNumbers': themeCase(
    (s) => s.copyWith(documentShowPageNumbers: true),
    (s) => s.documentShowPageNumbers,
  ),
  'documentHeadingFontFamily': themeCase(
    (s) => s.copyWith(documentHeadingFontFamily: 'Verdana'),
    (s) => s.documentHeadingFontFamily,
  ),
  'preferredFontFamily': themeCase(
    (s) => s.copyWith(preferredFontFamily: 'Aptos'),
    (s) => s.preferredFontFamily,
  ),
  'preferredDocumentHeadingFontFamily': themeCase(
    (s) => s.copyWith(preferredDocumentHeadingFontFamily: 'Aptos Display'),
    (s) => s.preferredDocumentHeadingFontFamily,
  ),
  'fontFamily': themeCase(
    (s) => s.copyWith(fontFamily: 'Georgia'),
    (s) => s.fontFamily,
  ),
  'footerText': themeCase(
    (s) => s.copyWith(footerText: 'Contractvoet'),
    (s) => s.footerText,
  ),
  'footerShowPageNumbers': themeCase(
    (s) => s.copyWith(footerShowPageNumbers: true),
    (s) => s.footerShowPageNumbers,
  ),
  'footerPosition': themeCase(
    (s) => s.copyWith(footerPosition: 'center'),
    (s) => s.footerPosition,
  ),
  'headerFontSize': themeCase(
    (s) => s.copyWith(headerFontSize: 18.0),
    (s) => s.headerFontSize,
  ),
  'footerFontSize': themeCase(
    (s) => s.copyWith(footerFontSize: 19.0),
    (s) => s.footerFontSize,
  ),
  'closingSlideEnabled': themeCase(
    (s) => s.copyWith(closingSlideEnabled: true),
    (s) => s.closingSlideEnabled,
  ),
  'closingSlideMarkdown': themeCase(
    (s) => s.copyWith(closingSlideMarkdown: '# Tot ziens'),
    (s) => s.closingSlideMarkdown,
  ),
  'animationDurationMs': themeCase(
    (s) => s.copyWith(animationDurationMs: 1200),
    (s) => s.animationDurationMs,
  ),
  'severityCriticalColor': themeCase(
    (s) => s.copyWith(severityCriticalColor: '#123456'),
    (s) => s.severityCriticalColor,
  ),
  'severityHighColor': themeCase(
    (s) => s.copyWith(severityHighColor: '#123456'),
    (s) => s.severityHighColor,
  ),
  'severityMediumColor': themeCase(
    (s) => s.copyWith(severityMediumColor: '#123456'),
    (s) => s.severityMediumColor,
  ),
  'severityLowColor': themeCase(
    (s) => s.copyWith(severityLowColor: '#123456'),
    (s) => s.severityLowColor,
  ),
  'severityNoneColor': themeCase(
    (s) => s.copyWith(severityNoneColor: '#123456'),
    (s) => s.severityNoneColor,
  ),
};
