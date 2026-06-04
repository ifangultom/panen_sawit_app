import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';
import 'input_panen.dart';
import 'api_service.dart';

class DetailPanenPage extends StatelessWidget {
  final Map<String, dynamic> data;
  final bool isReadOnly;

  const DetailPanenPage({super.key, required this.data, this.isReadOnly = false});

  // Helper untuk mendapatkan URL foto yang valid di Web
  String _getImageUrl(String? path) {
    if (path == null || path.isEmpty) return "";
    
    // 1. Handle Base64 Data URI
    if (path.startsWith('data:image')) return path;

    // 2. Handle jika data adalah string Base64 murni (tanpa header)
    // Jika teks sangat panjang (> 500) dan bukan URL, hampir pasti ini Base64
    if (path.length > 500 && !path.startsWith('http')) {
      return 'data:image/jpeg;base64,$path';
    }
    
    // 3. Handle Full URL (Firebase Storage atau Web URL)
    if (path.startsWith('http')) return path;
    
    // 4. Jika di Web dan path adalah path lokal mobile, arahkan ke storage Laravel
    if (kIsWeb) {
      String fileName = path.split(RegExp(r'[/\\]')).last;
      String baseUrl = ApiService.baseUrl.replaceAll('/api', '');
      return "$baseUrl/storage/panen/$fileName";
    }
    return path;
  }

  // Helper untuk menampilkan gambar yang mendukung URL, Base64, dan File Lokal
  Widget _buildImageWidget(String imageUrl, {double? height, double? width, BoxFit fit = BoxFit.cover}) {
    if (imageUrl.isEmpty) return const SizedBox.shrink();

    // Jika data adalah Base64
    if (imageUrl.startsWith('data:image')) {
      try {
        final base64Part = imageUrl.split(',').last.replaceAll(RegExp(r'\s+'), '');
        return Image.memory(
          base64Decode(base64Part),
          height: height,
          width: width,
          fit: fit,
          errorBuilder: (context, error, stackTrace) => _buildErrorWidget(height),
        );
      } catch (e) {
        return _buildErrorWidget(height);
      }
    }

    // Jika di Web atau URL
    if (kIsWeb || imageUrl.startsWith('http')) {
      return Image.network(
        imageUrl,
        height: height,
        width: width,
        fit: fit,
        errorBuilder: (context, error, stackTrace) => _buildErrorWidget(height),
      );
    }

    // Jika di Mobile (File Lokal)
    return Image.file(
      File(imageUrl),
      height: height,
      width: width,
      fit: fit,
      errorBuilder: (context, error, stackTrace) => _buildErrorWidget(height),
    );
  }

  Widget _buildErrorWidget(double? height) {
    return Container(
      width: double.infinity,
      height: height ?? 220,
      color: Colors.grey[300],
      child: const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.broken_image, size: 50, color: Colors.grey),
          SizedBox(height: 8),
          Text("Gambar tidak ditemukan", style: TextStyle(color: Colors.grey, fontSize: 12)),
        ],
      ),
    );
  }

  Widget item(String title, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(flex: 3, child: Text(value)),
        ],
      ),
    );
  }

  // ================= OPEN MAP =================
  void openMap() async {
    final lat = data['latitude'];
    final lng = data['longitude'];

    if (lat == null || lng == null) return;

    final url = Uri.parse("https://www.google.com/maps?q=$lat,$lng");

    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    }
  }

  @override
  Widget build(BuildContext context) {
    String status = data['status'] ?? data['sync_status'] ?? 'pending';
    String imageUrl = _getImageUrl(data['foto']);

    // Tentukan apakah dalam mode Web untuk mengecilkan ukuran card
    bool isWebLayout = kIsWeb && MediaQuery.of(context).size.width > 800;

    return Scaffold(
      backgroundColor: const Color(0xFFF2F4F7),
      appBar: AppBar(
        title: const Text("Detail Panen"),
        backgroundColor: const Color(0xFF0D47A1),
        centerTitle: isWebLayout,
        actions: [
          // EDIT (Only show if NOT read only)
          if (!isReadOnly)
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: () async {
                final result = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => InputPanenPage(data: data),
                  ),
                );
                if (result == true) {
                  Navigator.pop(context, true);
                }
              },
            )
        ],
      ),
      body: Center(
        child: Container(
          constraints: BoxConstraints(
            maxWidth: isWebLayout ? 700 : double.infinity,
          ),
          child: SingleChildScrollView(
            padding: EdgeInsets.all(isWebLayout ? 30 : 15),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ================= FOTO =================
                if (data['foto'] != null && data['foto'] != "")
                  GestureDetector(
                    onTap: () {
                      if (imageUrl.isEmpty) return;
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => Scaffold(
                            backgroundColor: Colors.black,
                            appBar: AppBar(
                              backgroundColor: Colors.black,
                              iconTheme: const IconThemeData(color: Colors.white),
                            ),
                            body: Center(
                              child: _buildImageWidget(imageUrl, fit: BoxFit.contain),
                            ),
                          ),
                        ),
                      );
                    },
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: _buildImageWidget(
                        imageUrl,
                        height: isWebLayout ? 350 : 220,
                        width: double.infinity,
                      ),
                    ),
                  ),

                const SizedBox(height: 15),

                // ================= CARD DATA =================
                Card(
                  elevation: isWebLayout ? 2 : 1,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        item("Tanggal", data['tanggal'] ?? "-"),
                        item("Pemanen", data['pemanen'] ?? "-"),
                        item("Blok", data['blok'] ?? "-"),
                        item("TPH", data['tph'] ?? "-"),
                        const Divider(height: 30),
                        item("Jumlah", "${data['brondolan'] ?? 0} Kg"),
                        item("Mentah", data['mentah'] ?? "0"),
                        item("Matang", data['matang'] ?? "0"),
                        const Divider(height: 30),
                        item("Status", status.toUpperCase()),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 15),

                // ================= MAP & LOKASI =================
                Card(
                  elevation: isWebLayout ? 2 : 1,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "Lokasi GPS",
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 15),
                        item("Latitude", data['latitude']?.toString() ?? "-"),
                        item("Longitude", data['longitude']?.toString() ?? "-"),
                        const SizedBox(height: 15),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: openMap,
                            icon: const Icon(Icons.map, color: Colors.white),
                            label: const Text("Buka di Google Maps", style: TextStyle(color: Colors.white)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF0D47A1),
                              padding: const EdgeInsets.symmetric(vertical: 15),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 15),

                // ================= CATATAN =================
                Card(
                  elevation: isWebLayout ? 2 : 1,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "Catatan",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          data['catatan'] ?? "-",
                          style: const TextStyle(height: 1.5),
                        ),
                      ],
                    ),
                  ),
                ),
                if (isWebLayout) const SizedBox(height: 50),
              ],
            ),
          ),
        ),
      ),
    );
  }
}