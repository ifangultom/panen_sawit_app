import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'database_helper.dart';

class DetailTripPage extends StatefulWidget {
  final dynamic tripId;

  const DetailTripPage({super.key, required this.tripId});

  @override
  State<DetailTripPage> createState() => _DetailTripPageState();
}

class _DetailTripPageState extends State<DetailTripPage> {
  List<Map<String, dynamic>> detailList = [];
  int totalJanjang = 0;
  double totalBrondolan = 0;

  @override
  void initState() {
    super.initState();
    loadDetail();
  }

  Future<void> loadDetail() async {
    if (kIsWeb) {
      // Logika khusus Web: Ambil data dari Firebase
      // Karena trip_detail tidak di-sync, kita bisa mencari panen berdasarkan kriteria tertentu
      // atau jika kedepannya trip_detail di-sync, kodenya akan diletakkan di sini.
      // Untuk sementara, kita tampilkan data kosong atau handle jika ada field trip_id di panen.
      setState(() {
        detailList = [];
      });
      return;
    }

    final db = await DatabaseHelper.instance.database;

    final data = await db.rawQuery('''
      SELECT panen.*
      FROM trip_detail
      JOIN panen ON trip_detail.panen_id = panen.id
      WHERE trip_detail.trip_id = ?
    ''', [widget.tripId]);

    int totalJ = 0;
    double totalB = 0;

    for (var item in data) {
      totalJ += int.tryParse(item['matang'].toString()) ?? 0;
      totalB += double.tryParse(item['brondolan'].toString()) ?? 0;
    }

    setState(() {
      detailList = data;
      totalJanjang = totalJ;
      totalBrondolan = totalB;
    });
  }

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xFF0D47A1);

    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F6),
      appBar: AppBar(
        title: const Text("Detail Muatan Trip"),
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // SUMMARY HEADER
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
              color: primaryColor,
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(24),
                bottomRight: Radius.circular(24),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildSummaryItem(Icons.grass, "Janjang", "$totalJanjang"),
                Container(width: 1, height: 40, color: Colors.white24),
                _buildSummaryItem(Icons.scatter_plot, "Brondolan", "${totalBrondolan.toStringAsFixed(1)} Kg"),
              ],
            ),
          ),

          const SizedBox(height: 10),

          // LIST DATA PANEN
          Expanded(
            child: detailList.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.inventory_2_outlined, size: 64, color: Colors.grey[400]),
                        const SizedBox(height: 16),
                        Text("Tidak ada data muatan", style: TextStyle(color: Colors.grey[600])),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    itemCount: detailList.length,
                    itemBuilder: (context, index) {
                      final item = detailList[index];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 2,
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: primaryColor.withOpacity(0.1),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.grid_view_rounded, color: primaryColor),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      "Blok ${item['blok']}",
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      "Pemanen: ${item['pemanen']}",
                                      style: TextStyle(color: Colors.grey[600], fontSize: 13),
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      children: [
                                        _buildMiniPill(Icons.grass, "${item['matang']} Janjang"),
                                        const SizedBox(width: 8),
                                        _buildMiniPill(Icons.scale, "${item['brondolan']} Kg"),
                                      ],
                                    ),
                                  ],
                                ),
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

  Widget _buildSummaryItem(IconData icon, String label, String value) {
    return Column(
      children: [
        Icon(icon, color: Colors.white, size: 24),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
        Text(
          value,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
        ),
      ],
    );
  }

  Widget _buildMiniPill(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: Colors.grey[700]),
          const SizedBox(width: 4),
          Text(text, style: TextStyle(fontSize: 11, color: Colors.grey[700])),
        ],
      ),
    );
  }
}
