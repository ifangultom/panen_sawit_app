import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:panen_sawit_app/database_helper.dart';
import 'package:panen_sawit_app/utils/date_utils.dart';

class SinkronisasiPage extends StatefulWidget {
  final bool readOnly;
  const SinkronisasiPage({super.key, this.readOnly = false});

  @override
  State<SinkronisasiPage> createState() => _SinkronisasiPageState();
}

class _SinkronisasiPageState extends State<SinkronisasiPage> {
  bool loading = false;
  List<Map<String, dynamic>> dataList = [];
  List<Map<String, dynamic>> filteredList = [];

  bool seleksiMode = false;
  Set<int> selectedIds = {};

  DateTime? filterTanggal;
  String filterStatus = "Semua"; // Semua / offline / synced
  String kcsLogin = "";

  int get totalOffline => dataList.where((e) => (e['sync_status'] ?? 'offline') != 'synced').length;
  int get totalSynced  => dataList.where((e) => (e['sync_status'] ?? '') == 'synced').length;

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  Future<void> _loadUser() async {
    final prefs = await SharedPreferences.getInstance();
    kcsLogin = prefs.getString('kcs_login') ?? "";
    String role = prefs.getString('role') ?? "";
    await loadData();
    
    // 🔥 HANYA KCS YANG BISA SYNC OTOMATIS
    // Mandor dan Admin hanya memantau (readOnly)
    if (totalOffline > 0 && role.toLowerCase() == 'kcs' && !widget.readOnly) {
      sync();
    }
  }

  Future<void> loadData() async {
    final db = await DatabaseHelper.instance.database;
    
    // Ambil semua data lokal
    final List<Map<String, dynamic>> allLocal = await db.query('panen', orderBy: 'id DESC');
    
    // Filter di memori agar konsisten dengan normalisasi AppDateUtils
    final String afdNormalized = AppDateUtils.mapKcsToAfd(kcsLogin);
    
    List<Map<String, dynamic>> filtered;
    if (afdNormalized.isEmpty || afdNormalized == "ALL") {
      filtered = allLocal;
    } else {
      filtered = allLocal.where((e) {
        String itemAfd = AppDateUtils.mapKcsToAfd(e['afdeling']?.toString() ?? e['kcs']?.toString() ?? "");
        return itemAfd == afdNormalized;
      }).toList();
    }

    setState(() {
      dataList = filtered;
      _applyFilter();
    });
  }

  void _applyFilter() {
    List<Map<String, dynamic>> result = List.from(dataList);

    // Filter tanggal
    if (filterTanggal != null) {
      final tgl = filterTanggal!.toString().split(" ")[0];
      result = result.where((e) {
        return (e['tanggal'] ?? "").toString().startsWith(tgl);
      }).toList();
    }

    // Filter status
    if (filterStatus == "Belum Sync") {
      result = result.where((e) => (e['sync_status'] ?? 'offline') != 'synced').toList();
    } else if (filterStatus == "Sudah Sync") {
      result = result.where((e) => (e['sync_status'] ?? '') == 'synced').toList();
    }

    filteredList = result;
  }

  Future<void> _pilihTanggal() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: filterTanggal ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      builder: (context, child) => Theme(
        data: ThemeData.light().copyWith(
          colorScheme: const ColorScheme.light(primary: Color(0xFF0D47A1)),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() { filterTanggal = picked; _applyFilter(); });
    }
  }

  // ===== SYNC DATA =====
  Future<void> sync() async {
    setState(() => loading = true);

    try {
      // 1. Sinkronisasi master data dari cloud ke lokal
      await DatabaseHelper.instance.syncHarvesters().timeout(const Duration(seconds: 10));
      await DatabaseHelper.instance.syncBlocks().timeout(const Duration(seconds: 10));

      // 2. Upload data panen ke Firebase & Laravel
      await DatabaseHelper.instance.syncData();

      // 3. Refresh data lokal untuk melihat perubahan status
      await loadData();
      
      setState(() => loading = false);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(children: [
            const Icon(Icons.check_circle, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            const Text("Sinkronisasi Berhasil!"),
          ]),
          backgroundColor: const Color(0xFF0D47A1),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
        ),
      );
    } catch (e) {
      setState(() => loading = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Sync gagal: $e"),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
        ),
      );
    }
  }

  void toggleSeleksiMode() {
    setState(() { seleksiMode = !seleksiMode; selectedIds.clear(); });
  }

  void pilihSemua() {
    setState(() {
      if (selectedIds.length == filteredList.length) {
        selectedIds.clear();
      } else {
        selectedIds = filteredList.map((e) => e['id'] as int).toSet();
      }
    });
  }

  Future<void> hapusSelected() async {
    if (selectedIds.isEmpty) return;
    final konfirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text("Hapus Data"),
        content: Text("Hapus ${selectedIds.length} data yang dipilih?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Batal")),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text("Hapus", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (konfirm == true) {
      for (final id in selectedIds) {
        await DatabaseHelper.instance.deletePanen(id);
      }
      setState(() { selectedIds.clear(); seleksiMode = false; });
      await loadData();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Data berhasil dihapus")),
      );
    }
  }

  String _formatTanggal(String? raw) {
    if (raw == null || raw.isEmpty) return "-";
    try {
      final dt = DateTime.parse(raw);
      const bln = ['','Jan','Feb','Mar','Apr','Mei','Jun','Jul','Ags','Sep','Okt','Nov','Des'];
      return "${dt.day} ${bln[dt.month]} ${dt.year}  ${dt.hour.toString().padLeft(2,'0')}:${dt.minute.toString().padLeft(2,'0')}";
    } catch (_) { return raw; }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4FF),
      appBar: AppBar(
        title: Text(
          seleksiMode ? "${selectedIds.length} Dipilih" : "Sinkronisasi",
          style: const TextStyle(color: Colors.white),
        ),
        backgroundColor: const Color(0xFF0D47A1),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: seleksiMode ? [
          IconButton(
            icon: Icon(selectedIds.length == filteredList.length
                ? Icons.deselect_rounded : Icons.select_all_rounded,
                color: Colors.white),
            onPressed: pilihSemua,
          ),
          IconButton(
            icon: const Icon(Icons.delete_rounded, color: Colors.white),
            onPressed: selectedIds.isEmpty ? null : hapusSelected,
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded, color: Colors.white),
            onPressed: toggleSeleksiMode,
          ),
        ] : [
          IconButton(
            icon: const Icon(Icons.calendar_today, color: Colors.white),
            onPressed: _pilihTanggal,
            tooltip: "Filter Tanggal",
          ),
          if (!widget.readOnly)
            IconButton(
              icon: const Icon(Icons.checklist_rounded, color: Colors.white),
              onPressed: toggleSeleksiMode,
              tooltip: "Pilih Data",
            ),
        ],
      ),
      body: Column(
        children: [

          // ===== STAT SUMMARY =====
          Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF0D47A1), Color(0xFF1976D2)],
              ),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  _statChip(Icons.cloud_off_rounded, "$totalOffline", "Belum Sync", Colors.orange),
                  const SizedBox(width: 10),
                  _statChip(Icons.cloud_done_rounded, "$totalSynced", "Sudah Sync", const Color(0xFF0D47A1)),
                  if (filterTanggal != null) ...[
                    const SizedBox(width: 15),
                    GestureDetector(
                      onTap: () => setState(() { filterTanggal = null; _applyFilter(); }),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.calendar_today, color: Colors.white, size: 12),
                            const SizedBox(width: 4),
                            Text(
                              "${filterTanggal!.day}/${filterTanggal!.month}/${filterTanggal!.year}",
                              style: const TextStyle(color: Colors.white, fontSize: 11),
                            ),
                            const SizedBox(width: 4),
                            const Icon(Icons.close, color: Colors.white70, size: 12),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

          // ===== BANNER READ-ONLY =====
          if (widget.readOnly)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              color: Colors.blue.shade50,
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 16, color: Colors.blue.shade700),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      "Hanya KCS yang dapat melakukan sinkronisasi data",
                      style: TextStyle(fontSize: 12, color: Colors.blue.shade700, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),

          // ===== FILTER STATUS =====
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: ["Semua", "Belum Sync", "Sudah Sync"].map((s) {
                final isActive = filterStatus == s;
                return GestureDetector(
                  onTap: () => setState(() { filterStatus = s; _applyFilter(); }),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                    decoration: BoxDecoration(
                      color: isActive ? const Color(0xFF0D47A1) : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isActive ? const Color(0xFF0D47A1) : Colors.grey.shade300,
                      ),
                    ),
                    child: Text(
                      s,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isActive ? Colors.white : Colors.grey.shade600,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),

          // ===== TOMBOL SYNC =====
          if (!seleksiMode && !widget.readOnly)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
              child: SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: loading || totalOffline == 0 ? null : sync,
                  icon: loading
                      ? const SizedBox(width: 18, height: 18,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Icon(Icons.cloud_upload_rounded),
                  label: Text(
                    loading ? "Mengupload..." :
                    totalOffline == 0 ? "Semua Data Sudah Tersinkron" :
                    "Sync $totalOffline Data Sekarang",
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: totalOffline == 0 ? Colors.grey : const Color(0xFF0D47A1),
                    foregroundColor: Colors.white,
                    elevation: totalOffline == 0 ? 0 : 4,
                    shadowColor: const Color(0xFF0D47A1).withOpacity(0.4),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
            ),

          if (loading) const LinearProgressIndicator(color: Color(0xFF0D47A1)),

          // ===== LIST =====
          Expanded(
            child: filteredList.isEmpty
                ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.cloud_done_outlined, size: 70,
                      color: Colors.grey.shade300),
                  const SizedBox(height: 12),
                  Text(
                    filterTanggal != null || filterStatus != "Semua"
                        ? "Tidak ada data untuk filter ini"
                        : "Semua data sudah tersinkron",
                    style: TextStyle(color: Colors.grey.shade500, fontSize: 15),
                  ),
                ],
              ),
            )
                : ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 20),
              itemCount: filteredList.length,
              itemBuilder: (context, index) {
                final item = filteredList[index];
                final status = item['sync_status']?.toString() ?? "offline";
                final isSynced = status == 'synced';
                final itemId = item['id'] as int;
                final isSelected = selectedIds.contains(itemId);

                return GestureDetector(
                  onLongPress: () {
                    if (!seleksiMode) {
                      setState(() { seleksiMode = true; selectedIds.add(itemId); });
                    }
                  },
                  onTap: seleksiMode ? () {
                    setState(() {
                      if (isSelected) selectedIds.remove(itemId);
                      else selectedIds.add(itemId);
                    });
                  } : null,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? const Color(0xFF0D47A1).withOpacity(0.08)
                          : Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isSelected
                            ? const Color(0xFF0D47A1)
                            : isSynced ? Colors.transparent : Colors.orange.shade200,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.03),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      leading: seleksiMode
                          ? Icon(
                        isSelected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                        color: isSelected ? const Color(0xFF0D47A1) : Colors.grey,
                      )
                          : CircleAvatar(
                        backgroundColor: isSynced ? Colors.green.shade50 : Colors.orange.shade50,
                        child: Icon(
                          isSynced ? Icons.cloud_done_rounded : Icons.cloud_off_rounded,
                          color: isSynced ? Colors.green : Colors.orange,
                          size: 20,
                        ),
                      ),
                      title: Text(
                        item['pemanen'] ?? "-",
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 4),
                          Text("${item['blok'] ?? '-'} • ${item['jumlah_jangjang'] ?? 0} Janjang"),
                          Text(
                            _formatTanggal(item['tanggal']),
                            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                          ),
                        ],
                      ),
                      trailing: isSynced ? null : const Icon(Icons.chevron_right_rounded, color: Colors.grey),
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

  Widget _statChip(IconData icon, String count, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4, offset: const Offset(0, 2)),
        ],
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(count, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: color)),
              Text(label, style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
            ],
          ),
        ],
      ),
    );
  }
}
