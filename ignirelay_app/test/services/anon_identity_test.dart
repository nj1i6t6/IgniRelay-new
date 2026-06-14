// AnonIdentityService — verifies the 16-byte anon_user_id is minted once,
// persisted, stable across launches, and decoupled from any signing key.

import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ignirelay_app/app/services/anon_identity.dart';

class _FakeKvStore implements SecureKvStore {
  final Map<String, String> m = {};
  int writes = 0;
  @override
  Future<String?> read(String key) async => m[key];
  @override
  Future<void> write(String key, String value) async {
    writes++;
    m[key] = value;
  }

  @override
  Future<void> delete(String key) async => m.remove(key);
}

void main() {
  test('getOrCreate mints a 16-byte id and persists it once', () async {
    final store = _FakeKvStore();
    final svc = AnonIdentityService(store: store);

    final a = await svc.getOrCreate();
    expect(a.length, AnonIdentityService.idBytes);
    expect(a.length, 16);
    expect(store.m.containsKey(AnonIdentityService.storageKey), isTrue);

    // Second call returns the SAME id and does not re-write.
    final b = await svc.getOrCreate();
    expect(b, orderedEquals(a));
    expect(store.writes, 1, reason: 'id must be minted exactly once');
  });

  test('id survives a fresh service instance (persistence)', () async {
    final store = _FakeKvStore();
    final first = await AnonIdentityService(store: store).getOrCreate();

    // New instance, same backing store = simulated relaunch.
    final second = await AnonIdentityService(store: store).getOrCreate();
    expect(second, orderedEquals(first));
  });

  test('is generated from the CSPRNG, not derived from a public key', () async {
    // Two devices (independent stores) get different ids — proves it is random,
    // not a deterministic function of some shared/public input.
    final a = await AnonIdentityService(store: _FakeKvStore()).getOrCreate();
    final b = await AnonIdentityService(store: _FakeKvStore()).getOrCreate();
    expect(a, isNot(orderedEquals(b)));

    // Deterministic RNG → deterministic id (confirms RNG is the only source).
    final seeded = AnonIdentityService(
      store: _FakeKvStore(),
      random: Random(42),
    );
    final id = await seeded.getOrCreate();
    final expected = Uint8List(16);
    final rng = Random(42);
    for (var i = 0; i < 16; i++) {
      expected[i] = rng.nextInt(256);
    }
    expect(id, orderedEquals(expected));
  });

  test('a corrupt stored value is replaced with a fresh 16-byte id', () async {
    final store = _FakeKvStore();
    store.m[AnonIdentityService.storageKey] = 'not-hex-zz';
    final svc = AnonIdentityService(store: store);

    final id = await svc.getOrCreate();
    expect(id.length, 16);
    // Stored value is now valid 32-char hex.
    expect(store.m[AnonIdentityService.storageKey]!.length, 32);
  });

  test('rotate is an explicit not-yet-implemented seam', () async {
    final svc = AnonIdentityService(store: _FakeKvStore());
    expect(() => svc.rotate(), throwsA(isA<UnimplementedError>()));
  });
}
