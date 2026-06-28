import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'database_helper.dart';

class InputPksPage extends StatefulWidget {
  final dynamic tripId;
  final Map<String, dynamic>? data;

  const InputPksPage({
    super.key,
    required this.tripId,
    this.data,
  });

  @override
  State<InputPksPage> createState() => _InputPksPageState();
}

class _InputPksPageState extends State<InputPksPage> {
  final beratController = TextEditingController();
  int totalJanjang = 0;
  DateTime selectedDate = DateTime.now();
  final _biru = const Color(0xFF0D47A1);

  final List<String> months = [
    "Januari", "Februari", "Maret", "April", "Mei", "Juni",
    "Juli", "Agustus", "September", "Oktober", "November", "Desember"
  ];

  @override
  void initState() {
    super.initState();
    loadJanjang();

    if (widget.data != null) {
      beratController.text = widget.data!['berat_netto']?.toString() ?? "";
      if (widget.data!['waktu_timbang'] != null) {
        selectedDate = DateTime.tryParse(widget.data!['waktu_timbang'].toString()) ?? DateTime.now();
      }
    }
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: _biru,
              onPrimary: Colors.white,
              onSurface: _biru,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && picked != selectedDate) {
      setState(() {
        selectedDate = picked;
      });
    }
  }

  void loadJanjang() async {
    if (kIsWeb) {
      // Logic for web if needed
      return;
    }
    final total = await DatabaseHelper.instance.getTotalJanjangByTrip(widget.tripId);
    if (!mounted) return;
    setState(() {
      totalJanjang = int.tryParse(total.toString()) ?? 0;
    });
  }

  Future<void> simpan() async {
    if (beratController.text.isEmpty) {
      _snack("Isi berat PKS dulu", isError: true);
      return;
    }

    double berat = double.tryParse(beratController.text) ?? 0;

    // Gabungkan tanggal terpilih dengan jam sekarang agar record tetap presisi
    final now = DateTime.now();
    final finalDate = DateTime(
      selectedDate.year,
      selectedDate.month,
      selectedDate.day,
      now.hour,
      now.minute,
      now.second,
    );

    final pksData = {
      'trip_id': widget.tripId,
      'berat_netto': berat,
      'waktu_timbang': finalDate.toIso8601String(),
    };

    if (widget.data != null && widget.data!['id_firebase'] != null) {
      // Mode Update (Web Admin)
      await FirebaseFirestore.instance.collection('pks').doc(widget.data!['id_firebase']).update(pksData);
    } else {
      // Mode Baru / Upsert (Mobile)
      await DatabaseHelper.instance.upsertPks(pksData);
    }

    if (!mounted) return;
    _snack("Data timbang PKS berhasil disimpan");
    Navigator.pop(context, true);
  }

  void _snack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? Colors.red : _biru,
      behavior: SnackBarBehavior.floating,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F6),
      appBar: AppBar(
        title: const Text("Input Timbang PKS"),
        backgroundColor: _biru,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Center(
        child: Container(
          constraints: BoxConstraints(maxWidth: kIsWeb ? 600 : double.infinity),
          child: SingleChildScrollView(
            child: Column(
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: _biru,
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(32),
                      bottomRight: Radius.circular(32),
                    ),
                  ),
                  child: Column(
                    children: [
                      const Icon(Icons.scale_rounded, color: Colors.white, size: 48),
                      const SizedBox(height: 16),
                      const Text(
                        "Total Muatan Trip",
                        style: TextStyle(color: Colors.white70, fontSize: 14),
                      ),
                      Text(
                        "$totalJanjang Janjang",
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Card(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    elevation: 4,
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "Informasi Timbangan",
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                          const SizedBox(height: 20),
                          const Text(
                            "Tanggal Timbang",
                            style: TextStyle(fontSize: 14, color: Colors.grey, fontWeight: FontWeight.w500),
                          ),
                          const SizedBox(height: 8),
                          InkWell(
                            onTap: () => _selectDate(context),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 15),
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.grey.shade300),
                                borderRadius: BorderRadius.circular(12),
                                color: Colors.grey[50],
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.calendar_today_rounded, color: _biru, size: 20),
                                  const SizedBox(width: 12),
                                  Text(
                                    "${selectedDate.day} ${months[selectedDate.month - 1]} ${selectedDate.year}",
                                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                                  ),
                                  const Spacer(),
                                  Icon(Icons.arrow_drop_down, color: Colors.grey[600]),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                          TextField(
                            controller: beratController,
                            keyboardType: TextInputType.number,
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                            decoration: InputDecoration(
                              labelText: "Berat Netto PKS",
                              hintText: "Masukkan berat (Kg)",
                              prefixIcon: const Icon(Icons.monitor_weight_rounded),
                              suffixText: "Kg",
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              filled: true,
                              fillColor: Colors.grey[50],
                            ),
                          ),
                          const SizedBox(height: 24),
                          SizedBox(
                            width: double.infinity,
                            height: 54,
                            child: ElevatedButton(
                              onPressed: simpan,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _biru,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                elevation: 2,
                              ),
                              child: const Text(
                                "SIMPAN DATA PKS",
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                            ),
                          ),
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
    );
  }
}
