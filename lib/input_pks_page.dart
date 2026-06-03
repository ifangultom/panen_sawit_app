import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  final _biru = const Color(0xFF0D47A1);

  @override
  void initState() {
    super.initState();
    loadJanjang();

    if (widget.data != null) {
      beratController.text = widget.data!['berat_netto']?.toString() ?? "";
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

    await DatabaseHelper.instance.upsertPks({
      'trip_id': widget.tripId,
      'berat_netto': berat,
      'waktu_timbang': DateTime.now().toIso8601String(),
    });

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
      body: SingleChildScrollView(
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
    );
  }
}
