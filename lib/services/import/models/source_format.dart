/// De presentatieformaten die de import herkent. Bepaald aan de
/// bestandsextensie en de zip-magie; de gebruikersnaam per formaat leeft in de
/// UI-laag (met l10n), niet hier.
///
/// De eLearning-formaten (#1992–#1997) zijn ZIP-pakketten of losse XML/JSON-
/// bestanden die een eigen marker dragen: IMS Manifest (`imsmanifest.xml`),
/// QTI (`imsqti.xml` of `.xml` met QTI-namespace), cmi5 (`cmi5.xml`), AICC
/// (`.crs`/`.au`/`.cst`/`.des`) of OLX (`course.xml` met OLX-namespace).
enum SourceFormat {
  pptx,
  odp,
  key,
  // eLearning-import (#1992–#1997).
  scorm, // IMS Content Packaging / SCORM 1.2 / 2004 (#1993)
  qti, // QTI 2.x/3.x assessment items en tests (#1994)
  xapiCmi5, // xAPI activity metadata / cmi5 course packages (#1995)
  aicc, // AICC course-structure (.crs/.au/.cst/.des) (#1996)
  olx, // Open Learning XML (Open edX) (#1997)
  unknown,
}
