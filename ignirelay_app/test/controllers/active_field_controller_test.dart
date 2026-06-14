// A5 (4-7) — ActiveFieldController: join / leave / setActive / initialize and
// the shared FieldKeyStore the production dispatcher holds by reference.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ignirelay_app/app/controllers/active_field_controller.dart';
import 'package:ignirelay_app/app/crypto/field_auth_v2.dart';
import 'package:ignirelay_app/app/db/database_helper.dart';
import 'package:ignirelay_app/app/services/anon_identity.dart'
    show SecureKvStore;
import 'package:ignirelay_app/app/services/field_session_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

final Uint8List _secretA = Uint8List.fromList(List<int>.filled(32, 0xA1));
final Uint8List _secretB = Uint8List.fromList(List<int>.filled(32, 0xB2));

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
    DatabaseHelper.testDatabasePathOverride = inMemoryDatabasePath;
  });

  setUp(() async {
    await DatabaseHelper().resetForTest();
  });

  ActiveFieldController makeController(SecureKvStore kv) => ActiveFieldController(
        store: FieldSessionStore(db: DatabaseHelper(), secureStore: kv),
      );

  test('initialize with no sessions → no active field + empty key store',
      () async {
    final c = makeController(_InMemorySecureKv());
    await c.initialize();
    expect(c.hasActiveField, isFalse);
    expect(c.active, isNull);
    expect(c.keyStore.joinedFieldCount, 0);
  });

  test('joinBySecret sets active + populates the shared key store', () async {
    final c = makeController(_InMemorySecureKv());
    var notified = 0;
    c.addListener(() => notified++);

    final f = await c.joinBySecret(_secretA, displayName: 'A');

    expect(c.active?.fieldIdHex, f.fieldIdHex);
    expect(c.keyStore.isJoined(f.fieldId), isTrue);
    expect(c.keyStore.macKeyFor(f.fieldId), isNotNull);
    expect(notified, greaterThan(0));

    final expectedId = await FieldAuthV2.deriveFieldId(_secretA);
    expect(f.fieldId, orderedEquals(expectedId));
    final expectedKey = await FieldAuthV2.deriveFieldMacKey(_secretA);
    expect(f.macKey, orderedEquals(expectedKey));
  });

  test('setActive switches the active sending field; both stay joined',
      () async {
    final c = makeController(_InMemorySecureKv());
    final a = await c.joinBySecret(_secretA, displayName: 'A');
    final b = await c.joinBySecret(_secretB, displayName: 'B');
    expect(c.active?.fieldIdHex, b.fieldIdHex,
        reason: 'most recent join becomes active');

    c.setActive(a.fieldIdHex);
    expect(c.active?.fieldIdHex, a.fieldIdHex);

    // Receive side resolves BOTH joined fields regardless of which is active.
    expect(c.macKeyForFieldId(a.fieldId), isNotNull);
    expect(c.macKeyForFieldId(b.fieldId), isNotNull);
  });

  test('leave removes the field from the key store + falls active back',
      () async {
    final c = makeController(_InMemorySecureKv());
    final a = await c.joinBySecret(_secretA, displayName: 'A');
    final b = await c.joinBySecret(_secretB, displayName: 'B'); // active = b

    await c.leave(b.fieldIdHex);
    expect(c.keyStore.isJoined(b.fieldId), isFalse);
    expect(c.macKeyForFieldId(b.fieldId), isNull);
    expect(c.active?.fieldIdHex, a.fieldIdHex, reason: 'fell back to a');

    await c.leave(a.fieldIdHex);
    expect(c.hasActiveField, isFalse);
    expect(c.keyStore.joinedFieldCount, 0);
  });

  test('initialize re-derives persisted fields after a restart', () async {
    final kv = _InMemorySecureKv();
    final first = makeController(kv);
    final a = await first.joinBySecret(_secretA, displayName: 'A');

    // A fresh controller over the SAME store/db/secure-kv = a process restart.
    final second = makeController(kv);
    await second.initialize();

    expect(second.hasActiveField, isTrue);
    expect(second.active?.fieldIdHex, a.fieldIdHex);
    expect(second.keyStore.isJoined(a.fieldId), isTrue);
    expect(second.keyStore.macKeyFor(a.fieldId), orderedEquals(a.macKey));
  });
}

class _InMemorySecureKv implements SecureKvStore {
  final Map<String, String> map = <String, String>{};
  @override
  Future<String?> read(String key) async => map[key];
  @override
  Future<void> write(String key, String value) async => map[key] = value;
  @override
  Future<void> delete(String key) async => map.remove(key);
}
