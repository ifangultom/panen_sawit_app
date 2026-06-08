import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'database_helper.dart';
import 'detail_pemanen_page.dart';
import 'utils/date_utils.dart';

class DashboardStatistikMandor extends StatefulWidget {
  const DashboardStatistikMandor({super.key});

  @override
  State<DashboardStatistikMandor> createState() =>
      _DashboardStatistikMandorState();
}

class _DashboardStatistikMandorState
    extends State<DashboardStatistikMandor> {
  int totalJanjang = 0;
  int totalBrondolan = 0;
  int totalTrip = 0;
  int totalPanen = 0;

  Map<String, int> totalKCS = {};
  List<Map<String, dynamic>> data = [];

  String selectedKCS = "Semua";
  String kcsLogin = "";
  DateTime? filterTanggal;

  // Untuk highlight bar chart
  int? touchedIndex;

  @override
  void initState() {
    super.initState();
    _loadKcs();
  }

  Future<void> _loadKcs() async {
    final prefs = await SharedPreferences.getInstance();
    kcsLogin = prefs.getString('kcs_login') ?? "KCS1";
    loadData();
  }

  void loadData() async {
    final db = await DatabaseHelper.instance.database;

    String whereClause = "1=1";
    List<dynamic> args = [];

    if (filterTanggal != null) {
      final tgl = filterTanggal!.toString().split(" ")[0];
      whereClause += " AND substr(tanggal,1,10) = ?";
      args.add(tgl);
    }

    final result = await db.rawQuery(
      "SELECT * FROM panen WHERE $whereClause ORDER BY id DESC",
      args,
    );

    // Trip stats
    String tripWhere = "t.kcs = ?";
    List<dynamic> tripArgs = [kcsLogin];
    if (filterTanggal != null) {
      final tgl = filterTanggal!.toString().split(" ")[0];
      tripWhere += " AND substr(t.tanggal,1,10) = ?";
      tripArgs.add(tgl);
    }

    final tripResult = await db.rawQuery('''
      SELECT COUNT(DISTINCT t.id) as total_trip
      FROM trip t
      WHERE $tripWhere
    ''', tripArgs);

    Map<String, int> kcsTemp = {};
    int totalJ = 0;
    int totalB = 0;

    for (var item in result) {
      int janjang = int.tryParse(item['matang'].toString()) ?? 0;
      int brond = int.tryParse(item['brondolan'].toString()) ?? 0;
      totalJ += janjang;
      totalB += brond;
      String kcs = item['kcs']?.toString() ?? "Lainnya";
      kcsTemp[kcs] = (kcsTemp[kcs] ?? 0) + janjang;
    }

    setState(() {
      data = result;
      totalJanjang = totalJ;
      totalBrondolan = totalB;
      totalPanen = result.length;
      totalKCS = kcsTemp;
      totalTrip = int.tryParse(
          tripResult.first['total_trip'].toString()) ??
          0;
    });
  }

  // ================= FILTER TANGGAL =================
  Future<void> _pilihTanggal() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: filterTanggal ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      builder: (context, child) => Theme(
        data: ThemeData.light().copyWith(
          colorScheme: const ColorScheme.light(
              primary: Color(0xFF1565C0)),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() => filterTanggal = picked);
      loadData();
    }
  }

  void _resetFilter() {
    setState(() => filterTanggal = null);
    loadData();
  }

  String _formatTanggal(DateTime dt) {
    const bulan = [
      '',
      'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun',
      'Jul', 'Ags', 'Sep', 'Okt', 'Nov', 'Des'
    ];
    return "${dt.day} ${bulan[dt.month]} ${dt.year}";
  }

  // ================= RANKING =================
  List<Map<String, dynamic>> buildRanking() {
    final Map<String, Map<String, int>> map = {};
    for (var item in data) {
      if (selectedKCS != "Semua" &&
          (item['kcs'] ?? "") != selectedKCS) {
        continue;
      }
      if ((item['status'] ?? '') != 'ACC') continue;

      final pemanen =
      (item['pemanen'] ?? '').toString().trim().toLowerCase();
      int janjang = int.tryParse(item['matang'].toString()) ?? 0;
      int brondolan = int.tryParse(item['brondolan'].toString()) ?? 0;

      map[pemanen] ??= {'janjang': 0, 'brondolan': 0};
      map[pemanen]!['janjang'] =
          map[pemanen]!['janjang']! + janjang;
      map[pemanen]!['brondolan'] =
          map[pemanen]!['brondolan']! + brondolan;
    }

    final ranking = map.entries
        .map((e) => {
      'pemanen': e.key,
      'janjang': e.value['janjang'],
      'brondolan': e.value['brondolan'],
    })
        .toList();
    ranking.sort((a, b) =>
        (b['janjang'] as int).compareTo(a['janjang'] as int));
    return ranking;
  }

  // ================= GRAFIK BAR CHART KEREN =================
  Widget _buildBarChart() {
    if (totalKCS.isEmpty) {
      return Container(
        height: 200,
        alignment: Alignment.center,
        child: const Text("Belum ada data grafik",
            style: TextStyle(color: Colors.grey)),
      );
    }

    final keys = totalKCS.keys.toList();
    final maxVal = totalKCS.values
        .reduce((a, b) => a > b ? a : b)
        .toDouble() *
        1.2;

    final gradients = [
      [const Color(0xFF1565C0), const Color(0xFF42A5F5)],
      [const Color(0xFF0D47A1), const Color(0xFF1976D2)],
      [const Color(0xFF005691), const Color(0xFF007BFF)],
      [const Color(0xFF01579B), const Color(0xFF039BE5)],
    ];

    return Container(
      padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 8,
              offset: const Offset(0, 3))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 8, bottom: 12),
            child: Row(
              children: [
                const Icon(Icons.bar_chart,
                    color: Color(0xFF1565C0), size: 20),
                const SizedBox(width: 6),
                const Text(
                  "Grafik Janjang per KCS",
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: Color(0xFF1565C0)),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 220,
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: maxVal,
                minY: 0,
                barTouchData: BarTouchData(
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipColor: (group) =>
                        const Color(0xFF1565C0).withValues(alpha: 0.9),
                    getTooltipItem: (group, groupIndex,
                        rod, rodIndex) {
                      return BarTooltipItem(
                        '${AppDateUtils.mapKcsToAfd(keys[groupIndex])}\n',
                        const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                        children: [
                          TextSpan(
                            text: '${rod.toY.toInt()} Janjang',
                            style: const TextStyle(
                              color: Colors.yellow,
                              fontSize: 12,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                  touchCallback:
                      (FlTouchEvent event, barTouchResponse) {
                    setState(() {
                      if (!event.isInterestedForInteractions ||
                          barTouchResponse == null ||
                          barTouchResponse.spot == null) {
                        touchedIndex = -1;
                        return;
                      }
                      touchedIndex = barTouchResponse
                          .spot!.touchedBarGroupIndex;
                    });
                  },
                ),
                titlesData: FlTitlesData(
                  show: true,
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        int i = value.toInt();
                        if (i >= 0 && i < keys.length) {
                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              AppDateUtils.mapKcsToAfd(keys[i]),
                              style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF1565C0)),
                            ),
                          );
                        }
                        return const SizedBox();
                      },
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 40,
                      getTitlesWidget: (value, meta) {
                        if (value == 0) {
                          return const Text('0',
                              style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.grey));
                        }
                        if (value == maxVal / 1.2) {
                          return Text(
                              '${value.toInt()}',
                              style: const TextStyle(
                                  fontSize: 10,
                                  color: Colors.grey));
                        }
                        return const SizedBox();
                      },
                    ),
                  ),
                  topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                ),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: maxVal / 4,
                  getDrawingHorizontalLine: (value) => FlLine(
                    color: Colors.grey.withValues(alpha: 0.15),
                    strokeWidth: 1,
                    dashArray: [5, 5],
                  ),
                ),
                borderData: FlBorderData(show: false),
                barGroups: List.generate(keys.length, (i) {
                  final isTouched = i == touchedIndex;
                  final g = gradients[i % gradients.length];
                  return BarChartGroupData(
                    x: i,
                    barRods: [
                      BarChartRodData(
                        toY: totalKCS[keys[i]]!.toDouble(),
                        width: isTouched ? 32 : 26,
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(8)),
                        gradient: LinearGradient(
                          colors: isTouched
                              ? [g[1], g[0]]
                              : [
                            g[0].withValues(alpha: 0.85),
                            g[1]
                          ],
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                        ),
                        backDrawRodData: BackgroundBarChartRodData(
                          show: true,
                          toY: maxVal,
                          color: Colors.grey.withValues(alpha: 0.05),
                        ),
                      ),
                    ],
                    showingTooltipIndicators:
                    isTouched ? [0] : [],
                  );
                }),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ================= STAT CARD =================
  Widget _statCard(
      String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
                color: color.withValues(alpha: 0.12),
                blurRadius: 8,
                offset: const Offset(0, 3))
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 18, color: color),
            ),
            const SizedBox(height: 8),
            Text(value,
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: color)),
            Text(label,
                style: const TextStyle(
                    fontSize: 11, color: Colors.grey)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ranking = buildRanking();

    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F8),
      appBar: AppBar(
        title: const Text("Statistik Mandor"),
        backgroundColor: const Color(0xFF1565C0),
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_today,
                color: Colors.white),
            onPressed: _pilihTanggal,
            tooltip: "Filter Tanggal",
          ),
          if (filterTanggal != null)
            IconButton(
              icon: const Icon(Icons.clear, color: Colors.white),
              onPressed: _resetFilter,
              tooltip: "Reset",
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            // ===== BANNER FILTER =====
            if (filterTanggal != null)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF1565C0).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: const Color(0xFF1565C0)
                          .withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.filter_alt,
                        size: 16, color: Color(0xFF1565C0)),
                    const SizedBox(width: 6),
                    Text(
                      "Filter: ${_formatTanggal(filterTanggal!)}",
                      style: const TextStyle(
                          color: Color(0xFF1565C0),
                          fontWeight: FontWeight.w600),
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: _resetFilter,
                      child: const Text("Reset",
                          style: TextStyle(
                              color: Colors.red,
                              fontSize: 12,
                              decoration:
                              TextDecoration.underline)),
                    ),
                  ],
                ),
              ),

            // ===== 4 STAT CARD =====
            Row(
              children: [
                _statCard("Janjang", "$totalJanjang",
                    Icons.grass, const Color(0xFF1565C0)),
                const SizedBox(width: 10),
                _statCard("Brondolan", "$totalBrondolan Kg",
                    Icons.scatter_plot, Colors.orange),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _statCard("Data Panen", "$totalPanen",
                    Icons.list_alt, Colors.teal),
                const SizedBox(width: 10),
                _statCard("Total Trip", "$totalTrip",
                    Icons.local_shipping, Colors.purple),
              ],
            ),

            const SizedBox(height: 16),

            // ===== GRAFIK =====
            _buildBarChart(),

            const SizedBox(height: 16),

            // ===== TOTAL PER KCS =====
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 6,
                      offset: const Offset(0, 2))
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                const Row(
                  children: [
                    Icon(Icons.pie_chart,
                        size: 18, color: Color(0xFF1565C0)),
                    SizedBox(width: 6),
                    Text("Total per KCS",
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1565C0))),
                  ],
                ),
                  const SizedBox(height: 10),
                  ...totalKCS.entries.map((e) {
                    final pct = totalJanjang > 0
                        ? (e.value / totalJanjang * 100)
                        .toStringAsFixed(1)
                        : "0";
                    return Padding(
                      padding:
                      const EdgeInsets.symmetric(vertical: 5),
                      child: Column(
                        crossAxisAlignment:
                        CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment:
                            MainAxisAlignment.spaceBetween,
                            children: [
                              Text(AppDateUtils.mapKcsToAfd(e.key),
                                  style: const TextStyle(
                                      fontWeight:
                                      FontWeight.w600)),
                              Text(
                                  "${e.value} Janjang  ($pct%)",
                                  style: const TextStyle(
                                      fontSize: 13)),
                            ],
                          ),
                          const SizedBox(height: 4),
                          ClipRRect(
                            borderRadius:
                            BorderRadius.circular(6),
                            child: LinearProgressIndicator(
                              value: totalJanjang > 0
                                  ? e.value / totalJanjang
                                  : 0,
                              backgroundColor:
                              Colors.grey.shade200,
                              color: const Color(0xFF1565C0),
                              minHeight: 7,
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // ===== FILTER KCS =====
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 4)
                ],
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: selectedKCS,
                  isExpanded: true,
                  icon: const Icon(Icons.keyboard_arrow_down,
                      color: Color(0xFF1565C0)),
                  items: [
                    const DropdownMenuItem(
                        value: "Semua",
                        child: Row(children: [
                          Icon(Icons.all_inclusive,
                              size: 16, color: Color(0xFF1565C0)),
                          SizedBox(width: 8),
                          Text("Semua KCS")
                        ])),
                    DropdownMenuItem(
                        value: "KCS1",
                        child: Row(children: [
                          const Icon(Icons.person,
                              size: 16, color: Colors.teal),
                          const SizedBox(width: 8),
                          Text(AppDateUtils.mapKcsToAfd("KCS 1"))
                        ])),
                    DropdownMenuItem(
                        value: "KCS2",
                        child: Row(children: [
                          const Icon(Icons.person,
                              size: 16, color: Colors.orange),
                          const SizedBox(width: 8),
                          Text(AppDateUtils.mapKcsToAfd("KCS 2"))
                        ])),
                    DropdownMenuItem(
                        value: "KCS3",
                        child: Row(children: [
                          const Icon(Icons.person,
                              size: 16, color: Colors.purple),
                          const SizedBox(width: 8),
                          Text(AppDateUtils.mapKcsToAfd("KCS 3"))
                        ])),
                  ],
                  onChanged: (v) {
                    setState(() => selectedKCS = v!);
                  },
                ),
              ),
            ),

            const SizedBox(height: 16),

            // ===== RANKING =====
            Row(
              children: [
                const Text("🏆 ",
                    style: TextStyle(fontSize: 18)),
                const Text("Ranking Pemanen",
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: Color(0xFF1565C0))),
                const Spacer(),
                Text("${ranking.length} pemanen",
                    style: const TextStyle(
                        fontSize: 12, color: Colors.grey)),
              ],
            ),
            const SizedBox(height: 8),

            if (ranking.isEmpty)
              Container(
                padding: const EdgeInsets.all(20),
                alignment: Alignment.center,
                child: const Text("Belum ada data",
                    style: TextStyle(color: Colors.grey)),
              )
            else
              ...ranking.asMap().entries.map((entry) {
                final index = entry.key;
                final item = entry.value;

                final medalColors = [
                  Colors.amber,
                  Colors.grey.shade400,
                  Colors.brown.shade300,
                ];
                final isMedal = index < 3;

                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  elevation: isMedal ? 3 : 1,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: isMedal
                        ? BorderSide(
                        color: medalColors[index]
                            .withValues(alpha: 0.5),
                        width: 1.5)
                        : BorderSide.none,
                  ),
                  child: ListTile(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => DetailPemanenPage(
                              nama: item['pemanen']),
                        ),
                      );
                    },
                    leading: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: isMedal
                            ? medalColors[index]
                            : const Color(0xFF1565C0)
                            .withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          "${index + 1}",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: isMedal
                                ? Colors.white
                                : const Color(0xFF1565C0),
                          ),
                        ),
                      ),
                    ),
                    title: Text(
                      item['pemanen'],
                      style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15),
                    ),
                    subtitle: Text(
                      "Janjang: ${item['janjang']}  |  Brondolan: ${item['brondolan']} Kg",
                      style: const TextStyle(fontSize: 12),
                    ),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          "${item['janjang']}",
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: Color(0xFF1565C0),
                          ),
                        ),
                        const Text("Janjang",
                            style: TextStyle(
                                fontSize: 10,
                                color: Colors.grey)),
                      ],
                    ),
                  ),
                );
              }),

            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}