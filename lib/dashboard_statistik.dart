import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'database_helper.dart';

class DashboardStatistikPage extends StatefulWidget {
  const DashboardStatistikPage({super.key});

  @override
  State<DashboardStatistikPage> createState() => _DashboardStatistikPageState();
}

class _DashboardStatistikPageState extends State<DashboardStatistikPage> {

  List<Map<String, dynamic>> data = [];
  Map<String, double> blokData = {};
  Map<String, int> ranking = {};

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final res = await DatabaseHelper.instance.getAllPanen();
    data = res;

    hitung();
    setState(() {});
  }

  // 🔥 HITUNG DATA
  void hitung() {
    blokData.clear();
    ranking.clear();

    for (var d in data) {

      // BLOK
      String blok = d['blok'] ?? "";
      double val = double.tryParse(d['brondolan'].toString()) ?? 0;
      blokData[blok] = (blokData[blok] ?? 0) + val;

      // 🔥 RANKING BERDASARKAN HASIL PANEN
      String pemanen = d['pemanen'] ?? "";
      int hasil = int.tryParse(d['brondolan'].toString()) ?? 0;

      ranking[pemanen] = (ranking[pemanen] ?? 0) + hasil;
    }
  }

  // 🔥 CARD STATISTIK
  Widget statCard(String title, String value, IconData icon) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.all(5),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF0D47A1), Color(0xFF1976D2)],
          ),
          borderRadius: BorderRadius.circular(15),
        ),
        child: Column(
          children: [
            Icon(icon, color: Colors.white),
            const SizedBox(height: 5),
            Text(value,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold)),
            Text(title, style: const TextStyle(color: Colors.white70)),
          ],
        ),
      ),
    );
  }

  // 🔥 WARNA GRAFIK
  List<Color> colors = [
    Colors.red,
    Colors.blue,
    Colors.green,
    Colors.orange,
    Colors.purple
  ];

  // 🔥 DATA GRAFIK
  List<BarChartGroupData> chartData() {
    int i = 0;

    return blokData.entries.map((e) {
      return BarChartGroupData(
        x: i++,
        barRods: [
          BarChartRodData(
            toY: e.value,
            gradient: LinearGradient(
              colors: [
                colors[(i - 1) % colors.length],
                colors[(i - 1) % colors.length].withOpacity(0.4),
              ],
            ),
            borderRadius: BorderRadius.circular(8),
          )
        ],
      );
    }).toList();
  }

  // 🔥 BADGE JUARA
  Widget badge(int i) {
    if (i == 0) return const Text("🥇", style: TextStyle(fontSize: 20));
    if (i == 1) return const Text("🥈", style: TextStyle(fontSize: 20));
    if (i == 2) return const Text("🥉", style: TextStyle(fontSize: 20));
    return Text("#${i + 1}");
  }

  @override
  Widget build(BuildContext context) {

    // 🔥 SORT RANKING (INI KUNCI FIX)
    final sortedRanking = ranking.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Scaffold(
      appBar: AppBar(
        title: const Text("Dashboard Statistik"),
        backgroundColor: const Color(0xFF0D47A1),
      ),

      body: data.isEmpty
          ? const Center(child: Text("Belum ada data"))
          : SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [

            // 🔥 CARD
            Row(
              children: [
                statCard("Total Panen", data.length.toString(), Icons.inventory),
                statCard("Total Blok", blokData.length.toString(), Icons.map),
              ],
            ),

            const SizedBox(height: 20),

            // 🔥 GRAFIK
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(15),
                boxShadow: [
                  BoxShadow(
                    blurRadius: 5,
                    color: Colors.grey.shade300,
                  )
                ],
              ),
              child: Column(
                children: [
                  const Text("Grafik Panen per Blok",
                      style: TextStyle(fontWeight: FontWeight.bold)),

                  const SizedBox(height: 10),

                  SizedBox(
                    height: 220,
                    child: BarChart(
                      BarChartData(
                        barGroups: chartData(),
                        gridData: FlGridData(show: true),
                        borderData: FlBorderData(show: false),

                        titlesData: FlTitlesData(
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              getTitlesWidget: (value, meta) {
                                int index = value.toInt();
                                if (index >= blokData.keys.length) {
                                  return const Text("");
                                }

                                return Text(
                                  blokData.keys.elementAt(index),
                                  style: const TextStyle(fontSize: 10),
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                      swapAnimationDuration:
                      const Duration(milliseconds: 800),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // 🔥 RANKING
            const Text("Ranking Pemanen",
                style: TextStyle(fontWeight: FontWeight.bold)),

            const SizedBox(height: 10),

            ...sortedRanking.asMap().entries.map((entry) {
              int i = entry.key;
              var e = entry.value;

              return Card(
                elevation: 3,
                child: ListTile(
                  leading: badge(i),
                  title: Text(e.key),
                  trailing: Text("${e.value} kg"),
                ),
              );
            }).toList(),
          ],
        ),
      ),
    );
  }
}