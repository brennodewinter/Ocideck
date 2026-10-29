part of 'image_service.dart';

/// De SVG-helft van de beeldimport.
///
/// SVG heeft geen magic bytes — het is XML en mag met witruimte, een BOM of
/// een declaratie beginnen. De extensie kiest daarom de route en de volledige,
/// begrensde parse in `sanitizeImportedSvgBytes` is de inhoudscontrole. Wat
/// hier terugkomt zijn de opgeschoonde bytes; de bron zelf bereikt een deck,
/// stagingmap of Library nooit.

/// Bestandstypen die de beeldkiezer aanbiedt. SVG staat hier expliciet bij:
/// `FileType.image` laat vectorbeelden op meerdere platformen weg.
const supportedImageExtensions = [
  'jpg',
  'jpeg',
  'png',
  'gif',
  'webp',
  'bmp',
  'heic',
  'tiff',
  'tif',
  'svg',
];

/// Valideer bytes uit een padloze web-picker/drop en geef de vorm terug die
/// opgeslagen mag worden. Rasterbytes blijven identiek; SVG wordt geparseerd
/// en gesanitiseerd. De naam is bij SVG nodig omdat XML geen magic bytes
/// heeft en het uiteindelijke `mem:`-pad zelf geen extensie draagt.
Uint8List? prepareImportedImageBytes(Uint8List bytes, {required String name}) {
  if (bytes.isEmpty || bytes.length > ImageService.maxImageBytes) return null;
  if (p.extension(name).toLowerCase() == '.svg') {
    return sanitizeImportedSvgBytes(bytes);
  }
  return ImageService.looksLikeImage(bytes) ? bytes : null;
}

/// De opgeschoonde bytes van een SVG-bestand, of null voor een ongeldig, te
/// groot of niet-SVG bestand. Publiek voor de Library-opnameroute, die
/// dezelfde grens moet gebruiken als een rechtstreekse slide-import.
extension ImageServiceSvg on ImageService {
  Future<Uint8List?> sanitizedSvgFileBytes(String path) async {
    if (p.extension(path).toLowerCase() != '.svg') return null;
    try {
      return await _sanitizedSvgBytesFromFile(File(path));
    } on FileSystemException catch (e) {
      logWarning('ImageService: SVG read failed', e);
      return null;
    }
  }
}

Future<Uint8List?> _sanitizedSvgBytesFromFile(File file) async {
  final length = await file.length();
  if (length <= 0 || length > ImageService.maxImageBytes) return null;
  return sanitizeImportedSvgBytes(await file.readAsBytes());
}
