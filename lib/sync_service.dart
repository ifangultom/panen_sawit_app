import 'dart:convert';
import 'package:http/http.dart' as http;
import 'database_helper.dart';

class SyncService {

  static Future<void> syncData() async {
    final data = await DatabaseHelper.instance.getAllPanen();

    for (var item in data) {

      if (item['sync_status'] == 'online') continue;

      try {
        // 🔥 GANTI URL DENGAN SERVER KAMU
        final response = await http.post(
          Uri.parse("https://your-api.com/panen"),
          headers: {"Content-Type": "application/json"},
          body: jsonEncode(item),
        );

        if (response.statusCode == 200) {
          await DatabaseHelper.instance.updatePanen(
            item['id'],
            {'sync_status': 'online'},
          );
        }

      } catch (e) {
        print("Sync gagal: $e");
      }
    }
  }
}