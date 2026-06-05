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

  static String mapKcsToAfd(String? kcs) {
    if (kcs == null) return "";
    final cleanKcs = kcs.toUpperCase().trim();
    if (cleanKcs.contains("KCS1")) return "AFD1";
    if (cleanKcs.contains("KCS2")) return "AFD2";
    if (cleanKcs.contains("KCS3")) return "AFD3";
    // Fallback if it already looks like AFD
    if (cleanKcs.contains("AFD")) return cleanKcs;
    return cleanKcs;
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
}
