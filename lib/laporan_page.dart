import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
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
  late String tanggal;
  int totalTrip = 0;
  int totalPanen = 0;
  int totalJanjang = 0;
  double totalBrondolan = 0;
  double totalPks = 0;
  bool isLoading = true;

  List<Map<String, dynamic>> listDetailPanen = [];
  List<Map<String, dynamic>> listDetailTrip = [];

  String? selectedAfdeling;
  DateTime? startDate;
  DateTime? endDate;
  int? selectedMonth;
  int? selectedYear;

  final List<String> months = [
    'Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni',
    'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember'
  ];
  final List<int> years = List.generate(5, (index) => DateTime.now().year - index);

  @override
  void initState() {
    super.initState();
    tanggal = widget.tanggal;
    selectedAfdeling = widget.initialAfdeling;
    selectedMonth = widget.initialMonth ?? DateTime.now().month;
    selectedYear = widget.initialYear ?? DateTime.now().year;

    if (widget.initialStartDate != null && widget.initialEndDate != null) {
      startDate = widget.initialStartDate;
      endDate = widget.initialEndDate;
    } else {
      startDate = DateTime(selectedYear!, selectedMonth!, 1);
      endDate = DateTime(selectedYear!, selectedMonth! + 1, 0);
    }
    _init();
  }

  Future<void> _init() async {
    if (selectedAfdeling == null && !widget.lockAfdeling) {
      final prefs = await SharedPreferences.getInstance();
      selectedAfdeling = prefs.getString('afd_login');
    }
    
    // Ensure selectedAfdeling is "ALL" if null to avoid dropdown assertion errors
    if (selectedAfdeling == null || selectedAfdeling!.isEmpty) {
      selectedAfdeling = "ALL";
    }
    
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      setState(() => isLoading = true);

      List<Map<String, dynamic>> allPanen = [];
      List<Map<String, dynamic>> allTrips = [];
      List<Map<String, dynamic>> allPks = [];
      List<Map<String, dynamic>> allDetails = [];

      if (widget.isWebView && widget.preloadedPanen != null) {
        allPanen = widget.preloadedPanen!;
        allTrips = widget.preloadedTrips ?? [];
        allPks = widget.preloadedPks ?? [];
      } else {
        final db = await DatabaseHelper.instance.database;
        allPanen = await db.query('panen');
        allTrips = await db.query('trip');
        allPks = await db.query('pks');
        allDetails = await db.query('trip_detail');
      }

      // Map for faster lookup
      final Map<dynamic, Map<String, dynamic>> panenMap = {
        for (var p in allPanen) (p['id'] ?? p['id_firebase']): p
      };

      // Filter Panen
      List<Map<String, dynamic>> fPanen = allPanen.where((p) {
        String? afd = p['afdeling']?.toString() ?? p['afd']?.toString();
        if (afd == null || afd.isEmpty) {
          String kcs = p['kcs']?.toString() ?? "";
          if (kcs == "KCS1") afd = "AFD1";
          else if (kcs == "KCS2") afd = "AFD2";
          else if (kcs == "KCS3") afd = "AFD3";
        }
        if (selectedAfdeling != null && selectedAfdeling != "ALL" && afd != selectedAfdeling) return false;
        return _isWithinFilter(_parseDate(p['tanggal'] ?? p['waktu']));
      }).toList();

      // Proses Trip & Hitung Total PKS
      List<Map<String, dynamic>> fTrips = [];
      double sPks = 0;
      for (var t in allTrips) {
        String? afd = t['afdeling']?.toString();
        if (selectedAfdeling != null && selectedAfdeling != "ALL" && afd != selectedAfdeling) continue;
        if (!_isWithinFilter(_parseDate(t['tanggal'] ?? t['tanggal_trip']))) continue;

        var tId = t['id'] ?? t['id_firebase'];
        int jjg = 0;
        int muat = 0;

        if (widget.isWebView && t.containsKey('jumlah_panen')) {
          muat = int.tryParse(t['jumlah_panen'].toString()) ?? 0;
          // Ambil janjang dari field jjg, janjang, atau total_janjang (Firestore)
          jjg = int.tryParse((t['jjg'] ?? t['janjang'] ?? t['total_janjang'] ?? "0").toString()) ?? 0;
        } else {
          var details = allDetails.where((d) => d['trip_id'] == tId);
          muat = details.length;
          for (var d in details) {
            var pId = d['panen_id'];
            var pData = panenMap[pId];
            if (pData != null) {
              jjg += (int.tryParse(pData['matang']?.toString() ?? "0") ?? 0) + 
                     (int.tryParse(pData['mentah']?.toString() ?? "0") ?? 0);
            }
          }
        }

        double netto = 0;
        if (widget.isWebView && t.containsKey('total_pks')) {
          netto = double.tryParse(t['total_pks'].toString()) ?? 0;
        } else if (widget.isWebView && t.containsKey('netto_pks')) {
          netto = double.tryParse(t['netto_pks'].toString()) ?? 0;
        } else if (widget.isWebView && t.containsKey('berat_netto')) {
          netto = double.tryParse(t['berat_netto'].toString()) ?? 0;
        } else {
          var pksMatch = allPks.where((p) => p['trip_id'] == tId).toList();
          if (pksMatch.isNotEmpty) {
            var v = pksMatch.first['berat_netto'] ?? pksMatch.first['netto'] ?? pksMatch.first['berat'] ?? 0;
            netto = v is num ? v.toDouble() : double.tryParse(v.toString()) ?? 0;
          }
        }

        fTrips.add({
          ...t,
          'muat': muat,
          'jjg': jjg,
          'netto_pks': netto,
        });
        sPks += netto;
      }

      int sJ = 0; double sB = 0;
      for (var p in fPanen) {
        sJ += (int.tryParse(p['matang']?.toString() ?? "0") ?? 0) + (int.tryParse(p['mentah']?.toString() ?? "0") ?? 0);
        sB += double.tryParse(p['brondolan']?.toString() ?? "0") ?? 0;
      }

      if (mounted) {
        setState(() {
          listDetailPanen = fPanen;
          listDetailTrip = fTrips;
          totalPanen = fPanen.length;
          totalJanjang = sJ;
          totalBrondolan = sB;
          totalTrip = fTrips.length;
          totalPks = sPks;
          isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error loading data: $e");
      if (mounted) setState(() => isLoading = false);
    }
  }

  bool _isWithinFilter(DateTime? dt) {
    if (dt == null) return false;
    DateTime d = DateTime(dt.year, dt.month, dt.day);
    DateTime s = DateTime(startDate!.year, startDate!.month, startDate!.day);
    DateTime e = DateTime(endDate!.year, endDate!.month, endDate!.day);
    return !d.isBefore(s) && !d.isAfter(e);
  }

  DateTime? _parseDate(dynamic val) {
    if (val == null || val.toString().isEmpty) return null;
    String s = val.toString();
    try {
      // Handle yyyy-MM-dd HH:mm:ss or yyyy-MM-dd
      if (s.contains('-') && s.indexOf('-') == 4) {
        return DateTime.parse(s);
      }
      // Handle dd-MM-yyyy
      if (s.contains('-') && s.indexOf('-') == 2) {
        return DateFormat("dd-MM-yyyy").parse(s);
      }
      // Fallback
      return DateTime.tryParse(s);
    } catch (_) {
      return null;
    }
  }

  Future<void> _generatePdf() async {
    if (listDetailPanen.isEmpty && listDetailTrip.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Data kosong, tidak dapat mengekspor PDF"),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    // Tampilkan loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      // Memuat font Roboto agar semua karakter (huruf & angka) muncul dengan benar di PDF
      final font = await PdfGoogleFonts.robotoRegular();
      final boldFont = await PdfGoogleFonts.robotoBold();

      final pdf = pw.Document(
        theme: pw.ThemeData.withFont(
          base: font,
          bold: boldFont,
        ),
      );
      final dateFormat = DateFormat('dd-MM-yyyy');
      final periodStr = "${dateFormat.format(startDate!)} s/d ${dateFormat.format(endDate!)}";

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(32),
          header: (context) => pw.Column(
            children: [
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(widget.isWebView ? "LAPORAN PANEN SAWIT" : "LAPORAN PRODUKSI MANDOR", 
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 16)),
                  pw.Text(dateFormat.format(DateTime.now()), style: const pw.TextStyle(fontSize: 10)),
                ],
              ),
              pw.Divider(thickness: 1),
              pw.SizedBox(height: 10),
            ]
          ),
          footer: (context) => pw.Container(
            alignment: pw.Alignment.centerRight,
            margin: const pw.EdgeInsets.only(top: 10),
            child: pw.Text('Halaman ${context.pageNumber} dari ${context.pagesCount}',
              style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey)),
          ),
          build: (context) => [
            pw.SizedBox(height: 10),
            pw.Text("Periode: $periodStr"),
            pw.Text("Afdeling: ${(selectedAfdeling == null || selectedAfdeling == 'ALL') ? 'Semua' : selectedAfdeling}"),
            pw.SizedBox(height: 20),

            // Ringkasan Section
            pw.Text("RINGKASAN OPERASIONAL", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12)),
            pw.SizedBox(height: 8),
            pw.Table.fromTextArray(
              headers: ["Kategori", "Nilai"],
              data: [
                ["Total Timbang PKS", "${totalPks.toStringAsFixed(0)} Kg"],
                ["Total Panen (Blok)", "$totalPanen"],
                ["Total Janjang", "$totalJanjang"],
                ["Total Brondolan", "${totalBrondolan.toStringAsFixed(1)} Kg"],
                ["Total Trip", "$totalTrip"],
              ],
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.blue800),
              cellAlignment: pw.Alignment.centerLeft,
              cellStyle: const pw.TextStyle(fontSize: 10),
            ),
            pw.SizedBox(height: 25),

            // Tabel Rincian Per Blok
            if (listDetailPanen.isNotEmpty) ...[
              pw.Text("RINCIAN PER BLOK", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12)),
              pw.SizedBox(height: 8),
              pw.Table.fromTextArray(
                headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10, color: PdfColors.white),
                headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey800),
                cellStyle: const pw.TextStyle(fontSize: 9),
                headers: ["Blok", "Pemanen", "Jjg", "Bron (Kg)"],
                data: listDetailPanen.map((p) => [
                  p['blok']?.toString() ?? "-",
                  p['pemanen']?.toString() ?? "-",
                  ((int.tryParse(p['matang']?.toString() ?? "0") ?? 0) + (int.tryParse(p['mentah']?.toString() ?? "0") ?? 0)).toString(),
                  (double.tryParse(p['brondolan']?.toString() ?? "0") ?? 0).toStringAsFixed(1)
                ]).toList(),
              ),
              pw.SizedBox(height: 25),
            ],

            // Tabel Riwayat Trip
            if (listDetailTrip.isNotEmpty) ...[
              pw.Text("RIWAYAT TRIP MOBIL", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12)),
              pw.SizedBox(height: 8),
              pw.Table.fromTextArray(
                headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10, color: PdfColors.white),
                headerDecoration: const pw.BoxDecoration(color: PdfColors.green800),
                cellStyle: const pw.TextStyle(fontSize: 9),
                headers: ["No Plat", "Sopir", "Muat", "Jjg", "Netto PKS (Kg)"],
                data: listDetailTrip.map((t) => [
                  t['no_plat']?.toString() ?? "-",
                  t['sopir']?.toString() ?? "-",
                  t['muat']?.toString() ?? "0",
                  t['jjg']?.toString() ?? "0",
                  "${t['netto_pks']?.toStringAsFixed(0) ?? 0}"
                ]).toList(),
              ),
            ],
            
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 40),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.end,
                children: [
                  pw.Column(
                    children: [
                      pw.Text("Dicetak pada: ${DateFormat('dd MMM yyyy HH:mm').format(DateTime.now())}", style: const pw.TextStyle(fontSize: 8)),
                      pw.SizedBox(height: 40),
                      pw.Text(widget.isWebView ? "KRANI PRODUKSI" : "Mandor Produksi,", style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                      pw.SizedBox(height: 50),
                      pw.Container(
                        width: 120, 
                        decoration: const pw.BoxDecoration(
                          border: pw.Border(bottom: pw.BorderSide(width: 1))
                        )
                      ),
                      pw.SizedBox(height: 4),
                      pw.Text("( ____________________ )", style: const pw.TextStyle(fontSize: 10)),
                    ]
                  )
                ]
              )
            )
          ],
        ),
      );

      if (mounted) Navigator.pop(context); // Tutup loading dialog

      await Printing.sharePdf(
        bytes: await pdf.save(),
        filename: "${widget.isWebView ? 'Laporan_Panen_Sawit' : 'Laporan_Produksi'}_${dateFormat.format(startDate!)}.pdf",
      );
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Tutup loading dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Gagal membuat PDF: $e"), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isWebView) {
      return isLoading 
        ? const Center(child: CircularProgressIndicator())
        : _buildWebViewLayout();
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back),
        ),
        title: Text(widget.isWebView ? "Laporan Panen Sawit" : "Laporan Produksi Mandor",
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            onPressed: _generatePdf,
            icon: const Icon(Icons.picture_as_pdf_outlined),
            tooltip: "Export PDF",
          ),
          const SizedBox(width: 8),
        ],
        backgroundColor: const Color(0xFF1565C0),
        foregroundColor: Colors.white,
      ),
      body: isLoading 
        ? const Center(child: CircularProgressIndicator())
        : SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Filter Section
                _buildFilters(),
                const SizedBox(height: 20),

                // Main Production Card
                _buildMainProductionCard(),
                const SizedBox(height: 24),

                const Text("RINGKASAN OPERASIONAL", 
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, letterSpacing: 1.1)),
                const SizedBox(height: 16),
                
                // Stat Cards Grid
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 16,
                  crossAxisSpacing: 16,
                  childAspectRatio: 1.5,
                  children: [
                    _statCard("Total Panen", "$totalPanen", Icons.inventory_2, Colors.blue),
                    _statCard("Total Janjang", "$totalJanjang", Icons.eco, Colors.orange),
                    _statCard("Brondolan", "${totalBrondolan.toStringAsFixed(1)} Kg", Icons.scale, Colors.purple),
                    _statCard("Total Trip", "$totalTrip", Icons.local_shipping, Colors.green),
                  ],
                ),
                const SizedBox(height: 32),

                const Text("RINCIAN PER BLOK", 
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, letterSpacing: 1.1)),
                const SizedBox(height: 12),
                _buildBlokTable(),
                
                const SizedBox(height: 32),
                const Text("RIWAYAT TRIP MOBIL", 
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, letterSpacing: 1.1)),
                const SizedBox(height: 12),
                _buildTripTable(),
                const SizedBox(height: 40),
              ],
            ),
          ),
    );
  }

  Widget _buildWebViewLayout() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Web Horizontal Filters
          _buildWebFilters(),
          const SizedBox(height: 24),

          // Main Production Banner
          _buildMainProductionCard(),
          const SizedBox(height: 32),

          const Text("RINGKASAN OPERASIONAL", 
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, letterSpacing: 1.1, color: Color(0xFF0D47A1))),
          const SizedBox(height: 20),
          
          // Stat Cards in a Row for Web
          Row(
            children: [
              Expanded(child: _statCard("Total Panen", "$totalPanen", Icons.inventory_2, Colors.blue)),
              const SizedBox(width: 16),
              Expanded(child: _statCard("Total Janjang", "$totalJanjang", Icons.eco, Colors.orange)),
              const SizedBox(width: 16),
              Expanded(child: _statCard("Brondolan", "${totalBrondolan.toStringAsFixed(1)} Kg", Icons.scale, Colors.purple)),
              const SizedBox(width: 16),
              Expanded(child: _statCard("Total Trip", "$totalTrip", Icons.local_shipping, Colors.green)),
            ],
          ),
          const SizedBox(height: 40),

          // Side-by-side Tables for Web
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("RINCIAN PER BLOK", 
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, letterSpacing: 1.1)),
                    const SizedBox(height: 12),
                    _buildBlokTable(),
                  ],
                ),
              ),
              const SizedBox(width: 24),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("RIWAYAT TRIP MOBIL", 
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, letterSpacing: 1.1)),
                    const SizedBox(height: 12),
                    _buildTripTable(isWeb: true),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildWebFilters() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)],
      ),
      child: Row(
        children: [
          const Icon(Icons.filter_list, color: Color(0xFF0D47A1)),
          const SizedBox(width: 16),
          // Filter Afdeling
          Expanded(
            child: DropdownButtonFormField<String>(
              value: (selectedAfdeling == null || selectedAfdeling == "") ? "ALL" : selectedAfdeling,
              decoration: const InputDecoration(
                labelText: "Afdeling", 
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              items: [
                const DropdownMenuItem(value: "ALL", child: Text("Semua AFD")),
                ...['AFD1', 'AFD2', 'AFD3'].map((a) => DropdownMenuItem(value: a, child: Text(a))),
              ],
              onChanged: widget.lockAfdeling ? null : (v) => setState(() { selectedAfdeling = v; _loadData(); }),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: DropdownButtonFormField<int>(
              value: selectedMonth,
              decoration: const InputDecoration(
                labelText: "Bulan", 
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              items: List.generate(12, (i) => DropdownMenuItem(value: i + 1, child: Text(months[i]))),
              onChanged: (v) => setState(() { selectedMonth = v; _updateDatesFromMonthYear(); }),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: DropdownButtonFormField<int>(
              value: selectedYear,
              decoration: const InputDecoration(
                labelText: "Tahun", 
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              items: years.map((y) => DropdownMenuItem(value: y, child: Text(y.toString()))).toList(),
              onChanged: (v) => setState(() { selectedYear = v; _updateDatesFromMonthYear(); }),
            ),
          ),
          const SizedBox(width: 12),
          ElevatedButton.icon(
            onPressed: () async {
              final picked = await showDateRangePicker(
                context: context,
                firstDate: DateTime(2020),
                lastDate: DateTime(2100),
                initialDateRange: DateTimeRange(start: startDate!, end: endDate!),
              );
              if (picked != null) {
                setState(() {
                  startDate = picked.start;
                  endDate = picked.end;
                  selectedMonth = null;
                });
                _loadData();
              }
            },
            icon: const Icon(Icons.calendar_month),
            label: const Text("Pilih Rentang"),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE3F2FD),
              foregroundColor: const Color(0xFF1565C0),
              elevation: 0,
              padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
            ),
          ),
          const SizedBox(width: 12),
          IconButton(
            onPressed: _loadData,
            icon: const Icon(Icons.refresh),
            style: IconButton.styleFrom(
              backgroundColor: Colors.grey.shade100,
              padding: const EdgeInsets.all(12),
            ),
          ),
          const SizedBox(width: 12),
          ElevatedButton.icon(
            onPressed: _generatePdf,
            icon: const Icon(Icons.picture_as_pdf),
            label: const Text("Export PDF"),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilters() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)],
      ),
      child: Column(
        children: [
          if (!widget.lockAfdeling) ...[
            DropdownButtonFormField<String>(
              value: (selectedAfdeling == null || selectedAfdeling == "") ? "ALL" : selectedAfdeling,
              decoration: const InputDecoration(labelText: "Afdeling", border: OutlineInputBorder()),
              items: [
                const DropdownMenuItem(value: "ALL", child: Text("Semua AFD")),
                ...['AFD1', 'AFD2', 'AFD3'].map((a) => DropdownMenuItem(value: a, child: Text(a))),
              ],
              onChanged: (v) => setState(() { selectedAfdeling = v; _loadData(); }),
            ),
            const SizedBox(height: 12),
          ],
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<int>(
                  value: selectedMonth,
                  decoration: const InputDecoration(labelText: "Bulan", border: OutlineInputBorder()),
                  items: List.generate(12, (i) => DropdownMenuItem(value: i + 1, child: Text(months[i]))),
                  onChanged: (v) => setState(() { selectedMonth = v; _updateDatesFromMonthYear(); }),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<int>(
                  value: selectedYear,
                  decoration: const InputDecoration(labelText: "Tahun", border: OutlineInputBorder()),
                  items: years.map((y) => DropdownMenuItem(value: y, child: Text(y.toString()))).toList(),
                  onChanged: (v) => setState(() { selectedYear = v; _updateDatesFromMonthYear(); }),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () async {
                    final picked = await showDateRangePicker(
                      context: context,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2100),
                      initialDateRange: DateTimeRange(start: startDate!, end: endDate!),
                    );
                    if (picked != null) {
                      setState(() {
                        startDate = picked.start;
                        endDate = picked.end;
                        selectedMonth = null; // Clear month/year dropdown selection if custom range picked
                      });
                      _loadData();
                    }
                  },
                  icon: const Icon(Icons.calendar_month),
                  label: const Text("Pilih Tanggal"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE3F2FD),
                    foregroundColor: const Color(0xFF1565C0),
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              IconButton(
                onPressed: _loadData,
                icon: const Icon(Icons.refresh),
                style: IconButton.styleFrom(backgroundColor: Colors.grey.shade100),
              )
            ],
          )
        ],
      ),
    );
  }

  void _updateDatesFromMonthYear() {
    if (selectedMonth != null && selectedYear != null) {
      startDate = DateTime(selectedYear!, selectedMonth!, 1);
      endDate = DateTime(selectedYear!, selectedMonth! + 1, 0);
      _loadData();
    }
  }

  Widget _buildMainProductionCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1E88E5), Color(0xFF1565C0)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.blue.withOpacity(0.3), blurRadius: 15, offset: const Offset(0, 5))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("LAPORAN PRODUKSI", 
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18, letterSpacing: 1.2)),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.calendar_today, color: Colors.white70, size: 14),
              const SizedBox(width: 8),
              Text("Periode: ${DateFormat('yyyy-MM-dd').format(startDate!)} s/d ${DateFormat('yyyy-MM-dd').format(endDate!)}",
                style: const TextStyle(color: Colors.white70, fontSize: 13)),
            ],
          ),
          const SizedBox(height: 24),
          const Text("TOTAL TIMBANG PKS", 
            style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w500)),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("${totalPks.toStringAsFixed(0)} KG", 
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 32)),
              const Icon(Icons.domain, color: Colors.white24, size: 48),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Icon(icon, color: color, size: 24),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: TextStyle(color: Colors.grey.shade600, fontSize: 11)),
              Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBlokTable() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Column(
          children: [
            _tableHeader(["Blok", "Pemanen", "Jjg", "Bron (Kg)"], isBlue: true),
            if (listDetailPanen.isEmpty) const Padding(padding: EdgeInsets.all(20), child: Text("Data tidak ditemukan")),
            ...listDetailPanen.map((p) => _tableRow([
              p['blok']?.toString() ?? "-",
              p['pemanen']?.toString() ?? "-",
              ((int.tryParse(p['matang']?.toString() ?? "0") ?? 0) + (int.tryParse(p['mentah']?.toString() ?? "0") ?? 0)).toString(),
              (double.tryParse(p['brondolan']?.toString() ?? "0") ?? 0).toStringAsFixed(1)
            ])),
          ],
        ),
      ),
    );
  }

  Widget _buildTripTable({bool isWeb = false}) {
    Widget table = Container(
      width: isWeb ? null : 450,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Column(
          children: [
            _tableHeader(["No Plat", "Sopir", "Muat", "Jjg", "PKS"], isDark: true),
            if (listDetailTrip.isEmpty) const Padding(padding: EdgeInsets.all(20), child: Text("Data tidak ditemukan")),
            ...listDetailTrip.map((t) => _tableRow([
              t['no_plat']?.toString() ?? "-",
              t['sopir']?.toString() ?? "-",
              t['muat']?.toString() ?? "0",
              t['jjg']?.toString() ?? "0",
              "${t['netto_pks']?.toStringAsFixed(0) ?? 0}"
            ])),
          ],
        ),
      ),
    );

    if (isWeb) return table;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: table,
    );
  }

  Widget _tableHeader(List<String> cols, {bool isBlue = false, bool isDark = false}) {
    Color bg = Colors.grey.shade50;
    Color textCol = Colors.black87;
    if (isBlue) { bg = const Color(0xFF1E88E5).withAlpha(26); textCol = const Color(0xFF1565C0); }
    if (isDark) { bg = Colors.blueGrey.shade50; textCol = Colors.blueGrey.shade900; }

    return Container(
      color: bg,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
      child: Row(
        children: cols.map((c) => Expanded(child: Text(c, 
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: textCol)))).toList(),
      ),
    );
  }

  Widget _tableRow(List<String> cells) {
    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: Colors.grey.shade100)),
      ),
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
      child: Row(
        children: cells.map((c) => Expanded(child: Text(c, style: const TextStyle(fontSize: 12, color: Colors.black87)))).toList(),
      ),
    );
  }
}
