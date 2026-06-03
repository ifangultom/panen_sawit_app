import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'database_helper.dart';

// ─── TEMA BIRU ─────────────────────────────────────────────────────────────
const _biru      = Color(0xFF0D47A1);
const _biruMuda  = Color(0xFF1976D2);
const _biruPudar = Color(0xFFE3F2FD);
const _bg        = Color(0xFFF0F4FF);
const _textGelap = Color(0xFF0D1B3E);
const _textAbu   = Color(0xFF5C6E8C);

class TripPage extends StatefulWidget {
  const TripPage({super.key});

  @override
  State<TripPage> createState() => _TripPageState();
}

class _TripPageState extends State<TripPage> {
  List<Map<String, dynamic>> panenList  = [];
  List<int>                  selectedPanen = [];

  final noPlatController = TextEditingController();
  final sopirController  = TextEditingController();

  String afdelingUser = "";
  String mandorLogin  = "";
  String kcsLogin     = "";

  DateTime selectedDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    loadUser();
  }

  // ─── LOAD USER ─────────────────────────────────────────────────────────────
  void loadUser() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    kcsLogin = prefs.getString('kcs_login') ?? "KCS1";
    afdelingUser = prefs.getString('afd_login') ?? "";
    
    // Auto-map jika salah satu kosong
    if (afdelingUser.isEmpty && kcsLogin.isNotEmpty) {
      afdelingUser = kcsLogin.replaceAll("KCS", "AFD");
    }
    if (kcsLogin.isEmpty && afdelingUser.isNotEmpty) {
      kcsLogin = afdelingUser.replaceAll("AFD", "KCS");
    }

    loadPanen();
  }

  // ─── LOAD PANEN ────────────────────────────────────────────────────────────
  Future<void> loadPanen() async {
    final tanggal = selectedDate.toString().split(" ")[0];
    final data = await DatabaseHelper.instance
        .getPanenByKcsAndTanggal(kcsLogin, tanggal);
    setState(() => panenList = data);
  }

  // ─── SIMPAN TRIP ───────────────────────────────────────────────────────────
  Future<void> simpanTrip() async {
    if (noPlatController.text.isEmpty || sopirController.text.isEmpty) {
      _snack("Isi No Plat & Sopir dulu", isError: true);
      return;
    }
    if (selectedPanen.isEmpty) {
      _snack("Pilih data panen dulu", isError: true);
      return;
    }

    final tglTrip = selectedDate.toString().split(" ")[0];
    final fullWaktu = "$tglTrip ${DateTime.now().toString().split(" ")[1]}";

    await DatabaseHelper.instance.insertTrip({
      'tanggal'  : fullWaktu,
      'no_plat'  : noPlatController.text,
      'sopir'    : sopirController.text,
      'afdeling' : afdelingUser,
      'kcs'      : kcsLogin,
    }, selectedPanen);

    selectedPanen.clear();
    noPlatController.clear();
    sopirController.clear();

    await loadPanen();
    _snack("Trip berhasil disimpan!");
    Navigator.pop(context, true);
  }

  void _snack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        Icon(isError ? Icons.warning_rounded : Icons.check_circle_rounded,
            color: Colors.white, size: 18),
        const SizedBox(width: 8),
        Text(msg),
      ]),
      backgroundColor: isError ? const Color(0xFFC62828) : _biru,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  // ─── PICK DATE ─────────────────────────────────────────────────────────────
  Future<void> _pickDate() async {
    DateTime? picked = await showDatePicker(
      context: context,
      initialDate: selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      builder: (context, child) => Theme(
        data: ThemeData.light().copyWith(
          colorScheme: const ColorScheme.light(primary: _biru),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() => selectedDate = picked);
      loadPanen();
    }
  }

  // ─── BUILD ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final tglStr = selectedDate.toString().split(" ")[0];
    final isPilihHariIni =
        tglStr == DateTime.now().toString().split(" ")[0];

    return Scaffold(
      backgroundColor: _bg,

      // ── APP BAR ────────────────────────────────────────────────────────
      appBar: AppBar(
        elevation: 0,
        backgroundColor: _biru,
        foregroundColor: Colors.white,
        title: const Text(
          "Trip Mobil",
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18, letterSpacing: 0.3),
        ),
      ),

      body: Column(
        children: [

          // ── HEADER GRADIENT ──────────────────────────────────────────
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [_biru, _biruMuda],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(28),
                bottomRight: Radius.circular(28),
              ),
            ),
            child: Column(
              children: [

                // No Plat
                _inputField(
                  controller: noPlatController,
                  hint: "No. Plat Kendaraan",
                  icon: Icons.directions_car_rounded,
                ),

                const SizedBox(height: 10),

                // Nama Sopir
                _inputField(
                  controller: sopirController,
                  hint: "Nama Sopir",
                  icon: Icons.person_rounded,
                ),

                const SizedBox(height: 12),

                // Tanggal row
                Row(
                  children: [
                    // Tanggal pill
                    Expanded(
                      child: GestureDetector(
                        onTap: _pickDate,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.white.withOpacity(0.3)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.event_rounded, size: 16, color: Colors.white),
                              const SizedBox(width: 8),
                              Text(
                                tglStr,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                ),
                              ),
                              const Spacer(),
                              const Icon(Icons.edit_calendar_rounded, size: 14, color: Colors.white70),
                            ],
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(width: 10),

                    // Hari Ini button
                    GestureDetector(
                      onTap: () {
                        setState(() => selectedDate = DateTime.now());
                        loadPanen();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: isPilihHariIni
                              ? Colors.white
                              : Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isPilihHariIni
                                ? Colors.transparent
                                : Colors.white.withOpacity(0.3),
                          ),
                        ),
                        child: Text(
                          "Hari Ini",
                          style: TextStyle(
                            color: isPilihHariIni ? _biru : Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // ── SECTION HEADER ────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Container(
                  width: 4, height: 18,
                  decoration: BoxDecoration(
                    color: _biru,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  "Pilih Data Panen",
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    color: _textGelap,
                    letterSpacing: 0.3,
                  ),
                ),
                const Spacer(),
                if (selectedPanen.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: _biruPudar,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      "${selectedPanen.length} dipilih",
                      style: const TextStyle(
                        fontSize: 11, color: _biru, fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // ── LIST PANEN ────────────────────────────────────────────────
          Expanded(
            child: panenList.isEmpty
                ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.inbox_rounded, size: 56, color: Colors.grey.shade300),
                  const SizedBox(height: 10),
                  Text(
                    "Tidak ada data panen",
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
                  ),
                ],
              ),
            )
                : ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              itemCount: panenList.length,
              itemBuilder: (context, index) {
                final item = panenList[index];
                final int id = int.tryParse(item['id'].toString()) ?? 0;
                final isChecked = selectedPanen.contains(id);

                return GestureDetector(
                  onTap: () {
                    setState(() {
                      if (isChecked) {
                        selectedPanen.remove(id);
                      } else {
                        selectedPanen.add(id);
                      }
                    });
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: isChecked ? _biruPudar : Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isChecked ? _biru : Colors.grey.shade200,
                        width: isChecked ? 1.5 : 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: _biru.withOpacity(isChecked ? 0.12 : 0.04),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        // Blok icon
                        Container(
                          width: 44, height: 44,
                          decoration: BoxDecoration(
                            color: isChecked ? _biru : _biruPudar,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            Icons.grid_view_rounded,
                            size: 20,
                            color: isChecked ? Colors.white : _biru,
                          ),
                        ),

                        const SizedBox(width: 12),

                        // Info
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "Blok ${item['blok']}  ·  ${item['pemanen']}",
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                  color: isChecked ? _biru : _textGelap,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 3),
                              Row(
                                children: [
                                  _pill(
                                    icon: Icons.local_florist_rounded,
                                    label: "${item['matang']} Janjang",
                                    isChecked: isChecked,
                                  ),
                                  const SizedBox(width: 6),
                                  _pill(
                                    icon: Icons.scale_rounded,
                                    label: "${item['brondolan']} Kg",
                                    isChecked: isChecked,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),

                        // Checkbox custom
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: 26, height: 26,
                          decoration: BoxDecoration(
                            color: isChecked ? _biru : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isChecked ? _biru : Colors.grey.shade400,
                              width: 1.5,
                            ),
                          ),
                          child: isChecked
                              ? const Icon(Icons.check_rounded, size: 16, color: Colors.white)
                              : null,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),

          // ── SIMPAN TRIP BUTTON ────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: simpanTrip,
                child: Ink(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [_biru, _biruMuda],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: _biru.withOpacity(0.35),
                        blurRadius: 12,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.save_rounded, color: Colors.white, size: 20),
                        SizedBox(width: 10),
                        Text(
                          "Simpan Trip",
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── HELPER WIDGETS ────────────────────────────────────────────────────────

  Widget _inputField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: TextField(
        controller: controller,
        style: const TextStyle(fontSize: 14, color: _textGelap, fontWeight: FontWeight.w500),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: _textAbu, fontSize: 13),
          prefixIcon: Icon(icon, color: _biru, size: 20),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: _biru, width: 1.5),
          ),
        ),
      ),
    );
  }

  Widget _pill({required IconData icon, required String label, required bool isChecked}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 11, color: isChecked ? _biruMuda : _textAbu),
        const SizedBox(width: 3),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: isChecked ? _biruMuda : _textAbu,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}