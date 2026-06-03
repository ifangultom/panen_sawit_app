import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'main.dart'; // Import themeNotifier

class PengaturanPage extends StatefulWidget {
  final bool isWebView;
  const PengaturanPage({super.key, this.isWebView = false});

  @override
  State<PengaturanPage> createState() => _PengaturanPageState();
}

class _PengaturanPageState extends State<PengaturanPage> {
  bool _notifEnabled = true;
  bool _darkMode = false;
  String _currentLang = "Bahasa Indonesia";

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  // Memuat pengaturan yang tersimpan di browser/HP
  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _notifEnabled = prefs.getBool('notifEnabled') ?? true;
      _darkMode = prefs.getBool('isDarkMode') ?? false;
      _currentLang = prefs.getString('language') ?? "Bahasa Indonesia";
    });
  }

  // Simpan pengaturan Tema
  Future<void> _toggleDarkMode(bool val) async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _darkMode = val;
      themeNotifier.value = val ? ThemeMode.dark : ThemeMode.light;
    });
    await prefs.setBool('isDarkMode', val);
  }

  // Simpan pengaturan Notifikasi
  Future<void> _toggleNotif(bool val) async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _notifEnabled = val);
    await prefs.setBool('notifEnabled', val);
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(val ? "Notifikasi diaktifkan" : "Notifikasi dimatikan"), duration: const Duration(seconds: 1)),
      );
    }
  }

  // Fungsi Bersihkan Cache (Menghapus SharedPreferences)
  Future<void> _clearCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Cache berhasil dibersihkan! Silakan login kembali.")),
      );
      Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget body = ListView(
      padding: widget.isWebView ? const EdgeInsets.all(25) : EdgeInsets.zero,
      children: [
        if (widget.isWebView) ...[
          const Text("Pengaturan Sistem", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 25),
        ],
        
        // 1. NOTIFIKASI
        SwitchListTile(
          title: const Text("Notifikasi Real-time"),
          subtitle: const Text("Terima pemberitahuan saat ada data panen baru"),
          value: _notifEnabled,
          onChanged: _toggleNotif,
          activeColor: const Color(0xFF0D47A1),
          secondary: const Icon(Icons.notifications, color: Color(0xFF0D47A1)),
        ),

        // 2. MODE GELAP
        SwitchListTile(
          title: const Text("Mode Gelap"),
          subtitle: const Text("Gunakan tema gelap untuk aplikasi"),
          value: _darkMode,
          onChanged: _toggleDarkMode,
          activeColor: const Color(0xFF0D47A1),
          secondary: const Icon(Icons.dark_mode, color: Color(0xFF0D47A1)),
        ),
        
        const Divider(),

        // 3. BERSIHKAN CACHE
        ListTile(
          leading: const Icon(Icons.storage, color: Color(0xFF0D47A1)),
          title: const Text("Bersihkan Cache Data"),
          subtitle: const Text("Menghapus data sementara yang tersimpan"),
          onTap: () {
            showDialog(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text("Bersihkan Cache"),
                content: const Text("Semua pengaturan lokal akan dihapus dan Anda harus login ulang. Lanjutkan?"),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(context), child: const Text("Batal")),
                  TextButton(
                    onPressed: () {
                      Navigator.pop(context);
                      _clearCache();
                    }, 
                    child: const Text("Ya, Bersihkan", style: TextStyle(color: Colors.red))
                  ),
                ],
              ),
            );
          },
        ),

        // 4. BAHASA
        ListTile(
          leading: const Icon(Icons.language, color: Color(0xFF0D47A1)),
          title: const Text("Bahasa"),
          trailing: Text(_currentLang),
          onTap: () {
            // Sederhananya kita ganti saja secara toggle untuk contoh ini
            setState(() {
              _currentLang = _currentLang == "Bahasa Indonesia" ? "English" : "Bahasa Indonesia";
            });
          },
        ),

        // 5. TENTANG
        ListTile(
          leading: const Icon(Icons.info_outline, color: Color(0xFF0D47A1)),
          title: const Text("Tentang Aplikasi"),
          subtitle: const Text("HarvestTrack Admin v1.0.1"),
          onTap: () {
            showAboutDialog(
              context: context,
              applicationName: "HarvestTrack Admin",
              applicationVersion: "1.0.1",
              applicationIcon: const Icon(Icons.agriculture, color: Color(0xFF0D47A1), size: 40),
              children: [
                const Text("Sistem Monitoring Panen Kelapa Sawit untuk memudahkan manajemen operasional di lapangan."),
              ],
            );
          },
        ),

        const Divider(),

        // 6. KELUAR AKUN
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 20),
          child: SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red, 
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))
              ),
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text("Konfirmasi Keluar"),
                    content: const Text("Apakah Anda yakin ingin keluar dari akun?"),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(context), child: const Text("Batal")),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                        onPressed: () async {
                          final prefs = await SharedPreferences.getInstance();
                          await prefs.remove('user_token'); // Hapus session login
                          if (mounted) {
                            Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
                          }
                        },
                        child: const Text("Keluar", style: TextStyle(color: Colors.white)),
                      ),
                    ],
                  ),
                );
              },
              child: const Text("Keluar Akun", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ),
        ),
      ],
    );

    if (widget.isWebView) return body;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Pengaturan", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF0D47A1),
        foregroundColor: Colors.white,
      ),
      body: body,
    );
  }
}
