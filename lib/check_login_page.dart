import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'login_page.dart';
import 'dashboard_admin.dart';
import 'dashboard_kcs.dart';
import 'dashboard_mandor.dart';

class CheckLoginPage extends StatefulWidget {
  const CheckLoginPage({super.key});

  @override
  State<CheckLoginPage> createState() => _CheckLoginPageState();
}

class _CheckLoginPageState extends State<CheckLoginPage> {

  @override
  void initState() {
    super.initState();
    checkLogin();
  }

  void checkLogin() async {
    final prefs = await SharedPreferences.getInstance();

    // Gunakan 'current_user' untuk konsistensi dengan LoginPage
    final String? currentUser = prefs.getString('current_user');
    
    // Ambil role berdasarkan user yang login
    final String role = prefs.getString('role_$currentUser') ?? "";

    // Beri waktu agar animasi splash screen terlihat
    await Future.delayed(const Duration(seconds: 2));

    if (!mounted) return;

    if (currentUser != null && currentUser.isNotEmpty) {
      if (role == "ADMIN") {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const DashboardAdmin()));
      } else if (role == "MANDOR") {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const DashboardMandor()));
      } else {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const DashboardKCS()));
      }
    } else {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginPage()));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF06402B),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Animasi Logo
            TweenAnimationBuilder(
              duration: const Duration(milliseconds: 1000),
              tween: Tween<double>(begin: 0, end: 1),
              builder: (context, double value, child) {
                return Transform.scale(
                  scale: value,
                  child: Opacity(opacity: value, child: child),
                );
              },
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.eco_rounded,
                  size: 80,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              "HARVESTTRACK",
              style: TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.w900,
                letterSpacing: 6,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              "Sistem Monitoring Panen Sawit",
              style: TextStyle(
                color: Colors.white.withOpacity(0.6),
                fontSize: 14,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 80),
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                color: Colors.white,
                strokeWidth: 2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
