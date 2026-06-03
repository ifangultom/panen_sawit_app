import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'database_helper.dart';

class DetailPemanenPage extends StatefulWidget {
  final String nama;
  final bool isWebView;

  const DetailPemanenPage({
    super.key, 
    required this.nama,
    this.isWebView = false,
  });

  @override
  State<DetailPemanenPage> createState() => _DetailPemanenPageState();
}

class _DetailPemanenPageState extends State<DetailPemanenPage> {
  List<Map<String, dynamic>> data = [];
  bool isLoading = true;
  int totalJanjang = 0;
  int totalBrondolan = 0;

  @override
  void initState() {
    super.initState();
    loadData();
  }

  void loadData() async {
    if (!mounted) return;
    setState(() => isLoading = true);
    
    List<Map<String, dynamic>> result = [];
    
    try {
      if (kIsWeb) {
        final snapshot = await FirebaseFirestore.instance.collection('panen').get();
        result = snapshot.docs.map((doc) => doc.data()).toList();
      } else {
        result = await DatabaseHelper.instance.getAllPanen();
      }
    } catch (e) {
      debugPrint("Error loading data: $e");
    }

    int janjang = 0;
    int brond = 0;
    List<Map<String, dynamic>> temp = [];
    String targetNama = widget.nama.toLowerCase().trim();

    for (var item in result) {
      String pemanen = (item['pemanen'] ?? "").toString().toLowerCase().trim();

      if (pemanen == targetNama) {
        // Hitung total janjang (Matang + Mentah) agar sesuai dengan ranking di dashboard
        int matang = int.tryParse(item['matang']?.toString() ?? "0") ?? 0;
        int mentah = int.tryParse(item['mentah']?.toString() ?? "0") ?? 0;
        int jjg = matang + mentah;
        
        janjang += jjg;
        brond += int.tryParse(item['brondolan']?.toString() ?? "0") ?? 0;

        temp.add(item);
      }
    }

    if (mounted) {
      setState(() {
        data = temp;
        totalJanjang = janjang;
        totalBrondolan = brond;
        isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F6),
      appBar: AppBar(
        title: Text("Detail: ${widget.nama}"),
        backgroundColor: const Color(0xFF0D47A1),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : widget.isWebView
              ? _buildWebView()
              : _buildMobileView(),
    );
  }

  Widget _buildMobileView() {
    return Column(
      children: [
        // 🔥 RINGKASAN PRODUKSI
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          margin: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(15),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)],
          ),
          child: Column(
            children: [
              const Text("Total Produksi Seluruhnya",
                  style: TextStyle(color: Colors.grey, fontSize: 13, fontWeight: FontWeight.w500)),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _summaryCol("Janjang", "$totalJanjang", const Color(0xFF0D47A1)),
                  _summaryCol("Brondolan", "$totalBrondolan Kg", Colors.orange),
                  _summaryCol("Record", "${data.length}", Colors.blue),
                ],
              ),
            ],
          ),
        ),

        // 🔥 DAFTAR RIWAYAT
        Expanded(
          child: data.isEmpty
              ? _emptyState()
              : ListView.builder(
                  itemCount: data.length,
                  padding: const EdgeInsets.symmetric(horizontal: 15),
                  itemBuilder: (context, index) {
                    final item = data[index];
                    int matang = int.tryParse(item['matang']?.toString() ?? "0") ?? 0;
                    int mentah = int.tryParse(item['mentah']?.toString() ?? "0") ?? 0;

                    return Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
                        title: Text("Blok ${item['blok'] ?? '-'}", style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 4),
                            Text("Tanggal: ${item['tanggal']?.toString().split(" ")[0] ?? "-"}"),
                            Text("Afdeling: ${item['afdeling'] ?? "-"} | KCS: ${item['kcs'] ?? "-"}"),
                          ],
                        ),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text("${matang + mentah} Jjg",
                                style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0D47A1), fontSize: 16)),
                            Text("${item['brondolan'] ?? '0'} Kg Brd",
                                style: const TextStyle(fontSize: 11, color: Colors.grey)),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildWebView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(30),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Card Web Style
          Container(
            padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 40),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 20)],
            ),
            child: Column(
              children: [
                const Text("TOTAL PRODUKSI SELURUHNYA",
                    style: TextStyle(color: Colors.grey, fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                const SizedBox(height: 30),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _statItemWeb("Janjang", "$totalJanjang", const Color(0xFF0D47A1), Icons.eco_rounded),
                    _statItemWeb("Brondolan", "$totalBrondolan Kg", Colors.orange, Icons.grain_rounded),
                    _statItemWeb("Record", "${data.length}", Colors.blue, Icons.assignment_rounded),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 40),
          Text("RIWAYAT OPERASIONAL",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blueGrey[800])),
          const SizedBox(height: 20),
          data.isEmpty
              ? _emptyState()
              : LayoutBuilder(builder: (context, constraints) {
                  int crossAxisCount = constraints.maxWidth > 1400 ? 3 : (constraints.maxWidth > 900 ? 2 : 1);
                  return GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: data.length,
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: crossAxisCount,
                      childAspectRatio: 3.2,
                      crossAxisSpacing: 20,
                      mainAxisSpacing: 20,
                    ),
                    itemBuilder: (context, index) => _productionCardWeb(data[index]),
                  );
                }),
        ],
      ),
    );
  }

  Widget _statItemWeb(String label, String value, Color color, IconData icon) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle),
          child: Icon(icon, color: color, size: 28),
        ),
        const SizedBox(height: 12),
        Text(value, style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: color)),
        Text(label, style: TextStyle(fontSize: 14, color: Colors.grey[600], fontWeight: FontWeight.w500)),
      ],
    );
  }

  Widget _productionCardWeb(Map<String, dynamic> item) {
    int matang = int.tryParse(item['matang']?.toString() ?? "0") ?? 0;
    int mentah = int.tryParse(item['mentah']?.toString() ?? "0") ?? 0;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withOpacity(0.15)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: const Color(0xFF0D47A1).withOpacity(0.08), borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.location_on, color: Color(0xFF0D47A1), size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text("Blok ${item['blok'] ?? '-'}",
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
                const SizedBox(height: 4),
                Text("${item['tanggal']?.toString().split(" ")[0] ?? "-"}",
                    style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                Text("AFD: ${item['afdeling'] ?? "-"} | KCS: ${item['kcs'] ?? "-"}",
                    style: TextStyle(color: Colors.grey[500], fontSize: 11)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text("${matang + mentah} Jjg",
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0D47A1), fontSize: 20)),
              Text("${item['brondolan'] ?? '0'} Kg Brd",
                  style: TextStyle(fontSize: 13, color: Colors.orange[800], fontWeight: FontWeight.w500)),
            ],
          )
        ],
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(50.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.assignment_late_outlined, size: 60, color: Colors.grey[300]),
            const SizedBox(height: 15),
            Text("Tidak ada data untuk ${widget.nama}", style: TextStyle(color: Colors.grey[500], fontSize: 16)),
          ],
        ),
      ),
    );
  }

  Widget _summaryCol(String label, String value, Color color) {
    return Column(
      children: [
        Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      ],
    );
  }
}
