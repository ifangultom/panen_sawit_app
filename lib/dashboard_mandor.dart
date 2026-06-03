import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'data_panen_page.dart';
import 'dashboard_statistik_mandor.dart';
import 'laporan_page.dart';
import 'trip_page.dart';
import 'riwayat_trip.dart';
import 'sinkronisasi_page.dart';
import 'reset_data_page.dart';
import 'profil_mandor_page.dart';
import 'user_helper.dart';
import 'login_page.dart';
import 'database_helper.dart';

class DashboardMandor extends StatefulWidget {
  const DashboardMandor({super.key});

  @override
  State<DashboardMandor> createState() => _DashboardMandorState();
}

class _DashboardMandorState extends State<DashboardMandor> with SingleTickerProviderStateMixin {
  String nama = "";
  String jabatan = "";
  String fotoPath = "";
  String username = "";
  String afdeling = "";

  late AnimationController _animController;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(vsync: this, duration: const Duration(milliseconds: 800));
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(begin: const Offset(0, 0.15), end: Offset.zero)
        .animate(CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic));
    loadUser();
    _animController.forward();

    // Trigger sinkronisasi otomatis ke cloud saat masuk dashboard
    Future.delayed(const Duration(seconds: 3), () {
      DatabaseHelper.instance.syncData();
    });
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

  void loadUser() async {
    final data = await UserHelper.getUser();
    final user = data['username'] ?? "";

    if (user.isEmpty) {
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const LoginPage()),
            (route) => false,
      );
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    String afd   = prefs.getString('afd_login') ?? "";
    
    // Jika afd_login kosong (misal setelah update app), coba ambil dari afdeling_$user
    if (afd.isEmpty && user.isNotEmpty) {
      afd = prefs.getString('afdeling_$user') ?? "";
      if (afd.isEmpty) {
        // Fallback terakhir: mapping dari kcs_login
        final kcs = prefs.getString('kcs_login') ?? "";
        const map = {"KCS1": "AFD1", "KCS2": "AFD2", "KCS3": "AFD3"};
        afd = map[kcs] ?? "";
      }
      if (afd.isNotEmpty) await prefs.setString('afd_login', afd);
    }

    final foto = await UserHelper.getFoto(user);

    if (mounted) {
      setState(() {
        username = user;
        nama = data['nama'] ?? (prefs.getString('nama_$user') ?? "Mandor");
        jabatan = data['jabatan'] ?? "Mandor";
        fotoPath = foto;
        afdeling = afd;
      });
    }
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

          // ===== HEADER SLIVER =====
          SliverToBoxAdapter(
            child: Stack(
              children: [
                // Background gradient header
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
                // Dekorasi lingkaran
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
                  bottom: 20, left: -20,
                  child: Container(
                    width: 100, height: 100,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withOpacity(0.05),
                    ),
                  ),
                ),
                // Konten header
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            // Foto profil
                            GestureDetector(
                              onTap: () async {
                                await Navigator.push(context,
                                    MaterialPageRoute(builder: (_) => const ProfilMandorPage()));
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
                                  backgroundImage: fotoPath.isNotEmpty ? FileImage(File(fotoPath)) : null,
                                  backgroundColor: Colors.white.withOpacity(0.2),
                                  child: fotoPath.isEmpty
                                      ? const Icon(Icons.person, size: 28, color: Colors.white)
                                      : null,
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
                                    nama.isEmpty ? "Mandor" : nama,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
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
                                      jabatan.isEmpty ? "Mandor" : jabatan,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(color: Colors.white70, fontSize: 11),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            // Tombol profil
                            GestureDetector(
                              onTap: () async {
                                await Navigator.push(context,
                                    MaterialPageRoute(builder: (_) => const ProfilMandorPage()));
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
                        // Info tanggal
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

          // ===== GRID MENU =====
          SliverToBoxAdapter(child: FadeTransition(opacity: _fadeAnim, child: SlideTransition(position: _slideAnim, child: const SizedBox()))),
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
                  icon: Icons.list_alt_rounded,
                  label: "Data Panen",
                  color1: const Color(0xFF1565C0),
                  color2: const Color(0xFF42A5F5),
                  onTap: () async {
                    await Navigator.push(context, MaterialPageRoute(builder: (_) => const DataPanenPage()));
                    loadUser();
                  },
                ),
                _menuCard(
                  icon: Icons.local_shipping_rounded,
                  label: "Trip Mobil",
                  color1: const Color(0xFF1976D2),
                  color2: const Color(0xFF42A5F5),
                  onTap: () async {
                    await Navigator.push(context, MaterialPageRoute(builder: (_) => const TripPage()));
                    loadUser();
                  },
                ),
                _menuCard(
                  icon: Icons.history_rounded,
                  label: "Riwayat Trip",
                  color1: const Color(0xFF1565C0),
                  color2: const Color(0xFF64B5F6),
                  onTap: () async {
                    await Navigator.push(context, MaterialPageRoute(
                      builder: (_) => const RiwayatTripPage(hideAfdelingFilter: true)
                    ));
                    loadUser();
                  },
                ),
                _menuCard(
                  icon: Icons.bar_chart_rounded,
                  label: "Laporan",
                  color1: const Color(0xFF0D47A1),
                  color2: const Color(0xFF1976D2),
                  onTap: () {
                    Navigator.push(context, MaterialPageRoute(
                      builder: (_) => LaporanPanenPage(
                        tanggal: DateTime.now().toString().split(" ")[0],
                        initialAfdeling: afdeling.isNotEmpty ? afdeling : null,
                        lockAfdeling: true,
                      ),
                    ));
                  },
                ),
                _menuCard(
                  icon: Icons.sync_rounded,
                  label: "Sinkronisasi",
                  color1: const Color(0xFF1565C0),
                  color2: const Color(0xFF1976D2),
                  onTap: () async {
                    await Navigator.push(context, MaterialPageRoute(builder: (_) => const SinkronisasiPage(readOnly: true)));
                    loadUser();
                  },
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
              // Dekorasi sudut kanan atas
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
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
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

  // Keep old helpers for compatibility (not used in new UI but kept to avoid errors)
  Widget menuItem(BuildContext context, IconData icon, String title, Widget page) {
    return _menuCard(
      icon: icon, label: title,
      color1: const Color(0xFF1565C0), color2: const Color(0xFF42A5F5),
      onTap: () async {
        await Navigator.push(context, MaterialPageRoute(builder: (_) => page));
        loadUser();
      },
    );
  }

  Widget menuItemAction(BuildContext context, IconData icon, String title, VoidCallback onTap) {
    return _menuCard(
      icon: icon, label: title,
      color1: const Color(0xFF1565C0), color2: const Color(0xFF42A5F5),
      onTap: onTap,
    );
  }
}