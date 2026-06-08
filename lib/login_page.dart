import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'dashboard_kcs.dart';
import 'dashboard_mandor.dart';
import 'dashboard_admin.dart';
import 'register_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> with TickerProviderStateMixin {
  final usernameC = TextEditingController();
  final passwordC = TextEditingController();

  bool showPass = false;
  bool isLoading = false;

  late AnimationController _floatController;
  late AnimationController _fadeController;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();

    _floatController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    _fadeAnim = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    );

    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOutCubic,
    ));

    _fadeController.forward();
  }

  @override
  void dispose() {
    _floatController.dispose();
    _fadeController.dispose();
    usernameC.dispose();
    passwordC.dispose();
    super.dispose();
  }

  void login() async {
    final email = usernameC.text.trim();
    final pass = passwordC.text.trim();

    if (email.isEmpty || pass.isEmpty) {
      _showSnack("Isi email & password", isError: true);
      return;
    }

    setState(() => isLoading = true);

    try {
      // 1. Tambahkan Timeout pada proses login Firebase (misal 10 detik)
      final userCredential = await FirebaseAuth.instance
          .signInWithEmailAndPassword(email: email, password: pass)
          .timeout(const Duration(seconds: 10));

      final uid = userCredential.user!.uid;
      
      // 2. Tambahkan Timeout pada pengambilan data Firestore
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get()
          .timeout(const Duration(seconds: 7));

      final userData = userDoc.data() ?? {};
      final role = userData['role'] ?? "KCS";
      final afdeling = userData['afdeling'] ?? "AFD1";
      final nama = userData['nama'] ?? email;

      final prefs = await SharedPreferences.getInstance();

      // Simpan data untuk login offline nanti
      await prefs.setString('last_email', email);
      await prefs.setString('last_pass', pass);
      await prefs.setString('current_user', email);
      await prefs.setString('role_$email', role);
      await prefs.setString('afd_login', afdeling);
      
      await prefs.setString('jabatan_$email', role == "ADMIN" ? (userData['jabatan'] ?? "Super Admin") : role);
      
      if (userData['foto'] != null) {
        await prefs.setString('foto_$email', userData['foto']);
      }
      
      await prefs.setString('nama_$email', nama);

      final kcsMap = {"AFD1": "KCS1", "AFD2": "KCS2", "AFD3": "KCS3"};
      final kcsLogin = kcsMap[afdeling] ?? "KCS1";
      await prefs.setString('kcs_login', kcsLogin);

      if (!mounted) return;

      if (role == "MANDOR") {
        Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const DashboardMandor()), (r) => false);
      } else if (role == "ADMIN") {
        Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const DashboardAdmin()), (r) => false);
      } else {
        Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const DashboardKCS()), (r) => false);
      }
    } catch (e) {
      // Jika terjadi timeout atau error network, coba Mode Offline
      bool isTimeout = e is Future<void> || e.toString().contains('TimeoutException');
      bool isNetworkError = e.toString().contains('network-request-failed') || 
                           e.toString().contains('unavailable') || 
                           e.toString().toLowerCase().contains('network');

      if (isTimeout || isNetworkError) {
        final prefs = await SharedPreferences.getInstance();
        final lastEmail = prefs.getString('last_email');
        final lastPass = prefs.getString('last_pass');

        if (email == lastEmail && pass == lastPass) {
          final role = prefs.getString('role_$email') ?? "KCS";
          await prefs.setString('current_user', email);
          
          _showSnack("Mode Offline: Login Berhasil");
          if (!mounted) return;
          
          if (role == "MANDOR") {
            Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const DashboardMandor()), (r) => false);
          } else if (role == "ADMIN") {
            Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const DashboardAdmin()), (r) => false);
          } else {
            Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const DashboardKCS()), (r) => false);
          }
          return;
        }
      }
      
      _showSnack(e.toString().contains('user-not-found') ? "User tidak ditemukan" : 
                 e.toString().contains('wrong-password') ? "Password salah" : 
                 "Login gagal: Periksa koneksi internet Anda", isError: true);
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(isError ? Icons.error_outline : Icons.check_circle, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text(msg)), // Membungkus teks agar tidak overflow
          ],
        ),
        backgroundColor: isError ? const Color(0xFFD32F2F) : const Color(0xFF1976D2),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: kIsWeb ? webLoginLayout() : mobileLoginLayout(),
    );
  }

  // ================= WEB LOGIN LAYOUT (CENTERED LIKE COMMON WEB LOGIN) =================
  Widget webLoginLayout() {
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0D47A1), Color(0xFF1565C0), Color(0xFF01579B)],
          stops: [0.0, 0.5, 1.0],
        ),
      ),
      child: Stack(
        children: [
          // Background Decorations
          Positioned(top: -100, right: -100, child: _circleDeco(300)),
          Positioned(bottom: -50, left: -50, child: _circleDeco(250)),
          
          Center(
            child: SingleChildScrollView(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Logo & App Name
                  FadeTransition(
                    opacity: _fadeAnim,
                    child: Column(
                      children: [
                        _logoWidget(100),
                        const SizedBox(height: 20),
                        _appNameWidget(fontSize: 35),
                        const SizedBox(height: 40),
                      ],
                    ),
                  ),
                  
                  // Login Card
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 450),
                    child: FadeTransition(
                      opacity: _fadeAnim,
                      child: Card(
                        elevation: 20,
                        shadowColor: Colors.black45,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                        child: Padding(
                          padding: const EdgeInsets.all(40.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text("Masuk ke Akun",
                                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: Color(0xFF0D47A1))),
                              const SizedBox(height: 6),
                              Text("Silakan masuk untuk melanjutkan ke Dashboard Admin",
                                  style: TextStyle(fontSize: 14, color: Colors.grey.shade500)),
                              const SizedBox(height: 32),
                              _buildField(controller: usernameC, hint: "Username / Email", icon: Icons.person_outline_rounded),
                              const SizedBox(height: 16),
                              _buildField(controller: passwordC, hint: "Password", icon: Icons.lock_outline_rounded, isPassword: true),
                              const SizedBox(height: 32),
                              _loginButton(isWeb: true),
                              const SizedBox(height: 24),
                              Center(child: _registerText()),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ================= MOBILE LOGIN LAYOUT (ORIGINAL DESIGN) =================
  Widget mobileLoginLayout() {
    final size = MediaQuery.of(context).size;
    return Stack(
      children: [
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF0D47A1), Color(0xFF1565C0), Color(0xFF01579B)],
              stops: [0.0, 0.5, 1.0],
            ),
          ),
        ),
        Positioned(top: -60, right: -60, child: _circleDeco(200)),
        Positioned(bottom: size.height * 0.25, left: -80, child: _circleDeco(250)),
        
        SafeArea(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: size.height - MediaQuery.of(context).padding.top,
              ),
              child: Column(
                children: [
                  // Logo Area
                  FadeTransition(
                    opacity: _fadeAnim,
                    child: Container(
                      padding: EdgeInsets.only(
                        top: size.height * 0.08,
                        bottom: 30,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _logoWidget(110, animated: true),
                          const SizedBox(height: 20),
                          _appNameWidget(),
                          const SizedBox(height: 6),
                          Text("SISTEM DIGITALISASI PANEN",
                              style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.65), letterSpacing: 1.2)),
                        ],
                      ),
                    ),
                  ),
                  
                  // Login Form
                  SlideTransition(
                    position: _slideAnim,
                    child: FadeTransition(
                      opacity: _fadeAnim,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.fromLTRB(28, 32, 28, 32),
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.vertical(top: Radius.circular(36)),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text("Masuk ke Akun",
                                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Color(0xFF0D47A1))),
                            const SizedBox(height: 4),
                            Text("Silakan masuk untuk melanjutkan", style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
                            const SizedBox(height: 24),
                            _buildField(controller: usernameC, hint: "Username", icon: Icons.person_outline_rounded),
                            const SizedBox(height: 14),
                            _buildField(controller: passwordC, hint: "Password", icon: Icons.lock_outline_rounded, isPassword: true),
                            const SizedBox(height: 28),
                            _loginButton(),
                            const SizedBox(height: 16),
                            Center(child: _registerText()),
                            const SizedBox(height: 16),
                            Center(child: _offlineModeBadge()),
                            const SizedBox(height: 10),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  // --- REUSABLE WIDGETS ---

  Widget _circleDeco(double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withOpacity(0.05)),
    );
  }

  Widget _logoWidget(double size, {bool animated = false}) {
    Widget child = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.25),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.35), blurRadius: 30, offset: const Offset(0, 12))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.25),
        child: Image.asset('assets/logo.png', fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(color: const Color(0xFF1565C0), child: const Icon(Icons.agriculture, size: 60, color: Colors.white))),
      ),
    );

    if (animated) {
      return AnimatedBuilder(
        animation: _floatController,
        builder: (_, child) => Transform.translate(offset: Offset(0, -8 * math.sin(_floatController.value * math.pi)), child: child),
        child: child,
      );
    }
    return child;
  }

  Widget _appNameWidget({double fontSize = 30}) {
    return RichText(
      text: TextSpan(
        children: [
          TextSpan(text: "Harvest", style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 3)),
          TextSpan(text: "Track", style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w900, color: const Color(0xFF4FC3F7), letterSpacing: 3)),
        ],
      ),
    );
  }

  Widget _loginButton({bool isWeb = false}) {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: ElevatedButton(
        onPressed: isLoading ? null : login,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF1565C0),
          foregroundColor: Colors.white,
          elevation: 6,
          shadowColor: const Color(0xFF1565C0).withOpacity(0.5),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        child: isLoading
            ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(isWeb ? "MASUK KE DASHBOARD" : "MASUK", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: 2)),
                  const SizedBox(width: 10),
                  const Icon(Icons.arrow_forward_rounded, size: 20),
                ],
              ),
      ),
    );
  }

  Widget _registerText() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text("Belum punya akun?  ", style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
        GestureDetector(
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RegisterPage())),
          child: const Text("Daftar", style: TextStyle(color: Color(0xFF1565C0), fontWeight: FontWeight.w700, fontSize: 13)),
        ),
      ],
    );
  }

  Widget _offlineModeBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.orange.shade200, width: 1)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.wifi_off_rounded, size: 14, color: Colors.orange.shade600),
          const SizedBox(width: 6),
          Text("Mode Offline Aktif", style: TextStyle(fontSize: 11, color: Colors.orange.shade700, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildField({required TextEditingController controller, required String hint, required IconData icon, bool isPassword = false}) {
    return Container(
      decoration: BoxDecoration(color: const Color(0xFFF5F7FF), borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFFDDE3F5))),
      child: TextField(
        controller: controller,
        obscureText: isPassword && !showPass,
        style: const TextStyle(fontSize: 15, color: Color(0xFF1A1A2E)),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
          prefixIcon: Icon(icon, color: const Color(0xFF1565C0), size: 22),
          suffixIcon: isPassword
              ? IconButton(
                  icon: Icon(showPass ? Icons.visibility_rounded : Icons.visibility_off_rounded, color: Colors.grey.shade400, size: 20),
                  onPressed: () => setState(() => showPass = !showPass),
                )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
      ),
    );
  }
}
