import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'database_helper.dart';

class LaporanPanenPage extends StatefulWidget {
  final String tanggal;
  final bool isWebView;
  final String? initialAfdeling;
  final bool lockAfdeling;
  final DateTime? initialStartDate;
  final DateTime? initialEndDate;
  final int? initialMonth;
  final int? initialYear;

  // Data Opsional dari Parent (untuk Web Dashboard agar sinkron dan cepat)
  final List<Map<String, dynamic>>? preloadedPanen;
  final List<Map<String, dynamic>>? preloadedPks;
  final List<Map<String, dynamic>>? preloadedTrips;

  const LaporanPanenPage({
    super.key,
    required this.tanggal,
    this.isWebView = false,
    this.initialAfdeling,
    this.lockAfdeling = false,
    this.initialStartDate,
    this.initialEndDate,
    this.initialMonth,
    this.initialYear,
    this.preloadedPanen,
    this.preloadedPks,
    this.preloadedTrips,
  });

  @override
  State<LaporanPanenPage> createState() => _LaporanPanenPageState();
}

class _LaporanPanenPageState extends State<LaporanPanenPage> {
  String tanggal = "";
  int totalTrip = 0;
  int totalPanen = 0;
  int totalJanjang = 0;
  int jumlahPemanen = 0;
  double totalBrondolan = 0;
  double totalPks = 0;
  String kcsLogin = "";
  bool isLoading = true;

  List<Map<String, dynamic>> listDetailPanen = [];
  List<Map<String, dynamic>> listDetailTrip = [];

  // Filter states
  int? selectedMonth;
  int? selectedYear;
  String? selectedAfdeling;
  DateTime? startDate;
  DateTime? endDate;

  final List<String> afdelings = ["AFD1", "AFD2", "AFD3"];
  final List<String> months = [
    "Januari", "Februari", "Maret", "April", "Mei", "Juni",
    "Juli", "Agustus", "September", "Oktober", "November", "Desember"
  ];
  final List<int> years = List.generate(5, (index) => DateTime.now().year - index);

  @override
  void initState() {
    super.initState();
    tanggal = widget.tanggal;
    selectedAfdeling = widget.initialAfdeling;
    startDate = widget.initialStartDate;
    endDate = widget.initialEndDate;
    selectedMonth = widget.initialMonth;
    selectedYear = widget.initialYear;
    _init();
  }

  @override
  void didUpdateWidget(LaporanPanenPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Sinkronisasi state internal saat parameter constructor berubah (penting untuk Web Admin)
    bool isChanged = oldWidget.initialStartDate != widget.initialStartDate ||
        oldWidget.initialEndDate != widget.initialEndDate ||
        oldWidget.initialAfdeling != widget.initialAfdeling ||
        oldWidget.initialMonth != widget.initialMonth ||
        oldWidget.initialYear != widget.initialYear;

    // Jika data preloaded berubah, update juga
    bool isDataChanged = oldWidget.preloadedPanen != widget.preloadedPanen ||
        oldWidget.preloadedPks != widget.preloadedPks ||
        oldWidget.preloadedTrips != widget.preloadedTrips;

    if (isChanged || isDataChanged) {
      setState(() {
        startDate = widget.initialStartDate;
        endDate = widget.initialEndDate;
        selectedAfdeling = widget.initialAfdeling;
        selectedMonth = widget.initialMonth;
        selectedYear = widget.initialYear;
        
        if (widget.preloadedPanen != null) {
          allPanenData = List.from(widget.preloadedPanen!);
          allTripsData = List.from(widget.preloadedTrips ?? []);
          allPksData = List.from(widget.preloadedPks ?? []);
        }
      });
      
      if (kIsWeb) {
        _combineDataWeb();
      } else {
        _loadData();
      }
    }
  }

  Future<void> _init() async {
    if (kIsWeb) {
      kcsLogin = "ADMIN";
      
      // Jika ada data preloaded dari DashboardAdmin, gunakan langsung
      if (widget.preloadedPanen != null) {
        allPanenData = List.from(widget.preloadedPanen!);
        allTripsData = List.from(widget.preloadedTrips ?? []);
        allPksData = List.from(widget.preloadedPks ?? []);
        _combineDataWeb();
      } else {
        _loadDataWeb();
      }
    } else {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      kcsLogin = prefs.getString('kcs_login') ?? "KCS1";
      await _loadData();
    }
  }

  DateTime? _parseDate(dynamic val) {
    if (val == null) return null;
    if (val is Timestamp) return val.toDate();
    if (val is DateTime) return val;
    return DateTime.tryParse(val.toString());
  }

  List<Map<String, dynamic>> allPksData = [];
  List<Map<String, dynamic>> allPanenData = [];
  List<Map<String, dynamic>> allTripsData = [];

  // Stream Subscriptions untuk menghindari memory leak
  StreamSubscription? _panenSub;
  StreamSubscription? _tripSub;
  StreamSubscription? _pksSub;

  @override
  void dispose() {
    _panenSub?.cancel();
    _tripSub?.cancel();
    _pksSub?.cancel();
    super.dispose();
  }

  void _loadDataWeb() {
    // Jika kita menggunakan data preloaded dari DashboardAdmin, tidak perlu membuat listener baru
    if (widget.preloadedPanen != null) {
      _combineDataWeb();
      return;
    }

    if (!isLoading) setState(() => isLoading = true);

    _panenSub?.cancel();
    _tripSub?.cancel();
    _pksSub?.cancel();

    // Gunakan Stream untuk data real-time di Web
    _panenSub = FirebaseFirestore.instance.collection('panen').snapshots().listen((panenSnap) {
      allPanenData = panenSnap.docs.map((d) => d.data()).toList();
      _combineDataWeb();
    }, onError: (e) => debugPrint("Error Panen Stream: $e"));

    _tripSub = FirebaseFirestore.instance.collection('trips').snapshots().listen((tripSnap) {
      allTripsData = tripSnap.docs.map((d) {
        var data = d.data();
        data['id'] = data['id']?.toString() ?? data['trip_id']?.toString() ?? d.id;
        return data;
      }).toList();
      _combineDataWeb();
    }, onError: (e) => debugPrint("Error Trips Stream: $e"));

    _pksSub = FirebaseFirestore.instance.collection('pks').snapshots().listen((pksSnap) {
      allPksData = pksSnap.docs.map((d) => d.data()).toList();
      _combineDataWeb();
    }, onError: (e) => debugPrint("Error PKS Stream: $e"));
  }

  void _refreshData() {
    if (kIsWeb) {
      if (widget.preloadedPanen != null) {
        // Sinkronkan ulang data dari props jika tersedia
        setState(() {
          allPanenData = List.from(widget.preloadedPanen!);
          allTripsData = List.from(widget.preloadedTrips ?? []);
          allPksData = List.from(widget.preloadedPks ?? []);
        });
        _combineDataWeb();
      } else {
        _loadDataWeb();
      }
    } else {
      _loadData();
    }
  }

  void _combineDataWeb() {
    if (!mounted) return;
    // Jika data allPanenData kosong tapi preloaded ada, gunakan preloaded
    if (allPanenData.isEmpty && widget.preloadedPanen != null) {
      allPanenData = List.from(widget.preloadedPanen!);
      allTripsData = List.from(widget.preloadedTrips ?? []);
      allPksData = List.from(widget.preloadedPks ?? []);
    }
    _processData(allPanenData, allTripsData);
  }

  void _processData(List<Map<String, dynamic>> allPanen, List<Map<String, dynamic>> allTrips) {
    // 1. Filter Panen
    List<Map<String, dynamic>> filteredPanen = allPanen.where((p) {
      // Filter Afdeling & Mapping KCS
      String? afd = p['afdeling']?.toString() ?? p['afd']?.toString();
      if (afd == null || afd.isEmpty) {
        String kcs = p['kcs']?.toString() ?? "";
        if (kcs == "KCS1") afd = "AFD1";
        else if (kcs == "KCS2") afd = "AFD2";
        else if (kcs == "KCS3") afd = "AFD3";
      }

      if (selectedAfdeling != null && afd != selectedAfdeling) return false;

      // Filter Tanggal
      DateTime? dt = _parseDate(p['tanggal'] ?? p['waktu'] ?? p['waktu_timbang']);
      return _isWithinFilter(dt);
    }).toList();

    // 2. Filter & Calculate PKS secara Independen (Sama seperti Dashboard Admin)
    List<Map<String, dynamic>> filteredPksList = allPksData.where((pks) {
      String? afd = pks['afdeling']?.toString() ?? pks['afd']?.toString();
      if (afd == null || afd.isEmpty) {
        String kcs = pks['kcs']?.toString() ?? "";
        if (kcs == "KCS1") afd = "AFD1";
        else if (kcs == "KCS2") afd = "AFD2";
        else if (kcs == "KCS3") afd = "AFD3";
      }
      if (selectedAfdeling != null && afd != selectedAfdeling) return false;
      
      DateTime? dt = _parseDate(pks['waktu_timbang'] ?? pks['tanggal_trip'] ?? pks['tanggal'] ?? pks['waktu']);
      return _isWithinFilter(dt);
    }).toList();

    double sumPks = 0;
    for (var pks in filteredPksList) {
      double berat = 0;
      var val = pks['berat_netto'] ?? pks['netto'] ?? pks['berat'];
      if (val is num) {
        berat = val.toDouble();
      } else if (val is String) {
        berat = double.tryParse(val) ?? 0;
      }
      sumPks += berat;
    }

    // 3. Gabungkan data Trip dengan PKS berdasarkan trip_id untuk Riwayat Trip
    List<Map<String, dynamic>> enrichedTrips = allTrips.map((t) {
      String tripId = t['id']?.toString() ?? "";
      String firebaseId = t['id_firebase']?.toString() ?? "";
      
      // Cari data PKS yang sesuai (matching trip_id atau id_firebase atau fallback enrichment)
      var pksMatch = allPksData.where((pks) {
        String pksTripId = pks['trip_id']?.toString() ?? "";
        if (pksTripId.isNotEmpty && (pksTripId == tripId || pksTripId == firebaseId)) return true;
        
        // Fallback: Matching by No Plat and Tanggal (Enriched fields)
        String tripNoPlat = t['no_plat']?.toString() ?? t['kendaraan']?.toString() ?? "";
        String tripTanggal = (t['tanggal'] ?? t['tanggal_trip'])?.toString().split(' ')[0] ?? "";
        
        String pksNoPlat = pks['no_plat']?.toString() ?? pks['kendaraan']?.toString() ?? "";
        String pksTanggal = (pks['tanggal_trip'] ?? pks['waktu_timbang'] ?? pks['tanggal'])?.toString().split(' ')[0] ?? "";
        
        return tripNoPlat.isNotEmpty && tripNoPlat == pksNoPlat && 
               tripTanggal.isNotEmpty && tripTanggal == pksTanggal;
      }).toList();

      double pksBerat = 0;
      if (pksMatch.isNotEmpty) {
        var firstPks = pksMatch.first;
        pksBerat = double.tryParse((firstPks['berat_netto'] ?? firstPks['netto'] ?? firstPks['berat'] ?? "0").toString()) ?? 0;
      }

      return {
        ...t,
        'total_pks': pksBerat > 0 ? pksBerat : (double.tryParse((t['total_pks'] ?? t['berat_netto'] ?? t['netto'] ?? "0").toString()) ?? 0),
      };
    }).toList();

    // 4. Filter Trip yang sudah di-enrich
    List<Map<String, dynamic>> filteredTrips = enrichedTrips.where((t) {
      // Mapping Afdeling & KCS untuk Trip
      String? afd = t['afdeling']?.toString() ?? t['afd']?.toString();
      if (afd == null || afd.isEmpty) {
        String kcs = t['kcs']?.toString() ?? "";
        if (kcs == "KCS1") afd = "AFD1";
        else if (kcs == "KCS2") afd = "AFD2";
        else if (kcs == "KCS3") afd = "AFD3";
      }

      if (selectedAfdeling != null && afd != selectedAfdeling) return false;

      DateTime? dt = _parseDate(t['tanggal'] ?? t['tanggal_trip'] ?? t['waktu'] ?? t['waktu_timbang']);
      return _isWithinFilter(dt);
    }).toList();

    // 5. Hitung Summary Panen
    int sumJanjang = 0;
    double sumBron = 0;
    Set<String> uniquePemanen = {};
    for (var p in filteredPanen) {
      int matang = int.tryParse(p['matang']?.toString() ?? "0") ?? 0;
      int mentah = int.tryParse(p['mentah']?.toString() ?? "0") ?? 0;
      sumJanjang += (matang + mentah);
      sumBron += (double.tryParse(p['brondolan']?.toString() ?? "0") ?? 0);
      if (p['pemanen'] != null) uniquePemanen.add(p['pemanen'].toString());
    }

    setState(() {
      listDetailPanen = filteredPanen;
      listDetailTrip = filteredTrips.map((t) => {
        ...t,
        'muatan': t['jumlah_panen'] ?? t['muatan'] ?? 0,
        'janjang_trip': t['total_janjang'] ?? t['janjang'] ?? 0,
        'berat_netto': t['total_pks'] ?? t['berat_netto'] ?? 0,
      }).toList();
      
      totalPanen = filteredPanen.length;
      totalJanjang = sumJanjang;
      totalBrondolan = sumBron;
      totalTrip = filteredTrips.length;
      totalPks = sumPks; // Menggunakan hasil filter PKS independen
      jumlahPemanen = uniquePemanen.length;
      isLoading = false;
    });
  }

  bool _isWithinFilter(DateTime? dt) {
    if (dt == null) return false;
    
    if (startDate != null && endDate != null) {
      // Gunakan pembandingan dateOnly agar lebih akurat (menghindari masalah jam/menit)
      DateTime dateOnly = DateTime(dt.year, dt.month, dt.day);
      DateTime startOnly = DateTime(startDate!.year, startDate!.month, startDate!.day);
      DateTime endOnly = DateTime(endDate!.year, endDate!.month, endDate!.day);
      
      return !dateOnly.isBefore(startOnly) && !dateOnly.isAfter(endOnly);
    } else if (selectedYear != null) {
      if (dt.year != selectedYear) return false;
      if (selectedMonth != null && dt.month != selectedMonth) return false;
      return true;
    } else {
      String filterTgl = tanggal.split(" ")[0];
      String itemTgl = dt.toIso8601String().split("T")[0];
      return filterTgl == itemTgl;
    }
  }

  Future<void> _loadData() async {
    setState(() => isLoading = true);
    final db = await DatabaseHelper.instance.database;

    List<String> panenConditions = [];
    List<String> tripConditions = [];
    List<dynamic> panenArgs = [];
    List<dynamic> tripArgs = [];

    // Filter Afdeling & KCS
    if (selectedAfdeling != null) {
      String afd = selectedAfdeling!;
      String kcs = afd.replaceAll("AFD", "KCS");
      panenConditions.add("(afdeling = ? OR kcs = ?)");
      panenArgs.addAll([afd, kcs]);
      tripConditions.add("(t.afdeling = ? OR t.kcs = ?)");
      tripArgs.addAll([afd, kcs]);
    }

    // Filter Tanggal
    if (startDate != null && endDate != null) {
      String start = startDate!.toIso8601String().split('T')[0];
      String end = endDate!.toIso8601String().split('T')[0];
      panenConditions.add("substr(tanggal, 1, 10) BETWEEN ? AND ?");
      tripConditions.add("substr(t.tanggal, 1, 10) BETWEEN ? AND ?");
      panenArgs.addAll([start, end]);
      tripArgs.addAll([start, end]);
    } else if (selectedYear != null) {
      panenConditions.add("CAST(substr(tanggal, 1, 4) AS INTEGER) = ?");
      tripConditions.add("CAST(substr(t.tanggal, 1, 4) AS INTEGER) = ?");
      panenArgs.add(selectedYear);
      tripArgs.add(selectedYear);
      if (selectedMonth != null) {
        panenConditions.add("CAST(substr(tanggal, 6, 2) AS INTEGER) = ?");
        tripConditions.add("CAST(substr(t.tanggal, 6, 2) AS INTEGER) = ?");
        panenArgs.add(selectedMonth);
        tripArgs.add(selectedMonth);
      }
    } else {
      panenConditions.add("tanggal LIKE ?");
      tripConditions.add("t.tanggal LIKE ?");
      panenArgs.add("$tanggal%");
      tripArgs.add("$tanggal%");
    }

    String panenWhere = panenConditions.isNotEmpty ? "WHERE ${panenConditions.join(" AND ")}" : "";
    String tripWhere = tripConditions.isNotEmpty ? "WHERE ${tripConditions.join(" AND ")}" : "";

    // 1. Get Summary Panen
    final panenSum = await db.rawQuery('''
      SELECT 
        COUNT(*) as total_panen,
        SUM(CAST(matang AS INTEGER)) as total_janjang,
        SUM(CAST(brondolan AS REAL)) as total_brondolan,
        COUNT(DISTINCT pemanen) as jumlah_pemanen
      FROM panen $panenWhere
    ''', panenArgs);

    // 2. Get All PKS for independent summing & enrichment
    final pksAll = await db.query('pks');
    
    // 3. Get Detail Panen
    final detail = await db.rawQuery("SELECT * FROM panen $panenWhere ORDER BY blok ASC", panenArgs);

    // 4. Get Detail Trip
    final detailTripRaw = await db.rawQuery('''
      SELECT 
        t.*, 
        (SELECT COUNT(*) FROM trip_detail td WHERE td.trip_id = t.id) as muatan,
        (SELECT SUM(CAST(p.matang AS INTEGER)) 
         FROM panen p 
         JOIN trip_detail td ON td.panen_id = p.id 
         WHERE td.trip_id = t.id) as janjang_trip,
        (SELECT SUM(CAST(p.brondolan AS REAL)) 
         FROM panen p 
         JOIN trip_detail td ON td.panen_id = p.id 
         WHERE td.trip_id = t.id) as brondolan_trip
      FROM trip t 
      $tripWhere 
      ORDER BY t.tanggal DESC
    ''', tripArgs);

    // 5. Manual Processing for PKS sum and Enriched Trip Detail (Match step in _processData)
    List<Map<String, dynamic>> filteredPksLocal = pksAll.where((pks) {
      String? afd = pks['afdeling']?.toString();
      if (selectedAfdeling != null && afd != selectedAfdeling) return false;
      DateTime? dt = _parseDate(pks['waktu_timbang'] ?? pks['tanggal_trip'] ?? pks['tanggal']);
      return _isWithinFilter(dt);
    }).toList();

    double sumPksLocal = 0;
    for (var pks in filteredPksLocal) {
      sumPksLocal += double.tryParse(pks['berat_netto']?.toString() ?? "0") ?? 0;
    }

    List<Map<String, dynamic>> enrichedTripsLocal = detailTripRaw.map((t) {
      String tripId = t['id']?.toString() ?? "";
      
      // Robust joining for PKS
      var pksMatch = pksAll.where((pks) {
        String pksTripId = pks['trip_id']?.toString() ?? "";
        if (pksTripId.isNotEmpty && pksTripId == tripId) return true;
        
        // Fallback: Matching by No Plat and Tanggal
        String tripNoPlat = t['no_plat']?.toString() ?? "";
        String tripTanggal = t['tanggal']?.toString().split(' ')[0] ?? "";
        String pksNoPlat = pks['no_plat']?.toString() ?? "";
        String pksTanggal = pks['tanggal_trip']?.toString().split(' ')[0] ?? "";
        
        return tripNoPlat.isNotEmpty && tripNoPlat == pksNoPlat && 
               tripTanggal.isNotEmpty && tripTanggal == pksTanggal;
      }).toList();

      double pksBerat = 0;
      if (pksMatch.isNotEmpty) {
        pksBerat = double.tryParse(pksMatch.first['berat_netto']?.toString() ?? "0") ?? 0;
      }

      return {
        ...t,
        'berat_netto': pksBerat,
      };
    }).toList();

    if (mounted) {
      setState(() {
        totalPanen = int.tryParse(panenSum.first['total_panen'].toString()) ?? 0;
        totalJanjang = int.tryParse(panenSum.first['total_janjang'].toString()) ?? 0;
        totalBrondolan = double.tryParse(panenSum.first['total_brondolan'].toString()) ?? 0;
        jumlahPemanen = int.tryParse(panenSum.first['jumlah_pemanen'].toString()) ?? 0;
        totalTrip = detailTripRaw.length;
        totalPks = sumPksLocal;
        listDetailPanen = detail;
        listDetailTrip = enrichedTripsLocal;
        isLoading = false;
      });
    }
  }

  Future<void> exportPdf() async {
    final pdf = pw.Document();

    String periodeStr = "";
    if (startDate != null && endDate != null) {
      periodeStr = "${startDate!.toString().split(" ")[0]} s/d ${endDate!.toString().split(" ")[0]}";
    } else if (selectedYear != null) {
      periodeStr = (selectedMonth != null ? "${months[selectedMonth! - 1]} $selectedYear" : "Tahun $selectedYear");
    } else {
      periodeStr = tanggal;
    }

    String unitName = kcsLogin == "ADMIN" ? "ADMIN" : "MANDOR";

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        footer: (context) => pw.Container(
          alignment: pw.Alignment.centerRight,
          margin: const pw.EdgeInsets.only(top: 10),
          child: pw.Text("Halaman ${context.pageNumber} dari ${context.pagesCount}", 
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey)),
        ),
        build: (context) => [
          // ─── HEADER BANNER (Model Gambar) ───────────────────────────────
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.all(20),
            decoration: pw.BoxDecoration(
              color: PdfColor.fromInt(0xFF0D47A1),
              borderRadius: pw.BorderRadius.circular(12),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text("LAPORAN PANEN SAWIT",
                    style: pw.TextStyle(
                        color: PdfColors.white,
                        fontWeight: pw.FontWeight.bold,
                        fontSize: 22)),
                pw.SizedBox(height: 4),
                pw.Text("Periode: $periodeStr",
                    style: const pw.TextStyle(color: PdfColors.white, fontSize: 12)),
                pw.Text("Unit: $unitName",
                    style: const pw.TextStyle(color: PdfColors.white, fontSize: 12)),
              ],
            ),
          ),

          pw.SizedBox(height: 25),
          pw.Text("RINGKASAN HASIL PANEN",
              style: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold,
                  fontSize: 14,
                  color: PdfColors.grey700)),
          pw.SizedBox(height: 12),

          // ─── RINGKASAN CARDS (2x2 Grid seperti Gambar) ───────────────────
          pw.Row(
            children: [
              _pdfStatCard("Total Trip", "$totalTrip Trip", PdfColor.fromInt(0xFFE3F2FD), PdfColor.fromInt(0xFF0D47A1)),
              pw.SizedBox(width: 12),
              _pdfStatCard("Total Panen", "$totalPanen Data", PdfColor.fromInt(0xFFE3F2FD), PdfColor.fromInt(0xFF0D47A1)),
            ],
          ),
          pw.SizedBox(height: 12),
          pw.Row(
            children: [
              _pdfStatCard("Total Janjang", "$totalJanjang Janjang", PdfColor.fromInt(0xFFFFF3E0), PdfColor.fromInt(0xFFE65100)),
              pw.SizedBox(width: 12),
              _pdfStatCard("Total Brondolan", "${totalBrondolan.toStringAsFixed(1)} Kg", PdfColor.fromInt(0xFFF5F5F5), PdfColor.fromInt(0xFF616161)),
            ],
          ),

          pw.SizedBox(height: 20),

          // ─── TOTAL TIMBANG PKS BANNER ─────────────────────────────────────
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.symmetric(horizontal: 20, vertical: 15),
            decoration: pw.BoxDecoration(
              color: PdfColor.fromInt(0xFF1976D2),
              borderRadius: pw.BorderRadius.circular(10),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text("TOTAL TIMBANG PKS",
                        style: pw.TextStyle(
                            color: PdfColors.white,
                            fontWeight: pw.FontWeight.bold,
                            fontSize: 15)),
                    pw.Text("Berat netto yang diterima PKS",
                        style: const pw.TextStyle(color: PdfColors.white, fontSize: 9)),
                  ],
                ),
                pw.Text("${totalPks.toStringAsFixed(0)} Kg",
                    style: pw.TextStyle(
                        color: PdfColors.white,
                        fontWeight: pw.FontWeight.bold,
                        fontSize: 26)),
              ],
            ),
          ),

          pw.SizedBox(height: 30),
          pw.Text("DETAIL DATA",
              style: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold,
                  fontSize: 14,
                  color: PdfColors.grey700)),
          pw.SizedBox(height: 10),

          // ─── TABEL SUMMARY (Model Gambar) ─────────────────────────────────
          pw.Table.fromTextArray(
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.black),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
            headers: ["Keterangan", "Nilai"],
            data: [
              ["Total Trip", "$totalTrip Trip"],
              ["Total Data Panen", "$totalPanen Data"],
              ["Total Janjang", "$totalJanjang"],
              ["Total Brondolan", "${totalBrondolan.toStringAsFixed(1)} Kg"],
              ["Timbang PKS", "${totalPks.toStringAsFixed(0)} Kg"],
            ],
            cellAlignment: pw.Alignment.centerLeft,
            headerAlignment: pw.Alignment.centerLeft,
            border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
          ),

          pw.SizedBox(height: 30),
          pw.Text("RINCIAN PER BLOK",
              style: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold,
                  fontSize: 14,
                  color: PdfColors.grey700)),
          pw.SizedBox(height: 10),

          // ─── TABEL DETAIL BLOK ────────────────────────────────────────────
          pw.Table.fromTextArray(
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white),
            headerDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFF0D47A1)),
            headers: ["Blok", "Pemanen", "Janjang", "Brondolan"],
            data: listDetailPanen.map((e) => [
              e['blok']?.toString() ?? "-",
              e['pemanen']?.toString() ?? "-",
              e['matang']?.toString() ?? "0",
              "${e['brondolan'] ?? 0} Kg",
            ]).toList(),
            cellAlignment: pw.Alignment.centerLeft,
            border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
          ),

          pw.SizedBox(height: 30),
          pw.Text("RIWAYAT TRIP MOBIL",
              style: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold,
                  fontSize: 14,
                  color: PdfColors.grey700)),
          pw.SizedBox(height: 10),

          pw.Table.fromTextArray(
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: 10),
            headerDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFF455A64)),
            cellStyle: const pw.TextStyle(fontSize: 9),
            headers: ["No Plat", "Sopir", "Muat", "Jjg", "Netto PKS"],
            data: listDetailTrip.map((e) => [
              e['no_plat']?.toString() ?? "-",
              e['sopir']?.toString() ?? "-",
              e['muatan']?.toString() ?? "0",
              e['janjang_trip']?.toString() ?? "0",
              "${e['berat_netto'] ?? 0} Kg",
            ]).toList(),
            cellAlignment: pw.Alignment.centerLeft,
            border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
          ),
        ],
      ),
    );

    await Printing.sharePdf(bytes: await pdf.save(), filename: 'Laporan_Panen_${tanggal}.pdf');
  }

  pw.Widget _pdfStatCard(String label, String value, PdfColor bg, PdfColor textColor) {
    return pw.Expanded(
      child: pw.Container(
        padding: const pw.EdgeInsets.all(16),
        decoration: pw.BoxDecoration(
          color: bg,
          borderRadius: pw.BorderRadius.circular(10),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(label, style: pw.TextStyle(fontSize: 10, color: textColor)),
            pw.SizedBox(height: 6),
            pw.Text(value, style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: textColor)),
          ],
        ),
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: widget.isWebView 
        ? null 
        : AppBar(
            title: const Text("Laporan Produksi & Panen", style: TextStyle(fontWeight: FontWeight.bold)),
            backgroundColor: const Color(0xFF0D47A1),
            foregroundColor: Colors.white,
            elevation: 0,
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 16),
                child: IconButton(
                  onPressed: exportPdf,
                  icon: const Icon(Icons.picture_as_pdf),
                  tooltip: "Ekspor PDF",
                ),
              ),
            ],
          ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF0D47A1)))
          : widget.isWebView 
              ? _buildWebLayout() 
              : _buildMobileLayout(),
    );
  }

  Widget _buildMobileLayout() {
    String periodeStr = "";
    if (startDate != null && endDate != null) {
      periodeStr = "${startDate!.toString().split(" ")[0]} s/d ${endDate!.toString().split(" ")[0]}";
    } else if (selectedYear != null) {
      periodeStr = (selectedMonth != null ? "${months[selectedMonth! - 1]} $selectedYear" : "Tahun $selectedYear");
    } else {
      periodeStr = tanggal.split(" ")[0];
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ─── FILTER MOBILE ───────────────────────────────────────────
          Card(
            elevation: 0,
            color: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey.shade200)),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _filterDropdown<int>(
                          value: selectedMonth,
                          hint: "Bulan",
                          items: months.asMap().entries.map((e) => DropdownMenuItem(value: e.key + 1, child: Text(e.value))).toList(),
                          onChanged: (v) {
                            setState(() { selectedMonth = v; startDate = null; endDate = null; });
                            _refreshData();
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _filterDropdown<int>(
                          value: selectedYear,
                          hint: "Tahun",
                          items: years.map((y) => DropdownMenuItem(value: y, child: Text(y.toString()))).toList(),
                          onChanged: (v) {
                            setState(() { selectedYear = v; startDate = null; endDate = null; });
                            _refreshData();
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _pilihRangeTanggal,
                          icon: const Icon(Icons.calendar_month, size: 18),
                          label: const Text("Pilih Tanggal"),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue.shade50,
                            foregroundColor: const Color(0xFF0D47A1),
                            elevation: 0,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        onPressed: () {
                          setState(() {
                            selectedAfdeling = widget.lockAfdeling ? widget.initialAfdeling : null;
                            selectedMonth = null;
                            selectedYear = null;
                            startDate = null;
                            endDate = null;
                            tanggal = widget.tanggal;
                          });
                          _refreshData();
                        },
                        icon: const Icon(Icons.refresh, color: Colors.grey),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // ─── BANNER PRODUKSI MOBILE (VERTIKAL/COMPACT) ────────────────
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFF1E40AF), Color(0xFF2563EB)]),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("LAPORAN PRODUKSI", 
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Icon(Icons.calendar_today, color: Colors.white70, size: 14),
                    const SizedBox(width: 6),
                    Text("Periode: $periodeStr", style: const TextStyle(color: Colors.white, fontSize: 14)),
                  ],
                ),
                const Divider(color: Colors.white24, height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("TOTAL TIMBANG PKS", style: TextStyle(color: Colors.white70, fontSize: 11)),
                        Text("${totalPks.toStringAsFixed(0)} KG", 
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 24)),
                      ],
                    ),
                    const Icon(Icons.factory_rounded, color: Colors.white30, size: 40),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),
          const Text("RINGKASAN OPERASIONAL", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 12),

          // Grid Summary Mobile (2 Kolom)
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.5,
            children: [
              _statCardMobile("Total Panen", "$totalPanen", Icons.inventory_2, Colors.blue),
              _statCardMobile("Total Janjang", "$totalJanjang", Icons.eco, Colors.orange),
              _statCardMobile("Brondolan", "${totalBrondolan.toStringAsFixed(1)} Kg", Icons.balance, Colors.purple),
              _statCardMobile("Total Trip", "$totalTrip", Icons.local_shipping, Colors.green),
            ],
          ),

          const SizedBox(height: 24),
          _buildDetailPanenSection(isMobile: true),
          const SizedBox(height: 16),
          _buildRiwayatTripSection(isMobile: true),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _statCardMobile(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 8),
          Text(title, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
          Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildWebLayout() {
    String periodeStr = "";
    if (startDate != null && endDate != null) {
      periodeStr = "${startDate!.toString().split(" ")[0]} s/d ${endDate!.toString().split(" ")[0]}";
    } else if (selectedYear != null) {
      periodeStr = (selectedMonth != null ? "${months[selectedMonth! - 1]} $selectedYear" : "Tahun $selectedYear");
    } else {
      periodeStr = tanggal.split(" ")[0];
    }

    final double screenWidth = MediaQuery.of(context).size.width;
    final bool isDesktop = screenWidth > 900;

    return Column(
      children: [
        // ─── WEB HEADER ─────────────────────
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          color: const Color(0xFF1E40AF),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "Laporan Produksi & Panen",
                style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
              ),
              ElevatedButton.icon(
                onPressed: exportPdf,
                icon: const Icon(Icons.picture_as_pdf, size: 18),
                label: const Text("Ekspor PDF"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white.withOpacity(0.15),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: const BorderSide(color: Colors.white30)),
                ),
              ),
            ],
          ),
        ),

        Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(horizontal: isDesktop ? 24 : 16, vertical: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ─── FILTER SECTION WEB ──────────────────────────────────────
                Card(
                  elevation: 2,
                  shadowColor: Colors.black12,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (!widget.lockAfdeling)
                          SizedBox(
                            width: 150,
                            child: _filterDropdown<String>(
                              value: selectedAfdeling,
                              hint: "Semua AFD",
                              items: [
                                const DropdownMenuItem(value: null, child: Text("Semua AFD")),
                                ...afdelings.map((a) => DropdownMenuItem(value: a, child: Text(a))),
                              ],
                              onChanged: (v) { setState(() => selectedAfdeling = v); _refreshData(); },
                            ),
                          ),
                        SizedBox(
                          width: 150,
                          child: _filterDropdown<int>(
                            value: selectedMonth,
                            hint: "Bulan",
                            items: months.asMap().entries.map((e) => DropdownMenuItem(value: e.key + 1, child: Text(e.value))).toList(),
                            onChanged: (v) {
                              setState(() { selectedMonth = v; startDate = null; endDate = null; });
                              _refreshData();
                            },
                          ),
                        ),
                        SizedBox(
                          width: 120,
                          child: _filterDropdown<int>(
                            value: selectedYear,
                            hint: "Tahun",
                            items: years.map((y) => DropdownMenuItem(value: y, child: Text(y.toString()))).toList(),
                            onChanged: (v) {
                              setState(() { selectedYear = v; startDate = null; endDate = null; });
                              _refreshData();
                            },
                          ),
                        ),
                        Container(
                          decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(8)),
                          child: IconButton(
                            onPressed: _pilihRangeTanggal,
                            icon: const Icon(Icons.calendar_month_rounded, color: Color(0xFF1E40AF)),
                            tooltip: "Pilih Range Tanggal",
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () {
                            setState(() {
                              selectedAfdeling = widget.lockAfdeling ? widget.initialAfdeling : null;
                              selectedMonth = null;
                              selectedYear = null;
                              startDate = null;
                              endDate = null;
                              tanggal = widget.tanggal;
                            });
                            _refreshData();
                          },
                          icon: const Icon(Icons.refresh, size: 20),
                          label: const Text("Reset", style: TextStyle(fontWeight: FontWeight.w600)),
                          style: TextButton.styleFrom(foregroundColor: Colors.blueGrey),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                // ─── MAIN INFO BANNER WEB ──────────────────────────────────────
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(28),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [Color(0xFF1E40AF), Color(0xFF2563EB)]),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [BoxShadow(color: Colors.blue.withOpacity(0.3), blurRadius: 20, offset: const Offset(0, 10))],
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text("LAPORAN PRODUKSI", 
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 24, letterSpacing: 1.5)),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                const Icon(Icons.calendar_today, color: Colors.white70, size: 16),
                                const SizedBox(width: 8),
                                Text("Periode: $periodeStr", 
                                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500)),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text("Unit: ${kcsLogin == "ADMIN" ? "ADMIN" : "MANDOR"} | AFD: ${selectedAfdeling ?? 'Semua'}",
                              style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 14)),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white24),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            const Text("TOTAL TIMBANG PKS", style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 4),
                            Text("${totalPks.toStringAsFixed(0)} KG", 
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 36)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 32),
                
                const Text("RINGKASAN OPERASIONAL", style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: Color(0xFF1E293B))),
                const SizedBox(height: 20),
                
                LayoutBuilder(
                  builder: (context, constraints) {
                    int crossAxisCount = constraints.maxWidth > 1200 ? 4 : (constraints.maxWidth > 600 ? 2 : 1);
                    return GridView.count(
                      crossAxisCount: crossAxisCount,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: 20,
                      crossAxisSpacing: 20,
                      childAspectRatio: 2.2,
                      children: [
                        _statCardWeb("Total Panen", "$totalPanen", "Data Panen", const Color(0xFFE0F2FE), const Color(0xFF0284C7), Icons.inventory_2_rounded),
                        _statCardWeb("Total Janjang", "$totalJanjang", "Janjang Matang", const Color(0xFFFEF3C7), const Color(0xFFD97706), Icons.eco_rounded),
                        _statCardWeb("Brondolan", "${totalBrondolan.toStringAsFixed(1)}", "Kilogram", const Color(0xFFF3E8FF), const Color(0xFF7C3AED), Icons.balance_rounded),
                        _statCardWeb("Total Trip", "$totalTrip", "Ritase Mobil", const Color(0xFFDCFCE7), const Color(0xFF059669), Icons.local_shipping_rounded),
                      ],
                    );
                  }
                ),

                const SizedBox(height: 40),

                if (isDesktop) 
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 4, child: _buildDetailPanenSection(isMobile: false)),
                      const SizedBox(width: 24),
                      Expanded(flex: 5, child: _buildRiwayatTripSection(isMobile: false)),
                    ],
                  )
                else
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildDetailPanenSection(isMobile: true),
                      const SizedBox(height: 32),
                      _buildRiwayatTripSection(isMobile: true),
                    ],
                  ),
                const SizedBox(height: 100),
              ],
            ),
          ),
        ),
      ],
    );
  }


  Widget _statCardWeb(String title, String value, String subtitle, Color bgColor, Color iconColor, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: iconColor, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(title, style: TextStyle(fontSize: 13, color: Colors.grey[600], fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: Color(0xFF1E293B))),
                Text(subtitle, style: TextStyle(fontSize: 11, color: Colors.grey[500])),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailPanenSection({bool isMobile = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("RINCIAN PER BLOK", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF475569))),
        const SizedBox(height: 16),
        _buildWebTableContainer(
          child: Column(
            children: [
              Container(
                color: const Color(0xFFF8FAFC),
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                child: Row(
                  children: [
                    const Expanded(child: Text("Blok", style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF64748B), fontSize: 12))),
                    const Expanded(flex: 2, child: Text("Pemanen", style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF64748B), fontSize: 12))),
                    Expanded(child: Text("Jjg", textAlign: isMobile ? TextAlign.center : TextAlign.start, style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF64748B), fontSize: 12))),
                    Expanded(child: Text("Brondolan", textAlign: isMobile ? TextAlign.right : TextAlign.start, style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF64748B), fontSize: 12))),
                  ],
                ),
              ),
              if (listDetailPanen.isEmpty)
                const Padding(padding: EdgeInsets.all(32), child: Text("Tidak ada data", style: TextStyle(color: Colors.grey)))
              else
                ...listDetailPanen.map((e) => Container(
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                  decoration: BoxDecoration(border: Border(top: BorderSide(color: Colors.grey.shade100))),
                  child: Row(
                    children: [
                      Expanded(child: Text(e['blok']?.toString() ?? "-", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
                      Expanded(flex: 2, child: Text(e['pemanen']?.toString() ?? "-", style: const TextStyle(fontSize: 13))),
                      Expanded(child: Text(e['matang']?.toString() ?? "0", textAlign: isMobile ? TextAlign.center : TextAlign.start, style: const TextStyle(fontSize: 13))),
                      Expanded(child: Text("${e['brondolan'] ?? 0} Kg", textAlign: isMobile ? TextAlign.right : TextAlign.start, style: const TextStyle(fontSize: 13))),
                    ],
                  ),
                )).toList(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRiwayatTripSection({bool isMobile = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("RIWAYAT TRIP MOBIL", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF475569))),
        const SizedBox(height: 16),
        _buildWebTableContainer(
          child: Column(
            children: [
              Container(
                color: const Color(0xFFF8FAFC),
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                child: Row(
                  children: [
                    if (isMobile) ...[
                      const Expanded(flex: 3, child: Text("Unit / Sopir", style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF64748B), fontSize: 12))),
                    ] else ...[
                      const Expanded(child: Text("No Plat", style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF64748B), fontSize: 12))),
                      const Expanded(flex: 2, child: Text("Sopir", style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF64748B), fontSize: 12))),
                    ],
                    Expanded(child: Text("Muat", textAlign: isMobile ? TextAlign.center : TextAlign.start, style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF64748B), fontSize: 12))),
                    Expanded(child: Text("Jjg", textAlign: isMobile ? TextAlign.center : TextAlign.start, style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF64748B), fontSize: 12))),
                    Expanded(flex: 2, child: Text("PKS (Kg)", textAlign: isMobile ? TextAlign.right : TextAlign.start, style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF64748B), fontSize: 12))),
                  ],
                ),
              ),
              if (listDetailTrip.isEmpty)
                const Padding(padding: EdgeInsets.all(32), child: Text("Tidak ada data trip", style: TextStyle(color: Colors.grey)))
              else
                ...listDetailTrip.map((e) => Container(
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                  decoration: BoxDecoration(border: Border(top: BorderSide(color: Colors.grey.shade100))),
                  child: Row(
                    children: [
                      if (isMobile) ...[
                        Expanded(
                          flex: 3,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(e['no_plat']?.toString() ?? "-", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                              Text(e['sopir']?.toString() ?? "-", style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                            ],
                          ),
                        ),
                      ] else ...[
                        Expanded(child: Text(e['no_plat']?.toString() ?? "-", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
                        Expanded(flex: 2, child: Text(e['sopir']?.toString() ?? "-", style: const TextStyle(fontSize: 13))),
                      ],
                      Expanded(child: Text(e['muatan']?.toString() ?? "0", textAlign: isMobile ? TextAlign.center : TextAlign.start, style: const TextStyle(fontSize: 13))),
                      Expanded(child: Text(e['janjang_trip']?.toString() ?? "0", textAlign: isMobile ? TextAlign.center : TextAlign.start, style: const TextStyle(fontSize: 13))),
                      Expanded(
                        flex: 2,
                        child: Text("${e['berat_netto'] ?? 0} Kg", 
                          textAlign: isMobile ? TextAlign.right : TextAlign.start,
                          style: const TextStyle(color: Color(0xFF1E40AF), fontWeight: FontWeight.bold, fontSize: 13)
                        )
                      ),
                    ],
                  ),
                )).toList(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildWebTableContainer({required Widget child}) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }


  Widget _filterDropdown<T>({required T? value, required String hint, required List<DropdownMenuItem<T?>> items, required ValueChanged<T?> onChanged}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade300)),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T?>(
          value: value,
          isExpanded: true,
          hint: Text(hint, style: const TextStyle(fontSize: 12)),
          items: items,
          onChanged: onChanged,
        ),
      ),
    );
  }

  Future<void> _pilihRangeTanggal() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDateRange: (startDate != null && endDate != null) ? DateTimeRange(start: startDate!, end: endDate!) : null,
      builder: (context, child) => Theme(
        data: ThemeData.light().copyWith(
          colorScheme: const ColorScheme.light(primary: Color(0xFF0D47A1)),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        startDate = picked.start;
        endDate = picked.end;
        selectedMonth = null;
        selectedYear = null;
      });
      if (kIsWeb) {
        _refreshData();
      } else {
        _loadData();
      }
    }
  }
}

class _HeaderCell extends StatelessWidget {
  final String text;
  const _HeaderCell(this.text);
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.all(12), child: Text(text, style: const TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.bold, fontSize: 12)));
}

class _TableCell extends StatelessWidget {
  final String text;
  const _TableCell(this.text);
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.all(12), child: Text(text, style: const TextStyle(fontSize: 12)));
}
