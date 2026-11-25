import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:image/image.dart' as img;

/// Turns a picked image into a small square JPEG kept on the user's own profile
/// document (`users/{uid}.photo`), so no file storage is needed.
abstract final class ProfilePhotoData {
  static const int maxSourceBytes = 20 * 1024 * 1024;

  /// Width and height of the stored photo, in pixels.
  static const int side = 256;

  /// The security rules accept at most this many characters.
  static const int maxStoredChars = 120000;

  static const String prefix = 'data:image/jpeg;base64,';

  static Future<String> prepare(Uint8List source) async {
    if (source.isEmpty || source.length > maxSourceBytes) {
      throw const FormatException('Choose an image smaller than 20 MB.');
    }

    // The platform decoder shrinks the image first (fast on web and phones), so the
    // pure-Dart JPEG encoder only handles a small square.
    final buffer = await ui.ImmutableBuffer.fromUint8List(source);
    final codec = await ui.instantiateImageCodecWithSize(
      buffer,
      getTargetSize: (w, h) {
        final scale = math.min(1.0, side / math.min(w, h));
        return ui.TargetImageSize(
          width: math.max(1, (w * scale).round()),
          height: math.max(1, (h * scale).round()),
        );
      },
    );
    ui.Image? decoded;
    ui.Image? square;
    try {
      decoded = (await codec.getNextFrame()).image;
      final w = decoded.width.toDouble();
      final h = decoded.height.toDouble();
      final crop = math.min(w, h);
      final out = math.min(side, crop.round());

      // Centre crop onto white, so transparent images do not turn black as JPEG.
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      final target = ui.Rect.fromLTWH(0, 0, out.toDouble(), out.toDouble());
      canvas.drawRect(target, ui.Paint()..color = const ui.Color(0xFFFFFFFF));
      canvas.drawImageRect(
        decoded,
        ui.Rect.fromLTWH((w - crop) / 2, (h - crop) / 2, crop, crop),
        target,
        ui.Paint()..filterQuality = ui.FilterQuality.high,
      );
      square = await recorder.endRecording().toImage(out, out);
      final rgba = await square.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (rgba == null) throw const FormatException('Could not read this image.');

      final pixels = img.Image.fromBytes(
        width: out,
        height: out,
        bytes: rgba.buffer,
        bytesOffset: rgba.offsetInBytes,
        numChannels: 4,
        order: img.ChannelOrder.rgba,
      );
      for (final quality in [85, 70, 55]) {
        final encoded = '$prefix${base64Encode(img.encodeJpg(pixels, quality: quality))}';
        if (encoded.length <= maxStoredChars) return encoded;
      }
      throw const FormatException('Could not resize this image. Choose another image.');
    } finally {
      decoded?.dispose();
      square?.dispose();
      codec.dispose();
    }
  }

  /// The JPEG bytes of a stored photo, or null when there is none or it is unreadable.
  static Uint8List? decode(Object? stored) {
    if (stored is! String || !stored.startsWith(prefix)) return null;
    try {
      return base64Decode(stored.substring(prefix.length));
    } on FormatException {
      return null;
    }
  }
}
