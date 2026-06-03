import 'package:shared_preferences/shared_preferences.dart';

class AuthService {

  static Future<void> registerUser(
      String username, String password, String role) async {

    final prefs = await SharedPreferences.getInstance();

    List<String> users = prefs.getStringList('users') ?? [];

    users.add("$username|$password|$role");

    await prefs.setStringList('users', users);
  }

  static Future<Map<String, dynamic>?> loginUser(
      String username, String password) async {

    final prefs = await SharedPreferences.getInstance();

    List<String> users = prefs.getStringList('users') ?? [];

    for (var u in users) {
      final split = u.split("|");

      if (split[0] == username && split[1] == password) {
        return {
          'username': split[0],
          'role': split[2],
        };
      }
    }

    return null;
  }
}