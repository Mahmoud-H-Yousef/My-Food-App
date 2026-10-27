// Draws the My Food launcher icon: green rounded square, white plate,
// fork on the left, knife on the right.
//
//   dart run tools/make_icon.dart
//
// Writes assets/icon/icon.png (full icon) and assets/icon/icon_foreground.png
// (transparent, for Android adaptive icons on a green background).
import 'dart:io';

import 'package:image/image.dart' as img;

final green = img.ColorRgba8(0x16, 0xA3, 0x4A, 255);
final white = img.ColorRgba8(255, 255, 255, 255);
final mint = img.ColorRgba8(0xBB, 0xF7, 0xD0, 255);

/// Draws the plate and cutlery in a 64-unit design space scaled by [s] and shifted by [ox], [oy].
void drawMark(img.Image im, double s, double ox, double oy) {
  int x(num v) => (ox + v * s).round();
  int y(num v) => (oy + v * s).round();
  int r(num v) => (v * s).round();

  // plate
  img.fillCircle(im, x: x(32), y: y(32), radius: r(15), color: white, antialias: true);
  img.fillCircle(im, x: x(32), y: y(32), radius: r(10.6), color: mint, antialias: true);
  img.fillCircle(im, x: x(32), y: y(32), radius: r(9.4), color: white, antialias: true);

  // fork: three tines, a bridge and a handle
  final t = (2.4 * s);
  for (final tx in [11.0, 13.5, 16.0]) {
    img.drawLine(im, x1: x(tx), y1: y(18), x2: x(tx), y2: y(26), color: white, thickness: t, antialias: true);
    img.fillCircle(im, x: x(tx), y: y(18), radius: (t / 2).round(), color: white, antialias: true);
  }
  img.fillRect(im, x1: x(11) - (t / 2).round(), y1: y(25), x2: x(16) + (t / 2).round(), y2: y(28.5), color: white, radius: r(1.6));
  img.drawLine(im, x1: x(13.5), y1: y(28), x2: x(13.5), y2: y(46), color: white, thickness: t * 1.05, antialias: true);
  img.fillCircle(im, x: x(13.5), y: y(46), radius: (t / 2).round(), color: white, antialias: true);

  // knife: curved blade then handle
  img.fillPolygon(im, vertices: [
    img.Point(x(52.8), y(17)),
    img.Point(x(51.6), y(17.8)),
    img.Point(x(50.6), y(19.2)),
    img.Point(x(49.8), y(21)),
    img.Point(x(49.3), y(23.5)),
    img.Point(x(49.2), y(26)),
    img.Point(x(49.4), y(28.5)),
    img.Point(x(50.0), y(31.5)),
    img.Point(x(53.4), y(31.5)),
    img.Point(x(53.4), y(17.5)),
  ], color: white);
  img.drawLine(im, x1: x(52.2), y1: y(31), x2: x(52.2), y2: y(46), color: white, thickness: t * 1.05, antialias: true);
  img.fillCircle(im, x: x(52.2), y: y(46), radius: (t / 2).round(), color: white, antialias: true);
}

void main() {
  const size = 1024;
  Directory('assets/icon').createSync(recursive: true);

  final full = img.Image(width: size, height: size, numChannels: 4);
  img.fill(full, color: img.ColorRgba8(0, 0, 0, 0));
  img.fillRect(full, x1: 0, y1: 0, x2: size - 1, y2: size - 1, color: green, radius: 240);
  drawMark(full, size / 64, 0, 0);
  File('assets/icon/icon.png').writeAsBytesSync(img.encodePng(full));

  // Adaptive icons crop to the middle ~66%, so draw the mark smaller and centered.
  final fg = img.Image(width: size, height: size, numChannels: 4);
  img.fill(fg, color: img.ColorRgba8(0, 0, 0, 0));
  const scale = 0.62;
  drawMark(fg, size / 64 * scale, size * (1 - scale) / 2, size * (1 - scale) / 2);
  File('assets/icon/icon_foreground.png').writeAsBytesSync(img.encodePng(fg));
  stdout.writeln('icons written');
}
