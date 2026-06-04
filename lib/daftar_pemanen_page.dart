import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'detail_pemanen_page.dart';

class DaftarPemanenPage extends StatelessWidget {
  const DaftarPemanenPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4FF),
      appBar: AppBar(
        title: const Text("Daftar Pemanen", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF0D47A1),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('harvesters')
            .orderBy('afdeling')
            .orderBy('nama')
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text("Error: ${snapshot.error}"));
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text("Belum ada data pemanen"));
          }

          // Group harvesters by Afdeling
          Map<String, List<Map<String, dynamic>>> groupedHarvesters = {};
          for (var doc in snapshot.data!.docs) {
            var data = doc.data() as Map<String, dynamic>;
            String afd = data['afdeling'] ?? "Unknown";
            groupedHarvesters.putIfAbsent(afd, () => []).add(data);
          }

          var afdelings = groupedHarvesters.keys.toList()..sort();

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: afdelings.length,
            itemBuilder: (context, index) {
              String afd = afdelings[index];
              List<Map<String, dynamic>> pemanen = groupedHarvesters[afd]!;
              
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(left: 8, top: 16, bottom: 8),
                    child: Row(
                      children: [
                        const Icon(Icons.group_work, color: Color(0xFF0D47A1), size: 20),
                        const SizedBox(width: 8),
                        Text(
                          afd,
                          style: const TextStyle(
                            fontSize: 18, 
                            fontWeight: FontWeight.bold, 
                            color: Color(0xFF0D47A1)
                          ),
                        ),
                      ],
                    ),
                  ),
                  Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                    child: Column(
                      children: pemanen.map((p) {
                        String name = p['nama'] ?? "Tanpa Nama";
                        bool isLast = pemanen.last == p;
                        return Column(
                          children: [
                            ListTile(
                              leading: CircleAvatar(
                                backgroundColor: const Color(0xFF0D47A1).withOpacity(0.1),
                                child: Text(
                                  name.isNotEmpty ? name[0] : "?", 
                                  style: const TextStyle(color: Color(0xFF0D47A1), fontWeight: FontWeight.bold)
                                ),
                              ),
                              title: Text(
                                name,
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                              trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => DetailPemanenPage(nama: name)
                                  ),
                                );
                              },
                            ),
                            if (!isLast) 
                              const Divider(height: 1, indent: 70, endIndent: 16),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}
