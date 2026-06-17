// UI-F3 — Field_Sessions.created_here migration (DB v14).
//
// Proves the owner/participant role column lands correctly across every
// upgrade path, defaults to 0 (participant — the conservative default), and is
// never double-added:
//   • fresh install (onCreate at v14),
//   • v13 → v14 (guarded ALTER backfills the column on the existing table),
//   • v12 → v14 (the <13 block creates Field_Sessions WITH the column, so the
//     guarded <14 block must SKIP the ALTER — a failed guard would throw
//     "duplicate column name", so the test merely running to green proves it).
//
// Uses a real temp-file DB (not :memory:) so the on-disk version survives the
// close/reopen that drives onUpgrade — same pattern as the v13 migration test.

import 'dart:io';

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
    tempDir = await Directory.systemTemp.createTemp('ignirelay_mig_v14_');
    dbPath = p.join(tempDir.path, 'mig.db');
  });

  tearDown(() async {
    await DatabaseHelper().resetForTest();
    DatabaseHelper.testDatabasePathOverride = null;
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Future<bool> hasCreatedHere(dynamic db) async {
    final cols = await db.rawQuery('PRAGMA table_info(Field_Sessions)');
    return cols.any((c) => c['name'] == 'created_here');
  }

  test('fresh install (onCreate) — Field_Sessions has created_here default 0',
      () async {
    DatabaseHelper.testDatabasePathOverride = dbPath; // fresh file → onCreate.
    final db = await DatabaseHelper().database;

    expect(await hasCreatedHere(db), isTrue);

    // A row inserted without created_here defaults to 0 (participant).
    await db.insert('Field_Sessions', <String, Object?>{
      'field_id_hex': 'a' * 32,
      'display_name': 'Fresh',
      'joined_at_ms': 1,
    });
    final rows = await db.query('Field_Sessions');
    expect(rows.single['created_here'], 0);
  });

  test('v13 → v14 — guarded ALTER adds created_here, backfills existing row to 0',
      () async {
    // 1) Seed a v13 DB with the OLD Field_Sessions shape (no created_here).
    final v13 = await databaseFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 13,
        onCreate: (db, _) async {
          await db.execute('''
            CREATE TABLE Field_Sessions (
              field_id_hex   TEXT PRIMARY KEY,
              display_name   TEXT NOT NULL,
              joined_at_ms   INTEGER NOT NULL,
              cloud_base_url TEXT
            )
          ''');
          await db.insert('Field_Sessions', <String, Object?>{
            'field_id_hex': 'b' * 32,
            'display_name': 'Legacy',
            'joined_at_ms': 100,
          });
        },
      ),
    );
    expect(await hasCreatedHere(v13), isFalse, reason: 'v13 has no created_here');
    await v13.close();

    // 2) Reopen through DatabaseHelper at v14 → onUpgrade(13 → 14).
    DatabaseHelper.testDatabasePathOverride = dbPath;
    final db = await DatabaseHelper().database;

    expect(await hasCreatedHere(db), isTrue);
    final rows = await db.query('Field_Sessions');
    expect(rows.single['display_name'], 'Legacy', reason: 'existing row kept');
    expect(rows.single['created_here'], 0,
        reason: 'pre-v14 field defaults to participant');
  });

  test('v12 → v14 — <13 creates table WITH column, <14 guard skips (no double-add)',
      () async {
    // 1) Seed an empty v12 DB. Going 12 → 14 runs the <13 block (which creates
    //    Field_Sessions WITH created_here) and the <14 block (which must SKIP
    //    its ALTER because the column already exists).
    final v12 = await databaseFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(version: 12, onCreate: (db, _) async {}),
    );
    final fs = await v12.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='Field_Sessions'");
    expect(fs, isEmpty, reason: 'v12 has no Field_Sessions');
    await v12.close();

    // 2) Reopen at v14 → onUpgrade(12 → 14). If the <14 guard were missing the
    //    duplicate ALTER would throw here and fail the test.
    DatabaseHelper.testDatabasePathOverride = dbPath;
    final db = await DatabaseHelper().database;

    expect(await hasCreatedHere(db), isTrue);
    await db.insert('Field_Sessions', <String, Object?>{
      'field_id_hex': 'c' * 32,
      'display_name': 'New',
      'joined_at_ms': 200,
    });
    final rows = await db.query('Field_Sessions');
    expect(rows.single['created_here'], 0);
  });
}
