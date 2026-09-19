/// Magic-byte herkenning van rasterafbeeldingen, gedeeld door de twee kanten
/// die beeldbinnenkomst controleren: `ImageService` (bestanden die de
/// gebruiker kiest of plakt) en de document-importeurs (bytes uit een
/// `.docx`/`.odt`-archief). Headless — geen Flutter, geen IO — zodat de
/// importeurs hem ook op web kunnen aanroepen.
///
/// De bestandsnaam of een aangeboden mimetype is hier bewust níet genoeg: een
/// archief kan een deel `logo.png` noemen terwijl er een HTML-pagina in zit.
/// Wat we bewaren en tonen wordt aan de bytes zelf gemeten.
library;

/// Het MIME-type achter de rasterhandtekening van [b], of `null` als de bytes
/// bij geen bekende vorm passen (PNG/JPEG/GIF/BMP/WebP). Dit is de enige bron
/// van waarheid voor "lijkt dit op een afbeelding"; wie het type moet noemen —
/// voor een `data:`-URI of een veilige extensie — snuift hier in plaats van
/// een extensie of een verklaard type van een buitenbestand te vertrouwen.
String? imageMimeFromBytes(List<int> b) {
  if (b.length < 4) return null;
  // PNG
  if (b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47) {
    return 'image/png';
  }
  if (b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF) return 'image/jpeg';
  if (b[0] == 0x47 && b[1] == 0x49 && b[2] == 0x46) return 'image/gif';
  if (b[0] == 0x42 && b[1] == 0x4D) return 'image/bmp';
  // WebP: "RIFF"...."WEBP"
  if (b.length >= 12 &&
      b[0] == 0x52 &&
      b[1] == 0x49 &&
      b[2] == 0x46 &&
      b[3] == 0x46 &&
      b[8] == 0x57 &&
      b[9] == 0x45 &&
      b[10] == 0x42 &&
      b[11] == 0x50) {
    return 'image/webp';
  }
  return null;
}

/// De bestandsextensie voor een MIME-type uit [imageMimeFromBytes]. Valt
/// terug op `png` zodat een gematerialiseerd bestand altijd een bruikbare
/// extensie draagt.
String extensionForImageMime(String mime) => switch (mime) {
  'image/jpeg' => 'jpg',
  'image/gif' => 'gif',
  'image/bmp' => 'bmp',
  'image/webp' => 'webp',
  _ => 'png',
};
