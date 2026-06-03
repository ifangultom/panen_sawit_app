import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'database_helper.dart';
import 'detail_trip_page.dart';
import 'input_pks_page.dart';

class RiwayatTripPage extends StatefulWidget {
  final bool isGlobal;
  final bool hideAfdelingFilter;
  final DateTime? initialDate;
  final int? initialMonth;
  final int? initialYear;
  final String? initialAfdeling;

  const RiwayatTripPage({
    super.key, 
    this.isGlobal = false,
    this.hideAfdelingFilter = false,
    this.initialDate,
    this.initialMonth,
    this.initialYear,
    this.initialAfdeling,
  });

  @override
  State<RiwayatTripPage> createState() => _RiwayatTripPageState();
}

class _RiwayatTripPageState extends State<RiwayatTripPage> {
  List<Map<String, dynamic>> tripList = [];
  List<Map<String, dynamic>> allPksData = [];
  List<Map<String, dynamic>> allTripsData = [];
  String kcsLogin = "";
  DateTime? filterTanggal;
  int? selectedMonth;
  int? selectedYear;
  String? selectedAfdeling;

  final List<String> afdelings = ["AFD1", "AFD2", "AFD3"];
  final List<String> months = [
    "Januari", "Februari", "Maret", "April", "Mei", "Juni",
    "Juli", "Agustus", "September", "Oktober", "November", "Desember"
  ];
  final List<int> years = List.generate(5, (index) => DateTime.now().year - index);

  @override
  void initState() {
    super.initState();
    filterTanggal = widget.initialDate;
    selectedMonth = widget.initialMonth;
    selectedYear = widget.initialYear;
    selectedAfdeling = widget.initialAfdeling;
    loadUser();
  }

  void loadUser() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    kcsLogin = prefs.getString('kcs_login') ?? "KCS1";
    loadTrip();
  }

  DateTime? _parseDate(dynamic val) {
    if (val == null) return null;
    if (val is Timestamp) return val.toDate();
    if (val is DateTime) return val;
    return DateTime.tryParse(val.toString());
  }

  Future<void> loadTrip() async {
    if (kIsWeb) {
      FirebaseFirestore.instance.collection('trips').snapshots().listen((snapshot) {
        allTripsData = snapshot.docs.map((doc) {
          var d = doc.data();
          d['id'] = d['id']?.toString() ?? d['trip_id']?.toString() ?? doc.id;
          return d;
        }).toList();
        _combineData();
      });

      FirebaseFirestore.instance.collection('pks').snapshots().listen((snapshot) {
        allPksData = snapshot.docs.map((doc) => doc.data()).toList();
        _combineData();
      });
      return;
    }

    final db = await DatabaseHelper.instance.database;

    List<String> conditions = [];
    List<dynamic> args = [];

    if (!widget.isGlobal) {
      conditions.add("t.kcs = ?");
      args.add(kcsLogin);
    }

    if (selectedAfdeling != null) {
      conditions.add("t.afdeling = ?");
      args.add(selectedAfdeling);
    }

    if (selectedYear != null) {
      conditions.add("CAST(substr(t.tanggal, 1, 4) AS INTEGER) = ?");
      args.add(selectedYear);
      if (selectedMonth != null) {
        conditions.add("CAST(substr(t.tanggal, 6, 2) AS INTEGER) = ?");
        args.add(selectedMonth);
      }
    } else if (filterTanggal != null) {
      conditions.add("substr(t.tanggal, 1, 10) = ?");
      args.add(filterTanggal.toString().split(" ")[0]);
    }

    String whereClause = conditions.isNotEmpty ? "WHERE ${conditions.join(" AND ")}" : "";

    final pksAll = await db.query('pks');

    final data = await db.rawQuery('''
      SELECT 
        t.id,
        t.tanggal,
        t.no_plat,
        t.sopir,
        t.afdeling,
        COUNT(p.id) as jumlah_panen,
        SUM(CAST(p.matang AS INTEGER)) as total_janjang,
        SUM(CAST(p.brondolan AS INTEGER)) as total_brondolan
      FROM trip t
      LEFT JOIN trip_detail td ON td.trip_id = t.id
      LEFT JOIN panen p ON p.id = td.panen_id
      $whereClause
      GROUP BY t.id
      ORDER BY t.tanggal DESC
    ''', args);

    List<Map<String, dynamic>> enrichedList = data.map((t) {
      String tripId = t['id'].toString();
      
      // Find matching PKS with fallback
      var pksMatch = pksAll.where((pks) {
        String pksTripId = pks['trip_id']?.toString() ?? "";
        if (pksTripId == tripId) return true;
        
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
        'total_pks': pksBerat,
      };
    }).toList();

    setState(() {
      tripList = enrichedList;
    });
  }

  void _combineData() {
    if (!mounted) return;
    setState(() {
      List<Map<String, dynamic>> allFetched = allTripsData.map((t) {
        String tripId = t['id']?.toString() ?? "";
        String firebaseId = t['id_firebase']?.toString() ?? "";

        var pksMatch = allPksData.firstWhere(
          (p) {
            String pksTripId = p['trip_id']?.toString() ?? "";
            if (pksTripId != "" && (pksTripId == tripId || pksTripId == firebaseId)) return true;
            
            // Fallback: Matching by No Plat and Tanggal
            String tripNoPlat = t['no_plat']?.toString() ?? t['kendaraan']?.toString() ?? "";
            String tripTanggal = (t['tanggal'] ?? t['tanggal_trip'])?.toString().split(' ')[0] ?? "";
            
            String pksNoPlat = p['no_plat']?.toString() ?? p['kendaraan']?.toString() ?? "";
            String pksTanggal = (p['tanggal_trip'] ?? p['waktu_timbang'] ?? p['tanggal'])?.toString().split(' ')[0] ?? "";
            
            return tripNoPlat.isNotEmpty && tripNoPlat == pksNoPlat && 
                   tripTanggal.isNotEmpty && tripTanggal == pksTanggal;
          },
          orElse: () => <String, dynamic>{},
        );

        double weight = 0;
        var val = pksMatch['berat_netto'] ?? t['total_pks'] ?? t['berat_netto'];
        if (val is num) {
          weight = val.toDouble();
        } else if (val is String) {
          weight = double.tryParse(val) ?? 0;
        }

        String? afd = t['afdeling']?.toString() ?? t['afd']?.toString();
        if (afd == null || afd.isEmpty) {
          String kcs = t['kcs']?.toString() ?? "";
          if (kcs == "KCS1") afd = "AFD1";
          else if (kcs == "KCS2") afd = "AFD2";
          else if (kcs == "KCS3") afd = "AFD3";
        }

        return {
          ...t,
          'id': tripId,
          'tanggal': t['tanggal'],
          'no_plat': t['no_plat'] ?? t['kendaraan'] ?? t['no_kendaraan'] ?? "-",
          'sopir': t['sopir'] ?? t['driver'] ?? "-",
          'afdeling': afd ?? "-",
          'jumlah_panen': t['jumlah_panen'] ?? t['muatan'] ?? 0,
          'total_janjang': t['total_janjang'] ?? t['janjang'] ?? 0,
          'total_brondolan': t['total_brondolan'] ?? t['brondolan'] ?? 0,
          'total_pks': weight,
        };
      }).toList();

      tripList = allFetched.where((t) {
        if (selectedAfdeling != null && t['afdeling'] != selectedAfdeling) return false;

        DateTime? dt = _parseDate(t['tanggal'] ?? t['waktu'] ?? t['tanggal_trip'] ?? t['waktu_timbang']);
        if (selectedYear == null && filterTanggal == null && selectedMonth == null) return true;
        if (dt == null) return false;

        if (selectedYear != null) {
          if (dt.year != selectedYear) return false;
          if (selectedMonth != null && dt.month != selectedMonth) return false;
          return true;
        } else if (filterTanggal != null) {
          String fDate = filterTanggal!.toIso8601String().split('T')[0];
          String itemDate = dt.toIso8601String().split('T')[0];
          return fDate == itemDate;
        }
        return true;
      }).toList();
      
      tripList.sort((a, b) {
        DateTime? da = _parseDate(a['tanggal']);
        DateTime? db = _parseDate(b['tanggal']);
        if (da == null || db == null) return 0;
        return db.compareTo(da);
      });
    });
  }

  String formatTanggal(dynamic tgl) {
    if (tgl == null) return "-";
    DateTime? dt = _parseDate(tgl);
    if (dt == null) return tgl.toString();
    return "${dt.day}-${dt.month}-${dt.year}";
  }

  Color getStatusColor(double berat) {
    return berat > 0 ? const Color(0xFF0D47A1) : Colors.orange;
  }

  String getStatusText(double berat) {
    return berat > 0 ? "EDIT TIMBANG" : "INPUT TIMBANG";
  }

  Future<void> hapusTrip(int tripId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Hapus Trip"),
        content: const Text("Yakin ingin menghapus trip ini? Data tidak bisa dikembalikan."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Batal"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Hapus", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final db = await DatabaseHelper.instance.database;
    await db.delete('trip_detail', where: 'trip_id = ?', whereArgs: [tripId]);
    await db.delete('pks', where: 'trip_id = ?', whereArgs: [tripId]);
    await db.delete('trip', where: 'id = ?', whereArgs: [tripId]);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Trip berhasil dihapus")),
    );

    loadTrip();
  }

  Future<void> pilihTanggal() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: filterTanggal ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );

    if (picked != null) {
      setState(() {
        filterTanggal = picked;
        selectedYear = null;
        selectedMonth = null;
      });
      loadTrip();
    }
  }

  void resetFilter() {
    setState(() {
      filterTanggal = null;
      selectedMonth = null;
      selectedYear = null;
      selectedAfdeling = null;
    });
    loadTrip();
  }

  Widget _filterDropdown<T>({
    required T? value,
    required String hint,
    required List<DropdownMenuItem<T?>> items,
    required ValueChanged<T?> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T?>(
          value: value,
          isExpanded: false,
          hint: Text(hint, style: const TextStyle(fontSize: 12)),
          style: const TextStyle(fontSize: 12, color: Colors.black),
          items: items,
          onChanged: onChanged,
        ),
      ),
    );
  }

  Future<void> _sharePdf() async {
    try {
      final pdf = pw.Document();
      
      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4.landscape,
          margin: const pw.EdgeInsets.all(32),
          build: (context) {
            return [
              pw.Center(
                child: pw.Text("LAPORAN RIWAYAT TRIP MOBIL", 
                  style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold))),
              pw.SizedBox(height: 10),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text("Tanggal Cetak: ${DateTime.now().toString().split('.')[0]}"),
                  pw.Text("Total Record: ${tripList.length}"),
                ],
              ),
              pw.Divider(),
              pw.SizedBox(height: 10),
              pw.Text("RINGKASAN", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12)),
              pw.SizedBox(height: 5),
              pw.Table.fromTextArray(
                headers: ["Total Trip", "Total Muatan", "Total Janjang", "Total Brondolan", "Total PKS"],
                data: [[
                  "${tripList.length}",
                  "${tripList.fold(0, (prev, element) => prev + (int.tryParse(element['jumlah_panen'].toString()) ?? 0))}",
                  "${tripList.fold(0, (prev, element) => prev + (int.tryParse(element['total_janjang'].toString()) ?? 0))}",
                  "${tripList.fold(0.0, (prev, element) => prev + (double.tryParse(element['total_brondolan'].toString()) ?? 0)).toStringAsFixed(1)} Kg",
                  "${tripList.fold(0.0, (prev, element) => prev + (double.tryParse(element['total_pks'].toString()) ?? 0)).toStringAsFixed(1)} Kg",
                ]],
                headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
                cellStyle: const pw.TextStyle(fontSize: 9),
              ),
              pw.SizedBox(height: 20),
              pw.Text("DETAIL DATA TRIP", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12)),
              pw.SizedBox(height: 5),
              pw.Table.fromTextArray(
                headers: ["Tanggal", "No Plat", "Sopir", "Afdeling", "Muat", "Jjg", "Bron", "Netto PKS"],
                headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8, color: PdfColors.white),
                cellStyle: const pw.TextStyle(fontSize: 8),
                headerDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFF0D47A1)),
                data: tripList.map((e) {
                  return [
                    formatTanggal(e['tanggal']),
                    e['no_plat'] ?? "-",
                    e['sopir'] ?? "-",
                    e['afdeling'] ?? "-",
                    "${e['jumlah_panen'] ?? 0}",
                    "${e['total_janjang'] ?? 0}",
                    "${e['total_brondolan'] ?? 0} Kg",
                    "${(double.tryParse(e['total_pks'].toString()) ?? 0).toStringAsFixed(1)} Kg",
                  ];
                }).toList(),
              ),
            ];
          },
        ),
      );

      await Printing.sharePdf(
        bytes: await pdf.save(),
        filename: "Laporan_Trip_${DateTime.now().millisecondsSinceEpoch}.pdf",
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Gagal share PDF: $e")));
      }
    }
  }

  Widget _statChip(IconData icon, String label, String value) {
    return Column(
      children: [
        Icon(icon, size: 20, color: Colors.grey[600]),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(fontSize: 10, color: Colors.grey[600]),
        ),
        Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
        ),
      ],
    );
  }

  Widget _buildFilterBar() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 5)],
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            if (kIsWeb) ...[
              const Text("Data Trip Mobil", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(width: 20),
            ],
            if (!widget.hideAfdelingFilter) ...[
              _filterDropdown<String?>(
                value: selectedAfdeling,
                hint: "AFD",
                items: [
                  const DropdownMenuItem(value: null, child: Text("Semua AFD")),
                  ...afdelings.map((a) => DropdownMenuItem(value: a, child: Text(a))),
                ],
                onChanged: (v) {
                  setState(() => selectedAfdeling = v);
                  loadTrip();
                },
              ),
              const SizedBox(width: 8),
            ],
            _filterDropdown<int?>(
              value: selectedMonth,
              hint: "Bulan",
              items: [
                const DropdownMenuItem(value: null, child: Text("Semua")),
                ...List.generate(12, (i) => DropdownMenuItem(value: i + 1, child: Text(months[i]))),
              ],
              onChanged: (v) {
                setState(() {
                  selectedMonth = v;
                  filterTanggal = null;
                });
                loadTrip();
              },
            ),
            const SizedBox(width: 8),
            _filterDropdown<int?>(
              value: selectedYear,
              hint: "Tahun",
              items: [
                const DropdownMenuItem(value: null, child: Text("Semua")),
                ...years.map((y) => DropdownMenuItem(value: y, child: Text(y.toString()))),
              ],
              onChanged: (v) {
                setState(() {
                  selectedYear = v;
                  filterTanggal = null;
                });
                loadTrip();
              },
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.calendar_month, color: Color(0xFF0D47A1)),
              onPressed: pilihTanggal,
            ),
            if (filterTanggal != null || selectedYear != null || selectedAfdeling != null)
              IconButton(
                icon: const Icon(Icons.refresh, color: Colors.red),
                onPressed: resetFilter,
              ),
            if (kIsWeb) ...[
              const SizedBox(width: 15),
              ElevatedButton.icon(
                onPressed: _sharePdf,
                icon: const Icon(Icons.picture_as_pdf, size: 16),
                label: const Text("Export PDF"),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTripList() {
    if (tripList.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.local_shipping_outlined, size: 60, color: Colors.grey),
            const SizedBox(height: 10),
            const Text("Tidak ada data trip", style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    if (kIsWeb) {
      return _buildDataTable();
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 6),
      itemCount: tripList.length,
      itemBuilder: (context, index) => _buildTripCard(tripList[index]),
    );
  }

  Widget _buildSummaryHeader() {
    int totalTrip = tripList.length;
    int totalMuatan = 0;
    int totalJanjang = 0;
    double totalBrondolan = 0;
    double totalPks = 0;

    for (var item in tripList) {
      totalMuatan += (int.tryParse(item['jumlah_panen'].toString()) ?? 0);
      totalJanjang += (int.tryParse(item['total_janjang'].toString()) ?? 0);
      totalBrondolan += (double.tryParse(item['total_brondolan'].toString()) ?? 0);
      totalPks += (double.tryParse(item['total_pks'].toString()) ?? 0);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("RINGKASAN", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _statCardWeb("Total Trip", "$totalTrip", const Color(0xFF0D47A1).withValues(alpha: 0.05), const Color(0xFF0D47A1), Icons.local_shipping_rounded)),
            const SizedBox(width: 12),
            Expanded(child: _statCardWeb("Total Muatan", "$totalMuatan", Colors.blue[50]!, const Color(0xFF0D47A1), Icons.inventory_2_rounded)),
            const SizedBox(width: 12),
            Expanded(child: _statCardWeb("Total Janjang", "$totalJanjang", Colors.orange[50]!, Colors.orange[900]!, Icons.grass_rounded)),
            const SizedBox(width: 12),
            Expanded(child: _statCardWeb("Brondolan", "${totalBrondolan.toStringAsFixed(1)} Kg", Colors.purple[50]!, Colors.purple[900]!, Icons.scale_rounded)),
          ],
        ),
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.blue[100],
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("TOTAL TIMBANG PKS", style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0D47A1))),
              Text("${totalPks.toStringAsFixed(0)} Kg", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: Color(0xFF0D47A1))),
            ],
          ),
        ),
        const SizedBox(height: 30),
      ],
    );
  }

  Widget _statCardWeb(String label, String value, Color bg, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [Icon(icon, size: 16, color: color), const SizedBox(width: 8), Text(label, style: TextStyle(fontSize: 12, color: color))]),
          const SizedBox(height: 8),
          Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }

  Widget _buildDataTable() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(25),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Column(
              children: [
                const Text(
                  "LAPORAN RIWAYAT TRIP MOBIL",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 1.2),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text("Tanggal Cetak: ${DateTime.now().toString().split('.')[0]}", 
                      style: const TextStyle(fontSize: 11, color: Colors.grey)),
                    Text("Total Record: ${tripList.length}", 
                      style: const TextStyle(fontSize: 11, color: Colors.grey)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 25),
          _buildSummaryHeader(),
          const Text("DETAIL DATA TRIP", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.black.withOpacity(0.1)),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 5)],
            ),
            child: Table(
              border: TableBorder.all(color: Colors.black.withOpacity(0.1), width: 0.5),
              columnWidths: const {
                0: FlexColumnWidth(1.2), // Tanggal
                1: FlexColumnWidth(1.2), // No Plat
                2: FlexColumnWidth(2),   // Sopir
                3: FlexColumnWidth(1),   // Afdeling
                4: FlexColumnWidth(1),   // Muatan
                5: FlexColumnWidth(1),   // Janjang
                6: FlexColumnWidth(1.2), // Brondolan
                7: FlexColumnWidth(1.5), // Netto PKS
              },
              children: [
                TableRow(
                  decoration: const BoxDecoration(color: Color(0xFF0D47A1)),
                  children: [
                    _cell("Tanggal", isHeader: true, textColor: Colors.white),
                    _cell("No Plat", isHeader: true, textColor: Colors.white),
                    _cell("Sopir", isHeader: true, textColor: Colors.white),
                    _cell("Afdeling", isHeader: true, textColor: Colors.white),
                    _cell("Muatan", isHeader: true, textColor: Colors.white),
                    _cell("Janjang", isHeader: true, textColor: Colors.white),
                    _cell("Brondolan", isHeader: true, textColor: Colors.white),
                    _cell("Netto PKS", isHeader: true, textColor: Colors.white),
                  ],
                ),
                ...tripList.map((item) {
                  final double totalPks = (item['total_pks'] as num?)?.toDouble() ?? 0;
                  return TableRow(
                    children: [
                      _cell(formatTanggal(item['tanggal'])),
                      _cell(item['no_plat'] ?? "-", isBold: true),
                      _cell(item['sopir'] ?? "-"),
                      _cell(item['afdeling'] ?? "-"),
                      _cell("${item['jumlah_panen'] ?? 0}"),
                      _cell("${item['total_janjang'] ?? 0}"),
                      _cell("${item['total_brondolan'] ?? 0} Kg"),
                      _cell("${totalPks.toStringAsFixed(1)} Kg", 
                        color: totalPks > 0 ? Colors.blue[900] : Colors.orange[900], isBold: true),
                    ],
                  );
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _cell(String text, {bool isHeader = false, bool isBold = false, Color? color, Color? textColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: isHeader ? 12 : 11,
          fontWeight: (isHeader || isBold) ? FontWeight.bold : FontWeight.normal,
          color: textColor ?? color ?? Colors.black87,
        ),
      ),
    );
  }

  Widget _buildTripCard(Map<String, dynamic> item) {
    final double totalPks = (item['total_pks'] as num?)?.toDouble() ?? 0;
    final String noPlat = item['no_plat'] ?? "-";
    final String sopir = item['sopir'] ?? "-";
    final int janjang = int.tryParse(item['total_janjang'].toString()) ?? 0;
    final int brond = int.tryParse(item['total_brondolan'].toString()) ?? 0;
    final int muatan = int.tryParse(item['jumlah_panen'].toString()) ?? 0;

    return Card(
      margin: kIsWeb ? EdgeInsets.zero : const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(noPlat, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
                GestureDetector(
                  onTap: () async {
                    final pks = await DatabaseHelper.instance.getPksByTrip(item['id']);
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => InputPksPage(tripId: item['id'], data: pks),
                      ),
                    );
                    loadTrip();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: getStatusColor(totalPks),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      getStatusText(totalPks),
                      style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text("Sopir: $sopir", style: const TextStyle(fontSize: 13)),
            Text("Tanggal: ${formatTanggal(item['tanggal'])}", style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 8),
            const Divider(height: 1),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _statChip(Icons.grass, "Janjang", "$janjang"),
                _statChip(Icons.scatter_plot, "Brond", "$brond Kg"),
                _statChip(Icons.inventory_2, "Muatan", "$muatan"),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: totalPks > 0 ? Colors.blue.shade50 : Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.scale, size: 16, color: totalPks > 0 ? Colors.blue : Colors.orange),
                  const SizedBox(width: 6),
                  Text(
                    totalPks > 0
                        ? "PKS: ${totalPks.toStringAsFixed(0)} Kg"
                        : "PKS: Belum ditimbang",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: totalPks > 0 ? Colors.blue : Colors.orange,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => DetailTripPage(tripId: item['id']),
                        ),
                      );
                    },
                    icon: const Icon(Icons.info_outline, size: 16),
                    label: const Text("Rincian"),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.blue,
                      side: const BorderSide(color: Colors.blue),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => hapusTrip(item['id']),
                    icon: const Icon(Icons.delete_outline, size: 16),
                    label: const Text("Hapus"),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: const BorderSide(color: Colors.red),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return Column(
        children: [
          _buildFilterBar(),
          Expanded(child: _buildTripList()),
        ],
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F6),
      appBar: AppBar(
        title: const Text("Riwayat Trip Mobil"),
        backgroundColor: const Color(0xFF0D47A1),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf),
            onPressed: _sharePdf,
          ),
        ],
      ),
      body: Column(
        children: [
          // Filter Bar
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 5)],
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  if (!widget.hideAfdelingFilter) ...[
                    _filterDropdown<String?>(
                      value: selectedAfdeling,
                      hint: "AFD",
                      items: [
                        const DropdownMenuItem(value: null, child: Text("Semua AFD")),
                        ...afdelings.map((a) => DropdownMenuItem(value: a, child: Text(a))),
                      ],
                      onChanged: (v) {
                        setState(() => selectedAfdeling = v);
                        loadTrip();
                      },
                    ),
                    const SizedBox(width: 8),
                  ],
                  _filterDropdown<int?>(
                    value: selectedMonth,
                    hint: "Bulan",
                    items: [
                      const DropdownMenuItem(value: null, child: Text("Semua")),
                      ...List.generate(12, (i) => DropdownMenuItem(value: i + 1, child: Text(months[i]))),
                    ],
                    onChanged: (v) {
                      setState(() {
                        selectedMonth = v;
                        filterTanggal = null;
                      });
                      loadTrip();
                    },
                  ),
                  const SizedBox(width: 8),
                  _filterDropdown<int?>(
                    value: selectedYear,
                    hint: "Tahun",
                    items: [
                      const DropdownMenuItem(value: null, child: Text("Semua")),
                      ...years.map((y) => DropdownMenuItem(value: y, child: Text(y.toString()))),
                    ],
                    onChanged: (v) {
                      setState(() {
                        selectedYear = v;
                        filterTanggal = null;
                      });
                      loadTrip();
                    },
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.calendar_month, color: Color(0xFF0D47A1)),
                    onPressed: pilihTanggal,
                  ),
                  if (filterTanggal != null || selectedYear != null || selectedAfdeling != null)
                    IconButton(
                      icon: const Icon(Icons.refresh, color: Colors.red),
                      onPressed: resetFilter,
                    ),
                ],
              ),
            ),
          ),

          Expanded(
            child: tripList.isEmpty
                ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.local_shipping_outlined, size: 60, color: Colors.grey),
                  const SizedBox(height: 10),
                  Text(
                    "Tidak ada data trip",
                    style: const TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            )
                : ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 6),
              itemCount: tripList.length,
              itemBuilder: (context, index) {
                final item = tripList[index];

                final double totalPks = (item['total_pks'] as num?)?.toDouble() ?? 0;
                final String noPlat = item['no_plat'] ?? "-";
                final String sopir = item['sopir'] ?? "-";
                final int janjang = int.tryParse(item['total_janjang'].toString()) ?? 0;
                final int brond = int.tryParse(item['total_brondolan'].toString()) ?? 0;
                final int muatan = int.tryParse(item['jumlah_panen'].toString()) ?? 0;

                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  elevation: 3,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [

                        // Baris 1: No Plat + Tombol PKS
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(noPlat, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
                            GestureDetector(
                              onTap: () async {
                                final pks = await DatabaseHelper.instance.getPksByTrip(item['id']);
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => InputPksPage(tripId: item['id'], data: pks),
                                  ),
                                );
                                loadTrip();
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: getStatusColor(totalPks),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  getStatusText(totalPks),
                                  style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 6),
                        Text("Sopir: $sopir", style: const TextStyle(fontSize: 13)),
                        Text("Tanggal: ${formatTanggal(item['tanggal'])}", style: const TextStyle(fontSize: 13)),

                        const SizedBox(height: 8),
                        const Divider(height: 1),
                        const SizedBox(height: 8),

                        // Baris statistik
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            _statChip(Icons.grass, "Janjang", "$janjang"),
                            _statChip(Icons.scatter_plot, "Brond", "$brond Kg"),
                            _statChip(Icons.inventory_2, "Muatan", "$muatan"),
                          ],
                        ),

                        const SizedBox(height: 8),

                        // PKS dalam Kg
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: totalPks > 0 ? Colors.blue.shade50 : Colors.orange.shade50,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.scale, size: 16, color: totalPks > 0 ? Colors.blue : Colors.orange),
                              const SizedBox(width: 6),
                              Text(
                                totalPks > 0
                                    ? "PKS: ${totalPks.toStringAsFixed(0)} Kg"
                                    : "PKS: Belum ditimbang",
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: totalPks > 0 ? Colors.blue : Colors.orange,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 10),

                        // Tombol Rincian & Hapus
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => DetailTripPage(tripId: item['id']),
                                    ),
                                  );
                                },
                                icon: const Icon(Icons.info_outline, size: 16),
                                label: const Text("Rincian"),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.blue,
                                  side: const BorderSide(color: Colors.blue),
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () => hapusTrip(item['id']),
                                icon: const Icon(Icons.delete_outline, size: 16),
                                label: const Text("Hapus"),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.red,
                                  side: const BorderSide(color: Colors.red),
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}