import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

/// Stores a small product image in the existing Firestore image field.
abstract final class ProductImageData {
  static const int maxSourceBytes = 20 * 1024 * 1024;
  static const int maxStoredBytes = 180 * 1024;
  static const int maxDimension = 640;

  static Future<String> prepare(Uint8List source) async {
    if (source.isEmpty || source.length > maxSourceBytes) {
      throw const FormatException('Choose an image smaller than 20 MB.');
    }

    final buffer = await ui.ImmutableBuffer.fromUint8List(source);
    late int width;
    late int height;
    // This callback supports web as well as native image decoders. The codec
    // factory owns and disposes the buffer, including when decoding fails.
    final initialCodec = await ui.instantiateImageCodecWithSize(
      buffer,
      getTargetSize: (intrinsicWidth, intrinsicHeight) {
        final scale = math.min(
          1.0,
          maxDimension / math.max(intrinsicWidth, intrinsicHeight),
        );
        width = math.max(1, (intrinsicWidth * scale).round());
        height = math.max(1, (intrinsicHeight * scale).round());
        return ui.TargetImageSize(width: width, height: height);
      },
    );

    for (var attempt = 0; attempt < 8; attempt++) {
      final codec = attempt == 0
          ? initialCodec
          : await ui.instantiateImageCodec(
              source,
              targetWidth: width,
              targetHeight: height,
              allowUpscaling: false,
            );
      ui.Image? image;
      Uint8List? png;
      try {
        image = (await codec.getNextFrame()).image;
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        png = data?.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      } finally {
        image?.dispose();
        codec.dispose();
      }

      // Base64 adds one third to the size; leave room for the other fields.
      if (png != null && png.length <= maxStoredBytes) {
        return 'data:image/png;base64,${base64Encode(png)}';
      }
      width = math.max(1, (width * 0.75).floor());
      height = math.max(1, (height * 0.75).floor());
    }
    throw const FormatException(
      'Could not resize this image. Choose another image.',
    );
  }
}
