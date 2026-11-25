import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/services/profile_edits.dart';

void main() {
  Future<FakeFirebaseFirestore> seed() async {
    final db = FakeFirebaseFirestore();
    await db.collection('users').doc('u1').set({'fullName': 'Maryam', 'storeCode': 'S'});
    await db.collection('stores').doc('S').set({'storeName': 'Al Reem', 'ownerUid': 'u1'});
    return db;
  }

  test('owner renames themselves and the store', () async {
    final db = await seed();
    final changed = await ProfileEdits.save(
      db,
      uid: 'u1',
      storeCode: 'S',
      isOwner: true,
      oldName: 'Maryam',
      newName: '  Maryam Ali ',
      oldStoreName: 'Al Reem',
      newStoreName: 'Al Reem Stationery',
    );
    expect(changed, isTrue);
    expect((await db.collection('users').doc('u1').get()).data()!['fullName'], 'Maryam Ali');
    expect(
      (await db.collection('stores').doc('S').get()).data()!['storeName'],
      'Al Reem Stationery',
    );
  });

  test('a cashier can change their name but never the store name', () async {
    final db = await seed();
    await ProfileEdits.save(
      db,
      uid: 'u1',
      storeCode: 'S',
      isOwner: false,
      oldName: 'Maryam',
      newName: 'Noora',
      oldStoreName: 'Al Reem',
      newStoreName: 'Hacked',
    );
    expect((await db.collection('users').doc('u1').get()).data()!['fullName'], 'Noora');
    expect((await db.collection('stores').doc('S').get()).data()!['storeName'], 'Al Reem');
  });

  test('nothing is written when nothing changed', () async {
    final db = await seed();
    final changed = await ProfileEdits.save(
      db,
      uid: 'u1',
      storeCode: 'S',
      isOwner: true,
      oldName: 'Maryam',
      newName: 'Maryam ',
      oldStoreName: 'Al Reem',
      newStoreName: 'Al Reem',
    );
    expect(changed, isFalse);
    expect(
      (await db.collection('users').doc('u1').get()).data()!.containsKey('updatedAt'),
      isFalse,
    );
  });

  test('names must be filled in and at most 60 characters', () {
    expect(ProfileEdits.checkName('  '), isNotNull);
    expect(ProfileEdits.checkName('x' * 61), isNotNull);
    expect(ProfileEdits.checkName('Noora'), isNull);
    expect(ProfileEdits.checkStoreName(''), isNotNull);
    expect(ProfileEdits.checkStoreName('Al Reem'), isNull);
  });

  test('phone is optional and saved only when it changes', () async {
    final db = await seed();
    await ProfileEdits.save(
      db,
      uid: 'u1',
      storeCode: 'S',
      isOwner: false,
      oldName: 'Maryam',
      newName: 'Maryam',
      oldStoreName: 'Al Reem',
      newStoreName: 'Al Reem',
      newPhone: ' +973 3300 0000 ',
    );
    expect((await db.collection('users').doc('u1').get()).data()!['phone'], '+973 3300 0000');
    expect(ProfileEdits.checkPhone(''), isNull, reason: 'optional');
    expect(ProfileEdits.checkPhone('+973 3300-0000'), isNull);
    expect(ProfileEdits.checkPhone('abc'), isNotNull);
    expect(ProfileEdits.checkPhone('12'), isNotNull);
  });

  test('a confirmed new email is copied to the profile once', () async {
    final db = await seed();
    await db.collection('users').doc('u1').update({'email': 'old@test.invalid'});
    expect(
      await ProfileEdits.syncEmail(
        db,
        uid: 'u1',
        profileEmail: 'old@test.invalid',
        authEmail: 'New@Test.invalid',
      ),
      isTrue,
    );
    expect((await db.collection('users').doc('u1').get()).data()!['email'], 'new@test.invalid');
    expect(
      await ProfileEdits.syncEmail(
        db,
        uid: 'u1',
        profileEmail: 'new@test.invalid',
        authEmail: 'new@test.invalid',
      ),
      isFalse,
    );
    expect(ProfileEdits.checkEmail('noora@shop.bh'), isNull);
    expect(ProfileEdits.checkEmail('noora@'), isNotNull);
  });
}
