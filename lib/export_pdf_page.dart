import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'database_helper.dart';
import 'utils/date_utils.dart';

class ExportPdfPage extends StatelessWidget {
  const ExportPdfPage({super.key});

  Future<void> generatePDF() async {
    final pdf = pw.Document();

    final data = await DatabaseHelper.instance.getAllPanen();

    int totalMatang = 0;
    int totalMentah = 0;
    int totalBrondolan = 0;

    for (var item in data) {
      totalMatang += int.tryParse(item['matang']?.toString() ?? "0") ?? 0;
      totalMentah += int.tryParse(item['mentah']?.toString() ?? "0") ?? 0;
      totalBrondolan += int.tryParse(item['brondolan']?.toString() ?? "0") ?? 0;
    }

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4.landscape,
        build: (context) {
          return pw.Padding(
            padding: const pw.EdgeInsets.all(16),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [

                // ===== JUDUL =====
                pw.Center(
                  child: pw.Text(
                    "LAPORAN REKAPITULASI PANEN SAWIT",
                    style: pw.TextStyle(
                      fontSize: 18,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ),

                pw.SizedBox(height: 10),

                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text("Tanggal Cetak: ${DateTime.now().toString().split('.')[0]}"),
                    pw.Text("Sistem: HarvestTrack Admin"),
                  ],
                ),

                pw.Divider(),
                pw.SizedBox(height: 10),

                // ===== RINGKASAN =====
                pw.Row(
                  children: [
                    pw.Expanded(child: pw.Text("Total Matang: $totalMatang Janjang")),
                    pw.Expanded(child: pw.Text("Total Mentah: $totalMentah Janjang")),
                    pw.Expanded(child: pw.Text("Total Brondolan: $totalBrondolan Kg")),
                  ],
                ),

                pw.SizedBox(height: 15),

                // ===== TABEL =====
                pw.Table.fromTextArray(
                  headers: ["Tanggal", "Pemanen", "Blok", "Afdeling", "Matang", "Mentah", "Brondolan (Kg)", "Catatan"],
                  headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10, color: PdfColors.white),
                  cellStyle: const pw.TextStyle(fontSize: 9),
                  headerDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFF0D47A1)),
                  data: data.map((e) {
                    String afdeling = e['afdeling']?.toString() ?? "";
                    if (afdeling.isEmpty) {
                      afdeling = AppDateUtils.mapKcsToAfd(e['kcs']?.toString());
                    }
                    if (afdeling.isEmpty) afdeling = "-";

                    return [
                      e['tanggal']?.toString().split(" ")[0] ?? "-",
                      e['pemanen'] ?? "-",
                      e['blok'] ?? "-",
                      afdeling,
                      e['matang'] ?? "0",
                      e['mentah'] ?? "0",
                      e['brondolan'] ?? "0",
                      e['catatan'] ?? "-",
                    ];
                  }).toList(),
                ),

                pw.Spacer(),

                // ===== TANDA TANGAN =====
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Column(
                      children: [
                        pw.Text("Mengetahui,", style: const pw.TextStyle(fontSize: 10)),
                        pw.SizedBox(height: 50),
                        pw.Container(
                          width: 100,
                          decoration: const pw.BoxDecoration(
                            border: pw.Border(bottom: pw.BorderSide(width: 0.5)),
                          ),
                        ),
                        pw.Text("Estate Manager", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                      ],
                    ),
                    pw.Column(
                      children: [
                        pw.Text("Dibuat Oleh,", style: const pw.TextStyle(fontSize: 10)),
                        pw.SizedBox(height: 50),
                        pw.Container(
                          width: 100,
                          decoration: const pw.BoxDecoration(
                            border: pw.Border(bottom: pw.BorderSide(width: 0.5)),
                          ),
                        ),
                        pw.Text("Admin Perkebunan", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );

    await Printing.sharePdf(
      bytes: await pdf.save(),
      filename: "Laporan_Rekap_Panen.pdf",
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Export PDF", style: TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF0D47A1),
      ),

      body: Center(
        child: ElevatedButton.icon(
          onPressed: generatePDF,
          icon: const Icon(Icons.picture_as_pdf),
          label: const Text("Export Laporan PDF"),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF0D47A1),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          ),
        ),
      ),
    );
  }
}
