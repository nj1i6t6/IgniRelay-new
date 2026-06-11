import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const String _kStorageKey = 'anon_user_id_v1';

class AnonIdentity {
  final FlutterSecureStorage _storage;
  Uint8List? _cached;

  AnonIdentity({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  Future<Uint8List> getOrCreate() async {
    if (_cached != null) return _cached!;
    final existing = await _storage.read(key: _kStorageKey);
    if (existing != null && existing.isNotEmpty) {
      _cached = base64.decode(existing);
      return _cached!;
    }
    final rng = Random.secure();
    final id = Uint8List(16);
    for (var i = 0; i < 16; i++) {
      id[i] = rng.nextInt(256);
    }
    await _storage.write(key: _kStorageKey, value: base64.encode(id));
    _cached = id;
    return id;
  }

  @visibleForTesting
  void resetForTest() {
    _cached = null;
  }
}
