import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'database_helper.dart';

class LaporanGrafikPage extends StatefulWidget {
  const LaporanGrafikPage({super.key});

  @override
  State<LaporanGrafikPage> createState() => _LaporanGrafikPageState();
}

class _LaporanGrafikPageState extends State<LaporanGrafikPage> {

  int total = 0;
  int acc = 0;
  int pending = 0;
  int reject = 0;

  @override
  void initState() {
    super.initState();
    loadData();
  }

  void loadData() async {
    final result = await DatabaseHelper.instance.getAllPanen();

    int t = 0;
    int a = 0;
    int p = 0;
    int r = 0;

    for (var item in result) {
      int jumlah = int.tryParse(item['brondolan'].toString()) ?? 0;

      t += jumlah;

      if (item['status'] == 'ACC') a += jumlah;
      if (item['status'] == 'pending') p += jumlah;
      if (item['status'] == 'REJECT') r += jumlah;
    }

    setState(() {
      total = t;
      acc = a;
      pending = p;
      reject = r;
    });
  }

  Widget legendItem(String text, Color color) {
    return Row(
      children: [
        Container(width: 12, height: 12, color: color),
        const SizedBox(width: 5),
        Text(text),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {

    return Scaffold(
      appBar: AppBar(
        title: const Text("Laporan Grafik"),
        backgroundColor: const Color(0xFF0D47A1),
      ),

      body: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(
          children: [

            // ================= SUMMARY =================
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [

                boxStat("Total", total, const Color(0xFF0D47A1)),
                boxStat("ACC", acc, const Color(0xFF1976D2)),
                boxStat("Pending", pending, Colors.orange),

              ],
            ),

            const SizedBox(height: 30),

            // ================= DONUT CHART =================
            Expanded(
              child: Stack(
                alignment: Alignment.center,
                children: [

                  PieChart(
                    PieChartData(
                      sectionsSpace: 3,
                      centerSpaceRadius: 70,
                      sections: [

                        PieChartSectionData(
                          value: acc.toDouble(),
                          color: const Color(0xFF1976D2),
                          title: total == 0 ? "0%" : "${((acc / total) * 100).toStringAsFixed(1)}%",
                          radius: 80,
                          titleStyle: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),

                        PieChartSectionData(
                          value: pending.toDouble(),
                          color: Colors.orange,
                          title: total == 0 ? "0%" : "${((pending / total) * 100).toStringAsFixed(1)}%",
                          radius: 80,
                          titleStyle: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),

                        PieChartSectionData(
                          value: reject.toDouble(),
                          color: Colors.red,
                          title: total == 0 ? "0%" : "${((reject / total) * 100).toStringAsFixed(1)}%",
                          radius: 80,
                          titleStyle: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // ================= TEXT TENGAH =================
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text("Total"),
                      Text(
                        "$total",
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0D47A1),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // ================= LEGEND =================
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [

                legendItem("ACC", const Color(0xFF1976D2)),
                legendItem("Pending", Colors.orange),
                legendItem("Reject", Colors.red),

              ],
            ),
          ],
        ),
      ),
    );
  }

  // ================= BOX STAT =================
  Widget boxStat(String title, int value, Color color) {
    return Container(
      width: 100,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(15),
      ),
      child: Column(
        children: [
          Text(title, style: const TextStyle(color: Colors.white)),
          const SizedBox(height: 5),
          Text(
            "$value",
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}