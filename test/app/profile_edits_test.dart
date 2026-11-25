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
}
