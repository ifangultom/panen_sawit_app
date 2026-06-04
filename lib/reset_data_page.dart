import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'database_helper.dart';
import 'login_page.dart';

class ResetDataPage extends StatefulWidget {
  const ResetDataPage({super.key});

  @override
  State<ResetDataPage> createState() => _ResetDataPageState();
}

class _ResetDataPageState extends State<ResetDataPage> {
  String roleUser = "";
  String afdelingUser = "";
  String kcsLogin = "";
  String namaUser = "";
  bool isLoading = false;

  // Statistik data
  int totalPanen = 0;
  int totalTrip = 0;
  int totalPks = 0;

  @override
  void initState() {
    super.initState();
    loadUser();
  }

  Future<void> loadUser() async {
    final prefs = await SharedPreferences.getInstance();
    final user = prefs.getString('current_user') ?? "";
    roleUser = prefs.getString('role_$user') ?? "";
    afdelingUser = prefs.getString('afd_login') ?? "";
    kcsLogin = prefs.getString('kcs_login') ?? "";
    namaUser = prefs.getString('nama_$user') ?? user;
    await _loadStats();
  }

  Future<void> _loadStats() async {
    final db = await DatabaseHelper.instance.database;

    List<Map> panenResult;
    List<Map> tripResult;

    if (roleUser == "ADMIN" || afdelingUser == "ALL") {
      panenResult = await db.rawQuery('SELECT COUNT(*) as c FROM panen');
      tripResult = await db.rawQuery('SELECT COUNT(*) as c FROM trip');
    } else {
      panenResult = await db.rawQuery(
          'SELECT COUNT(*) as c FROM panen WHERE afdeling = ?', [afdelingUser]);
      tripResult = await db.rawQuery(
          'SELECT COUNT(*) as c FROM trip WHERE kcs = ?', [kcsLogin]);
    }

    final pksResult = await db.rawQuery('SELECT COUNT(*) as c FROM pks');

    setState(() {
      totalPanen = int.tryParse(panenResult.first['c'].toString()) ?? 0;
      totalTrip = int.tryParse(tripResult.first['c'].toString()) ?? 0;
      totalPks = int.tryParse(pksResult.first['c'].toString()) ?? 0;
      isLoading = false;
    });
  }

  // ===== RESET PANEN =====
  Future<void> _resetPanen() async {
    final confirm = await _dialog(
      "Reset Data Panen",
      "Semua data panen ${roleUser == 'ADMIN' ? 'SEMUA AFD' : afdelingUser} akan dihapus permanen.\n\nData tidak bisa dikembalikan!",
      "Reset Panen",
      Colors.orange,
    );
    if (confirm != true) return;

    setState(() => isLoading = true);
    final db = await DatabaseHelper.instance.database;

    if (roleUser == "ADMIN" || afdelingUser == "ALL") {
      await db.delete('panen');
    } else {
      // 🔥 FIX: hapus berdasarkan afdeling ATAU kcs (untuk kompatibilitas data lama)
      await db.delete('panen',
          where: 'afdeling = ? OR kcs = ?',
          whereArgs: [afdelingUser, kcsLogin]);
    }

    await _loadStats();
    _snack("✅ Data panen $afdelingUser berhasil direset", Colors.orange);
  }

  // ===== RESET TRIP =====
  Future<void> _resetTrip() async {
    final confirm = await _dialog(
      "Reset Data Trip",
      "Semua data trip ${roleUser == 'ADMIN' ? 'SEMUA' : kcsLogin} akan dihapus permanen.\n\nData tidak bisa dikembalikan!",
      "Reset Trip",
      Colors.red,
    );
    if (confirm != true) return;

    setState(() => isLoading = true);
    final db = await DatabaseHelper.instance.database;

    if (roleUser == "ADMIN" || afdelingUser == "ALL") {
      await db.delete('trip_detail');
      await db.delete('pks');
      await db.delete('trip');
    } else {
      final trips = await db.query('trip', where: 'kcs = ?', whereArgs: [kcsLogin]);
      for (final t in trips) {
        final id = t['id'];
        await db.delete('trip_detail', where: 'trip_id = ?', whereArgs: [id]);
        await db.delete('pks', where: 'trip_id = ?', whereArgs: [id]);
      }
      await db.delete('trip', where: 'kcs = ?', whereArgs: [kcsLogin]);
    }

    await _loadStats();
    _snack("✅ Data trip $kcsLogin berhasil direset", Colors.red);
  }

  // ===== FACTORY RESET =====
  Future<void> _resetSemuaLokal() async {
    final confirm = await _dialog(
      "⚠️ Reset Aplikasi",
      "Aplikasi akan direset seperti baru diinstall.\n\nSemua data panen, trip, PKS, dan SEMUA AKUN akan dihapus permanen.\n\nTidak bisa dibatalkan!",
      "Reset Sekarang",
      Colors.red.shade900,
    );
    if (confirm != true) return;

    // Konfirmasi kedua
    final confirm2 = await _dialog(
      "Konfirmasi Terakhir",
      "Yakin? Ini akan menghapus SEMUA akun dan data. Kamu harus daftar ulang.",
      "Ya, Reset Total",
      Colors.red.shade900,
    );
    if (confirm2 != true) return;

    setState(() => isLoading = true);

    // 1. Hapus semua tabel SQLite menggunakan fungsi global
    await DatabaseHelper.instance.clearAllData();

    // 2. Hapus semua SharedPreferences (semua akun, semua session)
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();

    if (!mounted) return;

    // 3. Kembali ke LoginPage seperti baru install
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginPage()),
          (_) => false,
    );
  }

  // ===== LOGOUT =====
  Future<void> _logout() async {
    final confirm = await _dialog(
      "Keluar",
      "Yakin ingin keluar dari akun $namaUser?",
      "Keluar",
      const Color(0xFF1565C0),
    );
    if (confirm != true) return;

    final prefs = await SharedPreferences.getInstance();
    // 🔥 FIX: clear semua session prefs supaya tidak ada sisa data lama
    await prefs.remove('current_user');
    await prefs.remove('kcs_login');
    await prefs.remove('afd_login');
    await prefs.remove('isLogin');
    await prefs.remove('role_login');
    await prefs.remove('afdeling_login'); // key lama yang mungkin masih ada

    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginPage()),
          (_) => false,
    );
  }

  Future<bool?> _dialog(String title, String content, String confirmLabel, Color color) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(title, style: TextStyle(fontWeight: FontWeight.bold, color: color)),
        content: Text(content, style: const TextStyle(fontSize: 14)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Batal", style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: color,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
  }

  void _snack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.all(16),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = roleUser == "ADMIN" || afdelingUser == "ALL";

    return Scaffold(
      backgroundColor: const Color(0xFFF0F4FF),
      appBar: AppBar(
        title: const Text("Pengaturan & Reset", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF0D47A1),
        foregroundColor: Colors.white,
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF0D47A1)))
          : SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            // ===== INFO AKUN =====
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF0D47A1), Color(0xFF1976D2)],
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [BoxShadow(color: const Color(0xFF0D47A1).withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 4))],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.person, color: Colors.white, size: 28),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(namaUser, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                        Text(roleUser, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                        Text(
                          isAdmin ? "Akses: Semua AFD" : "Akses: $afdelingUser  |  $kcsLogin",
                          style: const TextStyle(color: Colors.white60, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // ===== STATISTIK DATA =====
            _sectionLabel("📊 Ringkasan Data Lokal"),
            const SizedBox(height: 10),
            Row(
              children: [
                _statCard("Data Panen", "$totalPanen", Icons.grass, const Color(0xFF0D47A1)),
                const SizedBox(width: 10),
                _statCard("Trip", "$totalTrip", Icons.local_shipping, const Color(0xFF1976D2)),
                const SizedBox(width: 10),
                _statCard("PKS", "$totalPks", Icons.scale, Colors.orange),
              ],
            ),

            const SizedBox(height: 24),

            // ===== RESET OPTIONS =====
            _sectionLabel("🗑️ Reset Data"),
            const SizedBox(height: 10),

            _resetCard(
              icon: Icons.grass,
              title: "Reset Data Panen",
              subtitle: isAdmin
                  ? "Hapus semua data panen dari database lokal"
                  : "Hapus data panen $afdelingUser dari database lokal",
              color: Colors.orange,
              onTap: _resetPanen,
            ),

            const SizedBox(height: 10),

            _resetCard(
              icon: Icons.local_shipping,
              title: "Reset Data Trip",
              subtitle: isAdmin
                  ? "Hapus semua trip, trip detail, dan PKS"
                  : "Hapus trip $kcsLogin beserta detail dan PKS",
              color: Colors.red,
              onTap: _resetTrip,
            ),

            const SizedBox(height: 10),

            _resetCard(
              icon: Icons.delete_forever,
              title: "🔄 Reset Aplikasi (Factory Reset)",
              subtitle: "Hapus semua data + akun, kembali seperti baru install",
              color: Colors.red.shade900,
              onTap: _resetSemuaLokal,
            ),

            const SizedBox(height: 10),

            _resetCard(
              icon: Icons.refresh_rounded,
              title: "Sinkron Ulang Master Data",
              subtitle: "Ambil ulang data Pemanen & Blok dari Cloud",
              color: const Color(0xFF0D47A1),
              onTap: () async {
                setState(() => isLoading = true);
                try {
                  await DatabaseHelper.instance.syncHarvesters();
                  await DatabaseHelper.instance.syncBlocks();
                  _snack("✅ Master data berhasil disinkronkan", const Color(0xFF0D47A1));
                } catch (e) {
                  _snack("❌ Gagal sinkron: $e", Colors.red);
                } finally {
                  setState(() => isLoading = false);
                }
              },
            ),

            const SizedBox(height: 10),

            _resetCard(
              icon: Icons.cloud_upload_rounded,
              title: "Upload Ulang Data Transaksi",
              subtitle: "Kirim kembali data Panen & Trip ke Cloud",
              color: Colors.teal,
              onTap: () async {
                setState(() => isLoading = true);
                try {
                  await DatabaseHelper.instance.resetSyncStatus();
                  _snack("✅ Status sinkronisasi direset. Silakan masuk ke menu Sinkronisasi.", Colors.teal);
                } catch (e) {
                  _snack("❌ Gagal reset: $e", Colors.red);
                } finally {
                  setState(() => isLoading = false);
                }
              },
            ),

            const SizedBox(height: 24),

            // ===== LOGOUT =====
            _sectionLabel("🔐 Akun"),
            const SizedBox(height: 10),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _logout,
                icon: const Icon(Icons.logout_rounded),
                label: const Text("Keluar dari Akun", style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0D47A1),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  elevation: 4,
                ),
              ),
            ),

            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.bold,
        color: Color(0xFF37474F),
        letterSpacing: 0.5,
      ),
    );
  }

  Widget _statCard(String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(color: color.withOpacity(0.1), blurRadius: 8, offset: const Offset(0, 3))],
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 6),
            Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
            Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
          ],
        ),
      ),
    );
  }

  Widget _resetCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        splashColor: color.withOpacity(0.1),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withOpacity(0.2)),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6, offset: const Offset(0, 2))],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: color)),
                    const SizedBox(height: 2),
                    Text(subtitle, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_ios_rounded, size: 14, color: color.withOpacity(0.5)),
            ],
          ),
        ),
      ),
    );
  }
}