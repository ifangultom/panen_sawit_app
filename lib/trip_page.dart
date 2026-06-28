import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
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
  final Map<String, dynamic>? data;
  const TripPage({super.key, this.data});

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

    if (widget.data != null) {
      noPlatController.text = widget.data!['no_plat'] ?? widget.data!['kendaraan'] ?? "";
      sopirController.text = widget.data!['sopir'] ?? "";
      if (widget.data!['tanggal'] != null) {
        selectedDate = DateTime.tryParse(widget.data!['tanggal'].toString()) ?? DateTime.now();
      }
    }
  }

  Future<void> loadUser() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    final user = prefs.getString('current_user') ?? "";
    final kcs = prefs.getString('kcs_login') ?? "KCS1";
    String afd = prefs.getString('afd_login') ?? "";
    
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

  Future<void> loadPanen() async {
    final String tglHyphen = selectedDate.toString().split(" ")[0];
    final String tglSlash = tglHyphen.replaceAll('-', '/');
    final String afdNormalized = afdelingUser.replaceAll(' ', '').toUpperCase();

    List<Map<String, dynamic>> temp = [];

    try {
      final localData = await _loadLocalPanenForTrip();
      final connectivity = await Connectivity().checkConnectivity();
      
      if (!connectivity.contains(ConnectivityResult.none)) {
        final snapshots = await Future.wait([
          FirebaseFirestore.instance.collection('panen')
              .where('tanggal', isGreaterThanOrEqualTo: tglHyphen)
              .where('tanggal', isLessThan: '${tglHyphen}z')
              .get(),
          FirebaseFirestore.instance.collection('panen')
              .where('tanggal', isGreaterThanOrEqualTo: tglSlash)
              .where('tanggal', isLessThan: '${tglSlash}z')
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

        onlineData = onlineData.where((d) {
          final status = (d['status'] ?? "").toString().toUpperCase();
          if (status != 'ACC') return false;
          if (afdNormalized == "ALL" || afdNormalized.isEmpty) return true;

          String itemAfd = (d['afdeling'] ?? "").toString().replaceAll(' ', '').toUpperCase();
          if (itemAfd.isEmpty) {
            itemAfd = (d['kcs'] ?? "").toString().replaceAll(' ', '').toUpperCase();
            if (itemAfd.contains("KCS")) itemAfd = itemAfd.replaceAll("KCS", "AFD");
          }
          return itemAfd == afdNormalized;
        }).toList();

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
              final localId = combined[key]!['id'];
              combined[key] = Map<String, dynamic>.from(d);
              combined[key]!['id'] = localId;
            } else {
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
      debugPrint("Error loading panen: $e");
      temp = await _loadLocalPanenForTrip();
    }
    setState(() => panenList = temp);
  }

  Future<List<Map<String, dynamic>>> _loadLocalPanenForTrip() async {
    final db = await DatabaseHelper.instance.database;
    final patterns = AppDateUtils.getDateSearchPatterns(selectedDate);
    final afdNormalized = afdelingUser.replaceAll(' ', '').toUpperCase();

    final allLocal = await db.rawQuery('''
      SELECT * FROM panen 
      WHERE id NOT IN (SELECT panen_id FROM trip_detail)
      AND TRIM(UPPER(status)) = 'ACC'
    ''');

    return allLocal.where((e) {
      String tglRaw = (e['tanggal'] ?? "").toString();
      bool matchDate = patterns.any((p) => tglRaw.startsWith(p));
      if (!matchDate) return false;
      if (afdNormalized == "ALL" || afdNormalized.isEmpty) return true;

      String itemAfd = (e['afdeling'] ?? "").toString().replaceAll(' ', '').toUpperCase();
      if (itemAfd.isEmpty) {
        itemAfd = (e['kcs'] ?? "").toString().replaceAll(' ', '').toUpperCase();
        if (itemAfd.contains("KCS")) itemAfd = itemAfd.replaceAll("KCS", "AFD");
      }
      return itemAfd == afdNormalized;
    }).map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Future<void> simpanTrip() async {
    if (isSaving) return;
    if (noPlatController.text.trim().isEmpty || sopirController.text.trim().isEmpty) {
      _snack("Lengkapi data kendaraan dan sopir", isError: true);
      return;
    }
    if (selectedPanen.isEmpty && widget.data == null) {
      _snack("Pilih minimal satu data panen", isError: true);
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Simpan Trip"),
        content: const Text("Simpan data trip ini?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Batal")),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Simpan")),
        ],
      ),
    );

    if (confirm != true) return;
    setState(() => isSaving = true);

    try {
      final tglTrip = selectedDate.toString().split(" ")[0];
      final fullWaktu = "$tglTrip ${DateTime.now().toString().split(" ")[1]}";
      final tripData = {
        'tanggal': fullWaktu,
        'no_plat': noPlatController.text.trim().toUpperCase(),
        'sopir': sopirController.text.trim(),
        'afdeling': afdelingUser,
        'kcs': kcsLogin,
      };

      if (widget.data != null && widget.data!['id_firebase'] != null) {
        await FirebaseFirestore.instance.collection('trips').doc(widget.data!['id_firebase']).update(tripData);
      } else {
        await DatabaseHelper.instance.insertTrip(tripData, selectedPanen);
      }
      _snack("Trip berhasil disimpan!");
      Navigator.pop(context, true);
    } catch (e) {
      _snack("Gagal: $e", isError: true);
    } finally {
      if (mounted) setState(() => isSaving = false);
    }
  }

  void _snack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? Colors.red : _biru,
      behavior: SnackBarBehavior.floating,
    ));
  }

  Future<void> _pickDate() async {
    DateTime? picked = await showDatePicker(
      context: context,
      initialDate: selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() => selectedDate = picked);
      loadPanen();
    }
  }

  @override
  Widget build(BuildContext context) {
    final tglStr = selectedDate.toString().split(" ")[0];
    final isPilihHariIni = tglStr == DateTime.now().toString().split(" ")[0];

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        title: const Text("Trip Mobil", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: _biru,
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: Container(
          constraints: BoxConstraints(maxWidth: kIsWeb ? 800 : double.infinity),
          child: SingleChildScrollView(
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: const BoxDecoration(
                    color: _biru,
                    borderRadius: BorderRadius.only(bottomLeft: Radius.circular(24), bottomRight: Radius.circular(24)),
                  ),
                  child: Column(
                    children: [
                      _inputField(controller: noPlatController, hint: "No. Plat", icon: Icons.directions_car),
                      const SizedBox(height: 10),
                      _inputField(controller: sopirController, hint: "Sopir", icon: Icons.person),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: InkWell(
                              onTap: _pickDate,
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(12)),
                                child: Text(tglStr, style: const TextStyle(color: Colors.white)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          ElevatedButton(
                            onPressed: () {
                              setState(() => selectedDate = DateTime.now());
                              loadPanen();
                            },
                            child: const Text("Hari Ini"),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: panenList.isEmpty 
                    ? const Text("Tidak ada data panen (ACC)")
                    : ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: panenList.length,
                        itemBuilder: (context, index) {
                          final item = panenList[index];
                          final id = int.tryParse(item['id'].toString()) ?? 0;
                          final isChecked = selectedPanen.contains(id);
                          return CheckboxListTile(
                            title: Text("Blok ${item['blok']} - ${item['pemanen']}"),
                            subtitle: Text("${item['matang']} Janjang"),
                            value: isChecked,
                            onChanged: (val) {
                              setState(() {
                                if (val == true) selectedPanen.add(id);
                                else selectedPanen.remove(id);
                              });
                            },
                          );
                        },
                      ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: simpanTrip,
                      style: ElevatedButton.styleFrom(backgroundColor: _biru, foregroundColor: Colors.white),
                      child: isSaving ? const CircularProgressIndicator(color: Colors.white) : const Text("SIMPAN TRIP"),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _inputField({required TextEditingController controller, required String hint, required IconData icon}) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: Icon(icon),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}
