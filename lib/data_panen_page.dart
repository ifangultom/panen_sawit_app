import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'database_helper.dart';
import 'detail_panen_page.dart';
import 'utils/date_utils.dart';
import 'api_service.dart';

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
  List<Map<String, dynamic>> allData = [];
  bool isLoading = true;
  String filter = "Semua";
  String filterKCS = "Semua";
  DateTime filterTanggal = DateTime.now();
  int? selectedMonth;
  int? selectedYear;
  String afdelingUser = "";
  String roleUser = "";

  bool seleksiMode = false;
  Set<String> terpilih = {};

  @override
  void initState() {
    super.initState();
    filter = widget.initialFilter;
    _initUser();
  }

  Future<void> _initUser() async {
    final prefs = await SharedPreferences.getInstance();
    final user = prefs.getString('current_user') ?? "";
    setState(() {
      roleUser = (prefs.getString('role_$user') ?? "").toUpperCase();
      afdelingUser = prefs.getString('afd_login') ?? "";
      if (afdelingUser.isEmpty) {
        afdelingUser = prefs.getString('afdeling_$user') ?? "";
        if (afdelingUser.isEmpty) {
          final kcsL = prefs.getString('kcs_login') ?? "";
          afdelingUser = AppDateUtils.mapKcsToAfd(kcsL);
        }
      }
    });
    loadData();
  }

  List<Map<String, dynamic>> get _filteredList {
    List<Map<String, dynamic>> temp = allData.where((e) {
      bool matchStatus = filter == "Semua" || (e['status'] ?? e['sync_status'] ?? "pending").toString().toUpperCase() == filter.toUpperCase();
      bool matchKCS = filterKCS == "Semua" || e['kcs'] == filterKCS;
      return matchStatus && matchKCS;
    }).toList();

    if (roleUser != "ADMIN" && afdelingUser.isNotEmpty && afdelingUser != "ALL") {
      final String afdNormalized = afdelingUser.replaceAll(' ', '').toUpperCase();
      temp = temp.where((d) {
        String itemAfd = (d['afdeling'] ?? "").toString().replaceAll(' ', '').toUpperCase();
        if (itemAfd.isEmpty) {
          itemAfd = AppDateUtils.mapKcsToAfd(d['kcs']?.toString());
        }
        return itemAfd == afdNormalized;
      }).toList();
    }

    final patterns = AppDateUtils.getDateSearchPatterns(filterTanggal);
    return temp.where((e) {
      String tgl = (e['tanggal'] ?? "").toString();
      if (selectedYear != null) {
        DateTime? dt = AppDateUtils.parseDate(tgl);
        if (dt == null) return false;
        bool matchYear = dt.year == selectedYear;
        bool matchMonth = selectedMonth == null || dt.month == selectedMonth;
        return matchYear && matchMonth;
      }
      return patterns.any((p) => tgl.startsWith(p));
    }).toList();
  }

  // ─── LOAD DATA (Firebase + SQLite merge) ──────────────────────────────────
  Future<void> loadData() async {
    final String afdNormalized = afdelingUser.replaceAll(' ', '').toUpperCase();
    List<Map<String, dynamic>> temp = [];

    try {
      // 1. Ambil data lokal dulu
      final localData = await _loadDataOffline();
      
      final connectivity = await Connectivity().checkConnectivity();
      if (!connectivity.contains(ConnectivityResult.none)) {
        // 2. Ambil data online dari Firebase
        Query query = FirebaseFirestore.instance.collection('panen');

        if (selectedYear != null) {
          DateTime firstDay = DateTime(selectedYear!, selectedMonth ?? 1, 1);
          DateTime lastDay = selectedMonth != null 
              ? DateTime(selectedYear!, selectedMonth! + 1, 0, 23, 59, 59)
              : DateTime(selectedYear!, 12, 31, 23, 59, 59);

          query = query.where('tanggal', isGreaterThanOrEqualTo: firstDay.toIso8601String().split('T')[0])
                       .where('tanggal', isLessThanOrEqualTo: lastDay.toIso8601String().split('T')[0]);
        } else {
          final tglFilter = filterTanggal.toString().split(" ")[0];
          query = query.where('tanggal', isGreaterThanOrEqualTo: tglFilter)
              .where('tanggal', isLessThan: '${tglFilter}Z');
        }

        final snapshot = await query.get();
        
        List<Map<String, dynamic>> onlineData = snapshot.docs.map((doc) {
          final d = Map<String, dynamic>.from(doc.data() as Map);
          d['firebase_id'] = doc.id;
          return d;
        }).toList();

        // 3. Filter afdeling online (In-Memory)
        if (roleUser != "ADMIN" && afdNormalized.isNotEmpty && afdNormalized != "ALL") {
          onlineData = onlineData.where((d) {
            String itemAfd = (d['afdeling'] ?? "").toString().replaceAll(' ', '').toUpperCase();
            if (itemAfd.isEmpty) {
              itemAfd = AppDateUtils.mapKcsToAfd(d['kcs']?.toString());
            }
            return itemAfd == afdNormalized;
          }).toList();
        }

        // 4. Gabungkan & De-duplikasi
        Map<String, Map<String, dynamic>> combined = {};
        final prefs = await SharedPreferences.getInstance();
        final user = prefs.getString('current_user') ?? "";

        for (var d in localData) {
          String key = d['firebase_id'] ?? d['doc_id'] ?? "${user}_${d['id']}";
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
              // Try to find if this online record exists locally but without firebase_id
              String localKey = "${d['user']}_${d['local_id'] ?? d['id']}";
              if (combined.containsKey(localKey)) {
                 final localId = combined[localKey]!['id'];
                 combined[key] = Map<String, dynamic>.from(d);
                 combined[key]!['id'] = localId;
                 combined.remove(localKey);
              } else {
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
      debugPrint("Error loading data: $e");
      temp = await _loadDataOffline();
    }

    // Pre-decode images for the combined list
    for (var d in temp) {
      if (d['foto_bytes'] == null && d['foto'] != null && d['foto'].toString().startsWith('data:image')) {
        try {
          final base64String = d['foto'].split(',').last;
          d['foto_bytes'] = base64Decode(base64String.replaceAll(RegExp(r'\s+'), ''));
        } catch (_) {}
      }
    }

    if (mounted) {
      setState(() {
        allData = temp;
        isLoading = false;
      });
    }
  }

  Future<List<Map<String, dynamic>>> _loadDataOffline() async {
    final List<Map<String, dynamic>> local = await DatabaseHelper.instance.getAllPanen();
    return local;
  }

  Future<void> _updateStatus(String status, {Set<String>? targetIds}) async {
    final ids = targetIds ?? Set.from(terpilih);
    if (ids.isEmpty) return;
    setState(() => isLoading = true);

    try {
      final db = DatabaseHelper.instance;
      final firestore = FirebaseFirestore.instance;
      final batch = firestore.batch();
      bool hasFirestoreUpdate = false;

      for (String id in ids) {
        final item = allData.firstWhere(
          (e) => (e['firebase_id'] ?? e['doc_id'] ?? e['id'].toString()) == id,
          orElse: () => {},
        );
        if (item.isEmpty) continue;
        
        final remoteId = item['firebase_id'] ?? item['doc_id'];
        if (remoteId != null) {
          batch.update(firestore.collection('panen').doc(remoteId), {'status': status});
          hasFirestoreUpdate = true;
        }
        
        if (item['id'] != null) {
          final database = await db.database;
          await database.update(
            'panen',
            {'status': status, 'sync_status': 'synced'},
            where: 'id = ?',
            whereArgs: [item['id']],
          );
        }
      }
      
      if (hasFirestoreUpdate) {
        await batch.commit();
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Berhasil update ${ids.length} data ke $status"),
            backgroundColor: status == "ACC" ? Colors.green : Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
        
        setState(() {
          terpilih.clear();
          seleksiMode = false;
        });
        loadData();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red)
        );
        setState(() => isLoading = false);
      }
    }
  }

  void _selectAll() {
    setState(() {
      final filtered = _filteredList;
      for (var item in filtered) {
        final id = (item['firebase_id'] ?? item['doc_id'] ?? item['id'].toString());
        terpilih.add(id);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredList;

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        title: seleksiMode 
            ? Text("${terpilih.length} dipilih", style: const TextStyle(fontWeight: FontWeight.bold))
            : const Text("Monitoring Panen", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: _biru,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (seleksiMode) ...[
            IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() { seleksiMode = false; terpilih.clear(); })),
          ] else ...[
            IconButton(
              icon: const Icon(Icons.checklist_rtl_rounded),
              onPressed: () => setState(() => seleksiMode = true),
              tooltip: "Mode Seleksi",
            ),
            IconButton(
              icon: const Icon(Icons.calendar_month_rounded),
              onPressed: () async {
                final d = await showDatePicker(
                  context: context,
                  initialDate: filterTanggal,
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2100),
                );
                if (d != null) {
                  setState(() => filterTanggal = d);
                  loadData();
                }
              },
              tooltip: "Filter Tanggal",
            ),
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: loadData,
              tooltip: "Refresh Data",
            ),
          ]
        ],
      ),
      bottomNavigationBar: seleksiMode ? _buildBulkActionBar() : null,
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
                                  onChanged: (v) {
                                    setState(() => filter = v);
                                  },
                                ),
                                const SizedBox(width: 8),
                                _dropdown(
                                  value: filterKCS,
                                  items: const ["Semua", "KCS1", "KCS2", "KCS3"],
                                  hint: "Pemanen",
                                  onChanged: (v) {
                                    setState(() => filterKCS = v);
                                  },
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
                                      color: Colors.white.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
                                    ),
                                    child: DropdownButtonHideUnderline(
                                      child: DropdownButton<int?>(
                                        value: selectedMonth,
                                        hint: const Text("Pilih Bulan", style: TextStyle(color: Colors.white, fontSize: 13)),
                                        dropdownColor: _biru,
                                        icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white),
                                        items: [
                                          const DropdownMenuItem(value: null, child: Text("Semua Bulan", style: TextStyle(color: Colors.white))),
                                          ...List.generate(
                                              12,
                                              (i) => DropdownMenuItem(
                                                    value: i + 1,
                                                    child: Text("${i + 1}", style: const TextStyle(color: Colors.white)),
                                                  )),
                                        ],
                                        onChanged: (v) {
                                          setState(() => selectedMonth = v);
                                          loadData();
                                        },
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
                                    ),
                                    child: DropdownButtonHideUnderline(
                                      child: DropdownButton<int?>(
                                        value: selectedYear,
                                        hint: const Text("Pilih Tahun", style: TextStyle(color: Colors.white, fontSize: 13)),
                                        dropdownColor: _biru,
                                        icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white),
                                        items: [
                                          const DropdownMenuItem(value: null, child: Text("Semua Tahun", style: TextStyle(color: Colors.white))),
                                          ...List.generate(
                                              5,
                                              (i) => DropdownMenuItem(
                                                    value: DateTime.now().year - i,
                                                    child: Text("${DateTime.now().year - i}", style: const TextStyle(color: Colors.white)),
                                                  )),
                                        ],
                                        onChanged: (v) {
                                          setState(() => selectedYear = v);
                                          loadData();
                                        },
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 12),

                            // Baris Tanggal
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.calendar_month, color: Colors.white70, size: 20),
                                  const SizedBox(width: 12),
                                  Text(
                                    "${filterTanggal.day}-${filterTanggal.month}-${filterTanggal.year}",
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                  ),
                                  const Spacer(),
                                  TextButton(
                                    onPressed: () async {
                                      final d = await showDatePicker(
                                        context: context,
                                        initialDate: filterTanggal,
                                        firstDate: DateTime(2020),
                                        lastDate: DateTime(2100),
                                      );
                                      if (d != null) {
                                        setState(() => filterTanggal = d);
                                        loadData();
                                      }
                                    },
                                    style: TextButton.styleFrom(
                                      backgroundColor: Colors.white.withValues(alpha: 0.2),
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(horizontal: 16),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                    ),
                                    child: const Text("Ubah Tanggal", style: TextStyle(fontSize: 12)),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
          ),

          // ── LIST DATA ──────────────────────────────────────────────────
          if (filtered.isNotEmpty && (roleUser == "ADMIN" || roleUser == "MANDOR"))
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 16, 0),
              child: Row(
                children: [
                  Text(
                    seleksiMode ? "${terpilih.length} Dipilih" : "${filtered.length} Data Ditemukan",
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: _textGelap),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () {
                      if (!seleksiMode) {
                        setState(() => seleksiMode = true);
                        _selectAll();
                      } else {
                        if (terpilih.length == filtered.length) {
                          setState(() {
                            terpilih.clear();
                            seleksiMode = false;
                          });
                        } else {
                          _selectAll();
                        }
                      }
                    },
                    icon: Icon(seleksiMode && terpilih.length == filtered.length ? Icons.deselect : Icons.checklist, size: 18),
                    label: Text(
                      seleksiMode && terpilih.length == filtered.length ? "Batal Pilih" : "Pilih Semua",
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                    style: TextButton.styleFrom(
                      foregroundColor: _biru,
                      backgroundColor: _biru.withValues(alpha: 0.05),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    ),
                  ),
                ],
              ),
            ),

          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator(color: _biru))
                : filtered.isEmpty
                    ? _emptyState()
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 10, 16, 80),
                        itemCount: filtered.length,
                        itemBuilder: (context, index) {
                          final item = filtered[index];
                          final id = (item['firebase_id'] ?? item['doc_id'] ?? item['id'].toString());
                          final isSelected = terpilih.contains(id);
                          final status = (item['status'] ?? item['sync_status'] ?? 'pending').toString();

                          return GestureDetector(
                            onLongPress: () {
                              if (roleUser == "ADMIN" || roleUser == "MANDOR") {
                                setState(() {
                                  seleksiMode = true;
                                  terpilih.add(id);
                                });
                              }
                            },
                            onTap: () async {
                              if (seleksiMode) {
                                setState(() {
                                  if (isSelected) terpilih.remove(id);
                                  else terpilih.add(id);
                                  if (terpilih.isEmpty) seleksiMode = false;
                                });
                              } else {
                                final refresh = await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => DetailPanenPage(
                                      data: item,
                                      isReadOnly: roleUser == "ADMIN",
                                    ),
                                  ),
                                );
                                if (refresh == true) loadData();
                              }
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              margin: const EdgeInsets.only(bottom: 12),
                              decoration: BoxDecoration(
                                color: isSelected ? _biru.withValues(alpha: 0.08) : Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                border: isSelected ? Border.all(color: _biru.withValues(alpha: 0.5), width: 1.5) : null,
                                boxShadow: [
                                  BoxShadow(color: _biru.withValues(alpha: 0.07), blurRadius: 12, offset: const Offset(0, 4)),
                                ],
                              ),
                              child: Column(
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.all(14),
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        if (seleksiMode) ...[
                                          Padding(
                                            padding: const EdgeInsets.only(right: 12, top: 20),
                                            child: Icon(
                                              isSelected ? Icons.check_circle : Icons.radio_button_unchecked,
                                              color: isSelected ? _biru : _textAbu,
                                            ),
                                          ),
                                        ],
                                        ClipRRect(
                                          borderRadius: BorderRadius.circular(12),
                                          child: _buildThumbnail(item),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                children: [
                                                  Text(
                                                    "Blok ${item['blok']} (${item['afdeling'] ?? '-'})",
                                                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: _textGelap),
                                                  ),
                                                  _statusBadge(status),
                                                ],
                                              ),
                                              const SizedBox(height: 4),
                                              _infoRow(Icons.person_outline_rounded, "Pemanen: ${item['pemanen']}"),
                                              Row(
                                                children: [
                                                  Expanded(child: _infoRow(Icons.eco_outlined, "Matang: ${item['matang'] ?? 0}")),
                                                  Expanded(child: _infoRow(Icons.eco_outlined, "Mentah: ${item['mentah'] ?? 0}", color: Colors.red)),
                                                ],
                                              ),
                                              _infoRow(Icons.scale_rounded, "Brondolan: ${item['brondolan']} Kg"),
                                              _infoRow(Icons.notes_rounded, "Catatan: ${item['catatan'] ?? "-"}"),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (!seleksiMode) ...[
                                    const Divider(height: 1),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                      child: Row(
                                        children: [
                                          _actionCapsuleButton(
                                            onPressed: () async {
                                              final refresh = await Navigator.push(
                                                context,
                                                MaterialPageRoute(
                                                  builder: (_) => DetailPanenPage(data: item, isReadOnly: true),
                                                ),
                                              );
                                              if (refresh == true) loadData();
                                            },
                                            icon: Icons.info_outline,
                                            label: "Rincian",
                                            color: _biru,
                                            bgColor: _biru.withValues(alpha: 0.08),
                                          ),
                                          const SizedBox(width: 8),
                                            if (roleUser == "MANDOR") ...[
                                            _actionCapsuleButton(
                                              onPressed: () async {
                                                final refresh = await Navigator.push(
                                                  context,
                                                  MaterialPageRoute(
                                                    builder: (_) => DetailPanenPage(data: item, isReadOnly: false),
                                                  ),
                                                );
                                                if (refresh == true) loadData();
                                              },
                                              icon: Icons.edit_outlined,
                                              label: "Edit",
                                              color: _textGelap,
                                              bgColor: Colors.grey.withValues(alpha: 0.1),
                                            ),
                                            if (status.toUpperCase() == "PENDING") ...[
                                              const Spacer(),
                                              _actionCircleButton(
                                                icon: Icons.check,
                                                color: Colors.green,
                                                tooltip: "ACC",
                                                onPressed: () => _updateStatus("ACC", targetIds: {id}),
                                              ),
                                              const SizedBox(width: 8),
                                              _actionCircleButton(
                                                icon: Icons.close,
                                                color: Colors.red,
                                                tooltip: "REJECT",
                                                onPressed: () => _updateStatus("REJECT", targetIds: {id}),
                                              ),
                                            ],
                                          ],
                                        ],
                                      ),
                                    ),
                                  ],
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

  Widget _buildBulkActionBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 10, offset: const Offset(0, -2))],
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () => _updateStatus("ACC"),
                icon: const Icon(Icons.check_circle, color: Colors.white),
                label: const Text("ACC SEMUA", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () => _updateStatus("REJECT"),
                icon: const Icon(Icons.cancel, color: Colors.white),
                label: const Text("REJECT SEMUA", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _actionCapsuleButton({
    required VoidCallback onPressed,
    required IconData icon,
    required String label,
    required Color color,
    required Color bgColor,
  }) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: color)),
          ],
        ),
      ),
    );
  }

  Widget _actionCircleButton({required IconData icon, required Color color, required VoidCallback onPressed, String? tooltip}) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(20),
      child: Tooltip(
        message: tooltip ?? "",
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            shape: BoxShape.circle,
            border: Border.all(color: color.withValues(alpha: 0.2)),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
      ),
    );
  }

  Widget _dropdown({required String value, required List<String> items, required String hint, required Function(String) onChanged}) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: value,
            isExpanded: true,
            items: items.map((s) => DropdownMenuItem(value: s, child: Text(s, style: const TextStyle(fontSize: 13)))).toList(),
            onChanged: (v) => onChanged(v!),
          ),
        ),
      ),
    );
  }

  Widget _infoRow(IconData icon, String text, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        children: [
          Icon(icon, size: 14, color: color ?? _textAbu),
          const SizedBox(width: 4),
          Expanded(child: Text(text, style: TextStyle(fontSize: 12, color: color ?? _textAbu), maxLines: 1, overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inventory_2_outlined, size: 80, color: _textAbu.withOpacity(0.2)),
          const SizedBox(height: 16),
          const Text("Tidak ada data ditemukan", style: TextStyle(color: _textAbu, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _statusBadge(String status) {
    Color color = _statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color, width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            status.toUpperCase() == "ACC" ? Icons.check_circle :
            status.toUpperCase() == "REJECT" ? Icons.cancel : Icons.access_time_filled,
            size: 12, color: color,
          ),
          const SizedBox(width: 4),
          Text(
            status.toUpperCase(),
            style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Color _statusBg(String s) {
    if (s.toUpperCase() == "ACC") return Colors.green.withValues(alpha: 0.1);
    if (s.toUpperCase() == "REJECT") return Colors.red.withValues(alpha: 0.1);
    return Colors.orange.withValues(alpha: 0.1);
  }

  Color _statusColor(String s) {
    if (s.toUpperCase() == "ACC") return Colors.green;
    if (s.toUpperCase() == "REJECT") return Colors.red;
    return Colors.orange;
  }

  Widget _buildThumbnail(Map<String, dynamic> item) {
    final path = (item['foto'] ?? "").toString();
    
    // 1. Handle Pre-decoded Bytes
    if (item['foto_bytes'] != null) {
      return Image.memory(
        item['foto_bytes'],
        width: 72, height: 72,
        fit: BoxFit.cover,
        errorBuilder: (c, e, s) => _buildPlaceholder(),
      );
    }

    // 2. Handle Base64 String (with or without header)
    if (path.startsWith('data:image') || (path.length > 100 && !path.startsWith('http') && !path.contains('/') && !path.contains('\\'))) {
      try {
        final base64Data = path.contains(',') ? path.split(',').last : path;
        final bytes = base64Decode(base64Data.replaceAll(RegExp(r'\s+'), ''));
        return Image.memory(
          bytes,
          width: 72, height: 72,
          fit: BoxFit.cover,
          errorBuilder: (c, e, s) => _buildPlaceholder(),
        );
      } catch (e) {
        return _buildPlaceholder();
      }
    }

    // 3. Handle Local File (Mobile)
    if (!kIsWeb && path.isNotEmpty && !path.startsWith('http')) {
      final file = File(path);
      if (file.existsSync()) {
        return Image.file(
          file,
          width: 72, height: 72,
          fit: BoxFit.cover,
          errorBuilder: (c, e, s) => _buildPlaceholder(),
        );
      }
    }

    // 4. Handle URL (Firebase or Web)
    if (path.startsWith('http')) {
      return Image.network(
        path,
        width: 72, height: 72,
        fit: BoxFit.cover,
        errorBuilder: (c, e, s) => _buildPlaceholder(),
      );
    }

    // 5. Handle Web Storage Fallback (if path is just filename)
    if (kIsWeb && path.isNotEmpty) {
      final fileName = path.split(RegExp(r'[/\\]')).last;
      final baseUrl = ApiService.baseUrl.replaceAll('/api', '');
      return Image.network(
        "$baseUrl/storage/panen/$fileName",
        width: 72, height: 72,
        fit: BoxFit.cover,
        errorBuilder: (c, e, s) => _buildPlaceholder(),
      );
    }

    return _buildPlaceholder();
  }

  Widget _buildPlaceholder() {
    return Container(
      width: 72, height: 72,
      color: _biruPudar,
      child: const Icon(Icons.image_not_supported_rounded, color: _biru, size: 28),
    );
  }
}
