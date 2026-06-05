import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'database_helper.dart';
import 'utils/date_utils.dart';

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
  bool isSaving = false;

  @override
  void initState() {
    super.initState();
    loadUser();
  }

  // ─── LOAD USER ─────────────────────────────────────────────────────────────
  Future<void> loadUser() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    final user = prefs.getString('current_user') ?? "";
    final kcs = prefs.getString('kcs_login') ?? "KCS1";
    String afd = prefs.getString('afd_login') ?? "";
    
    // Gunakan helper standar untuk mapping wilayah
    if (afd.isEmpty) {
      afd = AppDateUtils.mapKcsToAfd(kcs);
    }

    setState(() {
      kcsLogin = kcs;
      afdelingUser = afd;
      mandorLogin = user;
    });

    await loadPanen();
  }

  // ─── LOAD PANEN ────────────────────────────────────────────────────────────
  Future<void> loadPanen() async {
    final String tglHyphen = selectedDate.toString().split(" ")[0]; // 2026-01-12
    final String tglSlash = tglHyphen.replaceAll('-', '/'); // 2026/01/12
    final String afdNormalized = afdelingUser.replaceAll(' ', '').toUpperCase();

    List<Map<String, dynamic>> temp = [];

    try {
      // 1. Ambil data lokal (ACC & Belum Trip)
      final localData = await _loadLocalPanenForTrip();

      final connectivity = await Connectivity().checkConnectivity();
      if (connectivity != ConnectivityResult.none) {
        // 2. Ambil data online dari Firebase
        // 🔥 OPTIMASI: Hapus filter status 'ACC' di server agar tidak butuh composite index
        // Filter status akan dilakukan di sisi client (memory).
        final snapshots = await Future.wait([
          FirebaseFirestore.instance.collection('panen')
              .where('tanggal', isGreaterThanOrEqualTo: tglHyphen)
              .where('tanggal', isLessThan: tglHyphen + 'z')
              .get(),
          FirebaseFirestore.instance.collection('panen')
              .where('tanggal', isGreaterThanOrEqualTo: tglSlash)
              .where('tanggal', isLessThan: tglSlash + 'z')
              .get(),
        ]);

        List<Map<String, dynamic>> onlineData = [];
        for (var snap in snapshots) {
          for (var doc in snap.docs) {
            final d = Map<String, dynamic>.from(doc.data() as Map);
            d['firebase_id'] = doc.id;
            onlineData.add(d);
          }
        }

        // 3. Filter data online di sisi client (Afdeling & Status ACC)
        onlineData = onlineData.where((d) {
          // Filter Status ACC
          final status = (d['status'] ?? "").toString().toUpperCase();
          if (status != 'ACC') return false;

          // Filter Afdeling
          if (afdNormalized == "ALL" || afdNormalized.isEmpty) return true;

          String itemAfd = (d['afdeling'] ?? "").toString().replaceAll(' ', '').toUpperCase();
          if (itemAfd.isEmpty) {
            itemAfd = (d['kcs'] ?? "").toString().replaceAll(' ', '').toUpperCase();
            if (itemAfd.contains("KCS")) itemAfd = itemAfd.replaceAll("KCS", "AFD");
          }
          return itemAfd == afdNormalized;
        }).toList();

        // 4. Gabungkan & De-duplikasi (Gunakan key yang konsisten dengan RiwayatPanen)
        Map<String, Map<String, dynamic>> combined = {};
        for (var d in localData) {
          final u = d['user'] ?? mandorLogin;
          String key = d['firebase_id'] ?? d['doc_id'] ?? "${u}_${d['id']}";
          combined[key] = Map<String, dynamic>.from(d);
        }

        for (var d in onlineData) {
          String key = d['firebase_id'] ?? d['doc_id'] ?? "";
          if (key.isNotEmpty) {
            if (combined.containsKey(key)) {
              // Jika sudah ada di lokal, update data lokal (siapa tahu ada perubahan online)
              // namun tetap pertahankan ID lokal untuk trip_detail
              final localId = combined[key]!['id'];
              combined[key] = Map<String, dynamic>.from(d);
              combined[key]!['id'] = localId;
            } else {
              // Jika tidak ada di lokal (yang BELUM trip), 
              // kita masukkan asalkan data ini belum masuk trip manapun secara lokal
              final db = await DatabaseHelper.instance.database;
              final checkTrip = await db.rawQuery("SELECT id FROM trip_detail WHERE panen_id = ?", [d['id'] ?? -1]);
              
              if (checkTrip.isEmpty) {
                d['id'] = d['id'] ?? d['local_id'] ?? key.hashCode.abs();
                combined[key] = Map<String, dynamic>.from(d);
              }
            }
          }
        }
        temp = combined.values.toList();
      } else {
        temp = localData;
      }
    } catch (e) {
      print("Error loading panen for trip: $e");
      temp = await _loadLocalPanenForTrip();
    }

    setState(() => panenList = temp);
  }

  Future<List<Map<String, dynamic>>> _loadLocalPanenForTrip() async {
    final db = await DatabaseHelper.instance.database;
    final List<String> patterns = AppDateUtils.getDateSearchPatterns(selectedDate);
    final String afdNormalized = afdelingUser.replaceAll(' ', '').toUpperCase();

    // Ambil data lokal yang sudah ACC dan BELUM masuk trip
    final allLocal = await db.rawQuery('''
      SELECT * FROM panen 
      WHERE id NOT IN (SELECT panen_id FROM trip_detail)
      AND TRIM(UPPER(status)) = 'ACC'
    ''');

    return allLocal.where((e) {
      // Filter Tanggal
      String tglRaw = (e['tanggal'] ?? "").toString();
      bool matchDate = patterns.any((p) => tglRaw.startsWith(p));
      if (!matchDate) return false;

      // Filter Afdeling
      if (afdNormalized == "ALL" || afdNormalized.isEmpty) return true;

      String itemAfd = (e['afdeling'] ?? "").toString().replaceAll(' ', '').toUpperCase();
      if (itemAfd.isEmpty) {
        itemAfd = (e['kcs'] ?? "").toString().replaceAll(' ', '').toUpperCase();
        if (itemAfd.contains("KCS")) itemAfd = itemAfd.replaceAll("KCS", "AFD");
      }

      return itemAfd == afdNormalized;
    }).map((e) => Map<String, dynamic>.from(e)).toList();
  }

  // ─── SIMPAN TRIP ───────────────────────────────────────────────────────────
  Future<void> simpanTrip() async {
    if (isSaving) return;

    if (noPlatController.text.trim().isEmpty) {
      _snack("No. Plat Kendaraan wajib diisi", isError: true);
      return;
    }
    if (sopirController.text.trim().isEmpty) {
      _snack("Nama Sopir wajib diisi", isError: true);
      return;
    }
    if (selectedPanen.isEmpty) {
      _snack("Pilih minimal satu data panen", isError: true);
      return;
    }

    // Validasi Data User
    if (afdelingUser.isEmpty || kcsLogin.isEmpty) {
      _snack("Data wilayah tidak lengkap. Silakan login ulang.", isError: true);
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text("Simpan Trip"),
        content: Text("Simpan trip untuk ${selectedPanen.length} data panen ini?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Batal", style: TextStyle(color: _textAbu)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: _biru,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text("Simpan"),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => isSaving = true);

    try {
      final tglTrip = selectedDate.toString().split(" ")[0];
      final fullWaktu = "$tglTrip ${DateTime.now().toString().split(" ")[1]}";

      await DatabaseHelper.instance.insertTrip({
        'tanggal'  : fullWaktu,
        'no_plat'  : noPlatController.text.trim().toUpperCase(),
        'sopir'    : sopirController.text.trim(),
        'afdeling' : afdelingUser,
        'kcs'      : kcsLogin,
      }, selectedPanen);

      selectedPanen.clear();
      noPlatController.clear();
      sopirController.clear();

      _snack("Trip berhasil disimpan!");
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      _snack("Gagal menyimpan trip: $e", isError: true);
    } finally {
      if (mounted) setState(() => isSaving = false);
    }
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

      body: SingleChildScrollView(
        child: Column(
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
                    hint: "No. Plat Kendaraan (Contoh: BK 1234 ABC)",
                    icon: Icons.directions_car_rounded,
                    textInputAction: TextInputAction.next,
                  ),

                  const SizedBox(height: 10),

                  // Nama Sopir
                  _inputField(
                    controller: sopirController,
                    hint: "Nama Sopir",
                    icon: Icons.person_rounded,
                    textInputAction: TextInputAction.done,
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
            panenList.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 40),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.inbox_rounded, size: 56, color: Colors.grey.shade300),
                          const SizedBox(height: 10),
                          Text(
                            "Tidak ada data panen (ACC)",
                            style: TextStyle(fontSize: 14, color: Colors.grey.shade600, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 4),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 40),
                            child: Text(
                              "Pastikan data sudah di-ACC di menu Monitoring Panen sebelum membuat trip.",
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
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
                      child: isSaving
                          ? const Center(
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              ),
                            )
                          : const Row(
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
      ),
    );

  }

  // ─── HELPER WIDGETS ────────────────────────────────────────────────────────

  Widget _inputField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    TextInputAction? textInputAction,
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
        textInputAction: textInputAction,
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