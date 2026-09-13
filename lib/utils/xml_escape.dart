/// XML-escape voor vrije tekst in een element-body: `&` `<` `>`.
///
/// `&` gaat als eerste, anders wordt een letterlijke `<` na twee stappen
/// alsnog `<`.
String xmlEscape(String s) =>
    s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');

/// XML-escape voor attribuutwaarden: `&` `<` `>` `"` `'`.
///
/// Een attribuut heeft één meer breekvlak dan een element-body: het aanhalingsteken
/// dat de waarde omringt. Daarom komen `"` en `'` erbij.
String xmlAttr(String s) =>
    xmlEscape(s).replaceAll('"', '&quot;').replaceAll("'", '&apos;');
