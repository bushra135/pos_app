import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/utils/product_image_data.dart';
import 'package:pos_app/widgets/product_image.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Uint8List smallImage;

  setUpAll(() async {
    smallImage = await _createPng(16, 8);
  });

  test(
    'large photos become decodable images within the document budget',
    () async {
      final source = await _createPng(1200, 800, noisy: true);
      final data = await ProductImageData.prepare(source);
      final bytes = Uri.parse(data).data!.contentAsBytes();
      expect(bytes.length, lessThanOrEqualTo(ProductImageData.maxStoredBytes));
      expect(utf8.encode(data).length, lessThan(250 * 1024));
      final codec = await ui.instantiateImageCodec(bytes);
      final image = (await codec.getNextFrame()).image;
      expect(max(image.width, image.height), lessThanOrEqualTo(640));
      expect(image.width / image.height, closeTo(1.5, 0.02));
      image.dispose();
      codec.dispose();
    },
  );

  test(
    'small transparent images retain their dimensions and transparency',
    () async {
      final data = await ProductImageData.prepare(smallImage);
      final codec = await ui.instantiateImageCodec(
        Uri.parse(data).data!.contentAsBytes(),
      );
      final image = (await codec.getNextFrame()).image;
      expect(image.width, 16);
      expect(image.height, 8);
      final rgba = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      expect(rgba!.getUint8(3), 0);
      image.dispose();
      codec.dispose();
    },
  );

  test(
    'invalid files fail instead of producing an unusable saved image',
    () async {
      await expectLater(
        ProductImageData.prepare(Uint8List(0)),
        throwsFormatException,
      );
      await expectLater(
        ProductImageData.prepare(Uint8List.fromList([1, 2, 3])),
        throwsA(anything),
      );
    },
  );

  testWidgets(
    'embedded product images use memory and survive ordinary rebuilds',
    (tester) async {
      final source = 'data:image/png;base64,${base64Encode(smallImage)}';
      Widget build() => MaterialApp(
        home: ProductImage(
          source: source,
          placeholder: const Icon(Icons.inventory),
        ),
      );
      await tester.pumpWidget(build());
      final initial = tester.widget<Image>(find.byType(Image)).image;
      expect(initial, isA<MemoryImage>());
      expect((initial as MemoryImage).bytes, orderedEquals(smallImage));
      await tester.pumpWidget(build());
      expect(tester.widget<Image>(find.byType(Image)).image, same(initial));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'invalid saved data shows a placeholder and recovers after replacement',
    (tester) async {
      Widget build(String source) => MaterialApp(
        home: ProductImage(
          source: source,
          placeholder: const Icon(Icons.inventory),
        ),
      );
      await tester.pumpWidget(build('data:image/png;base64,%%%'));
      expect(find.byIcon(Icons.inventory), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(
        build('data:image/png;base64,${base64Encode(smallImage)}'),
      );
      expect(
        tester.widget<Image>(find.byType(Image)).image,
        isA<MemoryImage>(),
      );
      await tester.pumpWidget(build(''));
      expect(find.byIcon(Icons.inventory), findsOneWidget);
    },
  );
}

Future<Uint8List> _createPng(
  int width,
  int height, {
  bool noisy = false,
}) async {
  final pixels = Uint8List(width * height * 4);
  final random = Random(23);
  for (var offset = 0; offset < pixels.length; offset += 4) {
    pixels[offset] = noisy ? random.nextInt(256) : 30;
    pixels[offset + 1] = noisy ? random.nextInt(256) : 130;
    pixels[offset + 2] = noisy ? random.nextInt(256) : 170;
    pixels[offset + 3] = noisy ? 255 : 0;
  }
  final buffer = await ui.ImmutableBuffer.fromUint8List(pixels);
  final descriptor = ui.ImageDescriptor.raw(
    buffer,
    width: width,
    height: height,
    pixelFormat: ui.PixelFormat.rgba8888,
  );
  final codec = await descriptor.instantiateCodec();
  final image = (await codec.getNextFrame()).image;
  try {
    final data = (await image.toByteData(format: ui.ImageByteFormat.png))!;
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  } finally {
    image.dispose();
    codec.dispose();
    descriptor.dispose();
    buffer.dispose();
  }
}
