import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:pos_app/screens/profile/profile_screen.dart';
import 'dart:typed_data';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pos_app/services/profile_edits.dart';
import 'package:pos_app/utils/profile_photo_data.dart';

Uint8List png(int w, int h, {int alpha = 255}) {
  final image = img.Image(width: w, height: h, numChannels: 4);
  img.fill(image, color: img.ColorRgba8(21, 93, 252, alpha));
  return img.encodePng(image);
}

void main() {
  testWidgets('a wide photo becomes a small square JPEG the rules accept', (tester) async {
    final stored = await tester.runAsync(() => ProfilePhotoData.prepare(png(1200, 800)));
    expect(stored, startsWith(ProfilePhotoData.prefix));
    expect(stored!.length, lessThanOrEqualTo(ProfilePhotoData.maxStoredChars));
    final jpeg = img.decodeJpg(ProfilePhotoData.decode(stored)!)!;
    expect([jpeg.width, jpeg.height], [256, 256]);
  });

  testWidgets('a small photo is not enlarged, and transparency turns white', (tester) async {
    final stored = await tester.runAsync(() => ProfilePhotoData.prepare(png(90, 120, alpha: 0)));
    final jpeg = img.decodeJpg(ProfilePhotoData.decode(stored)!)!;
    expect([jpeg.width, jpeg.height], [90, 90]);
    final pixel = jpeg.getPixel(45, 45);
    expect(pixel.r, greaterThan(240));
    expect(pixel.b, greaterThan(240));
  });

  testWidgets('empty or unreadable images are refused', (tester) async {
    await tester.runAsync(() async {
      await expectLater(ProfilePhotoData.prepare(Uint8List(0)), throwsFormatException);
      await expectLater(
        ProfilePhotoData.prepare(Uint8List.fromList([1, 2, 3, 4])),
        throwsA(anything),
      );
    });
  });

  test('decode ignores anything that is not a stored JPEG photo', () {
    expect(ProfilePhotoData.decode(null), isNull);
    expect(ProfilePhotoData.decode(''), isNull);
    expect(ProfilePhotoData.decode('https://example.com/a.jpg'), isNull);
    expect(ProfilePhotoData.decode('${ProfilePhotoData.prefix}!!!'), isNull);
  });

  test('the photo is saved on the user only, and can be removed', () async {
    final db = FakeFirebaseFirestore();
    await db.collection('users').doc('u1').set({'fullName': 'Maryam', 'storeCode': 'S'});
    const photo = '${ProfilePhotoData.prefix}AAAA';
    await ProfileEdits.savePhoto(db, uid: 'u1', photo: photo);
    var data = (await db.collection('users').doc('u1').get()).data()!;
    expect(data['photo'], photo);
    expect(data['fullName'], 'Maryam');

    await ProfileEdits.savePhoto(db, uid: 'u1', photo: null);
    data = (await db.collection('users').doc('u1').get()).data()!;
    expect(data.containsKey('photo'), isFalse);
    expect(data['fullName'], 'Maryam');
  });
  testWidgets('avatar reuses image bytes across navigation rebuilds and replaces changed photos', (
    tester,
  ) async {
    final first =
        '${ProfilePhotoData.prefix}${base64Encode(img.encodeJpg(img.Image(width: 4, height: 4)))}';
    final second =
        '${ProfilePhotoData.prefix}${base64Encode(img.encodeJpg(img.Image(width: 5, height: 5)))}';
    Future<void> render(String photo, String name) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: Scaffold(
              body: ProfileAvatar(name: name, photo: photo, onTap: () {}),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await render(first, 'Owner');
    final bytes = (tester.widget<Image>(find.byType(Image)).image as MemoryImage).bytes;
    await render(first, 'Updated name');
    expect(
      identical(bytes, (tester.widget<Image>(find.byType(Image)).image as MemoryImage).bytes),
      isTrue,
    );
    await render(second, 'Updated name');
    expect(
      identical(bytes, (tester.widget<Image>(find.byType(Image)).image as MemoryImage).bytes),
      isFalse,
    );
    await render('', 'Updated name');
    expect(find.byType(Image), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
