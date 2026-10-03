import 'dart:convert';

import 'package:crypto/crypto.dart';

/// De SHA-512 van [bytes], in kleine-letter-hex — precies de vorm die
/// `sha512sum` afdrukt.
///
/// Bewust een losse functie en niet een methode op een service: het zegel
/// (`document_integrity.dart`) en de parser (`markdown_service_parse.dart`)
/// hebben allebei dezelfde hash nodig, en een gedeelde service tussen die twee
/// zou een importlus opleveren. Belangrijker: dít is het hele recept. Wie de
/// hash wil narekenen hoeft niets anders te weten dan "SHA-512 over de bytes",
/// en die belofte is makkelijker waar te maken als er geen laag omheen zit die
/// er nog iets aan zou kunnen doen.
String sha512Hex(List<int> bytes) => sha512.convert(bytes).toString();

/// De SHA-256 van [bytes], in kleine-letter-hex — precies de vorm die
/// `sha256sum` afdrukt. Het mirrorbeeld van [sha512Hex] voor de kortere hash.
String sha256Hex(List<int> bytes) => sha256.convert(bytes).toString();

/// De SHA-256 van [text] als UTF-8, zonder normalisatie. Zie [sha512HexOfText].
String sha256HexOfText(String text) => sha256Hex(utf8.encode(text));

/// De SHA-512 van [text] als UTF-8, zonder enige normalisatie: geen
/// regeleinde-omzetting, geen trimmen, geen BOM.
///
/// OciDeck schrijft een tekstbestand met `utf8.encode` van precies zo'n string
/// (zie `writeStringAtomic`), dus dit is de hash van het bestand op schijf —
/// voor wat OciDeck zélf schrijft. Wat het *inleest* kan een BOM voor de tekst
/// hebben gehad, die de decoder weggooit: daar is dit niet de hash van de bytes,
/// en een document dat met BOM opende schrijft hem terug via
/// `MarkdownDocument.toBytes` (hash: `DocumentIntegrity.hashDocument`).
String sha512HexOfText(String text) => sha512Hex(utf8.encode(text));
