import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  // ================= DATABASE =================
  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('panen.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 9,
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
    );
  }

  Future<void> kirimKeLaravel(Map<String, dynamic> data) async {
    try {
      final response = await http.post(
        Uri.parse("http://10.0.2.2:8000/api/panen"),
        headers: {
          "Accept": "application/json",
        },
        body: {
          "pemanen": data['pemanen'].toString(),
          "blok": data['blok'].toString(),
          "matang": data['matang'].toString(),
          "mentah": data['mentah'].toString(),
          "brondolan": data['brondolan'].toString(),
          "kcs": data['kcs'].toString(),
          "afdeling": data['afdeling'].toString(),
          "tanggal": data['tanggal'].toString(),
        },
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        print("✅ Laravel sync berhasil");
      } else {
        print("❌ Laravel error: ${response.body}");
      }
    } catch (e) {
      print("❌ Gagal kirim ke Laravel: $e");
    }
  }
  // ================= CREATE =================
  Future<void> _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS panen (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        tanggal TEXT,
        waktu TEXT,
        pemanen TEXT,
        blok TEXT,
        tph TEXT,
        thn_tanam TEXT,
        kcs TEXT,
        afdeling TEXT,
        brondolan TEXT,
        mentah TEXT,
        matang TEXT,
        catatan TEXT,
        foto TEXT,
        latitude TEXT,
        longitude TEXT,
        tracking TEXT,
        user TEXT,
        mandor TEXT,
        sync_status TEXT,
        status TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS trip (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        tanggal TEXT,
        no_plat TEXT,
        sopir TEXT,
        afdeling TEXT,
        kcs TEXT,
        sync_status TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS trip_detail (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        trip_id INTEGER,
        panen_id INTEGER
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS pks (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        trip_id INTEGER,
        berat_netto REAL,
        waktu_timbang TEXT,
        no_plat TEXT,
        sopir TEXT,
        afdeling TEXT,
        tanggal_trip TEXT,
        kcs TEXT,
        sync_status TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS harvesters_local (
        id TEXT PRIMARY KEY,
        nama TEXT,
        afdeling TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS blocks_local (
        id TEXT PRIMARY KEY,
        kcs TEXT,
        blok TEXT
      )
    ''');
  }

  // ================= UPGRADE =================
  Future<void> _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute("ALTER TABLE panen ADD COLUMN mandor TEXT");
    }
    if (oldVersion < 3) {
      await db.execute("ALTER TABLE trip ADD COLUMN kcs TEXT");
    }
    if (oldVersion < 4) {
      await db.execute("ALTER TABLE panen ADD COLUMN thn_tanam TEXT");
    }
    if (oldVersion < 5) {
      try { await db.execute("ALTER TABLE trip ADD COLUMN sync_status TEXT DEFAULT 'offline'"); } catch(_) {}
      try { await db.execute("ALTER TABLE pks ADD COLUMN sync_status TEXT DEFAULT 'offline'"); } catch(_) {}
    }
    if (oldVersion < 6) {
      try { await db.execute("ALTER TABLE pks ADD COLUMN no_plat TEXT"); } catch(_) {}
      try { await db.execute("ALTER TABLE pks ADD COLUMN sopir TEXT"); } catch(_) {}
      try { await db.execute("ALTER TABLE pks ADD COLUMN afdeling TEXT"); } catch(_) {}
      try { await db.execute("ALTER TABLE pks ADD COLUMN tanggal_trip TEXT"); } catch(_) {}
      try { await db.execute("ALTER TABLE pks ADD COLUMN kcs TEXT"); } catch(_) {}
    }
    if (oldVersion < 7) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS harvesters_local (
          id TEXT PRIMARY KEY,
          nama TEXT,
          afdeling TEXT
        )
      ''');
    }
    if (oldVersion < 8) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS blocks_local (
          id TEXT PRIMARY KEY,
          kcs TEXT,
          blok TEXT
        )
      ''');
    }
    if (oldVersion < 9) {
      try {
        await db.execute("ALTER TABLE panen ADD COLUMN waktu TEXT");
      } catch (_) {}
    }
  }

  // ================= FIREBASE =================
  Future<void> clearAllData() async {
    final db = await database;
    await db.delete('panen');
    await db.delete('trip');
    await db.delete('trip_detail');
    await db.delete('pks');
    await db.delete('harvesters_local');
    await db.delete('blocks_local');
    print("🔥 Seluruh database lokal telah dibersihkan");
  }

  /// Paksa semua data lokal untuk diupload ulang ke cloud
  Future<void> resetSyncStatus() async {
    final db = await database;
    await db.update('panen', {'sync_status': 'offline'});
    await db.update('trip', {'sync_status': 'offline'});
    await db.update('pks', {'sync_status': 'offline'});
    print("🔄 Status sinkronisasi telah direset ke offline");
  }

  Future<void> kirimKeFirebase(Map<String, dynamic> data) async {
    try {
      await FirebaseFirestore.instance.collection('panen').add(data);
      print("✅ Data berhasil dikirim ke Firebase");
    } catch (e) {
      print("❌ Gagal kirim: $e");
    }
  }

  // ================= INSERT PANEN =================
  Future<int> insertPanen(Map<String, dynamic> data) async {
    final db = await database;

    // 🔥 Sync Status
    data['sync_status'] = 'offline';
    data['status'] = 'pending';

    int id = await db.insert('panen', data);

    // 🔥 Coba kirim langsung ke Firebase jika sedang online
    try {
      final user = data['user'] ?? 'unknown';
      final docId = "${user}_$id"; 

      // Buat copy data untuk Firebase agar tidak merubah data asli (yang berisi path)
      Map<String, dynamic> syncData = Map.from(data);
      
      // Konversi Path ke Base64 untuk Web Admin jika kolom foto berisi path lokal
      if (syncData['foto'] != null && syncData['foto'].isNotEmpty && !syncData['foto'].startsWith('data:image')) {
        File f = File(syncData['foto']);
        if (await f.exists()) {
          int fileSize = await f.length();
          if (fileSize < 800000) { // Hanya kirim jika < 800KB (Base64 akan membengkak ke ~1MB)
            List<int> imageBytes = await f.readAsBytes();
            syncData['foto'] = "data:image/jpeg;base64,${base64Encode(imageBytes)}";
          } else {
            syncData['foto'] = ""; // Kosongkan foto jika terlalu besar agar data teks tetap masuk
            print("⚠️ Foto terlalu besar (${(fileSize/1024/1024).toStringAsFixed(2)}MB), mengirim data tanpa foto.");
          }
        }
      }

      await FirebaseFirestore.instance.collection('panen').doc(docId).set(syncData);
      
      // Jika sukses, langsung tandai sudah sync
      await db.update('panen', {'sync_status': 'synced'}, where: 'id = ?', whereArgs: [id]);
      print("✅ Data otomatis tersinkron ke Firebase (ID: $docId)");
    } catch (e) {
      print("ℹ️ Mode offline: Data disimpan lokal (ID: $id)");
    }

    return id;
  }

  // ================= GET =================
  Future<List<Map<String, dynamic>>> getAllPanen() async {
    final db = await database;
    return await db.query('panen', orderBy: 'id DESC');
  }

  // ================= UPDATE =================
  Future<int> updatePanen(int id, Map<String, dynamic> data) async {
    final db = await database;
    return await db.update(
      'panen',
      data,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // ================= DELETE =================
  Future<int> deletePanen(int id) async {
    final db = await database;
    return await db.delete(
      'panen',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // ================= ACC / REJECT =================
  Future<void> accPanen(int id) async {
    final db = await database;
    await db.update(
      'panen',
      {'status': 'ACC', 'sync_status': 'update'},
      where: 'id = ?',
      whereArgs: [id],
    );
    // Langsung coba sinkronkan status ke Firebase
    syncData();
  }

  Future<void> rejectPanen(int id) async {
    final db = await database;
    await db.update(
      'panen',
      {'status': 'REJECT', 'sync_status': 'update'},
      where: 'id = ?',
      whereArgs: [id],
    );
    // Langsung coba sinkronkan status ke Firebase
    syncData();
  }

  // ================= TRACKING =================
  String encodeTracking(List<Map<String, dynamic>> tracking) {
    return jsonEncode(tracking);
  }

  List<Map<String, dynamic>> decodeTracking(String? tracking) {
    if (tracking == null || tracking.isEmpty) return [];

    try {
      return List<Map<String, dynamic>>.from(jsonDecode(tracking));
    } catch (e) {
      return [];
    }
  }

  // ================= GET PANEN BY KCS & TANGGAL =================
  Future<List<Map<String, dynamic>>> getPanenByKcsAndTanggal(
      String kcs,
      String tanggal,
      ) async {
    final db = await database;

    return await db.rawQuery('''
    SELECT * FROM panen
    WHERE kcs = ?
    AND status = 'ACC'
    AND substr(tanggal,1,10) = ?
    AND id NOT IN (
      SELECT panen_id FROM trip_detail
    )
    ORDER BY id DESC
  ''', [kcs, tanggal]);
  }
  // ================= AMBIL DATA HARVESTERS & BLOCKS DARI FIREBASE =================
  Future<void> syncHarvesters() async {
    try {
      final snapshot = await FirebaseFirestore.instance.collection('harvesters').get();
      final db = await database;
      
      final batch = db.batch();
      // Bersihkan data lama agar sinkron sempurna
      batch.delete('harvesters_local');
      
      for (var doc in snapshot.docs) {
        final data = doc.data();
        batch.insert('harvesters_local', {
          'id': doc.id,
          'nama': data['nama'],
          'afdeling': data['afdeling'],
        });
      }
      
      await batch.commit(noResult: true);
      print("✅ Berhasil sinkron ${snapshot.docs.length} pemanen ke lokal");
    } catch (e) {
      print("❌ Gagal sinkron harvesters: $e");
    }
  }

  Future<void> syncBlocks() async {
    try {
      final snapshot = await FirebaseFirestore.instance.collection('blocks').get();
      final db = await database;
      
      final batch = db.batch();
      batch.delete('blocks_local');
      
      for (var doc in snapshot.docs) {
        final data = doc.data();
        batch.insert('blocks_local', {
          'id': doc.id,
          'kcs': data['kcs'],
          'blok': data['blok'],
        });
      }
      
      await batch.commit(noResult: true);
      print("✅ Berhasil sinkron ${snapshot.docs.length} blok ke lokal");
    } catch (e) {
      print("❌ Gagal sinkron blocks: $e");
    }
  }

  Future<List<String>> getHarvestersByAfdeling(String afdeling) async {
    final db = await database;
    final res = await db.query(
      'harvesters_local',
      where: 'afdeling = ?',
      whereArgs: [afdeling],
      orderBy: 'nama ASC',
    );
    return res.map((e) => e['nama'].toString()).toList();
  }

  Future<Map<String, List<String>>> getAllBlocksGroupedByKCS() async {
    final db = await database;
    final res = await db.query('blocks_local', orderBy: 'kcs ASC, blok ASC');
    
    Map<String, List<String>> grouped = {};
    for (var row in res) {
      String kcs = row['kcs'].toString();
      String blok = row['blok'].toString();
      if (!grouped.containsKey(kcs)) {
        grouped[kcs] = [];
      }
      grouped[kcs]!.add(blok);
    }
    return grouped;
  }

  Future<void> ambilDataDariFirebase() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('panen')
          .get();

      if (snapshot.docs.isEmpty) {
        print("Firebase kosong, skip sync!");
        return;
      }

      final db = await database;

      for (var doc in snapshot.docs) {
        Map<String, dynamic> data = Map.from(doc.data());
        // 🔥 FORCE STATUS: Jika data ada di Firebase, maka statusnya HARUS 'synced'
        data['sync_status'] = 'synced';
        
        await db.insert(
          'panen',
          data,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      print("✅ Berhasil menarik ${snapshot.docs.length} data dari Firebase");
    } catch (e) {
      print("❌ Gagal menarik data dari Firebase: $e");
    }
  }

  // ================= SYNC KE FIREBASE =================
  Future<void> syncData() async {
    final db = await database;

    // 1. Sync Panen
    final dataList = await db.query(
      'panen',
      where: "sync_status IS NULL OR sync_status = 'offline' OR sync_status = 'update' OR sync_status != 'synced'",
    );

    for (var data in dataList) {
      try {
        final Map<String, dynamic> dataMap = Map.from(data);
        final id = dataMap['id'];
        final user = dataMap['user'] ?? 'unknown';
        final String docId = "${user}_$id";

        Map<String, dynamic> uploadMap = Map.from(dataMap);
        uploadMap['sync_status'] = 'synced';
        // Pastikan status juga ikut terkirim jika sudah di-ACC/REJECT secara lokal
        if (uploadMap['status'] == null) {
          uploadMap['status'] = 'pending';
        }

        // Konversi Path ke Base64 untuk Web Admin sebelum sync manual
        if (uploadMap['foto'] != null && uploadMap['foto'].isNotEmpty && !uploadMap['foto'].startsWith('data:image')) {
          File f = File(uploadMap['foto']);
          if (await f.exists()) {
            int fileSize = await f.length();
            if (fileSize < 800000) {
              List<int> imageBytes = await f.readAsBytes();
              uploadMap['foto'] = "data:image/jpeg;base64,${base64Encode(imageBytes)}";
            } else {
              uploadMap['foto'] = ""; 
              print("⚠️ Foto ID $id terlalu besar, dikirim tanpa foto.");
            }
          }
        }

        await FirebaseFirestore.instance.collection('panen').doc(docId).set(uploadMap);
        kirimKeLaravel(uploadMap).catchError((e) => print("Laravel skip: $e"));

        await db.update('panen', {'sync_status': 'synced'}, where: 'id = ?', whereArgs: [id]);
        print("✅ Panen Sync ID: $id");
      } catch (e) {
        print("❌ Gagal sync Panen ID ${data['id']}: $e");
      }
    }

    // 2. Sync Trip
    final tripList = await db.query('trip', where: "sync_status IS NULL OR sync_status != 'synced'");
    for (var trip in tripList) {
      try {
        int tId = trip['id'] as int;
        String kcs = (trip['kcs'] ?? 'unknown').toString();
        final String docId = "trip_${kcs}_$tId";

        final totals = await db.rawQuery('''
          SELECT 
            COUNT(p.id) as jumlah_panen,
            SUM(CAST(p.matang AS INTEGER)) as total_janjang,
            SUM(CAST(p.brondolan AS INTEGER)) as total_brondolan
          FROM trip_detail td
          JOIN panen p ON p.id = td.panen_id
          WHERE td.trip_id = ?
        ''', [tId]);

        Map<String, dynamic> syncData = Map.from(trip);
        syncData['jumlah_panen'] = totals.first['jumlah_panen'] ?? 0;
        syncData['total_janjang'] = totals.first['total_janjang'] ?? 0;
        syncData['total_brondolan'] = totals.first['total_brondolan'] ?? 0;
        syncData['kendaraan'] = trip['no_plat'];
        syncData['sync_status'] = 'synced';

        await FirebaseFirestore.instance.collection('trips').doc(docId).set(syncData);
        await db.update('trip', {'sync_status': 'synced'}, where: 'id = ?', whereArgs: [tId]);
        print("✅ Trip Sync ID: $docId");
      } catch (e) {
        print("❌ Gagal sync Trip ID ${trip['id']}: $e");
      }
    }

    // 3. Sync PKS
    final pksList = await db.query('pks', where: "sync_status IS NULL OR sync_status != 'synced'");
    for (var pks in pksList) {
      try {
        int tId = pks['trip_id'] as int;
        final tripInfo = await db.query('trip', where: 'id = ?', whereArgs: [tId]);
        String kcs = tripInfo.isNotEmpty ? (tripInfo.first['kcs'] ?? 'unknown').toString() : 'unknown';
        final String docId = "pks_${kcs}_$tId";
        
        Map<String, dynamic> syncData = Map.from(pks);
        if (tripInfo.isNotEmpty) {
          syncData['no_plat'] = tripInfo.first['no_plat'];
          syncData['kendaraan'] = tripInfo.first['no_plat']; 
          syncData['sopir'] = tripInfo.first['sopir'];
          syncData['afdeling'] = tripInfo.first['afdeling'];
          syncData['tanggal_trip'] = tripInfo.first['tanggal'];
          syncData['kcs'] = tripInfo.first['kcs'];
        }
        syncData['sync_status'] = 'synced';

        await FirebaseFirestore.instance.collection('pks').doc(docId).set(syncData);
        await db.update('pks', {'sync_status': 'synced'}, where: 'trip_id = ?', whereArgs: [tId]);
        print("✅ PKS Sync ID: $docId");
      } catch (e) {
        print("❌ Gagal sync PKS TripID ${pks['trip_id']}: $e");
      }
    }
  }

  // ================= TRIP & PKS HELPERS =================
  Future<int> insertTrip(Map<String, dynamic> data, List<int> panenIds) async {
    final db = await database;
    data['sync_status'] = 'offline';
    int tripId = await db.insert('trip', data);

    for (var panenId in panenIds) {
      await db.insert('trip_detail', {'trip_id': tripId, 'panen_id': panenId});
    }

    // Attempt direct sync
    try {
      final totals = await db.rawQuery('''
        SELECT COUNT(p.id) as jumlah_panen, SUM(CAST(p.matang AS INTEGER)) as total_janjang,
        SUM(CAST(p.brondolan AS INTEGER)) as total_brondolan FROM trip_detail td
        JOIN panen p ON p.id = td.panen_id WHERE td.trip_id = ?
      ''', [tripId]);

      Map<String, dynamic> syncMap = Map.from(data);
      syncMap['id'] = tripId;
      syncMap['jumlah_panen'] = totals.first['jumlah_panen'] ?? 0;
      syncMap['total_janjang'] = totals.first['total_janjang'] ?? 0;
      syncMap['total_brondolan'] = totals.first['total_brondolan'] ?? 0;
      syncMap['kendaraan'] = data['no_plat']; // Unifikasi field name
      syncMap['sync_status'] = 'synced';

      String kcs = (data['kcs'] ?? 'unknown').toString();
      final String docId = "trip_${kcs}_$tripId";

      await FirebaseFirestore.instance.collection('trips').doc(docId).set(syncMap);
      await db.update('trip', {'sync_status': 'synced'}, where: 'id = ?', whereArgs: [tripId]);
    } catch (_) {}

    return tripId;
  }

  // ================= UPSERT PKS =================
  Future<void> upsertPks(Map<String, dynamic> data) async {
    final db = await database;
    dynamic tripId = data['trip_id'];
    data['sync_status'] = 'offline';

    // Enrichment Data for Local Fallback
    final tripInfo = await db.query('trip', where: 'id = ?', whereArgs: [tripId]);
    if (tripInfo.isNotEmpty) {
      data['no_plat'] = tripInfo.first['no_plat'];
      data['sopir'] = tripInfo.first['sopir'];
      data['afdeling'] = tripInfo.first['afdeling'];
      data['tanggal_trip'] = tripInfo.first['tanggal'];
      data['kcs'] = tripInfo.first['kcs'];
    }

    final existing = await getPksByTrip(tripId);
    if (existing == null) {
      await db.insert('pks', data);
    } else {
      await db.update('pks', data, where: 'trip_id = ?', whereArgs: [tripId]);
    }

    try {
      Map<String, dynamic> syncMap = Map.from(data);
      syncMap['kendaraan'] = data['no_plat']; // Unifikasi field name
      syncMap['sync_status'] = 'synced';

      String kcs = tripInfo.isNotEmpty ? (tripInfo.first['kcs'] ?? 'unknown').toString() : 'unknown';
      final String docId = "pks_${kcs}_$tripId";

      await FirebaseFirestore.instance.collection('pks').doc(docId).set(syncMap);
      await db.update('pks', {'sync_status': 'synced'}, where: 'trip_id = ?', whereArgs: [tripId]);
    } catch (_) {}
  }

  // ================= GET PKS BY TRIP =================
  Future<Map<String, dynamic>?> getPksByTrip(dynamic tripId) async {
    final db = await database;

    final result = await db.query(
      'pks',
      where: 'trip_id = ?',
      whereArgs: [tripId],
    );

    if (result.isNotEmpty) {
      return result.first;
    }

    return null;
  }

  // ================= TOTAL JANJANG =================
  Future<int> getTotalJanjangByTrip(dynamic tripId) async {
    final db = await database;

    final result = await db.rawQuery('''
    SELECT SUM(CAST(p.matang AS INTEGER)) as total
    FROM trip_detail td
    LEFT JOIN panen p ON p.id = td.panen_id
    WHERE td.trip_id = ?
  ''', [tripId]);

    return int.tryParse(result.first['total'].toString()) ?? 0;
  }

  // ================= GET DATA OFFLINE =================
  Future<List<Map<String, dynamic>>> getOfflineData() async {
    final db = await database;

    return await db.query(
      'panen',
      where: 'sync_status = ?',
      whereArgs: ['offline'],
    );
  }

  // ================= SET SYNCED =================
  Future<void> setSynced(int id) async {
    final db = await database;

    await db.update(
      'panen',
      {'sync_status': 'synced'},
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}