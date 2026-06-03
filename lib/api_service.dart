import 'dart:convert';
import 'package:http/http.dart' as http;
import 'database_helper.dart';

class ApiService {
  // 🔥 GANTI IP LARAVEL KAMU
  static const String baseUrl = "http://10.219.162.66:8000/api";

  // ==============================
  // 🔥 1. KIRIM LANGSUNG KE LARAVEL (Dengan Upload Foto)
  // ==============================
  static Future<void> kirimPanen(Map<String, dynamic> data) async {
    try {
      print("🔥 MASUK API LARAVEL");
      
      var request = http.MultipartRequest('POST', Uri.parse("$baseUrl/panen"));
      
      // Tambahkan data text
      data.forEach((key, value) {
        if (key != 'foto') {
          request.fields[key] = value.toString();
        }
      });

      // Tambahkan File Foto jika ada dan file-nya eksis
      if (data['foto'] != null && data['foto'] != "") {
        var file = await http.MultipartFile.fromPath('foto', data['foto']);
        request.files.add(file);
      }

      request.headers.addAll({
        "Accept": "application/json",
      });

      var streamedResponse = await request.send();
      var response = await http.Response.fromStream(streamedResponse);

      print("STATUS: ${response.statusCode}");
      print("BODY: ${response.body}");

      if (response.statusCode == 200 || response.statusCode == 201) {
        print("✅ Berhasil kirim ke Laravel");
        
        // Jika server mengembalikan URL foto baru, kita bisa update local data jika perlu
        // Namun biasanya data ini akan disinkronkan kembali dari server
      } else {
        print("❌ Gagal kirim: ${response.body}");
      }
    } catch (e) {
      print("❌ Error koneksi: $e");
    }
  }

  // ==============================
  // 🔥 2. SYNC DATA OFFLINE
  // ==============================
  static Future<void> syncData() async {
    final dataList = await DatabaseHelper.instance.getOfflineData();

    print("🔄 Total data offline: ${dataList.length}");

    for (var item in dataList) {
      try {
        print("📤 Sync ID: ${item['id']}");

        final response = await http.post(
          Uri.parse("$baseUrl/panen"),
          headers: {
            "Accept": "application/json",
            "Content-Type": "application/json",
          },
          body: jsonEncode(item),
        );

        if (response.statusCode == 200) {
          print("✅ Synced ID: ${item['id']}");
          await DatabaseHelper.instance.setSynced(item['id']);
        } else {
          print("❌ Gagal sync ID: ${item['id']}");
        }
      } catch (e) {
        print("❌ Error sync ID ${item['id']}: $e");
      }
    }
  }
}