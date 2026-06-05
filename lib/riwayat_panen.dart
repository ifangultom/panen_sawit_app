import 'dart:io';
import 'dart:math' as math;
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

import 'utils/date_utils.dart';
import 'database_helper.dart';
import 'input_panen.dart';

class RiwayatPanenPage extends StatefulWidget {
  const RiwayatPanenPage({super.key});

  @override
  State<RiwayatPanenPage> createState() => _RiwayatPanenPageState();
}

class _RiwayatPanenPageState extends State<RiwayatPanenPage> {

  List<Map<String, dynamic>> data = [];
  Map<String, dynamic>? selected;
  String kcsLogin = "";
  DateTime filterTanggal = DateTime.now();

  bool isLoading = false;

  @override
  void initState() {
    super.initState();
    loadUser();
  }

  Future<void> loadUser() async {
    setState(() => isLoading = true);
    final prefs = await SharedPreferences.getInstance();
    final String user = prefs.getString('current_user') ?? "";
    String kcs = prefs.getString('kcs_login') ?? "";
    String afd = prefs.getString('afd_login') ?? "";

    if (afd.isEmpty) {
      afd = prefs.getString('afdeling_$user') ?? "";
      if (afd.isEmpty && kcs.isNotEmpty) afd = AppDateUtils.mapKcsToAfd(kcs);
      if (afd.isNotEmpty) await prefs.setString('afd_login', afd);
    }

    setState(() {
      kcsLogin = kcs;
    });
    await loadData();
  }

  Future<void> loadData() async {
    if (!mounted) return;
    setState(() => isLoading = true);
    
    final prefs = await SharedPreferences.getInstance();
    final String user = prefs.getString('current_user') ?? "";
    final String roleUser = (prefs.getString('role_$user') ?? "").toUpperCase();
    String kcs = prefs.getString('kcs_login') ?? "";
    String afd = prefs.getString('afd_login') ?? "";
    
    final String afdFromPrefs = afd.isNotEmpty ? afd : kcs;
    final String afdNormalized = AppDateUtils.mapKcsToAfd(afdFromPrefs);

    final List<String> patterns = AppDateUtils.getDateSearchPatterns(filterTanggal);
    
    List<Map<String, dynamic>> temp = [];

    try {
      debugPrint("DEBUG: loadData for $afdNormalized (${patterns.first})");
      // 1. Load Local
      final localData = await _loadDataOffline(roleUser, afdNormalized);
      debugPrint("DEBUG: Local data count: ${localData.length}");
      
      final connectivityResult = await Connectivity().checkConnectivity();
      bool isOnline = connectivityResult != ConnectivityResult.none;

      if (isOnline) {
        // 2. Fetch Online (Query semua pola secara paralel + Fallback Timestamp)
        final List<Future<QuerySnapshot>> futures = patterns.map((p) => 
          FirebaseFirestore.instance.collection('panen')
            .where('tanggal', isGreaterThanOrEqualTo: p)
            .where('tanggal', isLessThan: p + 'z')
            .get()
            .timeout(const Duration(seconds: 10))
        ).toList();

        // Tambahkan query Timestamp jika tanggal tersimpan sebagai object Timestamp
        final start = DateTime(filterTanggal.year, filterTanggal.month, filterTanggal.day);
        final end = start.add(const Duration(days: 1));
        futures.add(
          FirebaseFirestore.instance.collection('panen')
            .where('tanggal', isGreaterThanOrEqualTo: start)
            .where('tanggal', isLessThan: end)
            .get()
            .timeout(const Duration(seconds: 10))
        );
        
        final snapshots = await Future.wait(futures);
        
        List<Map<String, dynamic>> onlineDataRaw = [];
        for (var snap in snapshots) {
          for (var doc in snap.docs) {
            final d = Map<String, dynamic>.from(doc.data() as Map);
            d['firebase_id'] = doc.id;
            onlineDataRaw.add(d);
          }
        }
        debugPrint("DEBUG: Online data raw count: ${onlineDataRaw.length}");
        
        // 3. Client-side Filtering & De-duplication
        Map<String, Map<String, dynamic>> combined = {};
        
        // Masukkan data lokal dulu
        for (var d in localData) {
          String u = (d['user'] ?? user).toString();
          String key = d['firebase_id'] ?? d['doc_id'] ?? "${u}_${d['id']}";
          combined[key] = Map<String, dynamic>.from(d);
        }
        
        // Masukkan data online (Filter afdeling di sini)
        int filteredCount = 0;
        for (var d in onlineDataRaw) {
          // Filter Wilayah untuk non-admin
          if (roleUser != "ADMIN" && afdNormalized != "ALL" && afdNormalized.isNotEmpty) {
            String rawAfd = (d['afdeling'] ?? "").toString();
            if (rawAfd.isEmpty) rawAfd = (d['kcs'] ?? "").toString();
            
            String itemAfd = AppDateUtils.mapKcsToAfd(rawAfd);
            if (itemAfd != afdNormalized) {
              filteredCount++;
              continue; // Skip jika tidak cocok
            }
          }

          String oUser = (d['user'] ?? "").toString();
          String oLocalId = (d['local_id'] ?? d['id'] ?? "").toString();
          String firebaseId = d['firebase_id'] ?? "";
          String localKey = "${oUser}_$oLocalId";
          
          if (firebaseId.isNotEmpty && combined.containsKey(firebaseId)) {
            var localId = combined[firebaseId]!['id'];
            combined[firebaseId] = Map<String, dynamic>.from(d);
            combined[firebaseId]!['id'] = localId;
            combined[firebaseId]!['sync_status'] = 'synced';
          } else if (localKey.length > 2 && combined.containsKey(localKey)) {
            var localId = combined[localKey]!['id'];
            combined[localKey] = Map<String, dynamic>.from(d);
            combined[localKey]!['id'] = localId;
            combined[localKey]!['sync_status'] = 'synced';
          } else {
            String key = firebaseId.isNotEmpty ? firebaseId : localKey;
            d['id'] = d['id'] ?? d['local_id'] ?? key.hashCode.abs();
            d['sync_status'] = 'synced';
            combined[key] = Map<String, dynamic>.from(d);
          }
        }
        debugPrint("DEBUG: Online filtered out: $filteredCount");
        temp = combined.values.toList();
      } else {
        temp = localData;
      }
    } catch (e) {
      debugPrint("RiwayatPanen Error: $e");
      temp = await _loadDataOffline(roleUser, afdNormalized);
    }

    if (!mounted) return;
    temp.sort((a, b) => (b['tanggal'] ?? "").toString().compareTo((a['tanggal'] ?? "").toString()));

    setState(() {
      data = temp;
      selected = data.isNotEmpty ? Map<String, dynamic>.from(data.first) : null;
      isLoading = false;
    });
  }

  Future<List<Map<String, dynamic>>> _loadDataOffline(String roleUser, String afdNormalized) async {
    final db = await DatabaseHelper.instance.database;
    final List<String> patterns = AppDateUtils.getDateSearchPatterns(filterTanggal);
    
    // Ambil SEMUA data dulu, baru filter di memori agar konsisten
    final allLocal = await db.query('panen', orderBy: 'id DESC');
    
    return allLocal.where((e) {
      // Filter Tanggal
      String tglRaw = (e['tanggal'] ?? "").toString();
      bool matchDate = patterns.any((p) => tglRaw.startsWith(p));
      if (!matchDate) return false;

      // Filter Afdeling
      if (roleUser == "ADMIN" || afdNormalized == "ALL" || afdNormalized.isEmpty) return true;
      
      String itemAfd = AppDateUtils.mapKcsToAfd(e['afdeling']?.toString() ?? e['kcs']?.toString() ?? "");
      return itemAfd == afdNormalized;
    }).map((e) => Map<String, dynamic>.from(e)).toList();
  }
  Future<void> _pilihTanggal() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: filterTanggal,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      builder: (context, child) => Theme(
        data: ThemeData.light().copyWith(
          colorScheme: const ColorScheme.light(primary: Color(0xFF0D47A1)),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        filterTanggal = picked;
        selected = null;
      });
      loadData();
    }
  }

  String _formatTanggal(String? raw) {
    if (raw == null || raw.isEmpty) return "-";
    try {
      final dt = DateTime.parse(raw);
      const bln = ['','Jan','Feb','Mar','Apr','Mei','Jun','Jul','Ags','Sep','Okt','Nov','Des'];
      return "${dt.day} ${bln[dt.month]} ${dt.year}  ${dt.hour.toString().padLeft(2,'0')}:${dt.minute.toString().padLeft(2,'0')}";
    } catch (_) { return raw; }
  }

  String _formatTanggalHeader(DateTime dt) {
    const bln = ['','Januari','Februari','Maret','April','Mei','Juni','Juli','Agustus','September','Oktober','November','Desember'];
    const hr = ['','Senin','Selasa','Rabu','Kamis','Jumat','Sabtu','Minggu'];
    return "${hr[dt.weekday]}, ${dt.day} ${bln[dt.month]} ${dt.year}";
  }

  int hitungJanjang(Map d) {
    return (int.tryParse(d['matang']?.toString() ?? "0") ?? 0)
        + (int.tryParse(d['mentah']?.toString() ?? "0") ?? 0);
  }

  bool hasGps(Map d) =>
      (d['latitude'] != null && d['latitude'] != "" && d['latitude'] != "0");

  Future<void> bukaMaps(String lat, String lng) async {
    final url = Uri.parse("https://www.google.com/maps?q=$lat,$lng");
    await launchUrl(url, mode: LaunchMode.externalApplication);
  }

  void hapus(int id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Hapus Data"),
        content: const Text("Yakin hapus data panen ini?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Batal")),
          TextButton(onPressed: () => Navigator.pop(ctx, true),
              child: const Text("Hapus", style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirm == true) {
      await DatabaseHelper.instance.deletePanen(id);
      loadData();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4FF),
      appBar: AppBar(
        title: const Text("Riwayat Panen"),
        backgroundColor: const Color(0xFF0D47A1),
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_today, color: Colors.white),
            onPressed: _pilihTanggal,
          ),
        ],
      ),
      body: Column(
        children: [

          // ===== FILTER TANGGAL BANNER =====
          GestureDetector(
            onTap: _pilihTanggal,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF0D47A1), Color(0xFF1976D2)],
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.calendar_month_rounded, color: Colors.white70, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    _formatTanggalHeader(filterTanggal),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text("Ubah", style: TextStyle(color: Colors.white, fontSize: 12)),
                  ),
                ],
              ),
            ),
          ),

          Expanded(
            child: isLoading 
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF0D47A1)))
                : data.isEmpty
                ? RefreshIndicator(
                    onRefresh: loadData,
                    child: SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      child: SizedBox(
                        height: MediaQuery.of(context).size.height * 0.6,
                        child: _emptyState(),
                      ),
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: loadData,
                    color: const Color(0xFF0D47A1),
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(12),
                      children: [
                        // ===== LIST KARTU =====
                        ...data.map((d) {
                    final isSelected = selected != null && selected!['id'] == d['id'];
                    final janjang = hitungJanjang(d);
                    final gps = hasGps(d);

                    return GestureDetector(
                      onTap: () => setState(() => selected = Map<String, dynamic>.from(d)),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.only(bottom: 10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isSelected
                                ? const Color(0xFF0D47A1)
                                : Colors.transparent,
                            width: 2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: isSelected
                                  ? const Color(0xFF0D47A1).withOpacity(0.2)
                                  : Colors.black.withOpacity(0.06),
                              blurRadius: 10,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Row(
                            children: [

                              // Foto atau placeholder dengan timestamp style
                              _fotoTimestamp(d),

                              const SizedBox(width: 12),

                              // Info
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF0D47A1).withOpacity(0.1),
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Text(
                                            "Blok ${d['blok'] ?? '-'}",
                                            style: const TextStyle(
                                              color: Color(0xFF0D47A1),
                                              fontWeight: FontWeight.w700,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                        const Spacer(),
                                        Icon(
                                          gps ? Icons.location_on : Icons.location_off,
                                          size: 14,
                                          color: gps ? const Color(0xFF0D47A1) : Colors.grey,
                                        ),
                                        const SizedBox(width: 2),
                                        Text(
                                          gps ? "GPS" : "Offline",
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: gps ? const Color(0xFF0D47A1) : Colors.grey,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      d['pemanen'] ?? "-",
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 15,
                                        color: Color(0xFF0D1B4B),
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        _chip(Icons.grass, "$janjang Janjang", const Color(0xFF0D47A1)),
                                        const SizedBox(width: 6),
                                        _chip(Icons.scatter_plot, "${d['brondolan'] ?? 0} Kg", Colors.brown),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      _formatTanggal(d['tanggal']),
                                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                                    ),
                                  ],
                                ),
                              ),

                              // Chevron
                              Icon(
                                Icons.chevron_right_rounded,
                                color: isSelected
                                    ? const Color(0xFF0D47A1)
                                    : Colors.grey.shade300,
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }).toList(),

                  // ===== DETAIL CARD =====
                  if (selected != null) ...[
                    const SizedBox(height: 4),
                    _detailCard(),
                  ],

                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFotoWidget(String? path, {required double size, double? height}) {
    if (path == null || path.isEmpty) {
      return Container(
        width: size,
        height: height ?? size,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0D1B4B), Color(0xFF0D47A1)],
          ),
        ),
        child: const Icon(Icons.photo_camera, color: Colors.white38, size: 28),
      );
    }

    if (path.startsWith('data:image')) {
      try {
        final base64Data = path.split(',').last.replaceAll(RegExp(r'\s+'), '');
        return Image.memory(base64Decode(base64Data), width: size, height: height ?? size, fit: BoxFit.cover);
      } catch (_) {
        return Container(width: size, height: height ?? size, color: Colors.black, child: const Icon(Icons.broken_image, color: Colors.white38));
      }
    }
    
    if (path.startsWith('http')) {
      return Image.network(path, width: size, height: height ?? size, fit: BoxFit.cover, 
        errorBuilder: (c, e, s) => Container(width: size, height: height ?? size, color: Colors.black, child: const Icon(Icons.broken_image, color: Colors.white38)));
    }

    return Image.file(File(path), width: size, height: height ?? size, fit: BoxFit.cover, 
      errorBuilder: (c, e, s) => Container(width: size, height: height ?? size, color: Colors.black, child: const Icon(Icons.broken_image, color: Colors.white38)));
  }

  // ===== FOTO DENGAN TIMESTAMP STYLE =====
  Widget _fotoTimestamp(Map<String, dynamic> d) {
    final path = (d['foto'] ?? "").toString();
    final hasFoto = path.isNotEmpty;
    final tanggalRaw = d['tanggal'] ?? "";
    String jam = "";
    try {
      final dt = DateTime.parse(tanggalRaw);
      jam = "${dt.hour.toString().padLeft(2,'0')}:${dt.minute.toString().padLeft(2,'0')}";
    } catch (_) {}

    return GestureDetector(
      onTap: hasFoto ? () => Navigator.push(context,
          MaterialPageRoute(builder: (_) => FullImagePage(imagePath: path, tanggal: tanggalRaw, lat: d['latitude'] ?? "", lng: d['longitude'] ?? "")))
          : null,
      child: Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: const Color(0xFF0D1B4B),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Stack(
            fit: StackFit.expand,
            children: [
              _buildFotoWidget(path, size: 72),

              // Overlay gradient bawah untuk timestamp
              Positioned(
                bottom: 0, left: 0, right: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        Colors.black.withOpacity(0.75),
                        Colors.transparent,
                      ],
                    ),
                  ),
                  child: Text(
                    jam.isNotEmpty ? jam : "--:--",
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),

              // Badge kamera kecil pojok kanan atas
              if (hasFoto)
                Positioned(
                  top: 4, right: 4,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Icon(Icons.camera_alt, color: Colors.white, size: 10),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ===== DETAIL CARD =====
  Widget _detailCard() {
    final d = selected!;
    final hasFoto = (d['foto'] ?? "").toString().isNotEmpty;
    final gps = hasGps(d);
    final lat = d['latitude'] ?? "0";
    final lng = d['longitude'] ?? "0";
    final tanggalRaw = d['tanggal'] ?? "";

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 15, offset: const Offset(0, 5)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          // Header biru
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            decoration: const BoxDecoration(
              gradient: LinearGradient(colors: [Color(0xFF0D47A1), Color(0xFF1976D2)]),
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                const Text("Detail Panen",
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
                const Spacer(),
                Text("Blok ${d['blok'] ?? '-'}",
                    style: const TextStyle(color: Colors.white70, fontSize: 13)),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [

                // FOTO BESAR DENGAN TIMESTAMP STYLE
                if (hasFoto)
                  GestureDetector(
                    onTap: () => Navigator.push(context, MaterialPageRoute(
                        builder: (_) => FullImagePage(imagePath: d['foto'], tanggal: tanggalRaw, lat: lat, lng: lng))),
                    child: _fotoBesarTimestamp(d),
                  )
                else
                  _fotoBesarTimestamp(d),

                const SizedBox(height: 14),

                // Stats row
                Row(
                  children: [
                    _statBox("Matang", d['matang']?.toString() ?? "0", const Color(0xFF0D47A1)),
                    const SizedBox(width: 8),
                    _statBox("Mentah", d['mentah']?.toString() ?? "0", Colors.orange),
                    const SizedBox(width: 8),
                    _statBox("Brondolan", "${d['brondolan'] ?? 0} Kg", Colors.brown),
                  ],
                ),

                const SizedBox(height: 12),

                // Info rows
                _infoRow(Icons.person_outline, "Pemanen", d['pemanen'] ?? "-"),
                _infoRow(Icons.calendar_today_outlined, "Tanggal", _formatTanggal(tanggalRaw)),
                _infoRow(Icons.domain_outlined, "Afdeling", d['afdeling'] ?? "-"),
                if ((d['catatan'] ?? "").toString().isNotEmpty)
                  _infoRow(Icons.notes_outlined, "Catatan", d['catatan']),

                if (gps) ...[
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: () => bukaMaps(lat, lng),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.blue.shade200),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.location_on, color: Colors.blue, size: 16),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text("$lat, $lng",
                                style: const TextStyle(color: Colors.blue, fontSize: 12)),
                          ),
                          const Icon(Icons.open_in_new, color: Colors.blue, size: 14),
                        ],
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 14),

                // Tombol aksi
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          await Navigator.push(context, MaterialPageRoute(
                              builder: (_) => InputPanenPage(data: d)));
                          loadData();
                        },
                        icon: const Icon(Icons.edit, size: 16),
                        label: const Text("Edit"),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF0D47A1),
                          side: const BorderSide(color: Color(0xFF0D47A1)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => Navigator.push(context, MaterialPageRoute(
                            builder: (_) => RincianPanenPage(data: d))),
                        icon: const Icon(Icons.list_alt, size: 16),
                        label: const Text("Rincian"),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF0D47A1),
                          side: const BorderSide(color: const Color(0xFF0D47A1)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => hapus(d['id']),
                        icon: const Icon(Icons.delete_outline, size: 16),
                        label: const Text("Hapus"),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red,
                          side: const BorderSide(color: Colors.red),
                        ),
                      ),
                    ),
                  ],
                ),

                // Mini Map
                if (gps) ...[
                  const SizedBox(height: 12),
                  _miniMap(d),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ===== FOTO BESAR TIMESTAMP STYLE =====
  Widget _fotoBesarTimestamp(Map<String, dynamic> d) {
    final path = (d['foto'] ?? "").toString();
    final hasFoto = path.isNotEmpty;
    final tanggalRaw = d['tanggal'] ?? "";
    final lat = d['latitude'] ?? "";
    final lng = d['longitude'] ?? "";

    String tglFormatted = "";
    try {
      final dt = DateTime.parse(tanggalRaw);
      const bln = ['','Jan','Feb','Mar','Apr','Mei','Jun','Jul','Ags','Sep','Okt','Nov','Des'];
      tglFormatted = "${dt.day} ${bln[dt.month]} ${dt.year}  ${dt.hour.toString().padLeft(2,'0')}:${dt.minute.toString().padLeft(2,'0')}:${dt.second.toString().padLeft(2,'0')}";
    } catch (_) { tglFormatted = tanggalRaw; }

    final hasCoord = lat.isNotEmpty && lat != "0" && lng.isNotEmpty && lng != "0";

    return Container(
      width: double.infinity,
      height: 200,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: Colors.black,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Stack(
          fit: StackFit.expand,
          children: [
            _buildFotoWidget(path, size: double.infinity, height: 200),

            // Overlay gelap bawah
            Positioned(
              bottom: 0, left: 0, right: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(12, 30, 12, 10),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Colors.black.withOpacity(0.85), Colors.transparent],
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Tanggal dan jam
                    Text(
                      tglFormatted,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        fontFamily: 'monospace',
                        letterSpacing: 0.5,
                      ),
                    ),
                    if (hasCoord)
                      Text(
                        "$lat, $lng",
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                          fontFamily: 'monospace',
                        ),
                      ),
                  ],
                ),
              ),
            ),

            // Badge GPS pojok kanan atas
            Positioned(
              top: 10, right: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: hasCoord
                      ? const Color(0xFF0D47A1).withOpacity(0.85)
                      : Colors.red.withOpacity(0.75),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(hasCoord ? Icons.gps_fixed : Icons.gps_off,
                        color: Colors.white, size: 12),
                    const SizedBox(width: 4),
                    Text(hasCoord ? "GPS ON" : "No GPS",
                        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ),

            // Watermark HARVESTRAK pojok kiri atas
            Positioned(
              top: 10, left: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  "HARVESTRAK",
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.5,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _miniMap(Map d) {
    double lat = double.tryParse(d['latitude'] ?? "0") ?? 0;
    double lng = double.tryParse(d['longitude'] ?? "0") ?? 0;

    return GestureDetector(
      onTap: () => bukaMaps(d['latitude'], d['longitude']),
      child: Stack(
        children: [
          Container(
            height: 140,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: Colors.grey[200],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: IgnorePointer(
                child: FlutterMap(
                  options: MapOptions(
                    initialCenter: LatLng(lat, lng),
                    initialZoom: 16,
                    interactionOptions: const InteractionOptions(flags: InteractiveFlag.none),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: "https://{s}.tile.openstreetmap.fr/hot/{z}/{x}/{y}.png",
                      subdomains: ['a','b','c'],
                      userAgentPackageName: 'com.example.panen_sawit_app',
                    ),
                    MarkerLayer(markers: [
                      Marker(
                        point: LatLng(lat, lng),
                        width: 40, height: 40,
                        child: const Icon(Icons.location_on, color: Colors.red, size: 40),
                      ),
                    ]),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            right: 8, bottom: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.6),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.open_in_new, color: Colors.white, size: 12),
                  SizedBox(width: 4),
                  Text("Buka Maps", style: TextStyle(color: Colors.white, fontSize: 11)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.grass_outlined, size: 70, color: Colors.grey.shade300),
          const SizedBox(height: 12),
          Text(
            "Tidak ada data panen",
            style: TextStyle(fontSize: 16, color: Colors.grey.shade500, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            "pada ${_formatTanggalHeader(filterTanggal)}",
            style: TextStyle(fontSize: 13, color: Colors.grey.shade400),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _pilihTanggal,
            icon: const Icon(Icons.calendar_today, size: 16),
            label: const Text("Pilih Tanggal Lain"),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF0D47A1),
              side: const BorderSide(color: Color(0xFF0D47A1)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(IconData icon, String text, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 11, color: color),
        const SizedBox(width: 3),
        Text(text, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
      ],
    );
  }

  Widget _statBox(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Column(
          children: [
            Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
            Text(label, style: TextStyle(fontSize: 10, color: color.withOpacity(0.7))),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.grey),
          const SizedBox(width: 8),
          Text("$label: ", style: const TextStyle(color: Colors.grey, fontSize: 13)),
          Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
        ],
      ),
    );
  }
}

// ================= FULL IMAGE DENGAN TIMESTAMP =================
class FullImagePage extends StatelessWidget {
  final String imagePath;
  final String tanggal;
  final String lat;
  final String lng;

  const FullImagePage({
    super.key,
    required this.imagePath,
    this.tanggal = "",
    this.lat = "",
    this.lng = "",
  });

  @override
  Widget build(BuildContext context) {
    String tglFormatted = "";
    try {
      final dt = DateTime.parse(tanggal);
      const bln = ['','Jan','Feb','Mar','Apr','Mei','Jun','Jul','Ags','Sep','Okt','Nov','Des'];
      tglFormatted = "${dt.day} ${bln[dt.month]} ${dt.year}  ${dt.hour.toString().padLeft(2,'0')}:${dt.minute.toString().padLeft(2,'0')}:${dt.second.toString().padLeft(2,'0')}";
    } catch (_) { tglFormatted = tanggal; }

    final hasCoord = lat.isNotEmpty && lat != "0" && lng.isNotEmpty && lng != "0";

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text("Foto Panen", style: TextStyle(color: Colors.white)),
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          InteractiveViewer(
            minScale: 0.5,
            maxScale: 4,
            child: _buildFullImage(imagePath),
          ),

          // Timestamp overlay bawah
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 40, 16, 20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Colors.black.withOpacity(0.9), Colors.transparent],
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (tglFormatted.isNotEmpty)
                    Text(
                      tglFormatted,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                      ),
                    ),
                  if (hasCoord)
                    Text(
                      "$lat, $lng",
                      style: TextStyle(color: Colors.white.withOpacity(0.75), fontSize: 13),
                    ),
                  const SizedBox(height: 4),
                  const Text(
                    "HARVESTRAK",
                    style: TextStyle(
                      color: Colors.white38,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 2,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFullImage(String path) {
    if (path.startsWith('data:image')) {
      try {
        final base64Data = path.split(',').last.replaceAll(RegExp(r'\s+'), '');
        return Image.memory(base64Decode(base64Data), fit: BoxFit.contain);
      } catch (_) {
        return const Center(child: Icon(Icons.broken_image, color: Colors.white38, size: 64));
      }
    }
    if (path.startsWith('http')) {
      return Image.network(path, fit: BoxFit.contain);
    }
    return Image.file(File(path), fit: BoxFit.contain);
  }
}

// ================= RINCIAN =================
class RincianPanenPage extends StatelessWidget {
  final Map data;
  const RincianPanenPage({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4FF),
      appBar: AppBar(
        title: const Text("Rincian Panen"),
        backgroundColor: const Color(0xFF0D47A1),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.07), blurRadius: 12, offset: const Offset(0,4))],
              ),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(colors: [Color(0xFF0D47A1), Color(0xFF1976D2)]),
                      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.agriculture, color: Colors.white),
                        const SizedBox(width: 10),
                        Text("Blok ${data['blok'] ?? '-'}",
                            style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            _statBox2("Matang", data['matang']?.toString() ?? "0", const Color(0xFF0D47A1)),
                            const SizedBox(width: 8),
                            _statBox2("Mentah", data['mentah']?.toString() ?? "0", Colors.orange),
                            const SizedBox(width: 8),
                            _statBox2("Brondolan", "${data['brondolan'] ?? 0} Kg", Colors.brown),
                          ],
                        ),
                        const SizedBox(height: 16),
                        _row(Icons.person, "Pemanen", data['pemanen'] ?? "-"),
                        _row(Icons.calendar_today, "Tanggal", data['tanggal'] ?? "-"),
                        _row(Icons.domain, "Afdeling", data['afdeling'] ?? "-"),
                        if ((data['catatan'] ?? "").toString().isNotEmpty)
                          _row(Icons.notes, "Catatan", data['catatan']),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statBox2(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Column(children: [
          Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
          Text(label, style: TextStyle(fontSize: 11, color: color.withOpacity(0.7))),
        ]),
      ),
    );
  }

  Widget _row(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(children: [
        Icon(icon, size: 16, color: Colors.grey),
        const SizedBox(width: 8),
        Text("$label: ", style: const TextStyle(color: Colors.grey, fontSize: 13)),
        Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
      ]),
    );
  }
}