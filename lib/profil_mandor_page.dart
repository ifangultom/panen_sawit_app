import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'user_helper.dart';
import 'login_page.dart';

// ─── WARNA TEMA BIRU ──────────────────────────────────────────────────────────
const _biru      = Color(0xFF0D47A1);
const _biruMuda  = Color(0xFF1565C0);
const _biruPudar = Color(0xFFE3F2FD);
const _bg        = Color(0xFFF0F4FF);
const _textGelap = Color(0xFF0D1B3E);
const _textAbu   = Color(0xFF5C6E8C);

class ProfilMandorPage extends StatefulWidget {
  const ProfilMandorPage({super.key});

  @override
  State<ProfilMandorPage> createState() => _ProfilMandorPageState();
}

class _ProfilMandorPageState extends State<ProfilMandorPage>
    with SingleTickerProviderStateMixin {

  final namaC    = TextEditingController();
  final jabatanC = TextEditingController();

  String username = "";
  String fotoPath = "";

  late AnimationController _animC;
  late Animation<double>   _slideUp;

  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _animC   = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
    _slideUp = CurvedAnimation(parent: _animC, curve: Curves.easeOut);
    _animC.forward();
    loadUser();
  }

  @override
  void dispose() {
    _animC.dispose();
    super.dispose();
  }

  // ─── FUNGSI ────────────────────────────────────────────────────────────────
  Future<void> loadUser() async {
    final data = await UserHelper.getUser();
    final user = data['username'] ?? "";
    if (user.isEmpty) {
      if (!mounted) return;
      Navigator.pushReplacement(context,
          MaterialPageRoute(builder: (_) => const LoginPage()));
      return;
    }
    final foto = await UserHelper.getFoto(user);
    setState(() {
      username      = user;
      namaC.text    = data['nama']    ?? "";
      jabatanC.text = data['jabatan'] ?? "";
      fotoPath      = foto;
    });
  }

  // ✅ FIX: pickFoto menggunakan ImageSource.gallery dengan imageQuality
  Future<void> pickFoto() async {
    final picker = ImagePicker();
    final file   = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
    );
    if (file != null && username.isNotEmpty) {
      await UserHelper.saveFoto(file.path, username);
      setState(() => fotoPath = file.path);
    }
  }

  Future<void> simpan() async {
    if (username.isEmpty) {
      _snack("Silakan login dulu", isError: true);
      return;
    }

    setState(() => _isSaving = true);

    try {
      final nameStr = namaC.text.trim();
      final jobStr = jabatanC.text.trim();

      // 1. Simpan Lokal (Shared Preferences)
      await UserHelper.saveUser(
          nama: nameStr,
          jabatan: jobStr,
          username: username);

      // 2. Simpan ke Firestore untuk persistensi permanen
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
          'nama': nameStr,
          'jabatan': jobStr,
        });
      }

      if (!mounted) return;
      _snack("Profil berhasil diperbarui");
      Navigator.pop(context, true);
    } catch (e) {
      debugPrint("Gagal menyimpan profil: $e");
      _snack("Gagal menyimpan ke server, tersimpan lokal", isError: false);
      if (mounted) Navigator.pop(context, true);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> logout() async {
    final konfirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text("Keluar Akun"),
        content: const Text("Apakah Anda yakin ingin logout?"),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text("Batal", style: TextStyle(color: _textAbu))),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red[600]),
            child: const Text("Logout", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (konfirm == true) {
      await UserHelper.logout();
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(context,
          MaterialPageRoute(builder: (_) => const LoginPage()),
              (r) => false);
    }
  }

  void _snack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? Colors.red[700] : _biru,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  // ─── BUILD ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: Column(children: [

        // ── HEADER MANDOR ─────────────────────────────────────────────────
        // ✅ FIX: Stack dengan clipBehavior: Clip.none agar avatar tidak terpotong
        Stack(clipBehavior: Clip.none, children: [
          // Background gradient
          Container(
            height: 200,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                  colors: [_biru, _biruMuda],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight),
              borderRadius: BorderRadius.vertical(
                  bottom: Radius.circular(0)),
            ),
          ),

          // Dekorasi lingkaran
          Positioned(
            top: -30, right: -30,
            child: Container(
              width: 130, height: 130,
              decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.07)),
            ),
          ),
          Positioned(
            top: 40, right: 20,
            child: Container(
              width: 60, height: 60,
              decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.07)),
            ),
          ),

          // Tombol back & logout
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                      icon: const Icon(Icons.arrow_back_ios_new_rounded,
                          color: Colors.white),
                      onPressed: () => Navigator.pop(context)),
                  const Text("Profil Mandor",
                      style: TextStyle(color: Colors.white,
                          fontWeight: FontWeight.w800, fontSize: 17,
                          letterSpacing: 0.5)),
                  IconButton(
                      icon: const Icon(Icons.logout_rounded, color: Colors.white),
                      onPressed: logout),
                ],
              ),
            ),
          ),

          // ✅ FIX: Avatar dengan Positioned bottom negatif — tidak terpotong lagi!
          Positioned(
            bottom: -50, left: 0, right: 0,
            child: Center(
              child: GestureDetector(
                onTap: pickFoto,
                child: Stack(clipBehavior: Clip.none, children: [
                  Container(
                    width: 100, height: 100,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 4),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withOpacity(0.2),
                            blurRadius: 12)
                      ],
                      color: Colors.grey[200],
                      image: fotoPath.isNotEmpty
                          ? DecorationImage(
                          image: FileImage(File(fotoPath)),
                          fit: BoxFit.cover)
                          : null,
                    ),
                    child: fotoPath.isEmpty
                        ? const Icon(Icons.person_rounded, size: 50,
                        color: Color(0xFF9E9E9E))
                        : null,
                  ),
                  // ✅ FIX: Tombol kamera lebih besar dan mudah di-tap
                  Positioned(
                    bottom: 0, right: 0,
                    child: Container(
                      width: 32, height: 32,
                      decoration: BoxDecoration(
                          color: _biru,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2.5),
                          boxShadow: [
                            BoxShadow(color: _biru.withOpacity(0.4),
                                blurRadius: 6, offset: const Offset(0, 2))
                          ]),
                      child: const Icon(Icons.camera_alt_rounded,
                          size: 16, color: Colors.white),
                    ),
                  ),
                ]),
              ),
            ),
          ),
        ]),

        // ✅ FIX: SizedBox 62 untuk kompensasi avatar yang menonjol ke bawah
        const SizedBox(height: 62),

        // ── BADGE JABATAN ──────────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
          decoration: BoxDecoration(
              color: _biruPudar,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _biru.withOpacity(0.3))),
          child: Text(
              jabatanC.text.isEmpty ? "MANDOR" : jabatanC.text.toUpperCase(),
              style: const TextStyle(color: _biru, fontWeight: FontWeight.w700,
                  fontSize: 11, letterSpacing: 1.5)),
        ),

        const SizedBox(height: 4),

        Text("@$username",
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: _textAbu, fontSize: 13)),

        const SizedBox(height: 24),

        // ── FORM FIELDS ────────────────────────────────────────────────────
        Expanded(
          child: SlideTransition(
            position: Tween<Offset>(
                begin: const Offset(0, 0.15), end: Offset.zero)
                .animate(_slideUp),
            child: FadeTransition(
              opacity: _slideUp,
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                child: Column(children: [

                  _formCard(
                    icon: Icons.person_outline_rounded,
                    label: "Nama Lengkap",
                    controller: namaC,
                    hint: "Masukkan nama lengkap",
                  ),

                  const SizedBox(height: 12),

                  _formCard(
                    icon: Icons.badge_outlined,
                    label: "Jabatan",
                    controller: jabatanC,
                    hint: "Jabatan Anda",
                  ),

                  const SizedBox(height: 40),

                  // ── SIMPAN ─────────────────────────────────────────────
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _isSaving ? null : simpan,
                      style: ElevatedButton.styleFrom(
                          backgroundColor: _biru,
                          foregroundColor: Colors.white,
                          elevation: 4,
                          shadowColor: _biru.withOpacity(0.4),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16))),
                      child: _isSaving
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.check_circle_outline_rounded, size: 20),
                          SizedBox(width: 8),
                          Text("SIMPAN PROFIL",
                              style: TextStyle(fontWeight: FontWeight.w800,
                                  fontSize: 14, letterSpacing: 1.2)),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),
                ]),
              ),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _formCard({
    required IconData icon,
    required String label,
    required TextEditingController controller,
    required String hint,
  }) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 6),
        child: Row(children: [
          Icon(icon, size: 14, color: _biru),
          const SizedBox(width: 5),
          Text(label,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                  color: _biru, letterSpacing: 0.5)),
        ]),
      ),
      Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.04),
                blurRadius: 8, offset: const Offset(0, 2))
          ],
        ),
        child: TextField(
          controller: controller,
          style: const TextStyle(fontSize: 15, color: _textGelap,
              fontWeight: FontWeight.w500),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: _textAbu, fontSize: 13),
            contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: _biru, width: 1.5)),
          ),
        ),
      ),
    ]);
  }
}