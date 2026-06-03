import 'package:shared_preferences/shared_preferences.dart';

class UserHelper {
  // ====== SAVE USER PROFILE ======
  static Future<void> saveUser({
    required String nama,
    required String jabatan,
    required String username,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString('nama_$username', nama);
    await prefs.setString('jabatan_$username', jabatan);

    // session aktif
    await prefs.setString('current_user', username);
  }

  // ====== GET USER PROFILE ======
  static Future<Map<String, String>> getUser() async {
    final prefs = await SharedPreferences.getInstance();
    final username = prefs.getString('current_user') ?? '';

    if (username.isEmpty) {
      return {'nama': '', 'jabatan': '', 'username': ''};
    }

    return {
      'nama': prefs.getString('nama_$username') ?? '',
      'jabatan': prefs.getString('jabatan_$username') ?? '',
      'username': username,
    };
  }

  // ====== LOGOUT ======
  static Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('current_user');
  }

  // ====== FOTO ======
  static Future<void> saveFoto(String path, String userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('foto_$userId', path);
  }

  static Future<String> getFoto(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('foto_$userId') ?? '';
  }
}