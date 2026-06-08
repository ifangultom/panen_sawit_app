import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'database_helper.dart';
import 'map_geo_tagging.dart';
import 'package:image/image.dart' as img;
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'api_service.dart';
import 'utils/date_utils.dart';

// ─── WARNA TEMA ───────────────────────────────────────────────────────────────
const _primaryBlue = Color(0xFF0D47A1);
const _accentBlue  = Color(0xFF1565C0);
const _lightBlue   = Color(0xFFE3F2FD);
const _kuning      = Color(0xFFFFC107);
const _bg          = Color(0xFFF0F4FF);
const _cardBg      = Colors.white;
const _textGelap   = Color(0xFF0D1B4B);
const _textAbu     = Color(0xFF5C6E8C);

class InputPanenPage extends StatefulWidget {
  final Map<String, dynamic>? data;
  const InputPanenPage({super.key, this.data});

  @override
  State<InputPanenPage> createState() => _InputPanenPageState();
}

class _InputPanenPageState extends State<InputPanenPage>
    with SingleTickerProviderStateMixin {

  // ─── STATE ─────────────────────────────────────────────────────────────────
  String trackingData = "";
  String selectedKCS  = "KCS1";
  String? selectedBlok;

  Map<String, List<String>> blokKCS = {};
  bool _isLoadingBlocks = true;

  final tanggal    = TextEditingController();
  final pemanen    = TextEditingController();
  final tph        = TextEditingController();
  final tahunTanam = TextEditingController();
  final brondolan  = TextEditingController();
  final mentah     = TextEditingController();
  final matang     = TextEditingController();
  final brondKetek = TextEditingController();
  final tbsKetek   = TextEditingController();
  final tangkai    = TextEditingController();
  final buahCacah  = TextEditingController();
  final tangkos    = TextEditingController();
  final buahSakit  = TextEditingController();
  final catatan    = TextEditingController();
  final latitude   = TextEditingController();
  final longitude  = TextEditingController();

  File? imageFile;
  late AnimationController _animC;
  late Animation<double> _fadeIn;

  // ─── INIT ──────────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _animC = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _fadeIn = CurvedAnimation(parent: _animC, curve: Curves.easeOut);
    _animC.forward();

    _loadBlocks();
  }

  Future<void> _loadBlocks() async {
    final blocks = await DatabaseHelper.instance.getAllBlocksGroupedByKCS();
    
    if (!mounted) return;
    
    setState(() {
      blokKCS = blocks;
      _isLoadingBlocks = false;

      // Inisialisasi default jika blokKCS tidak kosong
      if (blokKCS.isNotEmpty) {
        if (!blokKCS.containsKey(selectedKCS)) {
          selectedKCS = blokKCS.keys.first;
        }
        selectedBlok = blokKCS[selectedKCS]!.isNotEmpty ? blokKCS[selectedKCS]!.first : null;
      }

      // Overwrite dengan data jika mode edit
      if (widget.data != null) {
        final d = widget.data!;
        tanggal.text    = d['tanggal']         ?? "";
        pemanen.text    = d['pemanen']         ?? "";
        tph.text        = d['tph']             ?? "";
        tahunTanam.text = (d['thn_tanam'] ?? d['tahun_tanam']) ?? "";
        brondolan.text  = d['brondolan']       ?? "";
        mentah.text     = d['mentah']          ?? "";
        matang.text     = d['matang']          ?? "";
        brondKetek.text = d['brond_ketek']     ?? "";
        tbsKetek.text   = d['tbs_ketek']       ?? "";
        tangkai.text    = d['tangkai_panjang'] ?? "";
        buahCacah.text  = d['buah_cacah']      ?? "";
        tangkos.text    = d['tangkos']         ?? "";
        buahSakit.text  = d['buah_sakit']      ?? "";
        catatan.text    = d['catatan']         ?? "";
        latitude.text   = d['latitude']        ?? "";
        longitude.text  = d['longitude']       ?? "";
        trackingData    = d['tracking']        ?? "";

        String? blokData = d['blok'];
        if (blokData != null) {
          blokKCS.forEach((kcs, list) {
            if (list.contains(blokData)) selectedKCS = kcs;
          });
          selectedBlok = blokData;
        }
        if (blokKCS.containsKey(selectedKCS) && !blokKCS[selectedKCS]!.contains(selectedBlok)) {
          selectedBlok = blokKCS[selectedKCS]!.isNotEmpty ? blokKCS[selectedKCS]!.first : null;
        }
        if (d['foto'] != "") imageFile = File(d['foto']);
      }
    });
  }

  @override
  void dispose() {
    _animC.dispose();
    super.dispose();
  }

  // ─── FUNGSI ────────────────────────────────────────────────────────────────
  Future ambilGambar() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.camera, imageQuality: 80);
    if (picked == null) return;

    final bytes = await File(picked.path).readAsBytes();
    img.Image? original = img.decodeImage(bytes);
    if (original == null) return;

    DateTime now = DateTime.now();
    String waktu = "${now.day}-${now.month}-${now.year} ${now.hour}:${now.minute}";
    String lat = latitude.text.isEmpty ? "-" : latitude.text;
    String lng = longitude.text.isEmpty ? "-" : longitude.text;

    String text = """
$waktu
Blok ${selectedBlok ?? '-'}
Lat: $lat
Lng: $lng
Kec: Medan Tembung
Kota: Kota Medan
""";

    img.fillRect(original,
        x1: 0, y1: original.height - 260,
        x2: original.width, y2: original.height,
        color: img.ColorRgba8(0, 0, 0, 180));

    img.Image textImage = img.Image(width: original.width, height: 300);
    img.fill(textImage, color: img.ColorRgba8(0, 0, 0, 0));
    img.drawString(textImage, text, font: img.arial48, x: 10, y: 10,
        color: img.ColorRgb8(255, 255, 255));
    img.Image bigText = img.copyResize(textImage, width: original.width, height: 400);
    img.compositeImage(original, bigText, dstX: 0, dstY: original.height - 400);

    final dir  = await getApplicationDocumentsDirectory();
    final path = '${dir.path}/panen_${DateTime.now().millisecondsSinceEpoch}.jpg';
    File newFile = File(path);
    // Simpan dengan kualitas 30 agar ukuran Base64 tidak terlalu besar untuk Firestore
    await newFile.writeAsBytes(img.encodeJpg(original, quality: 30));
    setState(() => imageFile = newFile);
  }

  Future ambilLokasi() async {
    final result = await Navigator.push(
        context, MaterialPageRoute(builder: (_) => const MapGeoTaggingPage()));
    if (result != null) {
      setState(() {
        latitude.text  = result['lat'];
        longitude.text = result['lng'];
        trackingData   = result['tracking'] ?? "";
      });
    }
  }

  Future<void> simpan() async {
    if (selectedBlok == null || selectedBlok!.isEmpty) {
      _snack("Blok belum dipilih", isError: true);
      return;
    }

    SharedPreferences prefs = await SharedPreferences.getInstance();
    
    // 1. Siapkan String Base64 untuk Firestore (Web Admin)
    String base64Foto = "";
    if (imageFile != null) {
      final bytes = await imageFile!.readAsBytes();
      final base64String = base64Encode(bytes);
      base64Foto = "data:image/jpeg;base64,$base64String"; 
    }

    final kcsToMandor = {"KCS1": "mandor_afd1", "KCS2": "mandor_afd2", "KCS3": "mandor_afd3"};
    
    // Ambil waktu sekarang untuk jam yang presisi
    DateTime now = DateTime.now();
    String waktuLengkap = now.toIso8601String(); 

    // Jika user pilih tanggal, kita ambil YYYY-MM-DD-nya saja lalu gabung dengan jam sekarang
    String tglInput = tanggal.text.isNotEmpty ? tanggal.text.replaceAll('/', '-') : waktuLengkap.split('T')[0];
    if (tglInput.contains(' ')) tglInput = tglInput.split(' ')[0];
    
    // Standarisasi format tanggal untuk Firestore (YYYY-MM-DD)
    // tglInput bisa 2024-05-01
    List<String> parts = tglInput.split('-');
    if (parts.length == 3) {
      // Pastikan urutan YYYY-MM-DD
      if (parts[0].length < 4) { // Berarti DD-MM-YYYY
        tglInput = "${parts[2]}-${parts[1].padLeft(2,'0')}-${parts[0].padLeft(2,'0')}";
      } else {
        tglInput = "${parts[0]}-${parts[1].padLeft(2,'0')}-${parts[2].padLeft(2,'0')}";
      }
    }

    // Format: YYYY-MM-DDTHH:mm:ss...
    String tanggalFinal = "${tglInput}T${now.hour.toString().padLeft(2,'0')}:${now.minute.toString().padLeft(2,'0')}:${now.second.toString().padLeft(2,'0')}";

    // 2. Data untuk Firestore
    final dataFirestore = {
      'tanggal': tanggalFinal,
      'waktu': waktuLengkap,
      'pemanen': pemanen.text,
      'blok': selectedBlok ?? "",
      'tph': tph.text,
      'thn_tanam': tahunTanam.text,
      'kcs': selectedKCS,
      'afdeling': AppDateUtils.mapKcsToAfd(selectedKCS),
      'brondolan': brondolan.text,
      'mentah': mentah.text,
      'matang': matang.text,
      'catatan': catatan.text,
      'foto': base64Foto,
      'latitude': latitude.text,
      'longitude': longitude.text,
      'tracking': trackingData,
      'status': 'pending',
      'user': prefs.getString('current_user') ?? "",
    };

    // 3. Data untuk SQLite & Laravel (Foto = Path lokal agar upload file tidak rusak)
    final dataLokal = Map<String, dynamic>.from(dataFirestore);
    dataLokal['foto'] = imageFile?.path ?? "";
    dataLokal['sync_status'] = 'offline';
    dataLokal['afdeling'] = AppDateUtils.mapKcsToAfd(selectedKCS);
    dataLokal['mandor'] = kcsToMandor[selectedKCS] ?? "mandor_afd1";

    if (!mounted) return;

    Navigator.pop(context, true);
    _snack("Data berhasil disimpan");

    // Simpan lokal & Sinkronisasi ditangani oleh DatabaseHelper
    // Kirimkan juga base64Foto khusus untuk kebutuhan Firestore (Web Admin)
    await DatabaseHelper.instance.insertPanen(dataLokal, base64Foto: base64Foto);
    await ApiService.kirimPanen(dataLokal);
  }

  void _snack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, softWrap: true),
      backgroundColor: isError ? Colors.red[700] : _primaryBlue,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  // ─── UI HELPERS ────────────────────────────────────────────────────────────
  Widget _sectionLabel(String label, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, top: 4),
      child: Row(children: [
        Icon(icon, size: 16, color: _primaryBlue),
        const SizedBox(width: 6),
        Text(label,
            style: const TextStyle(
                fontSize: 12, fontWeight: FontWeight.w700,
                color: _primaryBlue, letterSpacing: 1.2)),
      ]),
    );
  }

  Widget _card(Widget child) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: _cardBg,
      borderRadius: BorderRadius.circular(16),
      boxShadow: [
        BoxShadow(color: Colors.black.withOpacity(0.05),
            blurRadius: 8, offset: const Offset(0, 2)),
      ],
    ),
    child: child,
  );

  InputDecoration _dec(String hint, {IconData? icon}) => InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(color: _textAbu, fontSize: 13),
    filled: true,
    fillColor: _lightBlue,
    prefixIcon: icon != null ? Icon(icon, size: 18, color: _accentBlue) : null,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none),
    focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _primaryBlue, width: 1.5)),
  );

  Widget _numBox(String hint, TextEditingController c) => Expanded(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: TextField(
        controller: c,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        style: const TextStyle(fontSize: 14, color: _textGelap, fontWeight: FontWeight.w500),
        decoration: _dec(hint),
      ),
    ),
  );

  // ─── BUILD ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _primaryBlue,
        elevation: 0,
        title: const Text("INPUT PANEN",
            style: TextStyle(
                fontWeight: FontWeight.w800, fontSize: 16,
                color: Colors.white, letterSpacing: 1.5)),
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(bottom: Radius.circular(20))),
      ),

      body: FadeTransition(
        opacity: _fadeIn,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(14, 16, 14, 30),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

            // ── FOTO ──────────────────────────────────────────────────────
            _card(Column(children: [
              _sectionLabel("DOKUMENTASI", Icons.camera_alt_rounded),
              GestureDetector(
                onTap: ambilGambar,
                child: Container(
                  height: imageFile != null ? null : 110,
                  decoration: BoxDecoration(
                    color: _lightBlue,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _primaryBlue.withOpacity(0.3)),
                  ),
                  child: imageFile != null
                      ? ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.file(imageFile!, fit: BoxFit.cover))
                      : Center(child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Icon(Icons.add_a_photo_rounded, size: 36, color: _primaryBlue),
                        SizedBox(height: 6),
                        Text("Ketuk untuk ambil foto",
                            style: TextStyle(color: _primaryBlue, fontSize: 12,
                                fontWeight: FontWeight.w600)),
                      ])),
                ),
              ),
            ])),

            // ── LOKASI ────────────────────────────────────────────────────
            _card(Column(children: [
              _sectionLabel("LOKASI & TRACKING", Icons.location_on_rounded),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: ambilLokasi,
                  icon: const Icon(Icons.my_location_rounded, size: 18),
                  label: const Text("Ambil Lokasi + Tracking",
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: _primaryBlue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12))),
                ),
              ),
              if (latitude.text.isNotEmpty) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                      color: _lightBlue,
                      borderRadius: BorderRadius.circular(10)),
                  child: Row(children: [
                    const Icon(Icons.gps_fixed, size: 14, color: _primaryBlue),
                    const SizedBox(width: 6),
                    Expanded(child: Text(
                        "Lat: ${latitude.text}  |  Lng: ${longitude.text}",
                        style: const TextStyle(fontSize: 11, color: _textGelap))),
                    if (trackingData.isNotEmpty)
                      const Icon(Icons.check_circle, size: 16, color: _accentBlue),
                  ]),
                ),
              ] else ...[
                const SizedBox(height: 6),
                Row(children: const [
                  SizedBox(width: 2),
                  Text("Lat: —  |  Lng: —",
                      style: TextStyle(fontSize: 12, color: _textAbu)),
                ]),
              ],
            ])),

            // ── TANGGAL ───────────────────────────────────────────────────
            _card(Column(children: [
              _sectionLabel("TANGGAL PANEN", Icons.event_rounded),
              TextField(
                controller: tanggal,
                readOnly: true,
                onTap: () async {
                  DateTime? pick = await showDatePicker(
                    context: context,
                    initialDate: DateTime.now(),
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2100),
                    builder: (ctx, child) => Theme(
                        data: Theme.of(ctx).copyWith(
                            colorScheme: const ColorScheme.light(primary: _primaryBlue)),
                        child: child!),
                  );
                  if (pick != null) {
                    tanggal.text = "${pick.year}/${pick.month.toString().padLeft(2,'0')}/${pick.day.toString().padLeft(2,'0')}";
                  }
                },
                style: const TextStyle(fontSize: 14, color: _textGelap, fontWeight: FontWeight.w600),
                decoration: _dec("Pilih tanggal panen", icon: Icons.calendar_today_rounded),
              ),
            ])),

            // ── AFD + PEMANEN ─────────────────────────────────────────────
            _card(Column(children: [
              _sectionLabel("AFD & PEMANEN", Icons.group_rounded),
              if (!_isLoadingBlocks && blokKCS.isEmpty)
                Container(
                  padding: const EdgeInsets.all(10),
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(color: Colors.red[50], borderRadius: BorderRadius.circular(10)),
                  child: Row(children: [
                    const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 18),
                    const SizedBox(width: 8),
                    Expanded(child: Text("Data Blok Kosong. Silakan sinkron master data di menu Sinkronisasi.", 
                      style: TextStyle(color: Colors.red[900], fontSize: 11, fontWeight: FontWeight.normal))),
                  ]),
                ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                    color: _lightBlue,
                    borderRadius: BorderRadius.circular(12)),
                child: DropdownButtonHideUnderline(
                  child: DropdownButtonFormField<String>(
                    value: blokKCS.containsKey(selectedKCS) ? selectedKCS : (blokKCS.isNotEmpty ? blokKCS.keys.first : null),
                    decoration: const InputDecoration(border: InputBorder.none),
                    icon: const Icon(Icons.keyboard_arrow_down_rounded, color: _primaryBlue),
                    style: const TextStyle(color: _textGelap, fontWeight: FontWeight.w600, fontSize: 14),
                    dropdownColor: Colors.white,
                    hint: const Text("Pilih AFD", style: TextStyle(color: _textAbu, fontSize: 13, fontWeight: FontWeight.normal)),
                    items: blokKCS.keys.map((kcs) {
                      return DropdownMenuItem(value: kcs, child: Text(kcs.replaceAll('KCS', 'AFD ')));
                    }).toList(),
                    onChanged: (v) => setState(() {
                      selectedKCS  = v!;
                      selectedBlok = blokKCS[selectedKCS]!.isNotEmpty ? blokKCS[selectedKCS]!.first : null;
                      pemanen.text = ""; // Reset nama pemanen saat pindah KCS
                    }),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              FutureBuilder<List<String>>(
                future: DatabaseHelper.instance.getHarvestersByAfdeling(selectedKCS.replaceAll('KCS', 'AFD')),
                builder: (context, localSnapshot) {
                  return StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('harvesters')
                        .where('afdeling', isEqualTo: selectedKCS.replaceAll('KCS', 'AFD'))
                        .snapshots(),
                    builder: (context, snapshot) {
                      List<String> listPemanen = localSnapshot.data ?? [];
                      
                      if (snapshot.hasData) {
                        listPemanen = snapshot.data!.docs
                            .map((doc) => (doc.data() as Map<String, dynamic>)['nama'] as String)
                            .toList();
                        // Sort alphabetical
                        listPemanen.sort();
                      }

                      return Container(
                        padding: const EdgeInsets.only(right: 14),
                        decoration: BoxDecoration(
                            color: _lightBlue,
                            borderRadius: BorderRadius.circular(12)),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButtonFormField<String>(
                            value: listPemanen.contains(pemanen.text) ? pemanen.text : null,
                            decoration: const InputDecoration(
                              border: InputBorder.none,
                              prefixIcon: Icon(Icons.person_rounded, size: 18, color: _accentBlue),
                            ),
                            icon: const Icon(Icons.keyboard_arrow_down_rounded, color: _primaryBlue),
                            style: const TextStyle(color: _textGelap, fontWeight: FontWeight.w600, fontSize: 14),
                            dropdownColor: Colors.white,
                            hint: Text(
                              snapshot.connectionState == ConnectionState.waiting && listPemanen.isEmpty
                                ? "Memuat data..." 
                                : "Pilih Nama Pemanen", 
                              style: const TextStyle(color: _textAbu, fontSize: 13, fontWeight: FontWeight.normal)
                            ),
                            items: listPemanen.map((p) =>
                                DropdownMenuItem<String>(value: p, child: Text(p))).toList(),
                            onChanged: (v) => setState(() => pemanen.text = v!),
                          ),
                        ),
                      );
                    }
                  );
                }
              ),
            ])),

            // ── BLOK + TPH ────────────────────────────────────────────────
            _card(Column(children: [
              _sectionLabel("BLOK & TPH", Icons.grid_view_rounded),
              Row(children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                        color: _lightBlue, borderRadius: BorderRadius.circular(12)),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButtonFormField<String>(
                        value: (blokKCS.containsKey(selectedKCS) && blokKCS[selectedKCS]!.contains(selectedBlok)) ? selectedBlok : null,
                        decoration: const InputDecoration(border: InputBorder.none),
                        icon: const Icon(Icons.keyboard_arrow_down_rounded, color: _primaryBlue),
                        style: const TextStyle(color: _textGelap, fontWeight: FontWeight.w600, fontSize: 14),
                        dropdownColor: Colors.white,
                        hint: Text(_isLoadingBlocks ? "Memuat..." : "Blok"),
                        items: (blokKCS[selectedKCS] ?? []).map((b) =>
                            DropdownMenuItem<String>(value: b, child: Text("Blok $b"))).toList(),
                        onChanged: (v) => setState(() => selectedBlok = v!),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: tph,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    style: const TextStyle(fontSize: 14, color: _textGelap, fontWeight: FontWeight.w500),
                    decoration: _dec("TPH", icon: Icons.numbers_rounded),
                  ),
                ),
              ]),
            ])),

            // ── DATA PRODUKSI ─────────────────────────────────────────────
            _card(Column(children: [
              _sectionLabel("DATA PRODUKSI", Icons.bar_chart_rounded),
              Row(children: [_numBox("Tahun Tanam", tahunTanam), _numBox("Brondolan", brondolan)]),
              const SizedBox(height: 8),
              Row(children: [_numBox("Mentah", mentah), _numBox("Matang", matang)]),
              const SizedBox(height: 8),
              Row(children: [_numBox("Brond Ketek", brondKetek), _numBox("TBS Ketek", tbsKetek)]),
              const SizedBox(height: 8),
              Row(children: [_numBox("Tangkai Panjang", tangkai), _numBox("Buah Cacah", buahCacah)]),
              const SizedBox(height: 8),
              Row(children: [_numBox("Tangkos", tangkos), _numBox("Buah Sakit", buahSakit)]),
            ])),

            // ── CATATAN ───────────────────────────────────────────────────
            _card(Column(children: [
              _sectionLabel("CATATAN", Icons.notes_rounded),
              TextField(
                controller: catatan,
                maxLines: 3,
                style: const TextStyle(fontSize: 14, color: _textGelap),
                decoration: _dec("Tambahkan catatan..."),
              ),
            ])),

            const SizedBox(height: 8),

            // ── TOMBOL SIMPAN ─────────────────────────────────────────────
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: simpan,
                style: ElevatedButton.styleFrom(
                    backgroundColor: _primaryBlue,
                    foregroundColor: Colors.white,
                    elevation: 4,
                    shadowColor: _primaryBlue.withOpacity(0.4),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16))),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.save_rounded, size: 20),
                    SizedBox(width: 8),
                    Text("SIMPAN DATA PANEN",
                        style: TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 14,
                            letterSpacing: 1.2)),
                  ],
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}