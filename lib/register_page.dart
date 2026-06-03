import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage>
    with TickerProviderStateMixin {

  final usernameC = TextEditingController();
  final passwordC = TextEditingController();
  final confirmC  = TextEditingController();

  String selectedAfd  = "AFD1";
  String selectedRole = "KCS";
  bool showPass       = false;
  bool showConfirm    = false;
  bool isLoading      = false;

  late AnimationController _bgController;
  late AnimationController _fadeController;
  late Animation<double>   _fadeAnim;
  late Animation<Offset>   _slideAnim;

  // Role config
  final _roles = const [
    {"value": "KCS",    "label": "KCS",    "icon": Icons.manage_accounts_rounded,  "color": Color(0xFF0D47A1)},
    {"value": "MANDOR", "label": "Mandor", "icon": Icons.supervisor_account_rounded,"color": Color(0xFF1976D2)},
    {"value": "ADMIN",  "label": "Admin",  "icon": Icons.admin_panel_settings_rounded,"color": Color(0xFF1565C0)},
  ];

  final _afds = const [
    {"value": "AFD1", "label": "Afdeling 1"},
    {"value": "AFD2", "label": "Afdeling 2"},
    {"value": "AFD3", "label": "Afdeling 3"},
  ];

  @override
  void initState() {
    super.initState();

    _bgController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat(reverse: true);

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );

    _fadeAnim = CurvedAnimation(parent: _fadeController, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.25),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _fadeController, curve: Curves.easeOutCubic));

    _fadeController.forward();
  }

  @override
  void dispose() {
    _bgController.dispose();
    _fadeController.dispose();
    usernameC.dispose();
    passwordC.dispose();
    confirmC.dispose();
    super.dispose();
  }

  void register() async {
    final email = usernameC.text.trim();
    final pass = passwordC.text.trim();
    final confirm = confirmC.text.trim();

    if (email.isEmpty || pass.isEmpty || confirm.isEmpty) {
      _showSnack("Isi semua data terlebih dahulu", isError: true);
      return;
    }

    if (pass != confirm) {
      _showSnack("Password tidak cocok", isError: true);
      return;
    }

    if (pass.length < 4) {
      _showSnack("Password minimal 4 karakter", isError: true);
      return;
    }

    setState(() => isLoading = true);

    try {
      // 🔐 REGISTER KE FIREBASE AUTH
      final userCredential = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(
        email: email,
        password: pass,
      );

      final uid = userCredential.user!.uid;

      // 🔥 SIMPAN DATA USER KE FIRESTORE
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .set({
        'email': email,
        'role': selectedRole,
        'afdeling': selectedRole == "ADMIN" ? "ALL" : selectedAfd,
        'created_at': DateTime.now().toIso8601String(),
      });

      _showSnack("Akun berhasil dibuat!");

      await Future.delayed(const Duration(milliseconds: 800));

      if (mounted) Navigator.pop(context);

    } on FirebaseAuthException catch (e) {
      _showSnack(e.message ?? "Register gagal", isError: true);
    }

    setState(() => isLoading = false);
  }

  void _showSnack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(children: [
          Icon(isError ? Icons.error_outline : Icons.check_circle,
              color: Colors.white, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(msg)),
        ]),
        backgroundColor: isError ? const Color(0xFFD32F2F) : const Color(0xFF1976D2),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  Color get _roleColor {
    final r = _roles.firstWhere((r) => r["value"] == selectedRole);
    return r["color"] as Color;
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return _buildWebLayout();
    }

    return Scaffold(
      body: Stack(
        children: [

          // ===== BACKGROUND =====
          AnimatedBuilder(
            animation: _bgController,
            builder: (_, __) => Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    const Color(0xFF0D47A1),
                    Color.lerp(const Color(0xFF1976D2),
                        const Color(0xFF1565C0), _bgController.value)!,
                    const Color(0xFF002171),
                  ],
                  stops: const [0.0, 0.5, 1.0],
                ),
              ),
            ),
          ),

          // Dekorasi lingkaran
          Positioned(
            top: -40, right: -40,
            child: Container(
              width: 160, height: 160,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.06),
              ),
            ),
          ),
          Positioned(
            top: 60, left: -30,
            child: Container(
              width: 100, height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.04),
              ),
            ),
          ),

          // Ikon dekorasi berputar
          Positioned(
            top: 80, right: 25,
            child: AnimatedBuilder(
              animation: _bgController,
              builder: (_, __) => Transform.rotate(
                angle: _bgController.value * math.pi * 0.4,
                child: Icon(Icons.eco, size: 24,
                    color: Colors.white.withOpacity(0.14)),
              ),
            ),
          ),
          Positioned(
            top: 130, left: 20,
            child: AnimatedBuilder(
              animation: _bgController,
              builder: (_, __) => Transform.rotate(
                angle: -_bgController.value * math.pi * 0.3,
                child: Icon(Icons.grass, size: 20,
                    color: Colors.white.withOpacity(0.1)),
              ),
            ),
          ),

          // ===== CONTENT =====
          SafeArea(
            child: Column(
              children: [

                // Header
                FadeTransition(
                  opacity: _fadeAnim,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                    child: Row(
                      children: [
                        GestureDetector(
                          onTap: () => Navigator.pop(context),
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(Icons.arrow_back_ios_new_rounded,
                                color: Colors.white, size: 18),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              "Buat Akun Baru",
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Text(
                              "Daftar untuk mulai menggunakan HARVESTRAK",
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.65),
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                // Form card
                Expanded(
                  child: SlideTransition(
                    position: _slideAnim,
                    child: FadeTransition(
                      opacity: _fadeAnim,
                      child: Container(
                        width: double.infinity,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.vertical(
                            top: Radius.circular(36),
                          ),
                        ),
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [

                              // Pilih Role dulu — chip style
                              const Text(
                                "Pilih Role",
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF37474F),
                                ),
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: _roles.map((r) {
                                  final isSelected = selectedRole == r["value"];
                                  final color = r["color"] as Color;
                                  return Expanded(
                                    child: GestureDetector(
                                      onTap: () => setState(
                                              () => selectedRole = r["value"] as String),
                                      child: AnimatedContainer(
                                        duration: const Duration(milliseconds: 200),
                                        margin: const EdgeInsets.only(right: 8),
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 12),
                                        decoration: BoxDecoration(
                                          color: isSelected
                                              ? color
                                              : color.withOpacity(0.07),
                                          borderRadius:
                                          BorderRadius.circular(14),
                                          border: Border.all(
                                            color: isSelected
                                                ? color
                                                : color.withOpacity(0.2),
                                            width: 1.5,
                                          ),
                                          boxShadow: isSelected
                                              ? [
                                            BoxShadow(
                                              color: color.withOpacity(0.35),
                                              blurRadius: 10,
                                              offset: const Offset(0, 4),
                                            )
                                          ]
                                              : [],
                                        ),
                                        child: Column(
                                          children: [
                                            Icon(r["icon"] as IconData,
                                                size: 22,
                                                color: isSelected
                                                    ? Colors.white
                                                    : color),
                                            const SizedBox(height: 4),
                                            Text(
                                              r["label"] as String,
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w700,
                                                color: isSelected
                                                    ? Colors.white
                                                    : color,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),

                              const SizedBox(height: 20),

                              // Username
                              _label("Username"),
                              const SizedBox(height: 6),
                              _buildField(
                                controller: usernameC,
                                hint: "Masukkan username",
                                icon: Icons.person_outline_rounded,
                              ),

                              const SizedBox(height: 14),

                              // Password
                              _label("Password"),
                              const SizedBox(height: 6),
                              _buildField(
                                controller: passwordC,
                                hint: "Minimal 4 karakter",
                                icon: Icons.lock_outline_rounded,
                                isPassword: true,
                                isConfirm: false,
                              ),

                              const SizedBox(height: 14),

                              // Konfirmasi Password
                              _label("Konfirmasi Password"),
                              const SizedBox(height: 6),
                              _buildField(
                                controller: confirmC,
                                hint: "Ulangi password",
                                icon: Icons.lock_reset_rounded,
                                isPassword: true,
                                isConfirm: true,
                              ),

                              // Afdeling — hanya tampil kalau bukan ADMIN
                              if (selectedRole != "ADMIN") ...[
                                const SizedBox(height: 14),
                                _label("Afdeling"),
                                const SizedBox(height: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 14),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF5F7FF),
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                        color: const Color(0xFFDDE3F5)),
                                  ),
                                  child: DropdownButtonHideUnderline(
                                    child: DropdownButton<String>(
                                      value: selectedAfd,
                                      isExpanded: true,
                                      icon: Icon(Icons.keyboard_arrow_down_rounded,
                                          color: _roleColor),
                                      items: _afds
                                          .map((a) => DropdownMenuItem(
                                        value: a["value"],
                                        child: Row(children: [
                                          Icon(Icons.location_on_outlined,
                                              size: 16,
                                              color: _roleColor),
                                          const SizedBox(width: 8),
                                          Text(a["label"]!),
                                        ]),
                                      ))
                                          .toList(),
                                      onChanged: (v) =>
                                          setState(() => selectedAfd = v!),
                                    ),
                                  ),
                                ),
                              ],

                              const SizedBox(height: 28),

                              // Tombol DAFTAR
                              SizedBox(
                                width: double.infinity,
                                height: 54,
                                child: ElevatedButton(
                                  onPressed: isLoading ? null : register,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: _roleColor,
                                    foregroundColor: Colors.white,
                                    elevation: 6,
                                    shadowColor: _roleColor.withOpacity(0.4),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                  ),
                                  child: isLoading
                                      ? const SizedBox(
                                      width: 22, height: 22,
                                      child: CircularProgressIndicator(
                                          color: Colors.white,
                                          strokeWidth: 2.5))
                                      : Row(
                                    mainAxisAlignment:
                                    MainAxisAlignment.center,
                                    children: const [
                                      Icon(Icons.person_add_rounded,
                                          size: 20),
                                      SizedBox(width: 10),
                                      Text(
                                        "BUAT AKUN",
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 1.5,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),

                              const SizedBox(height: 16),

                              // Sudah punya akun
                              Center(
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text("Sudah punya akun?  ",
                                        style: TextStyle(
                                            color: Colors.grey.shade500,
                                            fontSize: 13)),
                                    GestureDetector(
                                      onTap: () => Navigator.pop(context),
                                      child: Text(
                                        "Masuk",
                                        style: TextStyle(
                                          color: _roleColor,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              const SizedBox(height: 8),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWebLayout() {
    return Scaffold(
      backgroundColor: const Color(0xFF0D47A1),
      body: Center(
        child: Container(
          width: 900, // Lebar card disesuaikan untuk tampilan web
          height: MediaQuery.of(context).size.height * 0.85,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.2),
                blurRadius: 30,
                offset: const Offset(0, 10),
              )
            ],
          ),
          child: Column(
            children: [
              // Header Web
              Container(
                padding: const EdgeInsets.all(24),
                decoration: const BoxDecoration(
                  color: Color(0xFF0D47A1),
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(24),
                    topRight: Radius.circular(24),
                  ),
                ),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 18),
                      onPressed: () => Navigator.pop(context),
                    ),
                    const SizedBox(width: 16),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "Buat Akun Baru",
                          style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          "Daftar untuk mulai menggunakan HARVESTRAK",
                          style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 12),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Body Web
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 30),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _label("Pilih Role"),
                      const SizedBox(height: 12),
                      Row(
                        children: _roles.map((r) {
                          final isSelected = selectedRole == r["value"];
                          final color = r["color"] as Color;
                          return Expanded(
                            child: GestureDetector(
                              onTap: () => setState(() => selectedRole = r["value"] as String),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                margin: const EdgeInsets.only(right: 12),
                                padding: const EdgeInsets.symmetric(vertical: 20),
                                decoration: BoxDecoration(
                                  color: isSelected ? color : Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: isSelected ? color : Colors.grey.withOpacity(0.2),
                                    width: 1.5,
                                  ),
                                  boxShadow: isSelected
                                      ? [BoxShadow(color: color.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 4))]
                                      : [],
                                ),
                                child: Column(
                                  children: [
                                    Icon(r["icon"] as IconData, color: isSelected ? Colors.white : color, size: 28),
                                    const SizedBox(height: 8),
                                    Text(
                                      r["label"] as String,
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: isSelected ? Colors.white : color,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 24),
                      _label("Username"),
                      const SizedBox(height: 8),
                      _buildField(controller: usernameC, hint: "Masukkan username", icon: Icons.person_outline),
                      const SizedBox(height: 16),
                      _label("Password"),
                      const SizedBox(height: 8),
                      _buildField(controller: passwordC, hint: "Minimal 4 karakter", icon: Icons.lock_outline, isPassword: true),
                      const SizedBox(height: 16),
                      _label("Konfirmasi Password"),
                      const SizedBox(height: 8),
                      _buildField(controller: confirmC, hint: "Ulangi password", icon: Icons.lock_reset, isPassword: true, isConfirm: true),
                      if (selectedRole != "ADMIN") ...[
                        const SizedBox(height: 16),
                        _label("Afdeling"),
                        const SizedBox(height: 8),
                        _buildWebAfdDropdown(),
                      ],
                      const SizedBox(height: 32),
                      _buildWebSubmitButton(),
                      const SizedBox(height: 16),
                      Center(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text("Sudah punya akun?  ", style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
                            GestureDetector(
                              onTap: () => Navigator.pop(context),
                              child: Text(
                                "Masuk",
                                style: TextStyle(color: _roleColor, fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                            ),
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
      ),
    );
  }

  Widget _buildWebAfdDropdown() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F7FF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFDDE3F5)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: selectedAfd,
          isExpanded: true,
          items: _afds.map((a) => DropdownMenuItem(
            value: a["value"],
            child: Text(a["label"]!),
          )).toList(),
          onChanged: (v) => setState(() => selectedAfd = v!),
        ),
      ),
    );
  }

  Widget _buildWebSubmitButton() {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: isLoading ? null : register,
        style: ElevatedButton.styleFrom(
          backgroundColor: _roleColor,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 2,
        ),
        child: isLoading
            ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Icon(Icons.person_add_alt_1),
                  SizedBox(width: 12),
                  Text("BUAT AKUN", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, letterSpacing: 1.2)),
                ],
              ),
      ),
    );
  }

  Widget _label(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: Color(0xFF37474F),
      ),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    bool isPassword = false,
    bool isConfirm = false,
  }) {
    final obscure = isPassword
        ? (isConfirm ? !showConfirm : !showPass)
        : false;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF5F7FF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFDDE3F5)),
      ),
      child: TextField(
        controller: controller,
        obscureText: obscure,
        style: const TextStyle(fontSize: 15, color: Color(0xFF1A1A2E)),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
          prefixIcon: Icon(icon, color: _roleColor, size: 22),
          suffixIcon: isPassword
              ? IconButton(
            icon: Icon(
              obscure
                  ? Icons.visibility_rounded
                  : Icons.visibility_off_rounded,
              color: Colors.grey.shade400,
              size: 20,
            ),
            onPressed: () => setState(() {
              if (isConfirm) {
                showConfirm = !showConfirm;
              } else {
                showPass = !showPass;
              }
            }),
          )
              : null,
          border: InputBorder.none,
          contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
      ),
    );
  }
}