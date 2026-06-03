import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'database_helper.dart';
import 'input_panen.dart';
import 'detail_panen_page.dart';

// ─── TEMA BIRU ─────────────────────────────────────────────────────────────
const _biru       = Color(0xFF0D47A1);
const _biruMuda   = Color(0xFF1565C0);
const _biruPudar  = Color(0xFFE3F2FD);
const _bg         = Color(0xFFF0F4FF);
const _textGelap  = Color(0xFF0D1B3E);
const _textAbu    = Color(0xFF5C6E8C);

class DataPanenPage extends StatefulWidget {
  final String initialFilter;
  const DataPanenPage({super.key, this.initialFilter = "Semua"});

  @override
  State<DataPanenPage> createState() => _DataPanenPageState();
}

class _DataPanenPageState extends State<DataPanenPage> {
  List<Map<String, dynamic>> data = [];

  late String filter;

  @override
  void initState() {
    super.initState();
    filter = widget.initialFilter;
    loadUser();
  }
  String filterKCS = "Semua";
  DateTime filterTanggal = DateTime.now();
  
  // Tambahan Filter Bulan & Tahun
  int? selectedMonth;
  int? selectedYear;
  final List<String> months = [
    "Januari", "Februari", "Maret", "April", "Mei", "Juni",
    "Juli", "Agustus", "September", "Oktober", "November", "Desember"
  ];
  final List<int> years = List.generate(5, (index) => DateTime.now().year - index);

  String afdelingUser = "";
  String roleUser     = "";

  // ─── SELEKSI ───────────────────────────────────────────────────────────────
  bool seleksiMode = false;
  Set<int> selectedIds = {};


  // ─── LOAD USER ─────────────────────────────────────────────────────────────
  Future<void> loadUser() async {
    final prefs = await SharedPreferences.getInstance();
    String user  = prefs.getString('current_user') ?? "";
    afdelingUser = prefs.getString('afd_login')    ?? "";
    roleUser     = prefs.getString('role_$user')   ?? "";

    // 🔥 FIX: jika afd_login kosong, mapping dari kcs_login
    // INI PENTING: mandor KCS1 = AFD1, KCS2 = AFD2, KCS3 = AFD3
    if (afdelingUser.isEmpty) {
      final kcsLogin = prefs.getString('kcs_login') ?? "";
      const kcsToAfd = {"KCS1": "AFD1", "KCS2": "AFD2", "KCS3": "AFD3"};
      afdelingUser = kcsToAfd[kcsLogin] ?? "";
      // Simpan juga supaya konsisten di session ini
      if (afdelingUser.isNotEmpty) {
        await prefs.setString('afd_login', afdelingUser);
      }
    }

    await loadData();
  }

  // ─── LOAD DATA (Firebase + SQLite fallback) ────────────────────────────────
  Future<void> loadData() async {
    List<Map<String, dynamic>> temp = [];

    try {
      final connectivity = await Connectivity().checkConnectivity();

      if (connectivity != ConnectivityResult.none) {
        // 🔥 Online: baca dari Firebase
        Query query = FirebaseFirestore.instance.collection('panen');

        // Filter afdeling
        if (roleUser != "ADMIN" && afdelingUser.isNotEmpty) {
          query = query.where('afdeling', isEqualTo: afdelingUser);
        }

        // Jika filter bulan/tahun dipilih (Filter Tambahan)
        if (selectedYear != null) {
          DateTime firstDay = DateTime(selectedYear!, selectedMonth ?? 1, 1);
          DateTime lastDay = selectedMonth != null 
              ? DateTime(selectedYear!, selectedMonth! + 1, 0, 23, 59, 59)
              : DateTime(selectedYear!, 12, 31, 23, 59, 59);

          query = query.where('tanggal', isGreaterThanOrEqualTo: firstDay.toIso8601String().split('T')[0])
                       .where('tanggal', isLessThanOrEqualTo: lastDay.toIso8601String().split('T')[0]);
        } else {
          // Filter tanggal harian (default jika tahun tidak dipilih)
          final tglFilter = filterTanggal.toString().split(" ")[0];
          query = query.where('tanggal', isGreaterThanOrEqualTo: tglFilter)
              .where('tanggal', isLessThan: '${tglFilter}Z');
        }

        query = query.orderBy('tanggal', descending: true);

        final snapshot = await query.get();
        temp = snapshot.docs.map((doc) {
          final d = Map<String, dynamic>.from(doc.data() as Map);
          d['firebase_id'] = doc.id;
          // Firebase tidak punya int id, pakai hashCode sebagai lokal id
          d['id'] = d['local_id'] ?? doc.id.hashCode.abs();
          return d;
        }).toList();

      } else {
        // 📱 Offline: baca dari SQLite lokal
        final result = await DatabaseHelper.instance.getAllPanen();
        temp = result;

        if (roleUser != "ADMIN" && afdelingUser.isNotEmpty) {
          temp = temp.where((e) => (e['afdeling'] ?? "") == afdelingUser).toList();
        }

        final tglFilter = filterTanggal.toString().split(" ")[0];
        temp = temp.where((e) {
          String tgl = (e['tanggal'] ?? "").toString();
          
          if (selectedYear != null) {
            try {
              DateTime dt = DateTime.parse(tgl);
              bool matchYear = dt.year == selectedYear;
              bool matchMonth = selectedMonth == null || dt.month == selectedMonth;
              return matchYear && matchMonth;
            } catch (_) {
              return false;
            }
          }
          
          return tgl.startsWith(tglFilter);
        }).toList();
      }

    } catch (e) {
      // Error Firebase → fallback SQLite
      print("Firebase error, fallback SQLite: $e");
      final result = await DatabaseHelper.instance.getAllPanen();
      temp = result;
      if (roleUser != "ADMIN" && afdelingUser.isNotEmpty) {
        temp = temp.where((e) => (e['afdeling'] ?? "") == afdelingUser).toList();
      }

      // 🔥 FIX: Tetap filter berdasarkan tanggal jika Firebase error/fallback
      final tglFilter = filterTanggal.toString().split(" ")[0];
      temp = temp.where((e) {
        String tgl = (e['tanggal'] ?? "").toString();
        if (selectedYear != null) {
          try {
            DateTime dt = DateTime.parse(tgl);
            bool matchYear = dt.year == selectedYear;
            bool matchMonth = selectedMonth == null || dt.month == selectedMonth;
            return matchYear && matchMonth;
          } catch (_) {
            return false;
          }
        }
        return tgl.startsWith(tglFilter);
      }).toList();
    }

    // Filter status dan KCS (berlaku di semua mode)
    if (filter != "Semua") {
      temp = temp.where((e) =>
      (e['status'] ?? 'pending').toString().toLowerCase() == filter.toLowerCase()
      ).toList();
    }
    if (filterKCS != "Semua") {
      temp = temp.where((e) => (e['kcs'] ?? "") == filterKCS).toList();
    }

    setState(() => data = temp);
  }

  // ─── ACC / REJECT ──────────────────────────────────────────────────────────
  Future<void> acc(int id) async {
    await DatabaseHelper.instance.accPanen(id);
    // Sync ke Firebase juga
    final item = data.firstWhere((e) => e['id'] == id, orElse: () => {});
    if (item.isNotEmpty && item['firebase_id'] != null) {
      try {
        await FirebaseFirestore.instance.collection('panen').doc(item['firebase_id']).update({'status': 'ACC'});
      } catch (_) {}
    }
    loadData();
  }

  Future<void> reject(int id) async {
    await DatabaseHelper.instance.rejectPanen(id);
    final item = data.firstWhere((e) => e['id'] == id, orElse: () => {});
    if (item.isNotEmpty && item['firebase_id'] != null) {
      try {
        await FirebaseFirestore.instance.collection('panen').doc(item['firebase_id']).update({'status': 'REJECT'});
      } catch (_) {}
    }
    loadData();
  }

  // ─── HAPUS SELECTED ────────────────────────────────────────────────────────
  Future<void> hapusSelected() async {
    if (selectedIds.isEmpty) return;
    final konfirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text("Hapus Data"),
        content: Text("Hapus ${selectedIds.length} data yang dipilih?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Batal", style: TextStyle(color: _textAbu)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red[600]),
            child: const Text("Hapus", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (konfirm == true) {
      for (final id in selectedIds) {
        await DatabaseHelper.instance.deletePanen(id);
      }
      setState(() {
        selectedIds.clear();
        seleksiMode = false;
      });
      loadData();
    }
  }

  void toggleSeleksiMode() {
    setState(() {
      seleksiMode = !seleksiMode;
      selectedIds.clear();
    });
  }

  void pilihSemua() {
    setState(() {
      if (selectedIds.length == data.length) {
        selectedIds.clear();
      } else {
        selectedIds = data.map((e) => e['id'] as int).toSet();
      }
    });
  }

  // ─── PICK DATE ─────────────────────────────────────────────────────────────
  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: filterTanggal,
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
      setState(() => filterTanggal = picked);
      loadData();
    }
  }

  // ─── STATUS CONFIG ─────────────────────────────────────────────────────────
  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'pending': return const Color(0xFFF57C00);
      case 'acc':     return const Color(0xFF2E7D32);
      case 'reject':  return const Color(0xFFC62828);
      default:        return Colors.grey;
    }
  }

  Color _statusBg(String status) {
    switch (status.toLowerCase()) {
      case 'pending': return const Color(0xFFFFF3E0);
      case 'acc':     return const Color(0xFFE8F5E9);
      case 'reject':  return const Color(0xFFFFEBEE);
      default:        return Colors.grey.shade100;
    }
  }

  IconData _statusIcon(String status) {
    switch (status.toLowerCase()) {
      case 'pending': return Icons.access_time_rounded;
      case 'acc':     return Icons.check_circle_rounded;
      case 'reject':  return Icons.cancel_rounded;
      default:        return Icons.help_outline_rounded;
    }
  }

  // ─── DROPDOWN STYLE ────────────────────────────────────────────────────────
  Widget _dropdown({
    required String value,
    required List<String> items,
    required String hint,
    required void Function(String) onChanged,
    IconData? icon,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _biru.withOpacity(0.2)),
          boxShadow: [
            BoxShadow(
              color: _biru.withOpacity(0.06),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: value,
            isExpanded: true,
            icon: const Icon(Icons.keyboard_arrow_down_rounded, color: _biru),
            style: const TextStyle(fontSize: 13, color: _textGelap, fontWeight: FontWeight.w500),
            items: items.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
            onChanged: (v) => onChanged(v!),
          ),
        ),
      ),
    );
  }

  // ─── BUILD ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,

      // ── APP BAR ──────────────────────────────────────────────────────────
      appBar: AppBar(
        elevation: 0,
        backgroundColor: seleksiMode ? const Color(0xFF0D47A1) : _biru,
        foregroundColor: Colors.white,
        title: Text(
          seleksiMode
              ? "${selectedIds.length} Dipilih"
              : "Monitoring Panen",
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18, letterSpacing: 0.3),
        ),
        actions: seleksiMode
            ? [
          // Pilih Semua
          IconButton(
            icon: Icon(
              selectedIds.length == data.length
                  ? Icons.deselect_rounded
                  : Icons.select_all_rounded,
            ),
            onPressed: pilihSemua,
            tooltip: "Pilih Semua",
          ),
          // Hapus
          IconButton(
            icon: const Icon(Icons.delete_rounded),
            onPressed: selectedIds.isEmpty ? null : hapusSelected,
            tooltip: "Hapus",
          ),
          // Batal
          IconButton(
            icon: const Icon(Icons.close_rounded),
            onPressed: toggleSeleksiMode,
            tooltip: "Batal",
          ),
        ]
            : [
          // Pilih
          IconButton(
            icon: const Icon(Icons.checklist_rounded),
            onPressed: toggleSeleksiMode,
            tooltip: "Pilih Data",
          ),
          IconButton(
            icon: const Icon(Icons.calendar_month_rounded),
            onPressed: _pickDate,
            tooltip: "Filter Tanggal",
          ),
        ],
      ),

      body: Column(
        children: [

          // ── HEADER GRADIENT ────────────────────────────────────────────
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
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
                // Filter dropdowns
                Row(
                  children: [
                    _dropdown(
                      value: filter,
                      items: const ["Semua", "pending", "ACC", "REJECT"],
                      hint: "Status",
                      onChanged: (v) { setState(() => filter = v); loadData(); },
                    ),
                    const SizedBox(width: 8),
                    _dropdown(
                      value: filterKCS,
                      items: const ["Semua", "KCS1", "KCS2", "KCS3"],
                      hint: "Pemanen",
                      onChanged: (v) { setState(() => filterKCS = v); loadData(); },
                    ),
                  ],
                ),

                const SizedBox(height: 10),

                // Filter Bulan & Tahun
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white.withOpacity(0.3)),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<int?>(
                            value: selectedMonth,
                            hint: const Text("Pilih Bulan", style: TextStyle(color: Colors.white, fontSize: 13)),
                            dropdownColor: _biru,
                            icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white),
                            items: [
                              const DropdownMenuItem(value: null, child: Text("Semua Bulan", style: TextStyle(color: _textGelap))),
                              ...List.generate(12, (i) => DropdownMenuItem(
                                value: i + 1,
                                child: Text(months[i], style: const TextStyle(color: _textGelap)),
                              )),
                            ],
                            onChanged: (v) { setState(() => selectedMonth = v); loadData(); },
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white.withOpacity(0.3)),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<int?>(
                            value: selectedYear,
                            hint: const Text("Pilih Tahun", style: TextStyle(color: Colors.white, fontSize: 13)),
                            dropdownColor: _biru,
                            icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white),
                            items: [
                              const DropdownMenuItem(value: null, child: Text("Semua Tahun", style: TextStyle(color: _textGelap))),
                              ...years.map((y) => DropdownMenuItem(
                                value: y,
                                child: Text(y.toString(), style: const TextStyle(color: _textGelap)),
                              )),
                            ],
                            onChanged: (v) { setState(() => selectedYear = v); loadData(); },
                          ),
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 10),

                // Banner tanggal
                GestureDetector(
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
                        const Icon(Icons.event_rounded, size: 18, color: Colors.white),
                        const SizedBox(width: 8),
                        Text(
                          "${filterTanggal.day}-${filterTanggal.month}-${filterTanggal.year}",
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Text(
                            "Ubah Tanggal",
                            style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 8),

          // ── JUMLAH DATA ────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                Text(
                  "${data.length} Data Ditemukan",
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _textAbu,
                  ),
                ),
              ],
            ),
          ),

          // ── LIST DATA ──────────────────────────────────────────────────
          Expanded(
            child: data.isEmpty
                ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.inbox_rounded, size: 64, color: Colors.grey.shade300),
                  const SizedBox(height: 12),
                  Text(
                    "Belum ada data panen",
                    style: TextStyle(fontSize: 14, color: Colors.grey.shade500, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            )
                : ListView.builder(
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
              itemCount: data.length,
              itemBuilder: (context, index) {
                final item   = data[index];
                final status = (item['status'] ?? 'pending').toString().toLowerCase();
                final isPending = status == 'pending';
                final itemId = item['id'] as int;
                final isSelected = selectedIds.contains(itemId);

                return GestureDetector(
                  onLongPress: () {
                    if (!seleksiMode) {
                      setState(() {
                        seleksiMode = true;
                        selectedIds.add(itemId);
                      });
                    }
                  },
                  onTap: seleksiMode
                      ? () {
                    setState(() {
                      if (isSelected) {
                        selectedIds.remove(itemId);
                      } else {
                        selectedIds.add(itemId);
                      }
                    });
                  }
                      : null,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: isSelected ? _biru.withOpacity(0.08) : Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: isSelected
                          ? Border.all(color: _biru.withOpacity(0.5), width: 1.5)
                          : null,
                      boxShadow: [
                        BoxShadow(
                          color: _biru.withOpacity(0.07),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        // ── TOP ROW ──────────────────────────────────
                        Padding(
                          padding: const EdgeInsets.all(14),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [

                              // Checkbox (hanya di mode seleksi)
                              if (seleksiMode) ...[
                                Padding(
                                  padding: const EdgeInsets.only(right: 8, top: 4),
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 150),
                                    width: 24, height: 24,
                                    decoration: BoxDecoration(
                                      color: isSelected ? _biru : Colors.transparent,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: isSelected ? _biru : _textAbu,
                                        width: 2,
                                      ),
                                    ),
                                    child: isSelected
                                        ? const Icon(Icons.check_rounded, size: 14, color: Colors.white)
                                        : null,
                                  ),
                                ),
                              ],

                              // Foto
                              ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: (item['foto'] != null && item['foto'].toString().isNotEmpty)
                                    ? _buildThumbnail(item['foto'].toString())
                                    : Container(
                                        width: 72,
                                        height: 72,
                                        color: _biruPudar,
                                        child: const Icon(
                                          Icons.image_not_supported_rounded,
                                          color: _biru,
                                          size: 28,
                                        ),
                                      ),
                              ),

                              const SizedBox(width: 12),

                              // Info
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      "Blok ${item['blok']} (${item['afdeling'] ?? '-'})",
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 15,
                                        color: _textGelap,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 4),
                                    _infoRow(Icons.person_outline_rounded, "Pemanen: ${item['pemanen']}"),
                                    Row(
                                      children: [
                                        Expanded(child: _infoRow(Icons.eco_outlined, "Matang: ${item['matang'] ?? 0}")),
                                        const SizedBox(width: 8),
                                        Expanded(child: _infoRow(Icons.eco_outlined, "Mentah: ${item['mentah'] ?? 0}", color: Colors.red)),
                                      ],
                                    ),
                                    _infoRow(Icons.scale_rounded, "Brondolan: ${item['brondolan']} Kg"),
                                    if (item['catatan'] != null && item['catatan'].toString().isNotEmpty)
                                      _infoRow(Icons.notes_rounded, "Catatan: ${item['catatan']}"),
                                  ],
                                ),
                              ),

                              // Status badge
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: _statusBg(status),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(_statusIcon(status), size: 13, color: _statusColor(status)),
                                    const SizedBox(width: 4),
                                    Text(
                                      status.toUpperCase(),
                                      style: TextStyle(
                                        color: _statusColor(status),
                                        fontWeight: FontWeight.w800,
                                        fontSize: 11,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),

                        // ── DIVIDER ──────────────────────────────────
                        if (!seleksiMode) Divider(height: 1, color: Colors.grey.shade100),

                        // ── ACTION ROW ───────────────────────────────
                        if (!seleksiMode)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            child: Row(
                              children: [

                                // Rincian
                                _actionButton(
                                  label: "Rincian",
                                  icon: Icons.info_outline_rounded,
                                  color: _biru,
                                  onTap: () async {
                                    final result = await Navigator.push(
                                      context,
                                      MaterialPageRoute(builder: (_) => DetailPanenPage(data: item)),
                                    );
                                    if (result == true) loadData();
                                  },
                                ),

                                const SizedBox(width: 8),

                                // Edit
                                _actionButton(
                                  label: "Edit",
                                  icon: Icons.edit_outlined,
                                  color: _textAbu,
                                  onTap: () async {
                                    final result = await Navigator.push(
                                      context,
                                      MaterialPageRoute(builder: (_) => InputPanenPage(data: item)),
                                    );
                                    if (result == true) loadData();
                                  },
                                ),

                                const Spacer(),

                                // ACC / Reject (hanya untuk MANDOR/ADMIN dan status pending)
                                if ((roleUser == "MANDOR" || roleUser == "ADMIN") && isPending) ...[
                                  _iconActionButton(
                                    icon: Icons.check_rounded,
                                    color: const Color(0xFF2E7D32),
                                    bg: const Color(0xFFE8F5E9),
                                    onTap: () => acc(item['id']),
                                    tooltip: "ACC",
                                  ),
                                  const SizedBox(width: 8),
                                  _iconActionButton(
                                    icon: Icons.close_rounded,
                                    color: const Color(0xFFC62828),
                                    bg: const Color(0xFFFFEBEE),
                                    onTap: () => reject(item['id']),
                                    tooltip: "Reject",
                                  ),
                                ],
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ─── HELPER WIDGETS ────────────────────────────────────────────────────────

  Widget _buildThumbnail(String path) {
    if (path.startsWith('data:image')) {
      try {
        final base64Data = path.split(',').last.replaceAll(RegExp(r'\s+'), '');
        return Image.memory(
          base64Decode(base64Data),
          width: 72,
          height: 72,
          fit: BoxFit.cover,
          errorBuilder: (c, e, s) => Container(
            width: 72, height: 72,
            color: _biruPudar,
            child: const Icon(Icons.broken_image, color: _biru),
          ),
        );
      } catch (e) {
        return Container(
          width: 72, height: 72,
          color: _biruPudar,
          child: const Icon(Icons.broken_image, color: _biru),
        );
      }
    }

    if (kIsWeb) {
      if (path.startsWith('http')) {
        return Image.network(
          path,
          width: 72,
          height: 72,
          fit: BoxFit.cover,
          errorBuilder: (c, e, s) => Container(
            width: 72, height: 72,
            color: _biruPudar,
            child: const Icon(Icons.broken_image, color: _biru),
          ),
        );
      }
      return Container(
        width: 72, height: 72,
        color: _biruPudar,
        child: const Icon(Icons.image_rounded, color: _biru),
      );
    }

    return Image.file(
      File(path),
      width: 72,
      height: 72,
      fit: BoxFit.cover,
      errorBuilder: (c, e, s) => Container(
        width: 72, height: 72,
        color: _biruPudar,
        child: const Icon(Icons.broken_image, color: _biru),
      ),
    );
  }

  Widget _infoRow(IconData icon, String text, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        mainAxisSize: MainAxisSize.max,
        children: [
          Icon(icon, size: 12, color: color ?? _textAbu),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 12, color: color ?? _textAbu),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionButton({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 5),
            Text(label, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  Widget _iconActionButton({
    required IconData icon,
    required Color color,
    required Color bg,
    required VoidCallback onTap,
    required String tooltip,
  }) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            color: bg,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 18, color: color),
        ),
      ),
    );
  }
}