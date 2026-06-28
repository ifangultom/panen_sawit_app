import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'database_helper.dart';
import 'input_pks_page.dart';
import 'utils/date_utils.dart';

class RiwayatPksPage extends StatefulWidget {
  final DateTime? initialDate;
  final int? initialMonth;
  final int? initialYear;
  final String? initialAfdeling;

  const RiwayatPksPage({
    super.key,
    this.initialDate,
    this.initialMonth,
    this.initialYear,
    this.initialAfdeling,
  });

  @override
  State<RiwayatPksPage> createState() => _RiwayatPksPageState();
}

class _RiwayatPksPageState extends State<RiwayatPksPage> {
  List<Map<String, dynamic>> allData = [];
  List<Map<String, dynamic>> filteredData = [];
  bool isLoading = true;

  String searchQuery = "";
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
    loadData();
  }

  Future<void> loadData() async {
    setState(() => isLoading = true);
    try {
      if (kIsWeb) {
        FirebaseFirestore.instance.collection('pks').snapshots().listen((snapshot) {
          if (mounted) {
            setState(() {
              allData = snapshot.docs.map((doc) {
                var d = doc.data();
                d['id_firebase'] = doc.id;
                // 🔥 Fallback mapping KCS -> AFD
                if (d['afdeling'] == null || d['afdeling'].toString().isEmpty) {
                  d['afdeling'] = AppDateUtils.mapKcsToAfd(d['kcs']?.toString());
                }

                // Unifikasi field kendaraan/no_plat
                d['kendaraan_display'] = d['no_plat'] ?? d['kendaraan'] ?? d['no_kendaraan'] ?? "-";
                
                return d;
              }).toList();
              applyFilter();
              isLoading = false;
            });
          }
        });
        return;
      }

      final db = await DatabaseHelper.instance.database;
      final result = await db.rawQuery('''
        SELECT pks.*, trip.kendaraan, trip.sopir, trip.tanggal as trip_tanggal
        FROM pks
        LEFT JOIN trip ON trip.id = pks.trip_id
        ORDER BY pks.id DESC
      ''');

      setState(() {
        allData = result;
        applyFilter();
        isLoading = false;
      });
    } catch (e) {
      debugPrint("Error loading PKS: $e");
      setState(() => isLoading = false);
    }
  }

  void applyFilter() {
    setState(() {
      filteredData = allData.where((item) {
        // Gunakan mapping afdeling yang sudah dinormalisasi
        String? afd = item['afdeling']?.toString();
        if (afd == null || afd.isEmpty) {
          afd = AppDateUtils.mapKcsToAfd(item['kcs']?.toString());
        }
        
        if (selectedAfdeling != null && afd != selectedAfdeling) return false;

        bool matchesSearch = searchQuery.isEmpty ||
            (item['kendaraan_display']?.toString().toLowerCase() ?? "").contains(searchQuery.toLowerCase()) ||
            (item['sopir']?.toString().toLowerCase() ?? "").contains(searchQuery.toLowerCase()) ||
            (item['no_tiket']?.toString().toLowerCase() ?? "").contains(searchQuery.toLowerCase());

        DateTime? dt = AppDateUtils.parseDate(item['waktu_timbang'] ?? item['trip_tanggal'] ?? item['tanggal_trip'] ?? item['tanggal']);
        
        bool matchesDate = true;
        if (dt != null) {
          if (selectedYear != null) {
            if (dt.year != selectedYear) matchesDate = false;
            if (selectedMonth != null && dt.month != selectedMonth) matchesDate = false;
          } else if (filterTanggal != null) {
            String fDate = filterTanggal!.toIso8601String().split('T')[0];
            String itemDate = dt.toIso8601String().split('T')[0];
            if (fDate != itemDate) matchesDate = false;
          }
        } else {
          matchesDate = (selectedYear == null && filterTanggal == null);
        }
        
        return matchesSearch && matchesDate;
      }).toList();
    });
  }


  Future<void> _pickDate() async {
    DateTime? picked = await showDatePicker(
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
      applyFilter();
    }
  }

  void _resetFilter() {
    setState(() {
      filterTanggal = null;
      selectedMonth = null;
      selectedYear = null;
      selectedAfdeling = null;
      searchQuery = "";
    });
    applyFilter();
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return Column(
        children: [
          _buildFilterBar(),
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator())
                : filteredData.isEmpty
                    ? const Center(child: Text("Tidak ada data PKS"))
                    : _buildDataTable(),
          ),
        ],
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F6),
      appBar: AppBar(
        title: const Text("Monitoring Data PKS", style: TextStyle(fontWeight: FontWeight.bold)),
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
          _buildFilterBar(),
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator())
                : filteredData.isEmpty
                    ? const Center(child: Text("Belum ada data PKS"))
                    : ListView.builder(
                        padding: const EdgeInsets.all(10),
                        itemCount: filteredData.length,
                        itemBuilder: (context, index) {
                          final item = filteredData[index];
                          return Card(
                            elevation: 2,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            margin: const EdgeInsets.only(bottom: 12),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text("🚚 ${item['kendaraan'] ?? item['no_plat'] ?? '-'}",
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                            color: Colors.blue.withOpacity(0.1),
                                            borderRadius: BorderRadius.circular(8)),
                                        child: Text(
                                          "${item['berat_netto'] ?? 0} Kg",
                                          style: const TextStyle(
                                              color: Colors.blue, fontWeight: FontWeight.bold, fontSize: 12),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const Divider(height: 20),
                                  _infoRow(Icons.person, "Sopir", item['sopir'] ?? "-"),
                                  _infoRow(Icons.access_time, "Waktu", item['waktu_timbang'] ?? "-"),
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

  Widget _buildDataTable() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Table(
        border: TableBorder.all(color: Colors.grey.withValues(alpha: 0.2)),
        columnWidths: const {
          0: FixedColumnWidth(50),
          1: FlexColumnWidth(2),
          2: FlexColumnWidth(2),
          3: FlexColumnWidth(3),
          4: FlexColumnWidth(2),
          5: FixedColumnWidth(60),
        },
        children: [
          TableRow(
            decoration: BoxDecoration(color: const Color(0xFF0D47A1).withValues(alpha: 0.1)),
            children: [
              _cell("No", isHeader: true),
              _cell("Kendaraan", isHeader: true),
              _cell("Sopir", isHeader: true),
              _cell("Waktu Timbang", isHeader: true),
              _cell("Netto (Kg)", isHeader: true),
              _cell("Aksi", isHeader: true),
            ],
          ),
          ...filteredData.asMap().entries.map((entry) {
            int idx = entry.key + 1;
            var item = entry.value;
            return TableRow(
              children: [
                _cell("$idx"),
                _cell(item['kendaraan'] ?? item['no_plat'] ?? "-"),
                _cell(item['sopir'] ?? "-"),
                _cell(item['waktu_timbang'] ?? "-"),
                _cell("${item['berat_netto'] ?? 0}"),
                Padding(
                  padding: const EdgeInsets.all(4),
                  child: PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert, size: 18),
                    onSelected: (val) {
                      if (val == 'edit') {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => InputPksPage(tripId: item['trip_id'], data: item))
                        ).then((value) {
                          if (value == true) loadData();
                        });
                      } else if (val == 'delete') {
                        _deleteData(item['id_firebase']).then((_) => loadData());
                      }
                    },
                    itemBuilder: (ctx) => [
                      const PopupMenuItem(
                        value: 'edit',
                        child: Row(children: [
                          Icon(Icons.edit, size: 18, color: Colors.blue),
                          SizedBox(width: 8),
                          Text("Edit", style: TextStyle(color: Colors.blue)),
                        ]),
                      ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Row(children: [
                          Icon(Icons.delete, size: 18, color: Colors.red),
                          SizedBox(width: 8),
                          Text("Hapus", style: TextStyle(color: Colors.red)),
                        ]),
                      ),
                    ],
                  ),
                ),
              ],
            );
          }),
        ],
      ),
    );
  }

  Future<void> _deleteData(String? docId) async {
    if (docId == null) return;
    
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Hapus Data PKS"),
        content: const Text("Yakin ingin menghapus data timbang ini?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("BATAL")),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text("HAPUS", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await FirebaseFirestore.instance.collection('pks').doc(docId).delete();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Data PKS berhasil dihapus")));
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Gagal menghapus: $e")));
        }
      }
    }
  }

  Widget _cell(String text, {bool isHeader = false}) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Text(
        text,
        style: TextStyle(
          fontWeight: isHeader ? FontWeight.bold : FontWeight.normal,
          fontSize: isHeader ? 14 : 13,
        ),
        textAlign: TextAlign.center,
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
          Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13))),
        ],
      ),
    );
  }

  Widget _buildFilterBar() {
    return Container(
      padding: const EdgeInsets.all(12),
      color: Colors.white,
      child: Column(
        children: [
          TextField(
            decoration: InputDecoration(
              hintText: "Cari kendaraan, sopir, atau tiket...",
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 10),
            ),
            onChanged: (value) {
              searchQuery = value;
              applyFilter();
            },
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _filterDropdown<String?>(
                  value: selectedAfdeling,
                  hint: "Afdeling",
                  items: [
                    const DropdownMenuItem(value: null, child: Text("Semua AFD")),
                    ...afdelings.map((a) => DropdownMenuItem(value: a, child: Text(a))),
                  ],
                  onChanged: (v) {
                    setState(() => selectedAfdeling = v);
                    applyFilter();
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _filterDropdown<int?>(
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
                    applyFilter();
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _filterDropdown<int?>(
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
                    applyFilter();
                  },
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(Icons.calendar_month, color: Color(0xFF0D47A1), size: 20),
                onPressed: _pickDate,
              ),
              if (filterTanggal != null || selectedYear != null || selectedAfdeling != null || searchQuery.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.refresh, color: Colors.red, size: 20),
                  onPressed: _resetFilter,
                ),
            ],
          ),
        ],
      ),
    );
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
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T?>(
          value: value,
          isExpanded: true,
          hint: Text(hint, style: const TextStyle(fontSize: 13)),
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
                child: pw.Text("LAPORAN MONITORING PKS", 
                  style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold))),
              pw.SizedBox(height: 10),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text("Tanggal Cetak: ${DateTime.now().toString().split('.')[0]}"),
                  pw.Text("Total Record: ${filteredData.length}"),
                ],
              ),
              pw.Divider(),
              pw.SizedBox(height: 15),
              pw.Table.fromTextArray(
                headers: ["No", "Kendaraan", "Sopir", "Waktu Timbang", "Netto (Kg)"],
                headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10, color: PdfColors.white),
                cellStyle: const pw.TextStyle(fontSize: 9),
                headerDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFF0D47A1)),
                data: filteredData.asMap().entries.map((entry) {
                  int idx = entry.key + 1;
                  var e = entry.value;
                  return [
                    "$idx",
                    e['kendaraan'] ?? "-",
                    e['sopir'] ?? "-",
                    e['waktu_timbang'] ?? "-",
                    "${e['berat_netto'] ?? 0}",
                  ];
                }).toList(),
              ),
            ];
          },
        ),
      );

      if (kIsWeb) {
        await Printing.layoutPdf(
          onLayout: (PdfPageFormat format) async => pdf.save(),
          name: "Laporan_PKS_${DateTime.now().millisecondsSinceEpoch}.pdf",
        );
      } else {
        await Printing.sharePdf(
          bytes: await pdf.save(),
          filename: "Laporan_PKS_${DateTime.now().millisecondsSinceEpoch}.pdf",
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Gagal share PDF: $e")));
      }
    }
  }
}