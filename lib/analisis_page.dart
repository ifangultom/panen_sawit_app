import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'utils/date_utils.dart';

class AnalisisProduksiPage extends StatefulWidget {
  final bool isWebView;
  final List<Map<String, dynamic>> laporanPanen; 

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
    dataBlok = {};
    dataKualitas = {"Matang": 0, "Mentah": 0, "Brondolan": 0};
    totalJanjang = 0;

    final Map<String, List<String>> afdelingToBloks = {
      "AFD1": ["A", "B", "C", "D", "E", "F", "G", "H"],
      "AFD2": ["I", "J", "K", "L", "M", "N", "O"],
      "AFD3": ["P", "Q", "R", "S", "T", "U"],
    };

    if (selectedAfdeling != null) {
      String afdKey = selectedAfdeling!.toUpperCase();
      if (afdelingToBloks.containsKey(afdKey)) {
        for (var b in afdelingToBloks[afdKey]!) { dataBlok["BLOK $b"] = 0; }
      }
    } else {
      for (var afdKey in afdelingToBloks.keys) {
        for (var b in afdelingToBloks[afdKey]!) { dataBlok["BLOK $b"] = 0; }
      }
    }

    for (var item in widget.laporanPanen) {
      String status = (item['status'] ?? item['sync_status'] ?? "").toString().toUpperCase();
      if (status != "ACC") continue;

      String itemAfd = item['afdeling']?.toString() ?? "";
      if (itemAfd.isEmpty) {
        itemAfd = AppDateUtils.mapKcsToAfd(item['kcs']?.toString());
      }
      itemAfd = itemAfd.toUpperCase();

      if (selectedAfdeling != null && itemAfd != selectedAfdeling!.toUpperCase()) continue;

      DateTime? tgl = AppDateUtils.parseDate(item['tanggal'] ?? item['waktu']);
      if (tgl != null) {
        if (selectedMonth != null && tgl.month != selectedMonth) continue;
        if (selectedYear != null && tgl.year != selectedYear) continue;
      }

      String blokRaw = item['blok']?.toString().toUpperCase() ?? "";
      if (blokRaw.isNotEmpty) {
        String blokName = blokRaw.startsWith("BLOK ") ? blokRaw : "BLOK $blokRaw";
        double matang = double.tryParse(item['matang']?.toString() ?? "0") ?? 0;
        double mentah = double.tryParse(item['mentah']?.toString() ?? "0") ?? 0;
        double janjang = double.tryParse(item['janjang']?.toString() ?? "") ?? (matang + mentah);
        
        if (dataBlok.containsKey(blokName)) {
          dataBlok[blokName] = (dataBlok[blokName] ?? 0) + janjang;
          totalJanjang += janjang;
        }
      }

      dataKualitas["Matang"] = (dataKualitas["Matang"] ?? 0) + (double.tryParse(item['matang']?.toString() ?? "0") ?? 0);
      dataKualitas["Mentah"] = (dataKualitas["Mentah"] ?? 0) + (double.tryParse(item['mentah']?.toString() ?? "0") ?? 0);
      dataKualitas["Brondolan"] = (dataKualitas["Brondolan"] ?? 0) + (double.tryParse(item['brondolan']?.toString() ?? "0") ?? 0);
    }
  }

  Map<String, double> _hitungTotalPerAfdeling() {
    Map<String, double> totals = {"AFD1": 0, "AFD2": 0, "AFD3": 0};
    for (var item in widget.laporanPanen) {
      if ((item['status'] ?? item['sync_status'] ?? "").toString().toUpperCase() != "ACC") continue;

      DateTime? tgl = AppDateUtils.parseDate(item['tanggal'] ?? item['waktu']);
      if (tgl != null) {
        if (selectedMonth != null && tgl.month != selectedMonth) continue;
        if (selectedYear != null && tgl.year != selectedYear) continue;
      }

      String itemAfd = item['afdeling']?.toString() ?? "";
      if (itemAfd.isEmpty) {
        itemAfd = AppDateUtils.mapKcsToAfd(item['kcs']?.toString());
      }
      itemAfd = itemAfd.toUpperCase();
      
      if (totals.containsKey(itemAfd)) {
        double matang = double.tryParse(item['matang']?.toString() ?? "0") ?? 0;
        double mentah = double.tryParse(item['mentah']?.toString() ?? "0") ?? 0;
        totals[itemAfd] = (totals[itemAfd] ?? 0) + (matang + mentah);
      }
    }
    return totals;
  }

  void _showAfdDetail(String afdName) {
    // Filter data khusus afdeling ini
    Map<String, double> blockDetail = {};
    for (var item in widget.laporanPanen) {
      if ((item['status'] ?? item['sync_status'] ?? "").toString().toUpperCase() != "ACC") continue;
      
      DateTime? tgl = AppDateUtils.parseDate(item['tanggal'] ?? item['waktu']);
      if (tgl != null) {
        if (selectedMonth != null && tgl.month != selectedMonth) continue;
        if (selectedYear != null && tgl.year != selectedYear) continue;
      }

      String itemAfd = AppDateUtils.mapKcsToAfd(item['afdeling'] ?? item['kcs']);

      if (itemAfd == afdName) {
        String blok = (item['blok'] ?? "-").toString().toUpperCase();
        if (!blok.startsWith("BLOK ")) blok = "BLOK $blok";
        double matang = double.tryParse(item['matang']?.toString() ?? "0") ?? 0;
        double mentah = double.tryParse(item['mentah']?.toString() ?? "0") ?? 0;
        blockDetail[blok] = (blockDetail[blok] ?? 0) + (matang + mentah);
      }
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.domain, color: primaryBlue),
            const SizedBox(width: 10),
            Text("Detail Produksi $afdName"),
          ],
        ),
        content: SizedBox(
          width: 400,
          child: blockDetail.isEmpty 
            ? const Padding(padding: EdgeInsets.all(20), child: Text("Tidak ada data produksi untuk filter ini."))
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Divider(),
                  ...blockDetail.entries.map((e) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(e.key, style: const TextStyle(fontWeight: FontWeight.bold)),
                        Text("${e.value.toStringAsFixed(0)} Janjang", style: TextStyle(color: accentBlue, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  )),
                ],
              ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Tutup")),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    _prosesDataAsli(); 
    final afdTotals = _hitungTotalPerAfdeling();

    double totalJjgHitung = dataKualitas["Matang"]! + dataKualitas["Mentah"]!;
    double nilaiEfisiensi = totalJjgHitung > 0 ? (dataKualitas["Matang"]! / totalJjgHitung * 100) : 0;

    Widget content = SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.isWebView) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Analisis Produksi & Kualitas", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                    Text("Monitoring per Afdeling dan Blok (Data Ter-ACC)", style: TextStyle(fontSize: 14, color: Colors.grey)),
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
            Row(
              children: [
                _afdSummaryCard("AFDELING 1", "${afdTotals['AFD1']?.toStringAsFixed(0)}", "Blok A - H", const Color(0xFF0D47A1), Icons.domain, () => _showAfdDetail("AFD1")),
                const SizedBox(width: 16),
                _afdSummaryCard("AFDELING 2", "${afdTotals['AFD2']?.toStringAsFixed(0)}", "Blok I - O", const Color(0xFF1565C0), Icons.domain, () => _showAfdDetail("AFD2")),
                const SizedBox(width: 16),
                _afdSummaryCard("AFDELING 3", "${afdTotals['AFD3']?.toStringAsFixed(0)}", "Blok P - U", const Color(0xFF1976D2), Icons.domain, () => _showAfdDetail("AFD3")),
              ],
            ),
            const SizedBox(height: 24),
          ],
          
          Row(
            children: [
              _metricCard("Total Janjang", totalJanjang.toStringAsFixed(0), "Janjang", Icons.eco, primaryBlue),
              _metricCard("Blok Aktif", dataBlok.length.toString(), "Blok", Icons.grid_view_rounded, accentBlue),
              _metricCard("Efisiensi", nilaiEfisiensi.toStringAsFixed(1), "%", Icons.speed_rounded, const Color(0xFFFB8C00)),
            ],
          ),
          const SizedBox(height: 25),
          
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 2,
                child: _buildChartContainer(
                  title: "Produksi per Blok",
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
                      }),
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

  Widget _afdSummaryCard(String title, String value, String blocks, Color color, IconData icon, VoidCallback onTap) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [color, color.withValues(alpha: 0.8)], begin: Alignment.topLeft, end: Alignment.bottomRight),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [BoxShadow(color: color.withValues(alpha: 0.3), blurRadius: 12, offset: const Offset(0, 6))],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(title, style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                  const Icon(Icons.info_outline, color: Colors.white30, size: 20),
                ],
              ),
              const SizedBox(height: 12),
              Text(value, style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w900)),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(blocks, style: const TextStyle(color: Colors.white60, fontSize: 13, fontWeight: FontWeight.w500)),
                  const Text("Klik Rincian", style: TextStyle(color: Colors.white30, fontSize: 10)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTimeFilters() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.withValues(alpha: 0.2))),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<int?>(
              value: selectedMonth,
              hint: const Text("Bulan"),
              items: [
                const DropdownMenuItem(value: null, child: Text("Semua Bulan")),
                ...List.generate(months.length, (i) => DropdownMenuItem(value: i + 1, child: Text(months[i]))),
              ],
              onChanged: (val) => setState(() => selectedMonth = val),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.withValues(alpha: 0.2))),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<int?>(
              value: selectedYear,
              hint: const Text("Tahun"),
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
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.withOpacity(0.2))),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String?>(
          value: selectedAfdeling,
          hint: const Text("Semua Afdeling"),
          items: [
            const DropdownMenuItem(value: null, child: Text("Semua Afdeling")),
            ...afdelings.map((afd) => DropdownMenuItem(value: afd, child: Text(afd))),
          ],
          onChanged: (val) => setState(() => selectedAfdeling = val),
        ),
      ),
    );
  }

  Widget _metricCard(String title, String value, String unit, IconData icon, Color color) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.only(right: 15),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10)]),
        child: Row(
          children: [
            Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)), child: Icon(icon, color: color, size: 28)),
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
      width: double.infinity,
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
    var sortedKeys = dataBlok.keys.toList()..sort();
    return BarChartData(
      gridData: const FlGridData(show: false),
      titlesData: FlTitlesData(
        show: true,
        bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, getTitlesWidget: (value, meta) {
          int i = value.toInt();
          if (i >= 0 && i < sortedKeys.length) return Text(sortedKeys[i].replaceAll("BLOK ", ""), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold));
          return const Text("");
        }))),
      borderData: FlBorderData(show: false),
      barGroups: List.generate(sortedKeys.length, (i) => BarChartGroupData(x: i, barRods: [BarChartRodData(toY: dataBlok[sortedKeys[i]]!, color: accentBlue, width: 22, borderRadius: BorderRadius.circular(4))])),
    );
  }

  PieChartData _qualityPieChartData() {
    double sum = dataKualitas.values.fold(0, (a, b) => a + b);
    if (sum == 0) return PieChartData(sections: [PieChartSectionData(value: 1, color: Colors.grey[200], radius: 25, title: '')]);
    return PieChartData(sectionsSpace: 2, centerSpaceRadius: 40, sections: [
      PieChartSectionData(value: dataKualitas["Matang"]!, title: '', color: primaryBlue, radius: 25),
      PieChartSectionData(value: dataKualitas["Mentah"]!, title: '', color: const Color(0xFFFB8C00), radius: 25),
      PieChartSectionData(value: dataKualitas["Brondolan"]!, title: '', color: accentBlue, radius: 25),
    ]);
  }
}
