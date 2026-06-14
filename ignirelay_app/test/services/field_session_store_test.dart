// A5 (4-7) — FieldSessionStore persistence (secret in secure storage, metadata
// in SQLite Field_Sessions). DoD prohibition: secret never in SQLite plaintext.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ignirelay_app/app/crypto/field_auth_v2.dart';
import 'package:ignirelay_app/app/db/database_helper.dart';
import 'package:ignirelay_app/app/services/anon_identity.dart'
    show SecureKvStore;
import 'package:ignirelay_app/app/services/field_session_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
    DatabaseHelper.testDatabasePathOverride = inMemoryDatabasePath;
  });

  setUp(() async {
    await DatabaseHelper().resetForTest();
  });

  test('join puts the secret in secure storage, metadata in SQLite (no secret)',
      () async {
    final kv = _InMemorySecureKv();
    final store = FieldSessionStore(db: DatabaseHelper(), secureStore: kv);
    final secret = Uint8List.fromList(List<int>.filled(32, 0x11));

    final session = await store.join(secret, displayName: 'Alpha');
    final fieldId = await FieldAuthV2.deriveFieldId(secret);
    final hex = _hex(fieldId);

    expect(session.fieldIdHex, hex);
    expect(session.displayName, 'Alpha');

    // Secret in secure storage under field_secret_<hex>.
    expect(kv.map.containsKey('${FieldSessionStore.secretKeyPrefix}$hex'),
        isTrue);

    // SQLite row holds ONLY non-secret metadata (no secret column / value).
    final db = await DatabaseHelper().database;
    final rows = await db.query('Field_Sessions');
    expect(rows.length, 1);
    expect(rows.single['field_id_hex'], hex);
    expect(
      rows.single.keys.toSet(),
      <String>{'field_id_hex', 'display_name', 'joined_at_ms', 'cloud_base_url'},
    );
  });

  test('secretFor round-trips the joined secret; unknown field → null',
      () async {
    final store =
        FieldSessionStore(db: DatabaseHelper(), secureStore: _InMemorySecureKv());
    final secret = Uint8List.fromList(List<int>.generate(32, (i) => i + 1));
    final session = await store.join(secret, displayName: 'B');

    expect(await store.secretFor(session.fieldIdHex), orderedEquals(secret));
    expect(await store.secretFor('00112233445566778899aabbccddeeff'), isNull);
  });

  test('loadAll returns joined sessions oldest-first', () async {
    final store =
        FieldSessionStore(db: DatabaseHelper(), secureStore: _InMemorySecureKv());
    await store.join(Uint8List.fromList(List<int>.filled(32, 1)),
        displayName: 'one', joinedAtMs: 100);
    await store.join(Uint8List.fromList(List<int>.filled(32, 2)),
        displayName: 'two', joinedAtMs: 200);

    final all = await store.loadAll();
    expect(all.map((s) => s.displayName).toList(), <String>['one', 'two']);
  });

  test('leave deletes both the secret and the metadata row', () async {
    final kv = _InMemorySecureKv();
    final store = FieldSessionStore(db: DatabaseHelper(), secureStore: kv);
    final secret = Uint8List.fromList(List<int>.filled(32, 0x22));
    final session = await store.join(secret, displayName: 'gone');

    await store.leave(session.fieldIdHex);

    expect(await store.secretFor(session.fieldIdHex), isNull);
    expect(
        kv.map.containsKey(
            '${FieldSessionStore.secretKeyPrefix}${session.fieldIdHex}'),
        isFalse);
    expect(await store.loadAll(), isEmpty);
  });

  test('join is idempotent on field_id (replace metadata + secret)', () async {
    final store =
        FieldSessionStore(db: DatabaseHelper(), secureStore: _InMemorySecureKv());
    final secret = Uint8List.fromList(List<int>.filled(32, 0x33));
    await store.join(secret, displayName: 'first');
    await store.join(secret, displayName: 'second', cloudBaseUrl: 'https://x');

    final all = await store.loadAll();
    expect(all.length, 1);
    expect(all.single.displayName, 'second');
    expect(all.single.cloudBaseUrl, 'https://x');
  });
}

String _hex(List<int> bytes) {
  final sb = StringBuffer();
  for (final b in bytes) {
    sb.write(b.toRadixString(16).padLeft(2, '0'));
  }
  return sb.toString();
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
