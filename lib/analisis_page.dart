import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

class AnalisisProduksiPage extends StatefulWidget {
  final bool isWebView;
  final List<Map<String, dynamic>> laporanPanen; // Data asli dari dashboard

  const AnalisisProduksiPage({
    super.key, 
    this.isWebView = false, 
    this.laporanPanen = const []
  });

  @override
  State<AnalisisProduksiPage> createState() => _AnalisisProduksiPageState();
}

class _AnalisisProduksiPageState extends State<AnalisisProduksiPage> {
  final Color primaryBlue = const Color(0xFF0D47A1);
  final Color accentBlue = const Color(0xFF1976D2);
  final Color bgGrey = const Color(0xFFF4F7F6);

  // Variabel Hasil Olah Data
  Map<String, double> dataBlok = {};
  Map<String, double> dataKualitas = {"Matang": 0, "Mentah": 0, "Brondolan": 0};
  double totalJanjang = 0;
  String? selectedAfdeling;
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
    _prosesDataAsli();
  }

  void _prosesDataAsli() {
    // Reset data
    dataBlok = {};
    dataKualitas = {"Matang": 0, "Mentah": 0, "Brondolan": 0};
    totalJanjang = 0;

    // Define Blok per Afdeling (Strict Mapping)
    final Map<String, List<String>> afdelingToBloks = {
      "AFD1": ["A", "B", "C", "D", "E", "F", "G", "H"],
      "AFD2": ["I", "J", "K", "L", "M", "N", "O"],
      "AFD3": ["P", "Q", "R", "S", "T", "U"],
    };

    // 1. Inisialisasi blok sesuai filter Afdeling
    if (selectedAfdeling != null) {
      String afdKey = selectedAfdeling!.replaceAll(" ", "").toUpperCase();
      if (afdelingToBloks.containsKey(afdKey)) {
        for (var b in afdelingToBloks[afdKey]!) {
          dataBlok["BLOK $b"] = 0;
        }
      }
    } else {
      // Jika semua afdeling, tampilkan semua blok dari semua afdeling
      for (var afdKey in afdelingToBloks.keys) {
        for (var b in afdelingToBloks[afdKey]!) {
          dataBlok["BLOK $b"] = 0;
        }
      }
    }

    for (var item in widget.laporanPanen) {
      // 2. Filter Afdeling
      String itemAfd = (item['afdeling'] ?? "").toString().replaceAll(" ", "").toUpperCase();
      if (selectedAfdeling != null) {
        String selAfd = selectedAfdeling!.replaceAll(" ", "").toUpperCase();
        if (itemAfd != selAfd) continue;
      }

      // 3. Filter Waktu
      if (item['tanggal'] != null) {
        try {
          DateTime tgl = DateTime.parse(item['tanggal'].toString());
          if (selectedMonth != null && tgl.month != selectedMonth) continue;
          if (selectedYear != null && tgl.year != selectedYear) continue;
        } catch (_) {}
      }

      // 4. Hitung Produksi per Blok (Hanya jika blok tersebut milik afdeling-nya)
      String blokRaw = item['blok']?.toString().toUpperCase() ?? "";
      if (blokRaw.isNotEmpty) {
        String blokName = blokRaw.startsWith("BLOK ") ? blokRaw : "BLOK $blokRaw";
        
        if (dataBlok.containsKey(blokName)) {
           double janjang = double.tryParse(item['janjang']?.toString() ?? "0") ?? 
                          (double.tryParse(item['matang']?.toString() ?? "0") ?? 0) + 
                          (double.tryParse(item['mentah']?.toString() ?? "0") ?? 0);
          
          dataBlok[blokName] = (dataBlok[blokName] ?? 0) + janjang;
          totalJanjang += janjang;
        }
      }

      // 5. Hitung Kualitas
      int matang = int.tryParse(item['matang']?.toString() ?? "0") ?? 0;
      int mentah = int.tryParse(item['mentah']?.toString() ?? "0") ?? 0;
      double brondolan = double.tryParse(item['brondolan']?.toString() ?? "0") ?? 0;

      dataKualitas["Matang"] = (dataKualitas["Matang"] ?? 0) + matang;
      dataKualitas["Mentah"] = (dataKualitas["Mentah"] ?? 0) + mentah;
      dataKualitas["Brondolan"] = (dataKualitas["Brondolan"] ?? 0) + brondolan;
    }
  }

  // Tambahan untuk menghitung total per Afdeling (untuk Web Dashboard)
  Map<String, double> _hitungTotalPerAfdeling() {
    Map<String, double> totals = {"AFD1": 0, "AFD2": 0, "AFD3": 0};
    final Map<String, List<String>> mapping = {
      "AFD1": ["A", "B", "C", "D", "E", "F", "G", "H"],
      "AFD2": ["I", "J", "K", "L", "M", "N", "O"],
      "AFD3": ["P", "Q", "R", "S", "T", "U"],
    };

    for (var item in widget.laporanPanen) {
      String itemAfd = (item['afdeling'] ?? "").toString().replaceAll(" ", "").toUpperCase();
      String blokRaw = item['blok']?.toString().toUpperCase() ?? "";
      
      if (mapping.containsKey(itemAfd) && mapping[itemAfd]!.contains(blokRaw.replaceAll("BLOK ", ""))) {
        double janjang = double.tryParse(item['janjang']?.toString() ?? "0") ?? 
                        (double.tryParse(item['matang']?.toString() ?? "0") ?? 0) + 
                        (double.tryParse(item['mentah']?.toString() ?? "0") ?? 0);
        totals[itemAfd] = (totals[itemAfd] ?? 0) + janjang;
      }
    }
    return totals;
  }

  @override
  Widget build(BuildContext context) {
    _prosesDataAsli(); 
    final afdTotals = _hitungTotalPerAfdeling();

    Widget content = SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.isWebView) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("Analisis Produksi & Kualitas", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                    const Text("Monitoring per Afdeling dan Blok", style: TextStyle(fontSize: 14, color: Colors.grey)),
                  ],
                ),
                Row(
                  children: [
                    _buildTimeFilters(),
                    const SizedBox(width: 12),
                    _buildAfdFilter(),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 25),

            // --- WEB ONLY: Afdeling Summary Row ---
            Row(
              children: [
                _afdSummaryCard("AFDELING 1", "${afdTotals['AFD1']?.toStringAsFixed(0)}", "Blok A - H", const Color(0xFF0D47A1), Icons.domain),
                const SizedBox(width: 16),
                _afdSummaryCard("AFDELING 2", "${afdTotals['AFD2']?.toStringAsFixed(0)}", "Blok I - O", const Color(0xFF1565C0), Icons.domain),
                const SizedBox(width: 16),
                _afdSummaryCard("AFDELING 3", "${afdTotals['AFD3']?.toStringAsFixed(0)}", "Blok P - U", const Color(0xFF1976D2), Icons.domain),
              ],
            ),
            const SizedBox(height: 24),
          ],
          
          if (!widget.isWebView) ...[
             _buildTimeFilters(),
             const SizedBox(height: 10),
             _buildAfdFilter(),
             const SizedBox(height: 15),
          ],
          
          Row(
            children: [
              _metricCard("Total Janjang", totalJanjang.toStringAsFixed(0), "Janjang", Icons.eco, primaryBlue),
              _metricCard("Blok Aktif", dataBlok.length.toString(), "Blok", Icons.grid_view_rounded, accentBlue),
              _metricCard("Efisiensi", "94", "%", Icons.speed_rounded, const Color(0xFFFB8C00)),
            ],
          ),
          const SizedBox(height: 25),

          _buildBestWorstBlocks(),
          const SizedBox(height: 25),

          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 2,
                child: _buildChartContainer(
                  title: selectedAfdeling == null 
                      ? "Produksi per Blok (A - U)" 
                      : "Produksi per Blok ${selectedAfdeling == 'AFD1' ? '(A - H)' : selectedAfdeling == 'AFD2' ? '(I - O)' : '(P - U)'}",
                  subtitle: "Visualisasi kontribusi janjang tiap blok",
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: (dataBlok.length * 65).toDouble().clamp(widget.isWebView ? 1000 : 800, 3000),
                      height: 350,
                      child: BarChart(_barChartData()),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                flex: 1,
                child: _buildChartContainer(
                  title: "Komposisi Kualitas",
                  subtitle: "Persentase kondisi janjang",
                  child: Column(
                    children: [
                      SizedBox(height: 200, child: PieChart(_qualityPieChartData())),
                      const SizedBox(height: 20),
                      ...dataKualitas.entries.map((e) {
                        double sumKualitas = dataKualitas.values.fold(0, (prev, element) => prev + element);
                        double persen = sumKualitas > 0 ? (e.value / sumKualitas * 100) : 0;
                        Color c = e.key == "Matang" ? primaryBlue : (e.key == "Mentah" ? const Color(0xFFFB8C00) : accentBlue);
                        return _qualityLegendItem(e.key, "${persen.toStringAsFixed(1)}%", c);
                      }).toList(),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 40),
        ],
      ),
    );

    return widget.isWebView ? Container(color: bgGrey, child: content) : Scaffold(
      appBar: AppBar(title: const Text("Analisis Produksi"), backgroundColor: primaryBlue, foregroundColor: Colors.white),
      backgroundColor: bgGrey,
      body: content,
    );
  }

  Widget _afdSummaryCard(String title, String value, String blocks, Color color, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [color, color.withOpacity(0.8)], begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: color.withOpacity(0.3), blurRadius: 12, offset: const Offset(0, 6))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(title, style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                Icon(icon, color: Colors.white30, size: 24),
              ],
            ),
            const SizedBox(height: 12),
            Text(value, style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w900)),
            const SizedBox(height: 4),
            Text(blocks, style: const TextStyle(color: Colors.white60, fontSize: 13, fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }

  Widget _buildBestWorstBlocks() {
    if (dataBlok.isEmpty) return const SizedBox();

    var sortedEntries = dataBlok.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    var best = sortedEntries.first;
    var worst = sortedEntries.last;

    return Row(
      children: [
        Expanded(
          child: _summaryBlockCard(
            "Blok Produksi Tertinggi", 
            best.key, 
            "${best.value.toStringAsFixed(0)} Janjang", 
            Icons.trending_up_rounded, 
            const Color(0xFF0D47A1)
          ),
        ),
        const SizedBox(width: 20),
        Expanded(
          child: _summaryBlockCard(
            "Blok Produksi Terendah", 
            worst.key, 
            "${worst.value.toStringAsFixed(0)} Janjang", 
            Icons.trending_down_rounded, 
            const Color(0xFFD32F2F)
          ),
        ),
      ],
    );
  }

  Widget _summaryBlockCard(String title, String block, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white, 
        borderRadius: BorderRadius.circular(16), 
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)]
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12), 
            decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(12)), 
            child: Icon(icon, color: color, size: 28)
          ),
          const SizedBox(width: 15),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start, 
            children: [
              Text(title, style: const TextStyle(color: Colors.grey, fontSize: 12)),
              Text(block, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: color)),
            ]
          ),
        ],
      ),
    );
  }

  Widget _buildTimeFilters() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Filter Bulan
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.withOpacity(0.2)),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 5)],
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<int?>(
              value: selectedMonth,
              hint: const Text("Bulan"),
              icon: const Icon(Icons.calendar_month, color: Colors.blue, size: 20),
              items: [
                const DropdownMenuItem(value: null, child: Text("Semua Bulan")),
                ...List.generate(months.length, (i) => DropdownMenuItem(value: i + 1, child: Text(months[i]))),
              ],
              onChanged: (val) => setState(() => selectedMonth = val),
            ),
          ),
        ),
        const SizedBox(width: 8),
        // Filter Tahun
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.withOpacity(0.2)),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 5)],
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<int?>(
              value: selectedYear,
              hint: const Text("Tahun"),
              icon: const Icon(Icons.event_note, color: Colors.orange, size: 20),
              items: [
                const DropdownMenuItem(value: null, child: Text("Semua Tahun")),
                ...years.map((y) => DropdownMenuItem(value: y, child: Text(y.toString()))),
              ],
              onChanged: (val) => setState(() => selectedYear = val),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAfdFilter() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withOpacity(0.2)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 5)],
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String?>(
          value: selectedAfdeling,
          hint: const Text("Pilih Afdeling"),
          icon: Icon(Icons.filter_list_alt, color: primaryBlue),
          items: [
            const DropdownMenuItem(value: null, child: Text("Semua Afdeling")),
            ...afdelings.map((afd) => DropdownMenuItem(value: afd, child: Text(afd))),
          ],
          onChanged: (val) {
            setState(() {
              selectedAfdeling = val;
            });
          },
        ),
      ),
    );
  }

  Widget _metricCard(String title, String value, String unit, IconData icon, Color color) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.only(right: 15),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)]),
        child: Row(
          children: [
            Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(12)), child: Icon(icon, color: color, size: 28)),
            const SizedBox(width: 15),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(color: Colors.grey, fontSize: 13)),
              Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _buildChartContainer({required String title, required String subtitle, required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        Text(subtitle, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 25),
        child,
      ]),
    );
  }

  Widget _qualityLegendItem(String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Container(width: 12, height: 12, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 10),
        Text(label),
        const Spacer(),
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
      ]),
    );
  }

  BarChartData _barChartData() {
    // Sort blok A-Z
    var sortedKeys = dataBlok.keys.toList()..sort();
    
    return BarChartData(
      gridData: const FlGridData(show: false),
      titlesData: FlTitlesData(
        show: true,
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            getTitlesWidget: (value, meta) {
              int i = value.toInt();
              if (i >= 0 && i < sortedKeys.length) {
                return Text(sortedKeys[i].replaceAll("BLOK ", ""), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold));
              }
              return const Text("");
            },
          ),
        ),
        leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      ),
      borderData: FlBorderData(show: false),
      barGroups: List.generate(sortedKeys.length, (i) {
        return BarChartGroupData(x: i, barRods: [
          BarChartRodData(toY: dataBlok[sortedKeys[i]]!, color: accentBlue, width: 22, borderRadius: BorderRadius.circular(4))
        ]);
      }),
    );
  }

  PieChartData _qualityPieChartData() {
    return PieChartData(
      sectionsSpace: 2,
      centerSpaceRadius: 40,
      sections: [
        PieChartSectionData(value: dataKualitas["Matang"]!, title: '', color: primaryBlue, radius: 25),
        PieChartSectionData(value: dataKualitas["Mentah"]!, title: '', color: const Color(0xFFFB8C00), radius: 25),
        PieChartSectionData(value: dataKualitas["Brondolan"]!, title: '', color: accentBlue, radius: 25),
      ],
    );
  }
}
