import 'package:cloud_firestore/cloud_firestore.dart';

class AppDateUtils {
  static DateTime? parseDate(dynamic val) {
    if (val == null) return null;
    if (val is Timestamp) return val.toDate();
    if (val is DateTime) return val;
    if (val is String) {
      if (val.isEmpty) return null;
      try {
        return DateTime.parse(val);
      } catch (_) {
        try {
          // Handle format "dd-MM-yyyy" atau "dd/MM/yyyy"
          if (val.contains('-') || val.contains('/')) {
            String separator = val.contains('-') ? '-' : '/';
            final parts = val.split(separator);
            if (parts.length >= 3) {
              int d = int.parse(parts[0]);
              int m = int.parse(parts[1]);
              int y = int.parse(parts[2].split(' ')[0]); // Handle cases with time like "dd-MM-yyyy HH:mm"
              if (y < 100) y += 2000;
              return DateTime(y, m, d);
            }
          }
        } catch (__) {}
      }
    }
    return null;
  }

  static String mapKcsToAfd(String? input) {
    if (input == null) return "";
    // Normalisasi: Huruf besar, tanpa spasi
    String res = input.toUpperCase().replaceAll(' ', '').trim();
    // Jika mengandung KCS, ubah jadi AFD (misal KCS 1 -> AFD1, KCS2 -> AFD2)
    if (res.contains("KCS")) {
      res = res.replaceAll("KCS", "AFD");
    }
    return res;
  }

  static bool isWithinFilter(DateTime? dt, DateTime? startDate, DateTime? endDate, int? selectedMonth, int? selectedYear) {
    if (dt == null) return false;
    
    if (startDate != null && endDate != null) {
      DateTime d = DateTime(dt.year, dt.month, dt.day);
      DateTime s = DateTime(startDate.year, startDate.month, startDate.day);
      DateTime e = DateTime(endDate.year, endDate.month, endDate.day);
      return (d.isAtSameMomentAs(s) || d.isAfter(s)) && (d.isAtSameMomentAs(e) || d.isBefore(e));
    }

    if (selectedMonth != null && dt.month != selectedMonth) return false;
    if (selectedYear != null && dt.year != selectedYear) return false;

    return true;
  }

  /// Membantu menstandarkan pencarian tanggal untuk query SQLite
  /// Mengembalikan list string berisi kemungkinan format yang tersimpan (ISO dan Lokal)
  static List<String> getDateSearchPatterns(DateTime dt) {
    String y = dt.year.toString();
    String m = dt.month.toString().padLeft(2, '0');
    String d = dt.day.toString().padLeft(2, '0');
    
    return [
      "$y-$m-$d", // 2023-10-27
      "$d-$m-$y", // 27-10-2023
      "$y/$m/$d", // 2023/10/27
      "$d/$m/$y", // 27/10/2023
    ];
  }
}
