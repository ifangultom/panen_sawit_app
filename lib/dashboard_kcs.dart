import 'dart:io';
import 'package:flutter/material.dart';


// 🔥 IMPORT PAGE
import 'profile_page.dart';
import 'input_panen.dart';
import 'map_geo_tagging.dart';
import 'riwayat_panen.dart';
import 'sinkronisasi_page.dart';
import 'reset_data_page.dart';
import 'login_page.dart';

// 🔥 HELPER
import 'user_helper.dart';
import 'database_helper.dart';

class DashboardKCS extends StatefulWidget {
  const DashboardKCS({super.key});

  @override
  State<DashboardKCS> createState() => _DashboardKCSState();
}

class _DashboardKCSState extends State<DashboardKCS> with SingleTickerProviderStateMixin {

  String nama = "";
  String jabatan = "";
  String fotoPath = "";

  late AnimationController _animController;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _fadeAnim = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOut,
    );

    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.15),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _animController,
        curve: Curves.easeOutCubic,
      ),
    );

    loadUser();

    // 🔥 Perbaikan: Cek koneksi dulu atau bungkus dengan try-catch agar tidak crash saat offline
    _initData();

    _animController.forward();
  }

  Future<void> _initData() async {
    try {
      // Hanya ambil data dari firebase jika ada sinyal, agar tidak macet di layar awal
      await DatabaseHelper.instance.ambilDataDariFirebase().timeout(const Duration(seconds: 5));
      await DatabaseHelper.instance.syncHarvesters().timeout(const Duration(seconds: 5));
      await DatabaseHelper.instance.syncBlocks().timeout(const Duration(seconds: 5));
    } catch (e) {
      debugPrint("Gagal sinkron otomatis (offline): $e");
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 11) return "Selamat Pagi";
    if (h < 15) return "Selamat Siang";
    if (h < 18) return "Selamat Sore";
    return "Selamat Malam";
  }

  // ================= LOAD USER =================
  void loadUser() async {
    final data = await UserHelper.getUser();

    final user = data['username'] ?? "";

    // 🔥 kalau belum login → pindah ke login
    if (user.isEmpty) {
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const LoginPage()),
      );
      return;
    }

    final foto = await UserHelper.getFoto(user);

    setState(() {
      nama = (data['nama'] ?? "").isEmpty ? user.split('@')[0] : data['nama']!; 
      jabatan = (data['jabatan'] ?? "").isEmpty ? "KCS" : data['jabatan']!;
      fotoPath = foto;
    });
  }
  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    const bulan = ['','Jan','Feb','Mar','Apr','Mei','Jun','Jul','Ags','Sep','Okt','Nov','Des'];
    const hari = ['','Sen','Sel','Rab','Kam','Jum','Sab','Min'];
    final tanggalStr = "${hari[now.weekday]}, ${now.day} ${bulan[now.month]} ${now.year}";

    return Scaffold(
      backgroundColor: const Color(0xFFF0F4FF),
      body: CustomScrollView(
        slivers: [

          // ===== HEADER =====
          SliverToBoxAdapter(
            child: Stack(
              children: [
                Container(
                  height: 200,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF0D47A1), Color(0xFF1565C0), Color(0xFF1976D2)],
                    ),
                  ),
                ),
                Positioned(
                  top: -30, right: -30,
                  child: Container(
                    width: 140, height: 140,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withOpacity(0.06),
                    ),
                  ),
                ),
                Positioned(
                  bottom: 10, left: -20,
                  child: Container(
                    width: 90, height: 90,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withOpacity(0.05),
                    ),
                  ),
                ),
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            GestureDetector(
                              onTap: () async {
                                await Navigator.push(context,
                                    MaterialPageRoute(builder: (_) => const ProfilePage()));
                                loadUser();
                              },
                              child: Container(
                                padding: const EdgeInsets.all(2),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.white.withOpacity(0.8), width: 2),
                                ),
                                child: CircleAvatar(
                                  radius: 28,
                                  backgroundImage: fotoPath.isNotEmpty
                                      ? FileImage(File(fotoPath))
                                      : const AssetImage("assets/logo.png") as ImageProvider,
                                  backgroundColor: Colors.white.withOpacity(0.2),
                                ),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _greeting(),
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.75),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    nama.isEmpty ? "User" : nama,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 18,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.18),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text(
                                      jabatan.isEmpty ? "KCS" : jabatan,
                                      style: const TextStyle(color: Colors.white70, fontSize: 11),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            GestureDetector(
                              onTap: () async {
                                await Navigator.push(context,
                                    MaterialPageRoute(builder: (_) => const ProfilePage()));
                                loadUser();
                              },
                              child: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(Icons.settings_rounded, color: Colors.white, size: 20),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: Colors.white.withOpacity(0.2)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.calendar_today_rounded, color: Colors.white70, size: 16),
                              const SizedBox(width: 8),
                              Text(
                                tanggalStr,
                                style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                              ),
                              const Spacer(),
                              const Icon(Icons.agriculture_rounded, color: Colors.white38, size: 16),
                              const SizedBox(width: 4),
                              const Text("HARVESTRAK", style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ===== TITLE =====
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(20, 20, 20, 12),
              child: Row(
                children: [
                  Text(
                    "Menu Utama",
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0D1B4B),
                    ),
                  ),
                  SizedBox(width: 8),
                  Expanded(child: Divider(color: Color(0xFFDDE3F5), thickness: 1.5)),
                ],
              ),
            ),
          ),

          // ===== GRID =====
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 14,
                mainAxisSpacing: 14,
                childAspectRatio: 1.05,
              ),
              delegate: SliverChildListDelegate([
                _menuCard(
                  icon: Icons.add_circle_outline_rounded,
                  label: "Input Panen",
                  color1: const Color(0xFF1565C0),
                  color2: const Color(0xFF42A5F5),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const InputPanenPage())),
                ),
                _menuCard(
                  icon: Icons.location_on_rounded,
                  label: "Geo Tracking",
                  color1: const Color(0xFF1976D2),
                  color2: const Color(0xFF42A5F5),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MapGeoTaggingPage())),
                ),
                _menuCard(
                  icon: Icons.history_rounded,
                  label: "Riwayat Panen",
                  color1: const Color(0xFF1565C0),
                  color2: const Color(0xFF64B5F6),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RiwayatPanenPage())),
                ),
                _menuCard(
                  icon: Icons.person_rounded,
                  label: "Profil",
                  color1: const Color(0xFF0D47A1),
                  color2: const Color(0xFF1976D2),
                  onTap: () async {
                    await Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfilePage()));
                    loadUser();
                  },
                ),
                _menuCard(
                  icon: Icons.sync_rounded,
                  label: "Sinkronisasi",
                  color1: const Color(0xFF880E4F),
                  color2: const Color(0xFFEC407A),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SinkronisasiPage())),
                ),
                _menuCard(
                  icon: Icons.delete_forever_rounded,
                  label: "Reset Data",
                  color1: Colors.red.shade900,
                  color2: Colors.red.shade400,
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ResetDataPage())),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _menuCard({
    required IconData icon,
    required String label,
    required Color color1,
    required Color color2,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        splashColor: color1.withOpacity(0.12),
        highlightColor: color1.withOpacity(0.06),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: color1.withOpacity(0.15),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Stack(
            children: [
              Positioned(
                top: -12, right: -12,
                child: Container(
                  width: 70, height: 70,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(colors: [
                      color2.withOpacity(0.15),
                      color1.withOpacity(0.04),
                    ]),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [color1, color2],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: color1.withOpacity(0.4),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Icon(icon, color: Colors.white, size: 26),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF0D1B4B),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          width: 24, height: 3,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(colors: [color1, color2]),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget menuItem(IconData icon, String title, VoidCallback onTap) {
    return _menuCard(
      icon: icon, label: title,
      color1: const Color(0xFF1565C0), color2: const Color(0xFF42A5F5),
      onTap: onTap,
    );
  }
}