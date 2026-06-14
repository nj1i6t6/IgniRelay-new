// A5 (4-7) DoD D4 — Field_Sessions migration onUpgrade test.
//
// Builds a v12 database with the OLD Outbox_V2 schema (no field_id, no
// Field_Sessions), then reopens it through DatabaseHelper at v13 and asserts
// the v13 onUpgrade block ran: Field_Sessions created + Outbox_V2 gained a
// field_id column (drop + rebuild, ephemeral). Same "build old schema → upgrade
// → assert" pattern the plan references for the 4-3 purge migration.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ignirelay_app/app/db/database_helper.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory tempDir;
  late String dbPath;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('ignirelay_mig_v13_');
    dbPath = p.join(tempDir.path, 'mig.db');
  });

  tearDown(() async {
    await DatabaseHelper().resetForTest();
    DatabaseHelper.testDatabasePathOverride = null;
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('v12 → v13 creates Field_Sessions and adds Outbox_V2.field_id', () async {
    // 1) Seed a v12 DB with the OLD Outbox_V2 (no field_id column) + one row.
    final v12 = await databaseFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 12,
        onCreate: (db, _) async {
          await db.execute('''
            CREATE TABLE Outbox_V2 (
              id                  INTEGER PRIMARY KEY AUTOINCREMENT,
              envelope_id         BLOB NOT NULL UNIQUE,
              event_type          INTEGER NOT NULL,
              priority            INTEGER NOT NULL,
              payload             BLOB NOT NULL,
              created_at_hlc_ms   INTEGER NOT NULL,
              created_at_hlc_ctr  INTEGER NOT NULL,
              expires_at_hlc_ms   INTEGER NOT NULL,
              expires_at_hlc_ctr  INTEGER NOT NULL,
              max_hops            INTEGER NOT NULL,
              enqueued_at_ms      INTEGER NOT NULL
            )
          ''');
          await db.insert('Outbox_V2', <String, Object?>{
            'envelope_id': Uint8List.fromList(List<int>.filled(16, 1)),
            'event_type': 3,
            'priority': 6,
            'payload': Uint8List(0),
            'created_at_hlc_ms': 1,
            'created_at_hlc_ctr': 0,
            'expires_at_hlc_ms': 2,
            'expires_at_hlc_ctr': 0,
            'max_hops': 4,
            'enqueued_at_ms': 1,
          });
        },
      ),
    );
    final oldCols = await v12.rawQuery('PRAGMA table_info(Outbox_V2)');
    expect(oldCols.any((c) => c['name'] == 'field_id'), isFalse,
        reason: 'v12 Outbox_V2 has no field_id yet');
    final oldFs = await v12.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='Field_Sessions'");
    expect(oldFs, isEmpty, reason: 'v12 has no Field_Sessions');
    await v12.close();

    // 2) Reopen through DatabaseHelper at v13 → onUpgrade(12 → 13).
    DatabaseHelper.testDatabasePathOverride = dbPath;
    final db = await DatabaseHelper().database;

    // 3a) Field_Sessions now exists with the expected non-secret columns.
    final fsCols = await db.rawQuery('PRAGMA table_info(Field_Sessions)');
    final fsNames = fsCols.map((c) => c['name'] as String).toSet();
    expect(
      fsNames,
      containsAll(<String>[
        'field_id_hex',
        'display_name',
        'joined_at_ms',
        'cloud_base_url',
      ]),
    );

    // 3b) Outbox_V2 gained field_id and was dropped + rebuilt (row gone).
    final obCols = await db.rawQuery('PRAGMA table_info(Outbox_V2)');
    expect(obCols.any((c) => c['name'] == 'field_id'), isTrue);
    final obRows = await db.query('Outbox_V2');
    expect(obRows, isEmpty,
        reason: 'ephemeral Outbox_V2 is dropped + rebuilt on migration');
  });

  test('fresh install (onCreate) has Field_Sessions + Outbox_V2.field_id',
      () async {
    DatabaseHelper.testDatabasePathOverride = dbPath; // fresh file → onCreate
    final db = await DatabaseHelper().database;

    final fsCols = await db.rawQuery('PRAGMA table_info(Field_Sessions)');
    expect(fsCols, isNotEmpty, reason: 'fresh install creates Field_Sessions');

    final obCols = await db.rawQuery('PRAGMA table_info(Outbox_V2)');
    expect(obCols.any((c) => c['name'] == 'field_id'), isTrue);
  });
}
