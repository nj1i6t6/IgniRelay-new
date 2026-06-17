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

  test('createField → role owner; joinBySecret → participant', () async {
    final c = makeController(_InMemorySecureKv());
    final created = await c.createField(displayName: 'Mine');
    expect(created.field.role, FieldRole.owner);
    expect(c.active?.isOwner, isTrue);

    final joined = await c.joinBySecret(_secretB, displayName: 'Theirs');
    expect(joined.role, FieldRole.participant);
    expect(joined.isOwner, isFalse);
  });

  test('role survives an initialize() reload (owner stays owner)', () async {
    final kv = _InMemorySecureKv();
    final first = makeController(kv);
    final created = await first.createField(displayName: 'Mine');

    final second = makeController(kv);
    await second.initialize();
    expect(second.active?.fieldIdHex, created.field.fieldIdHex);
    expect(second.active?.isOwner, isTrue, reason: 'owner re-derived from DB');
  });

  test('sticky-owner: re-joining an owned field keeps isOwner in memory',
      () async {
    final c = makeController(_InMemorySecureKv());
    final created = await c.createField(displayName: 'Mine');
    final secret = await c.exportSecretForQr(created.field.fieldIdHex);

    // Re-join via the participant path (createdHere defaults false).
    final rejoined = await c.joinBySecret(secret!, displayName: 'Mine again');
    expect(rejoined.isOwner, isTrue, reason: 'owner not downgraded on re-join');
    expect(c.active?.isOwner, isTrue);
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
