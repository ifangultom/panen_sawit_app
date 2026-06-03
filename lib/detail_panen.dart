import 'dart:io';
import 'package:flutter/material.dart';
import 'input_panen.dart';

class DetailPanenPage extends StatelessWidget {
  final Map<String, dynamic> data;

  const DetailPanenPage({super.key, required this.data});

  Widget item(String title, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(flex: 2, child: Text(title)),
          Expanded(flex: 3, child: Text(value)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    String status = data['status'] ?? 'pending';

    return Scaffold(
      appBar: AppBar(
        title: const Text("Detail Panen", style: TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF0D47A1),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit, color: Colors.white),
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => InputPanenPage(data: data),
                ),
              );

              Navigator.pop(context, true); // refresh
            },
          ),
        ],
      ),

      body: SingleChildScrollView(
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            // FOTO
            if (data['foto'] != null && data['foto'] != "")
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.file(
                  File(data['foto']),
                  width: double.infinity,
                  height: 200,
                  fit: BoxFit.cover,
                ),
              ),

            const SizedBox(height: 15),

            item("Tanggal", data['tanggal'] ?? "-"),
            item("Pemanen", data['pemanen'] ?? "-"),
            item("Blok", data['blok'] ?? "-"),
            item("TPH", data['tph'] ?? "-"),

            const Divider(),

            item("Brondolan", data['brondolan'] ?? "0"),
            item("Mentah", data['mentah'] ?? "0"),
            item("Matang", data['matang'] ?? "0"),

            const Divider(),

            item("Latitude", data['latitude'] ?? "-"),
            item("Longitude", data['longitude'] ?? "-"),

            const Divider(),

            item("Status", status),

            const SizedBox(height: 10),

            const Text(
              "Catatan:",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            Text(data['catatan'] ?? "-"),
          ],
        ),
      ),
    );
  }
}