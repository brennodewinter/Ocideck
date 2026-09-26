/// De web-ophaalstap van de versiecheck: weigert altijd. De webbouw serveert
/// per definitie de versie die op de host staat — een check zou de bezoeker
/// alleen maar een extra uitgaand verzoek bezorgen waar niets aan te
/// veranderen valt.
Future<String?> pinnedUpdateCheckFetch(Uri uri) => Future.value();
