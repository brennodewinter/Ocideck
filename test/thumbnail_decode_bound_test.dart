// Een slidestrook-thumbnail is ongeveer 180 px breed. Tot #612 decodeerde hij
// de afbeelding op ware grootte: een telefoonfoto van 4032×3024 kost dan bijna
// 49 MiB, en tien zichtbare thumbnails met verschillende foto's zijn een halve
// gigabyte aan lévende bitmaps die de cache niet weggooit zolang ze in beeld
// staan.
//
// Op desktop is dat een geheugengrafiek die niemand ziet. Op web valt de tab
// om, en web is de demo-route.
//
// Wat hier bewaakt wordt is de grens én zijn beperktheid: alléén de strook
// verkleint. Preview, presentatiemodus en de rasteraar tekenen op ware grootte,
// want daar ís de resolutie het product — een export op 512 px zou een
// stilzwijgende kwaliteitsval zijn die veel erger is dan het geheugen dat we
// besparen.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/utils/image_limits.dart';

void main() {
  test('de gebonden variant vraagt echt een kleinere decode', () {
    // ResizeImage draagt de grens; zonder deze assertie zou een
    // implementatiewissel naar de ongebonden vorm stil doorgaan.
    final bounded = boundedFileImage(File('assets/images/cat-keiko.jpg'), 512);
    expect(bounded, isA<ResizeImage>());
    final resize = bounded as ResizeImage;
    expect(resize.width == 512 || resize.height == 512, isTrue);
  });

  test('512 is fors kleiner dan de gewone decode-cap', () {
    // De verhouding is het punt: de cap bestaat tegen een decodeerbom, niet
    // tegen geheugen per zichtbare thumbnail. 4096 vs 512 is een factor 64 in
    // pixels.
    expect(kMaxImageDecodeDimension, greaterThanOrEqualTo(512 * 8));
  });
}
