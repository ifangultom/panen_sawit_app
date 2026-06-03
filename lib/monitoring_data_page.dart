import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'database_helper.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart' as printing_lib;
import 'detail_panen_page.dart';

const Color _primaryBlue = Color(0xFF0D47A1);
const Color _accentBlue = Color(0xFF1976D2);
const Color _bgGrey = Color(0xFFF5F7FA);
const Color _textGelap = Color(0xFF1A237E);
const Color _textAbu = Color(0xFF78909C);

class MonitoringDataPage extends StatefulWidget {
  final List<Map<String, dynamic>>? initialData;
  const MonitoringDataPage({super.key, this.initialData});

  @override
  State<MonitoringDataPage> createState() => _MonitoringDataPageState();
}

class _MonitoringDataPageState extends State<MonitoringDataPage> {
  List<Map<String, dynamic>> allData = [];
  List<Map<String, dynamic>> filteredData = [];
  bool isLoading = true;

  String searchQuery = "";
  String? selectedAfdeling;
  DateTime? filterTanggal;
  int? selectedMonth;
  int? selectedYear;

  final List<String> afdelings = ["AFD1", "AFD2", "AFD3"];
  final List<String> months = [
    "Januari", "Februari", "Maret", "April", "Mei", "Juni",
    "Juli", "Agustus", "September", "Oktober", "November", "Desember"
  ];
  final List<int> years = List.generate(5, (index) => DateTime.now().year - index);

  @override
  void initState() {
    super.initState();
    if (widget.initialData != null) {
      allData = widget.initialData!;
      applyFilter();
      isLoading = false;
    } else {
      loadData();
    }
  }

  Future<void> loadData() async {
    setState(() => isLoading = true);
    List<Map<String, dynamic>> result = [];
    if (kIsWeb) {
      try {
        final snapshot = await FirebaseFirestore.instance.collection('panen').orderBy('tanggal', descending: true).get();
        result = snapshot.docs.map((doc) => doc.data()).toList();
      } catch (e) {
        debugPrint("Error loading firebase: $e");
      }
    } else {
      result = await DatabaseHelper.instance.getAllPanen();
      result.sort((a, b) => (b['tanggal'] ?? '').compareTo(a['tanggal'] ?? ''));
    }
    setState(() {
      allData = result;
      applyFilter();
      isLoading = false;
    });
  }

  void applyFilter() {
    setState(() {
      filteredData = allData.where((item) {
        if (selectedAfdeling != null && item['afdeling'] != selectedAfdeling) return false;

        bool matchesSearch = searchQuery.isEmpty ||
            (item['pemanen']?.toString().toLowerCase() ?? "").contains(searchQuery.toLowerCase()) ||
            (item['blok']?.toString().toLowerCase() ?? "").contains(searchQuery.toLowerCase()) ||
            (item['catatan']?.toString().toLowerCase() ?? "").contains(searchQuery.toLowerCase());

        String? tglStr = item['tanggal']?.toString();
        bool matchesDate = true;
        if (tglStr != null) {
          try {
            DateTime dt = DateTime.parse(tglStr);
            if (selectedYear != null && dt.year != selectedYear) matchesDate = false;
            if (selectedMonth != null && dt.month != selectedMonth) matchesDate = false;
            if (filterTanggal != null) {
              String fDate = filterTanggal!.toIso8601String().split('T')[0];
              if (!tglStr.startsWith(fDate)) matchesDate = false;
            }
          } catch (_) {}
        }

        return matchesSearch && matchesDate;
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgGrey,
      appBar: AppBar(
        title: const Text("Monitoring Data Panen", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: _primaryBlue,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf),
            onPressed: _sharePdf,
            tooltip: "Share PDF",
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: loadData,
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
                    ? const Center(child: Text("Tidak ada data yang cocok"))
                    : kIsWeb 
                        ? _buildWebLayout() 
                        : _buildMobileList(),
          ),
        ],
      ),
    );
  }

  // ================= WEB GRID WITH AFDELING GROUPING =================
  Widget _buildWebLayout() {
    // Terapkan filter tambahan jika ada (biasanya diwarisi dari DashboardAdmin jika dipanggil sebagai widget)
    // Tapi di sini kita asumsikan filteredData sudah benar dari applyFilter()
    
    Map<String, List<Map<String, dynamic>>> groupedData = {};
    for (var item in filteredData) {
      String afd = item['afdeling']?.toString() ?? "N/A";
      groupedData.putIfAbsent(afd, () => []).add(item);
    }
    List<String> sortedAfdelings = groupedData.keys.toList()..sort();

    return ListView.builder(
      padding: const EdgeInsets.all(25),
      itemCount: sortedAfdelings.length,
      itemBuilder: (context, idx) {
        String afd = sortedAfdelings[idx];
        List<Map<String, dynamic>> items = groupedData[afd]!;
        
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 15, left: 5),
              child: Row(
                children: [
                  const Icon(Icons.folder_shared_rounded, color: _accentBlue, size: 22),
                  const SizedBox(width: 10),
                  Text("Afdeling $afd", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _accentBlue)),
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                    decoration: BoxDecoration(color: _accentBlue.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
                    child: Text("${items.length} Records", style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _accentBlue)),
                  ),
                ],
              ),
            ),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4, // 4 Kolom untuk Desktop agar lebih padat
                crossAxisSpacing: 15,
                mainAxisSpacing: 15,
                mainAxisExtent: 180, // Tinggi disesuaikan dengan DashboardAdmin agar konsisten
              ),
              itemCount: items.length,
              itemBuilder: (context, index) => _buildDataCard(items[index], isWeb: true),
            ),
            const SizedBox(height: 35),
          ],
        );
      },
    );
  }

  Widget _buildMobileList() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: filteredData.length,
      itemBuilder: (context, index) => _buildDataCard(filteredData[index], isWeb: false),
    );
  }

  Widget _buildDataCard(Map<String, dynamic> item, {bool isWeb = false}) {
    String status = (item['sync_status'] ?? item['status'] ?? "online").toLowerCase();
    bool isOnline = status == "online" || status == "terkirim" || status == "acc" || status == "synced";

    if (isWeb) {
      // Return a card similar to DashboardAdmin for consistency
      return Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.withValues(alpha: 0.1)),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8, offset: const Offset(0, 2))
          ],
        ),
        child: InkWell(
          onTap: () {
            Navigator.push(context, MaterialPageRoute(builder: (_) => DetailPanenPage(data: item, isReadOnly: true)));
          },
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: SizedBox(
                        width: 70, height: 70,
                        child: _buildThumbnail(item['foto']?.toString() ?? ""),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("Blok ${item['blok'] ?? "-"}", 
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                            overflow: TextOverflow.ellipsis),
                          Text(item['pemanen']?.toString() ?? "-", 
                            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                            overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 4),
                          _statusBadge(status, isOnline),
                        ],
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                const Divider(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _buildStatItem("Matang", item['matang']?.toString() ?? "0", _accentBlue, CrossAxisAlignment.center),
                    _buildStatItem("Mentah", item['mentah']?.toString() ?? "0", Colors.red, CrossAxisAlignment.center),
                    _buildStatItem("Bron.", "${item['brondolan'] ?? 0}kg", Colors.orange, CrossAxisAlignment.center),
                  ],
                ),
                const SizedBox(height: 4),
                Text(item['tanggal']?.toString() ?? "-", 
                  style: TextStyle(fontSize: 10, color: Colors.grey[400])),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => DetailPanenPage(data: item, isReadOnly: true),
              ),
            );
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(item['tanggal']?.toString() ?? "-", style: const TextStyle(color: _textAbu, fontSize: 11)),
                    _statusBadge(status, isOnline),
                  ],
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    // Foto Preview
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: (item['foto'] != null && item['foto'].toString().isNotEmpty)
                          ? _buildThumbnail(item['foto'].toString())
                          : Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(color: _primaryBlue.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
                              child: const Icon(Icons.eco, color: _accentBlue, size: 24),
                            ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("Blok ${item['blok']} (${item['afdeling'] ?? '-'})", 
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: _textGelap)),
                          Text(item['pemanen'] ?? "Tanpa Nama", style: const TextStyle(color: _textAbu, fontSize: 13)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _buildStatItem("Matang", item['matang']?.toString() ?? "0", _primaryBlue, CrossAxisAlignment.start),
                    _buildStatItem("Mentah", item['mentah']?.toString() ?? "0", Colors.red, CrossAxisAlignment.center),
                    _buildStatItem("Brondolan", "${item['brondolan'] ?? 0} Kg", Colors.orange, CrossAxisAlignment.end),
                  ],
                ),
              ),
              const Spacer(),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                color: const Color(0xFFF8F9FA),
                child: Text("Catatan: ${item['catatan'] ?? "-"}", 
                  style: const TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: _textAbu),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatItem(String label, String value, Color color, CrossAxisAlignment align) {
    return Column(
      crossAxisAlignment: align,
      children: [
        Text(label, style: const TextStyle(color: _textAbu, fontSize: 10)),
        const SizedBox(height: 4),
        Text(value, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 14)),
      ],
    );
  }

  Widget _buildFilterBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      decoration: const BoxDecoration(
        color: _primaryBlue,
        borderRadius: BorderRadius.only(bottomLeft: Radius.circular(24), bottomRight: Radius.circular(24)),
      ),
      child: Column(
        children: [
          TextField(
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: "Cari pemanen, blok, atau catatan...",
              hintStyle: TextStyle(color: Colors.white.withOpacity(0.6)),
              prefixIcon: const Icon(Icons.search, color: Colors.white),
              filled: true,
              fillColor: Colors.white.withOpacity(0.15),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(horizontal: 10),
            ),
            onChanged: (value) {
              searchQuery = value;
              applyFilter();
            },
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _filterDropdown<String?>(
                value: selectedAfdeling,
                hint: "Afdeling",
                items: [
                  const DropdownMenuItem(value: null, child: Text("Semua AFD")),
                  ...afdelings.map((a) => DropdownMenuItem(value: a, child: Text(a))),
                ],
                onChanged: (v) { setState(() => selectedAfdeling = v); applyFilter(); },
              )),
              const SizedBox(width: 8),
              Expanded(child: _filterDropdown<int?>(
                value: selectedMonth,
                hint: "Bulan",
                items: [
                  const DropdownMenuItem(value: null, child: Text("Semua")),
                  ...List.generate(12, (i) => DropdownMenuItem(value: i + 1, child: Text(months[i]))),
                ],
                onChanged: (v) { setState(() => selectedMonth = v); applyFilter(); },
              )),
              const SizedBox(width: 8),
              Expanded(child: _filterDropdown<int?>(
                value: selectedYear,
                hint: "Tahun",
                items: [
                  const DropdownMenuItem(value: null, child: Text("Semua")),
                  ...years.map((y) => DropdownMenuItem(value: y, child: Text(y.toString()))),
                ],
                onChanged: (v) { setState(() => selectedYear = v); applyFilter(); },
              )),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: _pickDate,
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), borderRadius: BorderRadius.circular(12)),
                  child: Icon(Icons.calendar_month, color: filterTanggal != null ? Colors.amber : Colors.white, size: 20),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _filterDropdown<T>({required T? value, required String hint, required List<DropdownMenuItem<T?>> items, required ValueChanged<T?> onChanged}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), borderRadius: BorderRadius.circular(12)),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T?>(
          value: value,
          isExpanded: true,
          hint: Text(hint, style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.8))),
          dropdownColor: _primaryBlue,
          icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white, size: 18),
          style: const TextStyle(fontSize: 12, color: Colors.white),
          items: items,
          onChanged: onChanged,
        ),
      ),
    );
  }

  Future<void> _pickDate() async {
    DateTime? picked = await showDatePicker(
      context: context,
      initialDate: filterTanggal ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() => filterTanggal = picked);
      applyFilter();
    }
  }

  Widget _statusBadge(String status, bool isOnline) {
    Color color = isOnline ? _primaryBlue : Colors.orange;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color, width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(isOnline ? Icons.cloud_done : Icons.cloud_off, size: 12, color: color),
          const SizedBox(width: 4),
          Text(status, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildThumbnail(String path) {
    if (path.isEmpty) return _buildPlaceholder();

    if (path.startsWith('data:image')) {
      try {
        final base64Data = path.split(',').last.replaceAll(RegExp(r'\s+'), '');
        return Image.memory(
          base64Decode(base64Data),
          width: 70,
          height: 70,
          fit: BoxFit.cover,
          errorBuilder: (c, e, s) => _buildPlaceholder(icon: Icons.broken_image),
        );
      } catch (e) {
        return _buildPlaceholder(icon: Icons.broken_image);
      }
    }

    if (kIsWeb) {
      return _buildPlaceholder();
    }

    return Image.file(
      File(path),
      width: 70,
      height: 70,
      fit: BoxFit.cover,
      errorBuilder: (c, e, s) => _buildPlaceholder(icon: Icons.broken_image),
    );
  }

  Widget _buildPlaceholder({IconData icon = Icons.image_not_supported}) {
    return Container(
      width: 70,
      height: 70,
      decoration: BoxDecoration(
        color: _primaryBlue.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(icon, color: _accentBlue.withValues(alpha: 0.4), size: 24),
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
                child: pw.Text("LAPORAN MONITORING PANEN SAWIT", 
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
              pw.TableHelper.fromTextArray(
                headers: ["Tanggal", "Pemanen", "Blok", "Afdeling", "Matang", "Mentah", "Brondolan", "Catatan"],
                headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10, color: PdfColors.white),
                cellStyle: const pw.TextStyle(fontSize: 9),
                headerDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFF0D47A1)),
                data: filteredData.map((e) {
                  return [
                    e['tanggal']?.toString().split(" ")[0] ?? "-",
                    e['pemanen'] ?? "-",
                    e['blok'] ?? "-",
                    e['afdeling'] ?? "-",
                    e['matang'] ?? "0",
                    e['mentah'] ?? "0",
                    e['brondolan'] ?? "0",
                    e['catatan'] ?? "-",
                  ];
                }).toList(),
              ),
            ];
          },
        ),
      );

      if (kIsWeb) {
        // Mode Web: Buka jendela cetak/simpan browser
        await printing_lib.Printing.layoutPdf(
          onLayout: (PdfPageFormat format) async => pdf.save(),
          name: "Laporan_Panen_${DateTime.now().millisecondsSinceEpoch}.pdf",
        );
      } else {
        // Mode Mobile: Share menu
        await printing_lib.Printing.sharePdf(
          bytes: await pdf.save(),
          filename: "Laporan_Panen_${DateTime.now().millisecondsSinceEpoch}.pdf",
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Gagal export PDF: $e")));
      }
    }
  }
}
