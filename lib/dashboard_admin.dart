import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'database_helper.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'dart:io';
import 'dart:convert';
import 'package:image_picker/image_picker.dart';
import 'user_helper.dart';
import 'api_service.dart';
import 'utils/date_utils.dart';

// 🔥 Import Halaman Terkait
import 'login_page.dart';
import 'riwayat_pks_page.dart';
import 'riwayat_trip.dart';
import 'laporan_page.dart';
import 'detail_pemanen_page.dart';
import 'detail_panen_page.dart';
import 'input_panen.dart' as input;
import 'input_pks_page.dart';
import 'trip_page.dart';
import 'analisis_page.dart';
import 'pengaturan_page.dart';
import 'user_management_page.dart';
import 'monitoring_data_page.dart';

class DashboardAdmin extends StatefulWidget {
  const DashboardAdmin({super.key});

  @override
  State<DashboardAdmin> createState() => _DashboardAdminState();
}

class _DashboardAdminState extends State<DashboardAdmin> {
  List<Map<String, dynamic>> allData = [];
  List<Map<String, dynamic>> data = [];
  List<Map<String, dynamic>> allPksData = [];
  List<Map<String, dynamic>> allTripsData = [];
  bool isLoading = true;

  DateTime? filterTanggalStart;
  DateTime? filterTanggalEnd;
  int? selectedMonth;
  int? selectedYear;
  String? selectedAfdeling;
  String searchQuery = "";
  String _activeView = "dashboard";

  // Profile State
  final TextEditingController _namaC = TextEditingController();
  final TextEditingController _jabatanC = TextEditingController();
  String _username = "";
  String _fotoPath = "";

  // Harvester Registration State
  final TextEditingController _namaPemanenC = TextEditingController();
  String? _selectedAfdPemanen;

  // Block Registration State
  final TextEditingController _blokC = TextEditingController();
  String? _selectedKcsBlok;

  final List<String> afdelings = ["AFD1", "AFD2", "AFD3"];
  final List<String> kcsList = ["KCS1", "KCS2", "KCS3"];
  final List<String> months = [
    "Januari", "Februari", "Maret", "April", "Mei", "Juni",
    "Juli", "Agustus", "September", "Oktober", "November", "Desember"
  ];
  final List<int> years = List.generate(5, (index) => DateTime.now().year - index);

  final ScrollController _scrollController = ScrollController();
  final GlobalKey _monitoringKey = GlobalKey();

  int totalPanen = 0;
  double totalTon = 0;
  double totalPks = 0; // Tambahkan ini jika belum ada di state
  int jumlahPemanen = 0;
  int totalRegisteredPemanen = 0;
  int totalTrip = 0;
  String syncStatus = "Terkoneksi";
  List<FlSpot> chartSpots = [];
  List<Map<String, dynamic>> pemanenRanking = [];

  final Color primaryBlue = const Color(0xFF0D47A1);
  final Color accentBlue = const Color(0xFF1976D2);
  final Color bgGrey = const Color(0xFFF5F7FA);
  final Color cardShadow = Colors.black.withValues(alpha: 0.05);

  @override
  void initState() {
    super.initState();
    loadData();
  }

  void loadData() async {
    setState(() => isLoading = true);
    try {
      if (kIsWeb) {
        // Ambil profil terlebih dahulu
        await _loadProfile();
        // Load data dari Firebase dengan penanganan await yang benar
        await loadFromFirebase();
      } else {
        await loadFromSQLite();
      }
    } catch (e) {
      debugPrint("❌ Error loadData: $e");
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> loadFromFirebase() async {
    try {
      final results = await Future.wait([
        FirebaseFirestore.instance.collection('panen').get(),
        FirebaseFirestore.instance.collection('pks').get(),
        FirebaseFirestore.instance.collection('trips').get(),
      ]);

      if (!mounted) return;

      // Fungsi bantu untuk memproses item secara efisien
      Map<String, dynamic> processItem(DocumentSnapshot doc) {
        var d = doc.data() as Map<String, dynamic>;
        d['id_firebase'] = doc.id;
        d['tanggal'] = d['tanggal'] ?? d['waktu'] ?? d['waktu_timbang'] ?? d['tanggal_trip'];
        
        // JANGAN decode gambar di sini untuk ribuan data sekaligus karena akan memblock UI thread.
        // Cukup pastikan field foto ada. Decoding akan dilakukan di widget secara lazy.
        return d;
      }

      setState(() {
        allData = results[0].docs.map(processItem).toList();
        allData.sort((a, b) => (b['tanggal']?.toString() ?? "").compareTo(a['tanggal']?.toString() ?? ""));

        allPksData = results[1].docs.map((doc) {
          var d = doc.data() as Map<String, dynamic>;
          d['id_firebase'] = doc.id;
          d['tanggal'] = d['tanggal'] ?? d['waktu_timbang'] ?? d['tanggal_trip'] ?? d['waktu'];
          d['berat_netto'] = d['berat_netto'] ?? d['netto'] ?? d['berat'] ?? 0;
          return d;
        }).toList();
        allPksData.sort((a, b) => (b['tanggal']?.toString() ?? "").compareTo(a['tanggal']?.toString() ?? ""));

        allTripsData = results[2].docs.map((doc) {
          var d = doc.data() as Map<String, dynamic>;
          d['id_firebase'] = doc.id;
          d['tanggal'] = d['tanggal'] ?? d['tanggal_trip'] ?? d['waktu'] ?? d['waktu_timbang'];
          d['no_plat'] = d['no_plat'] ?? d['kendaraan'] ?? d['truk'] ?? "-";
          d['sopir'] = d['sopir'] ?? d['driver'] ?? "-";
          d['jumlah_panen'] = d['jumlah_panen'] ?? d['muatan'] ?? d['total_muatan'] ?? 0;
          return d;
        }).toList();
        allTripsData.sort((a, b) => (b['tanggal']?.toString() ?? "").compareTo(a['tanggal']?.toString() ?? ""));
      });
      applyFilter();

      // Update Listeners untuk juga menggunakan pre-processing
      FirebaseFirestore.instance.collection('panen').snapshots().listen((snapshot) {
        if (!mounted) return;
        setState(() {
          allData = snapshot.docs.map(processItem).toList();
        });
        applyFilter();
      });

      FirebaseFirestore.instance.collection('pks').snapshots().listen((snapshot) {
        if (!mounted) return;
        setState(() {
          allPksData = snapshot.docs.map((doc) {
            var d = doc.data() as Map<String, dynamic>;
            d['id_firebase'] = doc.id;
            d['tanggal'] = d['tanggal'] ?? d['waktu_timbang'] ?? d['tanggal_trip'] ?? d['waktu'];
            d['berat_netto'] = d['berat_netto'] ?? d['netto'] ?? d['berat'] ?? 0;
            return d;
          }).toList();
        });
        applyFilter();
      }, onError: (e) => debugPrint("❌ Error PKS Listener: $e"));

      FirebaseFirestore.instance.collection('trips').snapshots().listen((snapshot) {
        if (!mounted) return;
        setState(() {
          allTripsData = snapshot.docs.map((doc) {
            var d = doc.data() as Map<String, dynamic>;
            d['id_firebase'] = doc.id;
            d['tanggal'] = d['tanggal'] ?? d['tanggal_trip'] ?? d['waktu'] ?? d['waktu_timbang'];
            d['no_plat'] = d['no_plat'] ?? d['kendaraan'] ?? d['truk'] ?? "-";
            d['sopir'] = d['sopir'] ?? d['driver'] ?? "-";
            d['jumlah_panen'] = d['jumlah_panen'] ?? d['muatan'] ?? d['total_muatan'] ?? 0;
            return d;
          }).toList();
        });
        applyFilter();
      }, onError: (e) => debugPrint("❌ Error Trips Listener: $e"));

      FirebaseFirestore.instance.collection('harvesters').snapshots().listen((snapshot) {
        if (!mounted) return;
        setState(() {
          totalRegisteredPemanen = snapshot.docs.length;
        });
      }, onError: (e) => debugPrint("❌ Error Harvesters Listener: $e"));
    } catch (e) {
      debugPrint("❌ Error loadFromFirebase: $e");
    }
  }

  Future<void> loadFromSQLite() async {
    allData = await DatabaseHelper.instance.getAllPanen();
    try {
      final db = await DatabaseHelper.instance.database;
      allPksData = await db.rawQuery('''
        SELECT pks.*, trip.tanggal as trip_tanggal, trip.no_plat as kendaraan, trip.afdeling
        FROM pks
        LEFT JOIN trip ON trip.id = pks.trip_id
      ''');

      allTripsData = await db.rawQuery('''
        SELECT trip.*, 
        (SELECT COUNT(*) FROM trip_detail WHERE trip_id = trip.id) as jumlah_panen,
        COALESCE((SELECT berat_netto FROM pks WHERE trip_id = trip.id), 0) as total_pks
        FROM trip
      ''');
    } catch (e) {
      debugPrint("❌ SQLite Data Error: $e");
    }
    applyFilter();
  }

  // ─── PROFILE LOGIC (WEB ONLY) ───
  ImageProvider? _getProfileImage() {
    if (_fotoPath.isEmpty) return null;
    
    // 1. Handle Base64 Data URI
    if (_fotoPath.startsWith('data:image')) {
      try {
        final base64Data = _fotoPath.split(',').last;
        // Bersihkan string dari whitespace/newline jika ada
        final cleanedBase64 = base64Data.replaceAll(RegExp(r'\s+'), '');
        return MemoryImage(base64Decode(cleanedBase64));
      } catch (e) {
        debugPrint("Error decode base64: $e");
        return null;
      }
    }
    
    // 2. Handle Web Blob URLs (Expired/Invalid handling)
    if (kIsWeb) {
      if (_fotoPath.startsWith('blob:')) {
        // Blob URL hanya valid per sesi. Jika dari Firestore, ini pasti sudah kadaluarsa.
        return null; 
      }
      return NetworkImage(_fotoPath);
    } 
    
    // 3. Handle Mobile File Path
    return FileImage(File(_fotoPath));
  }

  Future<void> _loadProfile() async {
    // 1. Load dari lokal dulu (agar cepat muncul)
    final data = await UserHelper.getUser();
    final localUsername = data['username'] ?? "";
    final localFoto = await UserHelper.getFoto(localUsername);
    
    if (mounted) {
      setState(() {
        _username = localUsername;
        _namaC.text = data['nama'] ?? "";
        _jabatanC.text = data['jabatan'] ?? "";
        if (localFoto.isNotEmpty) {
          if (kIsWeb && localFoto.startsWith('data:image')) {
            _fotoPath = localFoto;
          } else if (!kIsWeb) {
            _fotoPath = localFoto;
          }
        }
      });
    }

    // 2. Sinkronkan dengan Firestore
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
        if (doc.exists) {
          final userData = doc.data();
          if (userData != null) {
            String? cloudFoto = userData['foto'];
            
            setState(() {
              if (userData['nama'] != null) _namaC.text = userData['nama'];
              if (userData['jabatan'] != null) _jabatanC.text = userData['jabatan'];
              
              // Validasi: Jangan ambil foto dari cloud jika itu format blob: lama
              if (cloudFoto != null && cloudFoto.startsWith('data:image')) {
                _fotoPath = cloudFoto;
              }
            });

            // Update lokal agar sinkron
            await UserHelper.saveUser(
              nama: _namaC.text,
              jabatan: _jabatanC.text,
              username: _username,
            );
            
            if (_fotoPath.startsWith('data:image') || !kIsWeb) {
              await UserHelper.saveFoto(_fotoPath, _username);
            }
          }
        }
      }
    } catch (e) {
      debugPrint("Error sync profile: $e");
    }
  }

  Future<void> _pickWebFoto() async {
    final picker = ImagePicker();
    // Gunakan kualitas menengah agar ukuran string Base64 aman untuk Firestore (limit 1MB)
    final file = await picker.pickImage(source: ImageSource.gallery, imageQuality: 40);
    
    if (file != null) {
      if (kIsWeb) {
        final bytes = await file.readAsBytes();
        final base64String = base64Encode(bytes);
        final fullPath = "data:image/png;base64,$base64String";
        
        setState(() => _fotoPath = fullPath);
        if (_username.isNotEmpty) {
          await UserHelper.saveFoto(fullPath, _username);
        }
      } else {
        setState(() => _fotoPath = file.path);
        if (_username.isNotEmpty) {
          await UserHelper.saveFoto(file.path, _username);
        }
      }
    }
  }

  Future<void> _simpanProfile() async {
    if (_username.isEmpty) return;
    
    // 1. Simpan ke Lokal (SharedPreferences)
    await UserHelper.saveUser(
      nama: _namaC.text.trim(),
      jabatan: _jabatanC.text.trim(),
      username: _username,
    );

    // 2. Simpan ke Firestore (Agar tidak hilang saat logout/pindah browser)
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        // Gunakan set dengan merge: true agar document dibuat jika belum ada
        await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
          'nama': _namaC.text.trim(),
          'jabatan': _jabatanC.text.trim(),
          'foto': _fotoPath, // Simpan path foto ke cloud
          'username': _username,
          'lastUpdated': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    } catch (e) {
      debugPrint("Gagal sinkron profil ke cloud: $e");
    }

    if (mounted) {
      setState(() {}); // Refresh TopBar UI
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text("Profil berhasil diperbarui dan tersinkron ke cloud"),
          backgroundColor: accentBlue,
          behavior: SnackBarBehavior.floating,
        )
      );
    }
  }

  // ─── HARVESTER MANAGEMENT LOGIC ───
  Future<void> _simpanPemanen() async {
    if (_namaPemanenC.text.isEmpty || _selectedAfdPemanen == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Nama dan Afdeling harus diisi"), backgroundColor: Colors.orange)
      );
      return;
    }

    try {
      await FirebaseFirestore.instance.collection('harvesters').add({
        'nama': _namaPemanenC.text.trim(),
        'afdeling': _selectedAfdPemanen?.trim(),
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        _namaPemanenC.clear();
        setState(() => _selectedAfdPemanen = null);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Pemanen berhasil didaftarkan ke sistem"),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          )
        );
      }
    } catch (e) {
      debugPrint("Gagal daftar pemanen: $e");
    }
  }

  Future<void> _importDataPemanenDefault() async {
    final Map<String, List<String>> defaultData = {
      "AFD1": [
        "Ahmad Syahputra", "Budi Santoso", "Dedi Saputra", "Eko Prasetyo", 
        "Faisal Harahap", "Gunawan Siregar", "Hendri Simatupang", 
        "Irwan Nasution", "Joko Susanto", "Kurniawan Gultom"
      ],
      "AFD2": [
        "Lukman Hakim", "Mulyadi Sinaga", "Nurhadi Sitorus", "Ongki Manurung", 
        "Parlindungan Simanjuntak", "Rahmat Hidayat", "Sabar Hutagalung", 
        "Taufik Hutasoit", "Ucok Situmorang", "Verry Silaban", 
        "Wahyu Ramadhan", "Yanto Purba"
      ],
      "AFD3": [
        "Zulkifli Pane", "Andi Saputra", "Bambang Setiawan", "Chandra Wijaya", 
        "Doni Irawan", "Erwin Lubis", "Firman Pasaribu", "Ganda Marbun", 
        "Ama Gulo", "Yared Zega", "Fajar Laoli", "Putra Harefa", "Riko Zebua"
      ],
    };

    setState(() => isLoading = true);
    try {
      final batch = FirebaseFirestore.instance.batch();
      final collection = FirebaseFirestore.instance.collection('harvesters');

      defaultData.forEach((afd, names) {
        for (var name in names) {
          var docRef = collection.doc();
          batch.set(docRef, {
            'nama': name,
            'afdeling': afd,
            'createdAt': FieldValue.serverTimestamp(),
          });
        }
      });

      await batch.commit();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Berhasil mengimpor daftar pemanen default"), backgroundColor: Colors.green)
        );
      }
    } catch (e) {
      debugPrint("Error import: $e");
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  // Helper widget to handle profile image rendering with fallback
  Widget _buildProfileImageWidget(double size) {
    final provider = _getProfileImage();
    if (provider == null) {
      return Container(
        color: Colors.grey[200],
        child: Icon(Icons.person, size: size * 0.6, color: Colors.grey[400]),
      );
    }

    return Image(
      image: ResizeImage(
        provider,
        width: (size * 2).toInt(),
        height: (size * 2).toInt(),
      ),
      fit: BoxFit.cover,
      width: size,
      height: size,
      filterQuality: FilterQuality.medium,
      errorBuilder: (context, error, stackTrace) {
        debugPrint("Image load error: $error");
        return Container(
          color: Colors.grey[200],
          child: Icon(Icons.person, size: size * 0.6, color: Colors.grey[400]),
        );
      },
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return Center(
          child: CircularProgressIndicator(
            value: loadingProgress.expectedTotalBytes != null
                ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
                : null,
            strokeWidth: 2,
          ),
        );
      },
    );
  }

  void applyFilter() {
    List<Map<String, dynamic>> filteredPanen = allData.where((item) {
      String? afd = item['afdeling']?.toString();
      if (afd == null || afd.isEmpty) {
        afd = AppDateUtils.mapKcsToAfd(item['kcs']?.toString());
      }

      if (selectedAfdeling != null && afd != selectedAfdeling) return false;
      
      DateTime? dt = AppDateUtils.parseDate(item['tanggal'] ?? item['waktu']);
      if (dt == null) return selectedYear == null && filterTanggalStart == null;

      if (selectedYear != null || selectedMonth != null) {
        if (selectedYear != null && dt.year != selectedYear) return false;
        if (selectedMonth != null && dt.month != selectedMonth) return false;
        return true;
      } else if (filterTanggalStart != null && filterTanggalEnd != null) {
        DateTime dateOnly = DateTime(dt.year, dt.month, dt.day);
        DateTime startOnly = DateTime(filterTanggalStart!.year, filterTanggalStart!.month, filterTanggalStart!.day);
        DateTime endOnly = DateTime(filterTanggalEnd!.year, filterTanggalEnd!.month, filterTanggalEnd!.day);
        
        if (dateOnly.isBefore(startOnly) || dateOnly.isAfter(endOnly)) return false;
      }
      return true;
    }).toList();

    List<Map<String, dynamic>> filteredPks = allPksData.where((item) {
      // 1. Mapping Afdeling
      String? afd = item['afdeling']?.toString();
      
      // Fallback: Resolve dari allTripsData jika ada trip_id
      if (afd == null || afd.isEmpty) {
        String tripId = item['trip_id']?.toString() ?? "";
        if (tripId.isNotEmpty) {
          try {
            final trip = allTripsData.firstWhere(
              (t) => (t['id']?.toString() == tripId || t['id_firebase']?.toString() == tripId),
              orElse: () => <String, dynamic>{}
            );
            if (trip.isNotEmpty) {
              afd = trip['afdeling']?.toString();
            }
          } catch (_) {}
        }
      }

      if (afd == null || afd.isEmpty) {
        afd = AppDateUtils.mapKcsToAfd(item['kcs']?.toString());
      }
      if (selectedAfdeling != null && afd != selectedAfdeling) return false;
      
      // 2. Mapping Tanggal
      DateTime? dt = AppDateUtils.parseDate(item['tanggal'] ?? item['waktu_timbang'] ?? item['waktu']);

      // Fallback Tanggal dari Trip
      if (dt == null) {
        String tripId = item['trip_id']?.toString() ?? "";
        if (tripId.isNotEmpty) {
          try {
            final trip = allTripsData.firstWhere(
              (t) => (t['id']?.toString() == tripId || t['id_firebase']?.toString() == tripId),
              orElse: () => <String, dynamic>{}
            );
            if (trip.isNotEmpty) {
              dt = AppDateUtils.parseDate(trip['tanggal'] ?? trip['tanggal_trip'] ?? trip['waktu']);
            }
          } catch (_) {}
        }
      }
      
      if (dt == null) return selectedYear == null && filterTanggalStart == null;

      if (selectedYear != null || selectedMonth != null) {
        if (selectedYear != null && dt.year != selectedYear) return false;
        if (selectedMonth != null && dt.month != selectedMonth) return false;
        return true;
      } else if (filterTanggalStart != null && filterTanggalEnd != null) {
        DateTime dateOnly = DateTime(dt.year, dt.month, dt.day);
        DateTime startOnly = DateTime(filterTanggalStart!.year, filterTanggalStart!.month, filterTanggalStart!.day);
        DateTime endOnly = DateTime(filterTanggalEnd!.year, filterTanggalEnd!.month, filterTanggalEnd!.day);
        
        if (dateOnly.isBefore(startOnly) || dateOnly.isAfter(endOnly)) return false;
      }
      return true;
    }).toList();

    List<Map<String, dynamic>> filteredTrips = allTripsData.where((item) {
      // 1. Mapping Afdeling
      String? afd = item['afdeling']?.toString();
      if (afd == null || afd.isEmpty) {
        afd = AppDateUtils.mapKcsToAfd(item['kcs']?.toString());
      }
      if (selectedAfdeling != null && afd != selectedAfdeling) return false;
      
      // 2. Mapping Tanggal (Sangat Fleksibel)
      DateTime? dt = AppDateUtils.parseDate(item['tanggal'] ?? item['tanggal_trip'] ?? item['waktu']);
      
      // Jika tidak ada tanggal, tampilkan jika tidak ada filter waktu aktif
      if (dt == null) return selectedYear == null && filterTanggalStart == null;

      if (selectedYear != null || selectedMonth != null) {
        if (selectedYear != null && dt.year != selectedYear) return false;
        if (selectedMonth != null && dt.month != selectedMonth) return false;
        return true;
      } else if (filterTanggalStart != null && filterTanggalEnd != null) {
        DateTime dateOnly = DateTime(dt.year, dt.month, dt.day);
        DateTime startOnly = DateTime(filterTanggalStart!.year, filterTanggalStart!.month, filterTanggalStart!.day);
        DateTime endOnly = DateTime(filterTanggalEnd!.year, filterTanggalEnd!.month, filterTanggalEnd!.day);
        
        if (dateOnly.isBefore(startOnly) || dateOnly.isAfter(endOnly)) return false;
      }
      return true;
    }).toList();

    processData(filteredPanen, filteredPks, filteredTrips);
  }

  void _applySearch(String query) {
    setState(() {
      searchQuery = query.toLowerCase();
    });
  }



  void processData(List<Map<String, dynamic>> filteredPanen, List<Map<String, dynamic>> filteredPks, List<Map<String, dynamic>> filteredTrips) {
    double totalPksKg = 0;
    Set<String> pemanenSet = {};
    int totalJjg = 0;

    Map<String, Map<String, dynamic>> rankingMap = {};

    for (var item in filteredPanen) {
      // Ambil nama pemanen terlebih dahulu (semua status) untuk hitungan KPI
      String? namaPemanen = item['pemanen']?.toString();
      if (namaPemanen != null && namaPemanen.isNotEmpty) {
        pemanenSet.add(namaPemanen);
      }

      // Hitung Janjang (Hanya yang ACC untuk ranking & total janjang utama)
      String status = (item['status'] ?? item['sync_status'] ?? "").toString().toUpperCase();
      bool isAcc = status == "ACC";

      if (isAcc) {
        int matang = int.tryParse(item['matang']?.toString() ?? "0") ?? 0;
        int mentah = int.tryParse(item['mentah']?.toString() ?? "0") ?? 0;
        int total = matang + mentah;
        totalJjg += total;
        
        if (namaPemanen != null) {
          if (!rankingMap.containsKey(namaPemanen)) {
            String? afd = item['afdeling']?.toString();
            if (afd == null || afd.isEmpty) {
              afd = AppDateUtils.mapKcsToAfd(item['kcs']?.toString());
            }
            rankingMap[namaPemanen] = {
              'nama': namaPemanen, 
              'janjang': 0, 
              'brondolan': 0.0,
              'afdeling': afd ?? "-"
            };
          }
          rankingMap[namaPemanen]!['janjang'] += total;
          rankingMap[namaPemanen]!['brondolan'] += double.tryParse(item['brondolan']?.toString() ?? "0") ?? 0;
        }
      }
    }

    List<Map<String, dynamic>> rankingList = rankingMap.values.toList();
    rankingList.sort((a, b) => b['janjang'].compareTo(a['janjang']));

    for (var item in filteredPks) {
      double berat = 0;
      // Cek berbagai kemungkinan field berat
      var val = item['berat_netto'] ?? item['netto'] ?? item['berat'] ?? item['tonase'];
      if (val is num) {
        berat = val.toDouble();
      } else if (val is String) {
        // Hapus unit 'kg' atau karakter non-numerik jika ada
        String cleaned = val.toLowerCase().replaceAll('kg', '').replaceAll(',', '').trim();
        berat = double.tryParse(cleaned) ?? 0;
      }
      totalPksKg += berat;
    }

    setState(() {
      data = filteredPanen;
      totalPanen = totalJjg;
      totalPks = totalPksKg; // Simpan dalam KG
      totalTon = totalPksKg / 1000; // Simpan dalam Ton
      jumlahPemanen = pemanenSet.length;
      totalTrip = filteredTrips.length;
      pemanenRanking = rankingList.take(5).toList();
      
      // Update Chart Data
      chartSpots = _generateChartSpots(filteredPanen);
    });
  }

  List<FlSpot> _generateChartSpots(List<Map<String, dynamic>> filteredPanen) {
    Map<double, double> stats = {};
    
    if (selectedYear != null && selectedMonth == null) {
      // View per bulan (1-12)
      for (var item in filteredPanen) {
        DateTime? dt = AppDateUtils.parseDate(item['tanggal'] ?? item['waktu']);
        if (dt != null) {
          double month = dt.month.toDouble();
          double matang = double.tryParse(item['matang']?.toString() ?? "0") ?? 0;
          double mentah = double.tryParse(item['mentah']?.toString() ?? "0") ?? 0;
          double total = double.tryParse(item['janjang']?.toString() ?? "") ?? (matang + mentah);
          stats[month] = (stats[month] ?? 0) + total;
        }
      }
    } else if (selectedMonth != null) {
      // View per tanggal (1-31)
      for (var item in filteredPanen) {
        DateTime? dt = AppDateUtils.parseDate(item['tanggal'] ?? item['waktu']);
        if (dt != null) {
          double day = dt.day.toDouble();
          double matang = double.tryParse(item['matang']?.toString() ?? "0") ?? 0;
          double mentah = double.tryParse(item['mentah']?.toString() ?? "0") ?? 0;
          double total = double.tryParse(item['janjang']?.toString() ?? "") ?? (matang + mentah);
          stats[day] = (stats[day] ?? 0) + total;
        }
      }
    } else {
      // View per jam (0-23) - Default/Daily
      for (var item in filteredPanen) {
        DateTime? dt = AppDateUtils.parseDate(item['waktu'] ?? item['tanggal']);
        if (dt != null) {
          double hour = dt.hour.toDouble();
          // Jika hour adalah 0 (mungkin karena hanya simpan tanggal), 
          // coba lihat apakah ada data jam di string
          if (hour == 0 && (item['waktu'] ?? item['tanggal']) is String) {
             try {
               // Asumsi format ISO atau ada jam di belakang
               String s = (item['waktu'] ?? item['tanggal']);
               if (s.contains("T")) {
                 hour = DateTime.parse(s).hour.toDouble();
               }
             } catch(_) {}
          }
          double matang = double.tryParse(item['matang']?.toString() ?? "0") ?? 0;
          double mentah = double.tryParse(item['mentah']?.toString() ?? "0") ?? 0;
          double total = double.tryParse(item['janjang']?.toString() ?? "") ?? (matang + mentah);
          stats[hour] = (stats[hour] ?? 0) + total;
        }
      }
    }

    if (stats.isEmpty) return [];
    
    List<FlSpot> spots = stats.entries.map((e) => FlSpot(e.key, e.value)).toList();
    spots.sort((a, b) => a.x.compareTo(b.x));

    // Jika hanya ada 1 titik, tambahkan titik 0 di awal dan akhir jam kerja agar membentuk garis
    if (spots.length == 1) {
      double x = spots[0].x;
      double y = spots[0].y;
      return [
        FlSpot(x > 6 ? 6 : x - 1, 0),
        spots[0],
        FlSpot(x < 18 ? 18 : x + 1, 0),
      ];
    }

    return spots;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgGrey,
      body: kIsWeb ? webLayout() : mobileLayout(),
    );
  }

  // ================= WEB LAYOUT =================
  Widget _webViewMap() {
    return ListView(
      padding: const EdgeInsets.all(25),
      children: [
        modernCard(
          title: "Peta Sebaran Panen",
          subtitle: "Lokasi pengambilan TPH secara Real-time",
          action: Row(
            children: [
              if (filterTanggalStart != null || selectedAfdeling != null || selectedYear != null)
                IconButton(
                  icon: const Icon(Icons.filter_alt_off, size: 20, color: Colors.redAccent),
                  onPressed: _clearFilter,
                  tooltip: "Bersihkan Filter",
                ),
              _filterDropdown<String?>(
                value: selectedAfdeling,
                hint: "AFD",
                items: [
                  const DropdownMenuItem(value: null, child: Text("Semua")),
                  ...afdelings.map((a) => DropdownMenuItem(value: a, child: Text(a))),
                ],
                onChanged: (v) {
                  setState(() => selectedAfdeling = v);
                  applyFilter();
                },
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.calendar_month, size: 20, color: Color(0xFF0D47A1)),
                onPressed: _pickDate,
                tooltip: "Filter Rentang Tanggal",
              ),
            ],
          ),
          child: SizedBox(
            height: MediaQuery.of(context).size.height - 200, 
            child: mapWidget(),
          ),
        ),
      ],
    );
  }

  // ================= WEB VIEWS =================
  Widget _webViewDashboard() {
    return ListView(
      controller: _scrollController,
      padding: const EdgeInsets.all(25),
      children: [
        // FILTER & REFRESH SECTION
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              "Ringkasan Statistik",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0D47A1)),
            ),
            Row(
              children: [
                if (filterTanggalStart != null || selectedAfdeling != null || selectedYear != null)
                  IconButton(
                    onPressed: _clearFilter,
                    icon: const Icon(Icons.filter_alt_off, size: 20, color: Colors.redAccent),
                    tooltip: "Hapus Semua Filter",
                  ),
                const SizedBox(width: 8),
                
                // TOMBOL HARI INI
                OutlinedButton(
                  onPressed: () {
                    setState(() {
                      filterTanggalStart = DateTime.now();
                      filterTanggalEnd = DateTime.now();
                      selectedYear = null;
                      selectedMonth = null;
                    });
                    applyFilter();
                  },
                  style: OutlinedButton.styleFrom(
                    backgroundColor: filterTanggalStart != null && 
                                   filterTanggalStart!.day == DateTime.now().day &&
                                   filterTanggalStart!.month == DateTime.now().month &&
                                   filterTanggalStart!.year == DateTime.now().year &&
                                   filterTanggalStart == filterTanggalEnd
                                   ? primaryBlue.withValues(alpha: 0.1) : Colors.white,
                    side: BorderSide(color: Colors.grey.withValues(alpha: 0.2)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: Text("Hari Ini", style: TextStyle(color: primaryBlue, fontSize: 13)),
                ),
                const SizedBox(width: 10),

                // Dropdown Bulan
                _filterDropdown<int?>(
                  value: selectedMonth,
                  hint: "Bulan",
                  items: [
                    const DropdownMenuItem(value: null, child: Text("Semua Bulan")),
                    ...List.generate(months.length, (i) => DropdownMenuItem(value: i + 1, child: Text(months[i]))),
                  ],
                  onChanged: (v) {
                    setState(() {
                      selectedMonth = v;
                      if (v != null) {
                        filterTanggalStart = null;
                        filterTanggalEnd = null;
                      }
                    });
                    applyFilter();
                  },
                ),
                const SizedBox(width: 10),

                // Dropdown Tahun
                _filterDropdown<int?>(
                  value: selectedYear,
                  hint: "Tahun",
                  items: [
                    const DropdownMenuItem(value: null, child: Text("Semua Tahun")),
                    ...years.map((y) => DropdownMenuItem(value: y, child: Text(y.toString()))),
                  ],
                  onChanged: (v) {
                    setState(() {
                      selectedYear = v;
                      if (v != null) {
                        filterTanggalStart = null;
                        filterTanggalEnd = null;
                      }
                    });
                    applyFilter();
                  },
                ),
                const SizedBox(width: 10),

                InkWell(
                  onTap: _pickDate,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.calendar_today, size: 16, color: primaryBlue),
                        const SizedBox(width: 8),
                        Text(
                          filterTanggalStart == null 
                            ? "Rentang"
                            : "${filterTanggalStart!.day}/${filterTanggalStart!.month} - ${filterTanggalEnd!.day}/${filterTanggalEnd!.month}",
                          style: TextStyle(fontSize: 13, color: Colors.grey[800]),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                IconButton(
                  onPressed: () => loadData(),
                  icon: Icon(Icons.refresh_rounded, color: primaryBlue),
                  tooltip: "Refresh Data",
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                      side: BorderSide(color: Colors.grey.withValues(alpha: 0.2)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 20),

        // KPI CARDS
        Row(
          children: [
            kpiCard("Jumlah Laporan", data.length.toString(), "Record", Icons.assignment_rounded, accentBlue, 
                onTap: () => setState(() => _activeView = "data_panen")),
            kpiCard("Total Janjang", totalPanen.toString(), "Janjang", Icons.eco, primaryBlue, 
                onTap: () => setState(() => _activeView = "analisis")),
            kpiCard("Data PKS", totalTon.toStringAsFixed(1), "Ton", Icons.factory_rounded, Colors.blue, 
                onTap: () => setState(() => _activeView = "data_pks")),
            kpiCard("Trip Mobil", totalTrip.toString(), "Trip", Icons.local_shipping_rounded, Colors.orange,
                onTap: () => setState(() => _activeView = "trip_mobil")),
            kpiCard("Jumlah Pemanen", jumlahPemanen.toString(), "Orang", Icons.people, Colors.purple,
                onTap: () => _showPemanenDialog()),
          ],
        ),
        const SizedBox(height: 25),

        // CHARTS & SUMMARY
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: modernCard(
                title: "Analisis Produksi Harian",
                subtitle: "Statistik pergerakan hasil panen",
                child: SizedBox(height: 300, child: lineChartWidget()),
              ),
            ),
            const SizedBox(width: 20),
            Expanded(
              flex: 1,
              child: modernCard(
                title: filterTanggalStart != null && 
                       filterTanggalStart!.day == DateTime.now().day &&
                       filterTanggalStart!.month == DateTime.now().month &&
                       filterTanggalStart!.year == DateTime.now().year &&
                       filterTanggalStart == filterTanggalEnd
                       ? "Ringkasan Hari Ini" 
                       : (filterTanggalStart == null ? "Ringkasan Hari Ini" : "Ringkasan Terfilter"),
                child: dailySummaryWidget(),
              ),
            ),
          ],
        ),
        const SizedBox(height: 25),

        // MAP & ACTIVITY
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 2,
              child: modernCard(
                title: "Peta Sebaran Panen",
                subtitle: "Lokasi pengambilan TPH secara Real-time",
                action: TextButton(
                  onPressed: () => setState(() => _activeView = "map"),
                  child: Text("Lihat Full Map", style: TextStyle(color: accentBlue)),
                ),
                child: SizedBox(height: 400, child: mapWidget()),
              ),
            ),
            const SizedBox(width: 20),
            Expanded(
              flex: 1,
              child: Column(
                children: [
                  modernCard(
                    title: "🏆 Ranking Pemanen",
                    child: rankingWidget(),
                  ),
                  const SizedBox(height: 20),
                  modernCard(
                    title: "Aktivitas Terbaru",
                    child: recentActivityWidget(),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 25),
        
        // Link to Full Data
        Center(
          child: ElevatedButton(
            onPressed: () => setState(() => _activeView = "data_panen"),
            style: ElevatedButton.styleFrom(backgroundColor: primaryBlue, foregroundColor: Colors.white),
            child: const Text("Buka Semua Data Panen"),
          ),
        ),
      ],
    );
  }

  Widget _webViewDataPanen() {
    // Filter data berdasarkan search query
    List<Map<String, dynamic>> filteredBySearch = data.where((item) {
      if (searchQuery.isEmpty) return true;
      String pemanen = (item['pemanen'] ?? "").toString().toLowerCase();
      String blok = (item['blok'] ?? "").toString().toLowerCase();
      String afd = (item['afdeling'] ?? "").toString().toLowerCase();
      return pemanen.contains(searchQuery) || blok.contains(searchQuery) || afd.contains(searchQuery);
    }).toList();

    // Kelompokkan data berdasarkan Afdeling
    Map<String, List<Map<String, dynamic>>> groupedData = {};
    for (var item in filteredBySearch) {
      String afd = item['afdeling']?.toString() ?? "N/A";
      groupedData.putIfAbsent(afd, () => []).add(item);
    }
    List<String> sortedAfdelings = groupedData.keys.toList()..sort();

    return CustomScrollView(
      controller: _scrollController,
      slivers: [
        // 1. Header & Filter (Tetap di atas)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(25),
            child: _buildWebDataHeader(),
          ),
        ),

        // 2. Data Terkelompok
        if (filteredBySearch.isEmpty)
          const SliverFillRemaining(
            child: Center(child: Text("Tidak ada data ditemukan", style: TextStyle(color: Colors.grey))),
          )
        else
          ...sortedAfdelings.expand((afd) => [
            // Header Afdeling
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(30, 10, 30, 15),
                child: Row(
                  children: [
                    const Icon(Icons.folder_shared_rounded, color: Color(0xFF0D47A1), size: 20),
                    const SizedBox(width: 10),
                    Text("Afdeling $afd", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: primaryBlue)),
                    const SizedBox(width: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                      decoration: BoxDecoration(color: primaryBlue.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
                      child: Text("${groupedData[afd]!.length} Records", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: primaryBlue)),
                    ),
                  ],
                ),
              ),
            ),
            // Grid Data (Hanya render yang terlihat di layar)
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 30),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  crossAxisSpacing: 15,
                  mainAxisSpacing: 15,
                  mainAxisExtent: 180,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, index) => _dataCard(groupedData[afd]![index]),
                  childCount: groupedData[afd]!.length,
                ),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 35)),
          ]),
      ],
    );
  }

  // Pisahkan Header agar kode lebih bersih
  Widget _buildWebDataHeader() {
    return Container(
      padding: const EdgeInsets.all(25),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: cardShadow, blurRadius: 20, offset: const Offset(0, 8))],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("Monitoring Data Panen Terkini", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              Row(
                children: [
                  _filterDropdown<String?>(
                    value: selectedAfdeling,
                    hint: "Semua AFD",
                    items: [
                      const DropdownMenuItem(value: null, child: Text("Semua AFD")),
                      ...afdelings.map((a) => DropdownMenuItem(value: a, child: Text(a))),
                    ],
                    onChanged: (v) { setState(() => selectedAfdeling = v); applyFilter(); },
                  ),
                  const SizedBox(width: 8),
                  _filterDropdown<int?>(
                    value: selectedMonth,
                    hint: "Semua",
                    items: [
                      const DropdownMenuItem(value: null, child: Text("Semua")),
                      ...List.generate(12, (i) => DropdownMenuItem(value: i + 1, child: Text(months[i]))),
                    ],
                    onChanged: (v) { setState(() => selectedMonth = v); applyFilter(); },
                  ),
                  const SizedBox(width: 8),
                  _filterDropdown<int?>(
                    value: selectedYear,
                    hint: "Semua",
                    items: [
                      const DropdownMenuItem(value: null, child: Text("Semua")),
                      ...years.map((y) => DropdownMenuItem(value: y, child: Text(y.toString()))),
                    ],
                    onChanged: (v) { setState(() => selectedYear = v); applyFilter(); },
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: Icon(Icons.calendar_month, color: primaryBlue), 
                    onPressed: _pickDate
                  ),
                  const SizedBox(width: 15),
                  exportButton("PDF", const Color(0xFFEF5350), Icons.picture_as_pdf),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),
          TextField(
            onChanged: _applySearch,
            decoration: InputDecoration(
              hintText: "Cari Pemanen atau Blok...",
              prefixIcon: const Icon(Icons.search, color: Color(0xFF0D47A1)),
              filled: true,
              fillColor: bgGrey,
              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey.withValues(alpha: 0.1)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _webViewDaftarPemanen() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('harvesters').snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text("Terjadi kesalahan: ${snapshot.error}"));
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        
        final docs = snapshot.data?.docs ?? [];
        Map<String, List<String>> grouped = {};
        
        // Debugging log (hanya terlihat di konsol pengembang)
        debugPrint("DEBUG: Ditemukan ${docs.length} dokumen di koleksi 'harvesters'");

        if (docs.isNotEmpty) {
          for (var doc in docs) {
            var data = doc.data() as Map<String, dynamic>;
            // Normalisasi key Afdeling agar konsisten
            String rawAfd = (data['afdeling'] ?? "Unknown").toString().toUpperCase().replaceAll(" ", "");
            String nama = (data['nama'] ?? "Tanpa Nama").toString().trim();
            
            if (nama.isNotEmpty) {
              grouped.putIfAbsent(rawAfd, () => []).add(nama);
            }
          }
          grouped.forEach((key, value) => value.sort());
        }

        if (grouped.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.people_outline, size: 80, color: Colors.grey[300]),
                const SizedBox(height: 16),
                const Text(
                  "Database Pemanen Kosong", 
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey)
                ),
                const SizedBox(height: 8),
                Text(
                  "Ditemukan ${docs.length} data mentah di server.\nPastikan pendaftaran berhasil (ada pesan sukses).", 
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey, fontSize: 13)
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ElevatedButton.icon(
                      onPressed: () => setState(() => _activeView = "registrasi_pemanen"),
                      icon: const Icon(Icons.add),
                      label: const Text("Daftarkan Sekarang"),
                      style: ElevatedButton.styleFrom(backgroundColor: primaryBlue, foregroundColor: Colors.white),
                    ),
                    const SizedBox(width: 12),
                    OutlinedButton.icon(
                      onPressed: () => setState(() {}),
                      icon: const Icon(Icons.refresh),
                      label: const Text("Refresh"),
                    ),
                  ],
                ),
              ],
            ),
          );
        }

        var sortedAfds = grouped.keys.toList()..sort();

        return ListView(
          padding: const EdgeInsets.all(25),
          children: [
            modernCard(
              title: "Daftar Master Pemanen",
              subtitle: "Total Terdaftar: ${docs.length} Orang",
              action: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.refresh_rounded),
                    onPressed: () => setState(() {}),
                    tooltip: "Refresh Data",
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: () => setState(() => _activeView = "registrasi_pemanen"),
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text("Tambah Pemanen"),
                    style: ElevatedButton.styleFrom(backgroundColor: primaryBlue, foregroundColor: Colors.white),
                  ),
                ],
              ),
              child: Column(
                children: sortedAfds.map((afdKey) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(bottom: 15, top: 10),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: primaryBlue.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(Icons.holiday_village_rounded, color: primaryBlue, size: 20),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              "Afdeling ${afdKey.replaceAll('AFD', '')}",
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: primaryBlue),
                            ),
                            const SizedBox(width: 10),
                            Text("(${grouped[afdKey]!.length} Orang)", style: const TextStyle(color: Colors.grey, fontSize: 14)),
                          ],
                        ),
                      ),
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 4,
                          crossAxisSpacing: 15,
                          mainAxisSpacing: 15,
                          mainAxisExtent: 70,
                        ),
                        itemCount: grouped[afdKey]!.length,
                        itemBuilder: (context, index) {
                          String name = grouped[afdKey]![index];
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.grey.withOpacity(0.15)),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.02),
                                  blurRadius: 5,
                                  offset: const Offset(0, 2)
                                )
                              ],
                            ),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: 16,
                                  backgroundColor: primaryBlue.withOpacity(0.1),
                                  child: Text(
                                    name.isNotEmpty ? name[0].toUpperCase() : "?", 
                                    style: TextStyle(color: primaryBlue, fontWeight: FontWeight.bold, fontSize: 12)
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    name,
                                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 30),
                    ],
                  );
                }).toList(),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _webViewDaftarBlok() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('blocks').snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text("Terjadi kesalahan: ${snapshot.error}"));
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        
        final docs = snapshot.data?.docs ?? [];
        Map<String, List<String>> grouped = {};
        
        if (docs.isNotEmpty) {
          for (var doc in docs) {
            var data = doc.data() as Map<String, dynamic>;
            String kcs = (data['kcs'] ?? "Unknown").toString();
            String blok = (data['blok'] ?? "-").toString();
            
            grouped.putIfAbsent(kcs, () => []).add(blok);
          }
          grouped.forEach((key, value) => value.sort());
        }

        if (grouped.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.grid_off_rounded, size: 80, color: Colors.grey[300]),
                const SizedBox(height: 16),
                const Text("Database Blok Kosong", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey)),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: () => setState(() => _activeView = "registrasi_blok"),
                  icon: const Icon(Icons.add),
                  label: const Text("Daftarkan Blok"),
                  style: ElevatedButton.styleFrom(backgroundColor: primaryBlue, foregroundColor: Colors.white),
                ),
              ],
            ),
          );
        }

        var sortedKcs = grouped.keys.toList()..sort();

        return ListView(
          padding: const EdgeInsets.all(25),
          children: [
            modernCard(
              title: "Daftar Master Blok",
              subtitle: "Total Terdaftar: ${docs.length} Blok",
              action: ElevatedButton.icon(
                onPressed: () => setState(() => _activeView = "registrasi_blok"),
                icon: const Icon(Icons.add, size: 16),
                label: const Text("Tambah Blok"),
                style: ElevatedButton.styleFrom(backgroundColor: primaryBlue, foregroundColor: Colors.white),
              ),
              child: Column(
                children: sortedKcs.map((kcsKey) {
                  return ExpansionTile(
                    title: Text("KCS: $kcsKey", style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text("${grouped[kcsKey]!.length} Blok"),
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: grouped[kcsKey]!.map((blok) => Chip(
                            label: Text(blok),
                            backgroundColor: bgGrey,
                          )).toList(),
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _webViewRegistrasiPemanen() {
    return ListView(
      padding: const EdgeInsets.all(25),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: modernCard(
              title: "Pendaftaran Pemanen Baru",
              subtitle: "Tambahkan data pemanen ke dalam database pusat",
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _webFormItem("Nama Lengkap Pemanen", _namaPemanenC, Icons.person_add_alt_1),
                  const SizedBox(height: 25),
                  const Text("Afdeling Penempatan", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.blueGrey)),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                    decoration: BoxDecoration(
                      color: bgGrey,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.withValues(alpha: 0.1)),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _selectedAfdPemanen,
                        isExpanded: true,
                        hint: const Text("Pilih Afdeling (AFD)"),
                        items: afdelings.map((afd) => DropdownMenuItem(
                          value: afd, 
                          child: Text(afd, style: const TextStyle(fontSize: 14))
                        )).toList(),
                        onChanged: (v) => setState(() => _selectedAfdPemanen = v),
                      ),
                    ),
                  ),
                  const SizedBox(height: 40),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _simpanPemanen,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryBlue,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.how_to_reg_rounded),
                          SizedBox(width: 12),
                          Text("DAFTARKAN PEMANEN", style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.1)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 15),
                  Center(
                    child: TextButton(
                      onPressed: () => setState(() => _activeView = "daftar_pemanen"),
                      child: Text("Lihat Daftar Pemanen Terdaftar", style: TextStyle(color: accentBlue)),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Center(
                    child: TextButton.icon(
                      onPressed: _importDataPemanenDefault,
                      icon: const Icon(Icons.download_rounded, size: 18),
                      label: const Text("IMPORT PEMANEN DEFAULT"),
                      style: TextButton.styleFrom(foregroundColor: Colors.grey),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _webViewLaporan() {
    return LaporanPanenPage(
      tanggal: DateTime.now().toString().split(" ")[0],
      isWebView: true,
      initialAfdeling: selectedAfdeling,
      initialStartDate: filterTanggalStart,
      initialEndDate: filterTanggalEnd,
      initialMonth: selectedMonth,
      initialYear: selectedYear,
      preloadedPanen: allData,
      preloadedPks: allPksData,
      preloadedTrips: allTripsData,
    );
  }

  Widget _webViewPks() {
    return RiwayatPksPage(
      initialDate: filterTanggalStart,
      initialMonth: selectedMonth,
      initialYear: selectedYear,
      initialAfdeling: selectedAfdeling,
    );
  }

  Widget _webViewTrip() {
    return RiwayatTripPage(
      isGlobal: true,
      initialDate: filterTanggalStart,
      initialMonth: selectedMonth,
      initialYear: selectedYear,
      initialAfdeling: selectedAfdeling,
    );
  }

  Widget _webViewAnalisis() {
    return AnalisisProduksiPage(isWebView: true, laporanPanen: allData);
  }

  Widget webLayout() {
    return Row(
      children: [
        // SIDEBAR
        sidebarWidget(),

        // MAIN CONTENT
        Expanded(
          child: Column(
            children: [
              topBarWidget(),
              Expanded(
                child: isLoading
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            CircularProgressIndicator(color: primaryBlue),
                            const SizedBox(height: 16),
                            const Text("Sinkronisasi Data..."),
                          ],
                        ),
                      )
                    : KeyedSubtree(
                        key: ValueKey(_activeView),
                        child: _buildCurrentWebView(),
                      ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCurrentWebView() {
    switch (_activeView) {
      case "map":
        return _webViewMap();
      case "data_panen":
        return _webViewDataPanen();
      case "registrasi_pemanen":
        return _webViewRegistrasiPemanen();
      case "registrasi_blok":
        return _webViewRegistrasiBlok();
      case "daftar_blok":
        return _webViewDaftarBlok();
      case "daftar_pemanen":
        return _webViewDaftarPemanen();
      case "profile":
        return _webViewProfile();
      case "sync":
        return _webViewSync();
      case "laporan":
        return _webViewLaporan();
      case "data_pks":
        return _webViewPks();
      case "trip_mobil":
        return _webViewTrip();
      case "analisis":
        return _webViewAnalisis();
      case "user_mgmt":
        return _webViewUserMgmt();
      case "settings":
        return _webViewSettings();
      case "reset_sistem":
        return _webViewResetSistem();
      case "dashboard":
      default:
        return _webViewDashboard();
    }
  }

  Widget _webViewUserMgmt() {
    return const UserManagementPage(isWebView: true);
  }

  Widget _webViewSettings() {
    return const PengaturanPage(isWebView: true);
  }

  // ================= WIDGETS =================

  Widget sidebarWidget() {
    return Container(
      width: 260,
      color: primaryBlue,
      child: Column(
        children: [
          const SizedBox(height: 40),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                // LOGO PROFIL (DINAMIS)
                Container(
                  width: 45,
                  height: 45,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      )
                    ],
                  ),
                  child: ClipOval(
                    child: _buildProfileImageWidget(45),
                  ),
                ),
                const SizedBox(width: 12),
                const Text("HARVESTTRACK",
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18, letterSpacing: 1.2)),
              ],
            ),
          ),
          const SizedBox(height: 40),
          Expanded(
            child: ListView(
              children: [
                _sidebarItem(Icons.dashboard_rounded, "Dashboard", active: _activeView == "dashboard", onTap: () {
                  setState(() {
                    _activeView = "dashboard";
                    // Scroll ke atas jika kembali ke dashboard
                    if (_scrollController.hasClients) {
                      _scrollController.animateTo(0, duration: const Duration(milliseconds: 500), curve: Curves.easeInOut);
                    }
                  });
                }),
                _sidebarItem(Icons.person_rounded, "Profil Saya", active: _activeView == "profile", onTap: () {
                  setState(() => _activeView = "profile");
                }),
                _sidebarItem(Icons.assignment_rounded, "Data Panen", active: _activeView == "data_panen", onTap: () {
                  setState(() => _activeView = "data_panen");
                }),
                _sidebarItem(Icons.people_alt_rounded, "Daftar Pemanen", active: _activeView == "daftar_pemanen", onTap: () {
                  setState(() => _activeView = "daftar_pemanen");
                }),
                _sidebarItem(Icons.grid_view_rounded, "Daftar Blok", active: _activeView == "daftar_blok", onTap: () {
                  setState(() => _activeView = "daftar_blok");
                }),
                _sidebarItem(Icons.factory_rounded, "Data PKS", active: _activeView == "data_pks", onTap: () {
                  setState(() => _activeView = "data_pks");
                }),
                _sidebarItem(Icons.local_shipping_rounded, "Data Trip Mobil", active: _activeView == "trip_mobil", onTap: () {
                  setState(() => _activeView = "trip_mobil");
                }),
                _sidebarItem(Icons.map_rounded, "Peta Sebaran Panen", active: _activeView == "map", onTap: () {
                  setState(() => _activeView = "map");
                }),
                _sidebarItem(Icons.bar_chart_rounded, "Analisis Produksi", active: _activeView == "analisis", onTap: () {
                  setState(() => _activeView = "analisis");
                }),
                _sidebarItem(Icons.sync_rounded, "Sinkronisasi", active: _activeView == "sync", onTap: () {
                  setState(() => _activeView = "sync");
                }),
                _sidebarItem(Icons.description_rounded, "Laporan Panen", active: _activeView == "laporan", onTap: () {
                  setState(() => _activeView = "laporan");
                }),
                _sidebarItem(Icons.manage_accounts_rounded, "Manajemen User", active: _activeView == "user_mgmt", onTap: () {
                  setState(() => _activeView = "user_mgmt");
                }),
                _sidebarItem(Icons.settings_rounded, "Pengaturan", active: _activeView == "settings", onTap: () {
                  setState(() => _activeView = "settings");
                }),
                const Divider(color: Colors.white10),
                _sidebarItem(Icons.delete_sweep_rounded, "Reset Sistem", active: _activeView == "reset_sistem", onTap: () {
                  setState(() => _activeView = "reset_sistem");
                }),
              ],
            ),
          ),
          _sidebarItem(Icons.logout_rounded, "Logout", onTap: () async {
            await UserHelper.logout();
            if (mounted) {
              Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginPage()));
            }
          }),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget topBarWidget() {
    return Container(
      height: 75,
      padding: const EdgeInsets.symmetric(horizontal: 30),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey.withValues(alpha: 0.1))),
      ),
      child: Row(
        children: [
          const Text("Sistem Monitoring Panen", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
          const Spacer(),
          IconButton(onPressed: () {}, icon: const Icon(Icons.notifications_none_rounded, color: Colors.grey)),
          const SizedBox(width: 20),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(color: bgGrey, borderRadius: BorderRadius.circular(30)),
            child: InkWell(
              onTap: () => setState(() => _activeView = "profile"),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: primaryBlue,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 1.5),
                    ),
                    child: ClipOval(
                      child: _buildProfileImageWidget(32),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_namaC.text.isNotEmpty ? _namaC.text : "Admin Perkebunan", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      Text(_jabatanC.text.isNotEmpty ? _jabatanC.text : "Super Admin", style: const TextStyle(fontSize: 11, color: Colors.grey)),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget kpiCard(String title, String value, String unit, IconData icon, Color color, {VoidCallback? onTap}) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          margin: const EdgeInsets.only(right: 15),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [BoxShadow(color: cardShadow, blurRadius: 15, offset: const Offset(0, 5))],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(height: 15),
              Text(title, style: const TextStyle(color: Colors.grey, fontSize: 13, fontWeight: FontWeight.w500)),
              const SizedBox(height: 5),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                  const SizedBox(width: 5),
                  Text(unit, style: const TextStyle(color: Colors.grey, fontSize: 12)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _webViewProfile() {
    return ListView(
      padding: const EdgeInsets.all(25),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Left Side: Profile Photo Card
            Expanded(
              flex: 1,
              child: modernCard(
                title: "Foto Profil",
                child: Column(
                  children: [
                    Center(
                      child: Stack(
                        children: [
                          Container(
                            width: 150,
                            height: 150,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.grey.withValues(alpha: 0.1), width: 4),
                              color: bgGrey,
                            ),
                            child: ClipOval(
                              child: _buildProfileImageWidget(150),
                            ),
                          ),
                          Positioned(
                            bottom: 5,
                            right: 5,
                            child: InkWell(
                              onTap: _pickWebFoto,
                              child: CircleAvatar(
                                radius: 18,
                                backgroundColor: primaryBlue,
                                child: const Icon(Icons.camera_alt, color: Colors.white, size: 18),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 25),
                    Text(_username.isNotEmpty ? "@$_username" : "Admin", 
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                    const SizedBox(height: 4),
                    Text(_jabatanC.text.isNotEmpty ? _jabatanC.text.toUpperCase() : "SUPER ADMIN", 
                      style: const TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.1)),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 25),
            // Right Side: Form Card
            Expanded(
              flex: 2,
              child: modernCard(
                title: "Informasi Profil",
                subtitle: "Perbarui informasi akun Anda di sini",
                child: Column(
                  children: [
                    _webFormItem("Nama Lengkap", _namaC, Icons.person_outline_rounded),
                    const SizedBox(height: 20),
                    _webFormItem("Jabatan / Role", _jabatanC, Icons.badge_outlined),
                    const SizedBox(height: 35),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: _simpanProfile,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primaryBlue,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.save_rounded, size: 20),
                            SizedBox(width: 10),
                            Text("SIMPAN PERUBAHAN", style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.1)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _webViewSync() {
    // Di Web Admin, kita asumsikan data yang sudah masuk ke list allData (dari Firebase) adalah Synced
    int totalSynced = allData.length;
    int totalOffline = 0; // Di web tidak ada data offline lokal

    return ListView(
      padding: const EdgeInsets.all(25),
      children: [
        modernCard(
          title: "Status Sinkronisasi Data",
          subtitle: "Pantau integritas data antara aplikasi mobile dan server",
          action: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(color: Colors.blue.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
            child: Row(
              children: [
                const Icon(Icons.info_outline, size: 16, color: Colors.blue),
                const SizedBox(width: 8),
                const Text("Mode Monitor", style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold, fontSize: 12)),
              ],
            ),
          ),
          child: Column(
            children: [
              // Statistics Cards
              Row(
                children: [
                  _syncStatCard("Total Data Masuk", "$totalSynced", "Data yang telah berhasil disimpan dan aman di database pusat.", primaryBlue),
                  const SizedBox(width: 20),
                  _syncStatCard("Status Sistem", "ONLINE", "Koneksi ke server Firebase Firestore aktif.", Colors.blue),
                ],
              ),
              const SizedBox(height: 30),
              
              // Information Box
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: bgGrey,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.withValues(alpha: 0.1)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.help_center_rounded, color: Color(0xFF0D47A1), size: 24),
                    const SizedBox(width: 15),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text("Apa fungsi halaman ini untuk Admin?", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                          const SizedBox(height: 8),
                          const Text(
                            "Sebagai Admin, Anda menggunakan halaman ini untuk memantau kelancaran pengiriman data dari lapangan. "
                            "Jika angka 'Menunggu Sinkronisasi' terlalu tinggi, ini menandakan petugas di lapangan (KCS/Pemanen) "
                            "mungkin mengalami kendala jaringan atau lupa menekan tombol sinkron di aplikasi mereka.",
                            style: TextStyle(color: Colors.blueGrey, fontSize: 13, height: 1.5),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            "⚠️ Catatan: Admin Web hanya bersifat memantau. Proses sinkronisasi fisik tetap dilakukan oleh petugas melalui aplikasi mobile.",
                            style: TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 20),
                          const Divider(),
                          const SizedBox(height: 10),
                          const Text(
                            "Tindakan Berbahaya",
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.red),
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            "Jika sistem perlu dikosongkan untuk musim panen baru atau alasan teknis lainnya, Anda dapat melakukan Reset Data. "
                            "Tindakan ini AKAN MENGHAPUS SEMUA DATA TRANSAKSI DAN MASTER dari database cloud secara permanen.",
                            style: TextStyle(color: Colors.grey, fontSize: 12),
                          ),
                          const SizedBox(height: 15),
                          ElevatedButton.icon(
                            onPressed: _confirmFullReset,
                            icon: const Icon(Icons.warning_amber_rounded),
                            label: const Text("RESET SISTEM (HAPUS SEMUA DATA)"),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                              foregroundColor: Colors.white,
                              elevation: 0,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 30),
              
              // Recent Unsynced List (Mini)
              if (totalOffline > 0) ...[
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text("Data Terakhir Belum Sinkron", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                ),
                const SizedBox(height: 15),
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: allData.where((e) => (e['sync_status'] ?? 'offline') != 'synced').take(5).length,
                  itemBuilder: (context, index) {
                    var items = allData.where((e) => (e['sync_status'] ?? 'offline') != 'synced').toList();
                    var item = items[index];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border.all(color: Colors.orange.withValues(alpha: 0.2)),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.cloud_off_rounded, color: Colors.orange, size: 20),
                          const SizedBox(width: 15),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text("Blok ${item['blok']} - ${item['pemanen']}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                Text(item['tanggal'] ?? "-", style: const TextStyle(fontSize: 11, color: Colors.grey)),
                              ],
                            ),
                          ),
                          const Text("OFFLINE", style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 10)),
                        ],
                      ),
                    );
                  },
                ),
              ] else 
                Center(
                  child: Column(
                    children: [
                      const SizedBox(height: 40),
                          Icon(Icons.cloud_done_rounded, size: 60, color: primaryBlue.withValues(alpha: 0.3)),
                      const SizedBox(height: 15),
                      const Text("Semua data telah tersinkronisasi dengan baik.", style: TextStyle(color: Colors.grey)),
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _syncStatCard(String title, String value, String desc, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: color.withValues(alpha: 0.1)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(title, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 14)),
                Icon(color == primaryBlue ? Icons.cloud_done : Icons.cloud_off, color: color, size: 20),
              ],
            ),
            const SizedBox(height: 15),
            Text(value, style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Text(desc, style: const TextStyle(color: Colors.blueGrey, fontSize: 12, height: 1.4)),
          ],
        ),
      ),
    );
  }

  Widget _webFormItem(String label, TextEditingController controller, IconData icon) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.blueGrey)),
        const SizedBox(height: 10),
        TextField(
          controller: controller,
          decoration: InputDecoration(
            prefixIcon: Icon(icon, color: primaryBlue, size: 20),
            filled: true,
            fillColor: bgGrey,
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.withValues(alpha: 0.1)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: primaryBlue, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }

  Widget modernCard({Key? key, required String title, String? subtitle, required Widget child, Widget? action}) {
    return Container(
      key: key,
      padding: const EdgeInsets.all(25),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: cardShadow, blurRadius: 20, offset: const Offset(0, 8))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  if (subtitle != null) ...[
                    const SizedBox(height: 4),
                    Text(subtitle, style: const TextStyle(fontSize: 13, color: Colors.grey)),
                  ],
                ],
              ),
              if (action != null) action,
            ],
          ),
          const SizedBox(height: 25),
          child,
        ],
      ),
    );
  }

  Widget lineChartWidget() {
    if (chartSpots.isEmpty || (chartSpots.length == 1 && chartSpots[0].x == 0 && chartSpots[0].y == 0)) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.bar_chart_rounded, size: 40, color: Colors.grey),
            SizedBox(height: 10),
            Text("Tidak ada data untuk grafik", style: TextStyle(color: Colors.grey)),
          ],
        )
      );
    }

    double maxX = chartSpots.last.x;
    double minX = chartSpots.first.x;
    
    // Pastikan rentang X cukup untuk ditampilkan
    if (maxX == minX) {
      maxX += 1;
      minX -= 1;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth <= 0 || constraints.maxHeight <= 0) {
          return const Center(child: CircularProgressIndicator());
        }
        
        // Tentukan batas sumbu X agar grafik terlihat proposional
        double minXVal = selectedYear != null && selectedMonth == null ? 1 : (selectedMonth != null ? 1 : 6); // Jam mulai 6 pagi
        double maxXVal = selectedYear != null && selectedMonth == null ? 12 : (selectedMonth != null ? 31 : 18); // Jam selesai 6 sore
        
        // Jika ada data di luar batas default, sesuaikan
        for (var spot in chartSpots) {
          if (spot.x < minXVal) minXVal = spot.x;
          if (spot.x > maxXVal) maxXVal = spot.x;
        }

        return LineChart(
          LineChartData(
            minX: minXVal,
            maxX: maxXVal,
            minY: 0,
            lineTouchData: LineTouchData(
              touchTooltipData: LineTouchTooltipData(
                getTooltipColor: (touchedSpot) => primaryBlue,
                getTooltipItems: (List<LineBarSpot> touchedBarSpots) {
                  return touchedBarSpots.map((barSpot) {
                    return LineTooltipItem(
                      "${barSpot.y.toInt()} Janjang",
                      const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    );
                  }).toList();
                },
              ),
            ),
            gridData: FlGridData(
              show: true, 
              drawVerticalLine: false, 
              getDrawingHorizontalLine: (value) => FlLine(color: Colors.grey.withValues(alpha: 0.1), strokeWidth: 1)
            ),
            titlesData: FlTitlesData(
              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true, 
                  reservedSize: 40,
                  getTitlesWidget: (value, meta) {
                    return Text(value.toInt().toString(), style: const TextStyle(fontSize: 10, color: Colors.grey));
                  }
                )
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true, 
                  reservedSize: 30,
                  interval: selectedYear != null && selectedMonth == null ? 1 : (selectedMonth != null ? 5 : 4),
                  getTitlesWidget: (value, meta) {
                    if (selectedYear != null && selectedMonth == null) {
                      if (value < 1 || value > 12) return const SizedBox();
                      List<String> shortMonths = ["Jan", "Feb", "Mar", "Apr", "Mei", "Jun", "Jul", "Ags", "Sep", "Okt", "Nov", "Des"];
                      return Text(shortMonths[value.toInt() - 1], style: const TextStyle(fontSize: 10, color: Colors.grey));
                    } else if (selectedMonth != null) {
                      return Text("${value.toInt()}", style: const TextStyle(fontSize: 10, color: Colors.grey));
                    } else {
                      return Text("${value.toInt().toString().padLeft(2, '0')}:00", style: const TextStyle(fontSize: 10, color: Colors.grey));
                    }
                  }
                )
              ),
            ),
            borderData: FlBorderData(show: false),
            lineBarsData: [
              LineChartBarData(
                spots: chartSpots,
                isCurved: true,
                color: accentBlue,
                barWidth: 4,
                isStrokeCapRound: true,
                dotData: FlDotData(
                  show: true,
                  getDotPainter: (spot, percent, barData, index) => FlDotCirclePainter(
                    radius: 4,
                    color: Colors.white,
                    strokeWidth: 2,
                    strokeColor: accentBlue,
                  ),
                ),
                belowBarData: BarAreaData(
                  show: true, 
                  gradient: LinearGradient(
                    begin: Alignment.topCenter, 
                    end: Alignment.bottomCenter, 
                    colors: [accentBlue.withValues(alpha: 0.2), accentBlue.withValues(alpha: 0.0)]
                  )
                ),
              ),
            ],
          ),
        );
      }
    );
  }

  Widget dailySummaryWidget() {
    // Menghitung ringkasan berdasarkan data yang sudah terfilter (data)
    int countLaporan = data.length;
    int totalJanjang = 0;
    for (var item in data) {
      totalJanjang += int.tryParse(item['matang']?.toString() ?? "0") ?? 0;
    }
    
    // Menghitung rata-rata kg per janjang
    double avgKg = totalJanjang > 0 ? (totalTon * 1000) / totalJanjang : 0.0;

    return Column(
      children: [
        _summaryItem("Total Laporan", "$countLaporan", Icons.assignment_outlined, Colors.blue),
        _summaryItem("Total Janjang", "$totalJanjang", Icons.wb_sunny_outlined, Colors.orange),
        _summaryItem("Jumlah Trip", "$totalTrip", Icons.local_shipping_outlined, const Color(0xFF1976D2)),
        _summaryItem("Rata-rata/Janjang", "${avgKg.toStringAsFixed(1)} Kg", Icons.analytics_outlined, Colors.purple),
      ],
    );
  }

  Widget _summaryItem(String label, String value, IconData icon, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Text(label, style: const TextStyle(fontSize: 14, color: Colors.black87, fontWeight: FontWeight.w500)),
          ),
          Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget mapWidget() {
    if (data.isEmpty) {
      return const Center(child: Text("Tidak ada data lokasi"));
    }

    List<Marker> markers = [];
    double avgLat = 0;
    double avgLng = 0;
    int validCount = 0;

    for (var item in data) {
      double? lat;
      double? lng;

      // 1. Coba deteksi jika data adalah GeoPoint (Firebase)
      if (item['location'] != null && item['location'] is GeoPoint) {
        lat = (item['location'] as GeoPoint).latitude;
        lng = (item['location'] as GeoPoint).longitude;
      } 
      // 2. Coba deteksi dari berbagai variasi nama field (String/Double)
      else {
        var latVal = item['latitude'] ?? item['lat'] ?? item['Latitude'] ?? item['gps_lat'];
        var lngVal = item['longitude'] ?? item['lng'] ?? item['Longitude'] ?? item['gps_lng'];
        lat = double.tryParse(latVal?.toString() ?? "");
        lng = double.tryParse(lngVal?.toString() ?? "");
      }
      
      // Validasi koordinat (menghindari angka 0 atau kosong)
      if (lat != null && lng != null && lat != 0 && lng != 0) {
        avgLat += lat;
        avgLng += lng;
        validCount++;

        int janjang = (int.tryParse(item['matang']?.toString() ?? "0") ?? 0) + 
                      (int.tryParse(item['mentah']?.toString() ?? "0") ?? 0);
        
        // Warna Marker: Merah untuk hasil tinggi, Hijau untuk normal
        Color markerColor = janjang > 50 ? Colors.red : (janjang > 20 ? Colors.orange : primaryBlue);

        markers.add(
          Marker(
            point: LatLng(lat, lng),
            width: 50,
            height: 50,
            child: GestureDetector(
              onTap: () => _showMarkerDetail(item),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Efek bayangan/glow agar terlihat jelas di web
                  Icon(Icons.location_on, color: markerColor.withValues(alpha: 0.3), size: 45),
                  Icon(Icons.location_on, color: markerColor, size: 38),
                  // Icon putih kecil di tengah agar lebih premium
                  const Positioned(
                    top: 10,
                    child: Icon(Icons.circle, color: Colors.white, size: 10),
                  ),
                ],
              ),
            ),
          ),
        );
      }
    }

    if (markers.isEmpty) {
      return const Center(child: Text("Data tidak memiliki koordinat valid untuk ditampilkan"));
    }

    // Hitung titik tengah otomatis
    LatLng center = LatLng(avgLat / validCount, avgLng / validCount);

    return ClipRRect(
      borderRadius: BorderRadius.circular(15),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth <= 0 || constraints.maxHeight <= 0) {
            return const Center(child: CircularProgressIndicator());
          }
          
          return FlutterMap(
            options: MapOptions(
              initialCenter: center, 
              initialZoom: 13,
              interactionOptions: const InteractionOptions(flags: InteractiveFlag.all),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.harvesttrack.app',
              ),
              MarkerLayer(markers: markers),
            ],
          );
        }
      ),
    );
  }

  void _showMarkerDetail(Map<String, dynamic> item) {
    int matang = int.tryParse(item['matang']?.toString() ?? "0") ?? 0;
    int mentah = int.tryParse(item['mentah']?.toString() ?? "0") ?? 0;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.person_pin_circle, color: Color(0xFF0D47A1)),
            const SizedBox(width: 10),
            const Text("Rincian Pemanen", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _rincianRow("Nama Pemanen", item['pemanen'] ?? "-", isBold: true),
            _rincianRow("Afdeling", item['afdeling'] ?? "-"),
            _rincianRow("Blok", item['blok'] ?? "-"),
            const Divider(),
            _rincianRow("Janjang Matang", "$matang Jjg", valueColor: primaryBlue),
            _rincianRow("Janjang Mentah", "$mentah Jjg", valueColor: Colors.red),
            _rincianRow("Brondolan", "${item['brondolan'] ?? 0} Kg"),
            _rincianRow("Waktu", item['waktu'] ?? item['tanggal'] ?? "-"),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Tutup")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: primaryBlue, foregroundColor: Colors.white),
            onPressed: () {
              Navigator.pop(context);
              _navigate(DetailPanenPage(data: item, isReadOnly: true));
            },
            child: const Text("Lihat Full Detail"),
          ),
        ],
      ),
    );
  }

  Widget _rincianRow(String label, String value, {bool isBold = false, Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 13)),
          Text(value, style: TextStyle(
            fontWeight: isBold ? FontWeight.bold : FontWeight.w600, 
            fontSize: 13,
            color: valueColor ?? Colors.black87
          )),
        ],
      ),
    );
  }

  Widget rankingWidget() {
    if (pemanenRanking.isEmpty) {
      return const Center(child: Text("Tidak ada data pemanen", style: TextStyle(fontSize: 12, color: Colors.grey)));
    }
    return Column(
      children: pemanenRanking.asMap().entries.map((entry) {
        int idx = entry.key;
        var item = entry.value;
        return InkWell(
          onTap: () => _navigate(DetailPemanenPage(nama: item['nama'], isWebView: true)),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 12,
                  backgroundColor: idx == 0 ? Colors.amber : (idx == 1 ? Colors.grey[300] : (idx == 2 ? Colors.orange[300] : primaryBlue.withValues(alpha: 0.2))),
                  child: Text("${idx + 1}", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: idx == 0 ? Colors.white : Colors.black87)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(item['nama'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                            decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(4)),
                            child: Text(item['afdeling'], style: TextStyle(fontSize: 9, color: Colors.grey[600], fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      LinearProgressIndicator(
                        value: item['janjang'] / (pemanenRanking[0]['janjang'] > 0 ? pemanenRanking[0]['janjang'] : 1),
                        backgroundColor: Colors.grey[200],
                        color: accentBlue,
                        minHeight: 4,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Text("${item['janjang']} Jjg", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF0D47A1))),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget recentActivityWidget() {
    List<Map<String, dynamic>> activities = [];

    // Ambil 10 panen terbaru untuk diseleksi
    for (var item in allData.take(10)) {
      int mentah = int.tryParse(item['mentah']?.toString() ?? "0") ?? 0;
      String timeStr = item['waktu'] ?? item['tanggal'] ?? "";
      
      if (mentah > 5) {
        activities.add({
          'title': "Peringatan",
          'desc': "Banyak buah mentah ($mentah Jjg) di Blok ${item['blok']}",
          'time': _formatActivityTime(timeStr),
          'color': Colors.red,
          'rawTime': timeStr,
        });
      }

      activities.add({
        'title': "Panen Baru",
        'desc': "${item['pemanen'] ?? 'Pemanen'} kirim data Blok ${item['blok'] ?? '-'}",
        'time': _formatActivityTime(timeStr),
        'color': primaryBlue,
        'rawTime': timeStr,
      });
    }

    // Ambil 10 trip PKS terbaru
    for (var item in allPksData.take(10)) {
      String timeStr = item['waktu_timbang']?.toString() ?? item['tanggal']?.toString() ?? "";
      activities.add({
        'title': "Trip Selesai",
        'desc': "Truk #${item['trip_id'] ?? item['no_tiket'] ?? 'ID'} tiba di ${item['pks_nama'] ?? 'PKS'}",
        'time': _formatActivityTime(timeStr),
        'color': Colors.green,
        'rawTime': timeStr,
      });
    }

    // Urutkan berdasarkan waktu terbaru (rawTime)
    activities.sort((a, b) {
      String timeA = a['rawTime']?.toString() ?? "";
      String timeB = b['rawTime']?.toString() ?? "";
      return timeB.compareTo(timeA);
    });
    
    // Batasi 6 aktivitas saja yang tampil
    var displayActivities = activities.take(6).toList();

    if (displayActivities.isEmpty) {
      return const Center(child: Padding(
        padding: EdgeInsets.all(20),
        child: Text("Belum ada aktivitas", style: TextStyle(color: Colors.grey, fontSize: 12)),
      ));
    }

    return Column(
      children: displayActivities.map((act) => 
        _activityItem(act['title'], act['desc'], act['time'], act['color'])
      ).toList(),
    );
  }

  String _formatActivityTime(String dateTimeStr) {
    try {
      DateTime dt = DateTime.parse(dateTimeStr);
      DateTime now = DateTime.now();
      if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
        return "${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";
      } else if (dt.year == now.year && dt.month == now.month && dt.day == now.day - 1) {
        return "Kemarin";
      } else {
        return "${dt.day}/${dt.month}";
      }
    } catch (e) {
      return "-";
    }
  }

  Widget _activityItem(String title, String desc, String time, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 15),
      child: Row(
        children: [
          Container(width: 4, height: 40, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                Text(desc, style: const TextStyle(color: Colors.grey, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          Text(time, style: const TextStyle(color: Colors.grey, fontSize: 10)),
        ],
      ),
    );
  }

  Widget dataTableWidget() {
    if (data.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(40.0),
          child: Text("Tidak ada data panen tersedia", style: TextStyle(color: Colors.grey)),
        ),
      );
    }

    return Column(
      children: [
    // Header Row Modern (Background Biru Tipis Sesuai Tema)
    Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFE3F2FD),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(flex: 5, child: _headerText("Tanggal")),
          Expanded(flex: 3, child: _headerText("Pemanen")),
          Expanded(flex: 1, child: _headerText("Blok")),
          Expanded(flex: 2, child: _headerText("Afdeling")),
          Expanded(flex: 2, child: _headerText("Matang")),
          Expanded(flex: 2, child: _headerText("Mentah")),
          Expanded(flex: 3, child: _headerText("Status")),
          Expanded(flex: 1, child: _headerText("Aksi")),
        ],
      ),
    ),
    const SizedBox(height: 5),
    // Data Rows
    ...data.take(20).map((item) {
      return InkWell(
        onTap: () => _navigate(DetailPanenPage(data: item, isReadOnly: true)),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 10),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: Colors.grey.withValues(alpha: 0.1), width: 1)),
          ),
          child: Row(
            children: [
              Expanded(flex: 5, child: _dataText(item['tanggal']?.toString() ?? "-", fontSize: 11)),
              Expanded(flex: 3, child: _dataText(item['pemanen']?.toString() ?? "-", isBold: true)),
              Expanded(flex: 1, child: _dataText(item['blok']?.toString() ?? "-")),
              Expanded(flex: 2, child: _dataText(item['afdeling']?.toString() ?? "-")),
              Expanded(flex: 2, child: _dataText(item['matang']?.toString() ?? "0", color: primaryBlue, isBold: true)),
              Expanded(flex: 2, child: _dataText(item['mentah']?.toString() ?? "0", color: const Color(0xFFEF5350), isBold: true)),
              Expanded(
                flex: 3,
                child: Center(child: statusBadge(item['sync_status'] ?? "OFFLINE")),
              ),
              Expanded(
                flex: 1,
                child: PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, size: 20, color: Colors.grey),
                  onSelected: (val) {
                    if (val == 'edit') {
                      _navigate(input.InputPanenPage(data: item));
                    } else if (val == 'delete') {
                      _deleteData('panen', item['id_firebase']);
                    }
                  },
                  itemBuilder: (ctx) => [
                    const PopupMenuItem(value: 'edit', child: Row(children: [Icon(Icons.edit, size: 18), SizedBox(width: 8), Text("Edit")])),
                    const PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete, size: 18, color: Colors.red), SizedBox(width: 8), Text("Hapus", style: TextStyle(color: Colors.red))])),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }),
  ],
);
}

  Widget _headerText(String text) {
    return Text(
      text,
      textAlign: TextAlign.center,
      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.black87),
    );
  }

  Widget _dataText(String text, {bool isBold = false, Color? color, double? fontSize}) {
    return Text(
      text,
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: fontSize ?? 12,
        fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
        color: color ?? Colors.black87,
      ),
    );
  }

  Widget statusBadge(String status) {
    String s = status.toUpperCase();
    Color color = Colors.grey;
    IconData icon = Icons.info_outline;

    if (s == "PENDING") {
      color = Colors.orange;
      icon = Icons.access_time_rounded;
    } else if (s == "ACC" || s == "SYNCED" || s == "TERKIRIM" || s == "ONLINE") {
      color = Colors.green;
      icon = Icons.check_circle_rounded;
    } else if (s == "REJECT") {
      color = Colors.red;
      icon = Icons.cancel_rounded;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            s,
            style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget webDataSection() {
    // Filter data berdasarkan search query
    List<Map<String, dynamic>> filteredBySearch = data.where((item) {
      if (searchQuery.isEmpty) return true;
      String pemanen = (item['pemanen'] ?? "").toString().toLowerCase();
      String blok = (item['blok'] ?? "").toString().toLowerCase();
      String afd = (item['afdeling'] ?? "").toString().toLowerCase();
      return pemanen.contains(searchQuery) || blok.contains(searchQuery) || afd.contains(searchQuery);
    }).toList();

    // Kelompokkan data berdasarkan Afdeling
    Map<String, List<Map<String, dynamic>>> groupedData = {};
    for (var item in filteredBySearch) {
      String afd = item['afdeling']?.toString() ?? "N/A";
      groupedData.putIfAbsent(afd, () => []).add(item);
    }
    List<String> sortedAfdelings = groupedData.keys.toList()..sort();

    return Column(
      key: _monitoringKey,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header Card for Title and Filters
        Container(
          padding: const EdgeInsets.all(25),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [BoxShadow(color: cardShadow, blurRadius: 20, offset: const Offset(0, 8))],
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("Monitoring Data Panen Terkini", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  Row(
                    children: [
                      _filterDropdown<String?>(
                        value: selectedAfdeling,
                        hint: "Semua AFD",
                        items: [
                          const DropdownMenuItem(value: null, child: Text("Semua AFD")),
                          ...afdelings.map((a) => DropdownMenuItem(value: a, child: Text(a))),
                        ],
                        onChanged: (v) { setState(() => selectedAfdeling = v); applyFilter(); },
                      ),
                      const SizedBox(width: 8),
                      _filterDropdown<int?>(
                        value: selectedMonth,
                        hint: "Semua",
                        items: [
                          const DropdownMenuItem(value: null, child: Text("Semua")),
                          ...List.generate(12, (i) => DropdownMenuItem(value: i + 1, child: Text(months[i]))),
                        ],
                        onChanged: (v) { setState(() => selectedMonth = v); applyFilter(); },
                      ),
                      const SizedBox(width: 8),
                      _filterDropdown<int?>(
                        value: selectedYear,
                        hint: "Semua",
                        items: [
                          const DropdownMenuItem(value: null, child: Text("Semua")),
                          ...years.map((y) => DropdownMenuItem(value: y, child: Text(y.toString()))),
                        ],
                        onChanged: (v) { setState(() => selectedYear = v); applyFilter(); },
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: Icon(Icons.calendar_month, color: primaryBlue), 
                        onPressed: _pickDate
                      ),
                      const SizedBox(width: 15),
                      exportButton("PDF", const Color(0xFFEF5350), Icons.picture_as_pdf),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 20),
              // Search Bar
              TextField(
                onChanged: _applySearch,
                decoration: InputDecoration(
                  hintText: "Cari Pemanen atau Blok...",
                  prefixIcon: const Icon(Icons.search, color: Color(0xFF0D47A1)),
                  filled: true,
                  fillColor: bgGrey,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey.withValues(alpha: 0.1)),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 25),

        // Grid Content Grouped by Afdeling
        if (filteredBySearch.isEmpty)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(40.0),
              child: Text("Tidak ada data ditemukan", style: TextStyle(color: Colors.grey)),
            ),
          )
        else
          ...sortedAfdelings.map((afd) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 5, bottom: 15),
                child: Row(
                  children: [
                    const Icon(Icons.folder_shared_rounded, color: Color(0xFF0D47A1), size: 20),
                    const SizedBox(width: 10),
                    Text("Afdeling $afd", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: primaryBlue)),
                    const SizedBox(width: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                      decoration: BoxDecoration(color: primaryBlue.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
                      child: Text("${groupedData[afd]!.length} Records", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: primaryBlue)),
                    ),
                  ],
                ),
              ),
              dataGridWidget(groupedData[afd]!),
              const SizedBox(height: 35),
            ],
          )),
      ],
    );
  }

  Widget dataGridWidget(List<Map<String, dynamic>> displayData) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4, // Lebih banyak kolom untuk tampilan web
        crossAxisSpacing: 15,
        mainAxisSpacing: 15,
        mainAxisExtent: 180, // Tinggi lebih pendek tapi proporsional
      ),
      itemCount: displayData.length,
      itemBuilder: (context, index) => _dataCard(displayData[index]),
    );
  }

  Widget _dataCard(Map<String, dynamic> item) {
    String status = item['status'] ?? item['sync_status'] ?? "pending";
    
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2)
          )
        ],
      ),
      child: InkWell(
        onTap: () => _navigate(DetailPanenPage(data: item, isReadOnly: true)),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Thumbnail Foto
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      width: 70,
                      height: 70,
                      child: _buildThumbnail(item),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Info Utama
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Blok ${item['blok'] ?? "-"}",
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          item['pemanen']?.toString() ?? "-",
                          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        statusBadge(status),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert, size: 20, color: Colors.grey),
                    onSelected: (val) {
                      if (val == 'edit') {
                        _navigate(input.InputPanenPage(data: item));
                      } else if (val == 'delete') {
                        _deleteData('panen', item['id_firebase']);
                      }
                    },
                    itemBuilder: (ctx) => [
                      const PopupMenuItem(value: 'edit', child: Row(children: [Icon(Icons.edit, size: 18), SizedBox(width: 8), Text("Edit")])),
                      const PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete, size: 18, color: Colors.red), SizedBox(width: 8), Text("Hapus", style: TextStyle(color: Colors.red))])),
                    ],
                  ),
                ],
              ),
              const Spacer(),
              const Divider(height: 20),
              // Stats bar
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _miniStat("Matang", "${item['matang'] ?? 0}", primaryBlue),
                  _miniStat("Mentah", "${item['mentah'] ?? 0}", Colors.red),
                  _miniStat("Bron.", "${item['brondolan'] ?? 0}kg", Colors.orange),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                item['tanggal']?.toString() ?? "-",
                style: TextStyle(fontSize: 10, color: Colors.grey[400]),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _miniStat(String label, String value, Color color) {
    return Column(
      children: [
        Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: color)),
        Text(label, style: const TextStyle(fontSize: 9, color: Colors.grey)),
      ],
    );
  }

  void _showPemanenDialog() {
    Set<String> pemanenSet = {};
    for (var item in data) {
      if (item['pemanen'] != null) pemanenSet.add(item['pemanen']);
    }
    List<String> pemanenList = pemanenSet.toList();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Daftar Pemanen Aktif"),
        content: SizedBox(
          width: 300,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: pemanenList.length,
            itemBuilder: (context, index) {
              return ListTile(
                leading: const CircleAvatar(child: Icon(Icons.person)),
                title: Text(pemanenList[index]),
                onTap: () {
                  Navigator.pop(context);
                  _navigate(DetailPemanenPage(nama: pemanenList[index], isWebView: true));
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Tutup")),
        ],
      ),
    );
  }

  Widget exportButton(String label, Color color, IconData icon) {
    return ElevatedButton.icon(
      onPressed: () {
        if (label == "PDF") {
          _sharePdf();
        }
      },
      icon: Icon(icon, size: 16),
      label: Text("Share $label"),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  Future<void> _sharePdf() async {
    try {
      if (data.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Tidak ada data untuk diexport"), backgroundColor: Colors.orange)
          );
        }
        return;
      }

      final pdf = pw.Document();
      
      // Hitung ringkasan data untuk header PDF
      int totalMatang = 0;
      int totalMentah = 0;
      double totalBron = 0;
      for (var item in data) {
        // Hanya hitung data yang ACC untuk konsistensi dengan dashboard
        String status = (item['status'] ?? item['sync_status'] ?? "").toString().toUpperCase();
        if (status == "ACC") {
          totalMatang += int.tryParse(item['matang']?.toString() ?? "0") ?? 0;
          totalMentah += int.tryParse(item['mentah']?.toString() ?? "0") ?? 0;
          totalBron += double.tryParse(item['brondolan']?.toString() ?? "0") ?? 0;
        }
      }

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4.landscape,
          maxPages: 2000, // Tingkatkan limit halaman untuk data besar
          margin: const pw.EdgeInsets.all(24),
          footer: (context) => pw.Container(
            alignment: pw.Alignment.centerRight,
            margin: const pw.EdgeInsets.only(top: 10),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text("Dicetak pada: ${DateTime.now().toString().split(".")[0]}", 
                    style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey)),
                pw.Text("Halaman ${context.pageNumber}", // Hapus pagesCount untuk menghindari layout loop
                    style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey)),
              ],
            ),
          ),
          build: (context) => [
            // Banner Header (Biru sesuai tema Admin)
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                color: PdfColor.fromInt(0xFF0D47A1),
                borderRadius: pw.BorderRadius.circular(6),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text("LAPORAN MONITORING PANEN SAWIT",
                      style: pw.TextStyle(
                          color: PdfColors.white,
                          fontWeight: pw.FontWeight.bold,
                          fontSize: 16)),
                  pw.SizedBox(height: 4),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(
                        "Filter: ${selectedAfdeling ?? 'Semua AFD'} | ${filterTanggalStart != null ? "${filterTanggalStart!.day}/${filterTanggalStart!.month}/${filterTanggalStart!.year} - ${filterTanggalEnd!.day}/${filterTanggalEnd!.month}/${filterTanggalEnd!.year}" : "${selectedMonth != null ? months[selectedMonth! - 1] : 'Semua Bulan'} ${selectedYear ?? 'Semua Tahun'}"}",
                        style: const pw.TextStyle(color: PdfColors.white, fontSize: 9),
                      ),
                      pw.Text("Total Record: ${data.length}",
                          style: const pw.TextStyle(color: PdfColors.white, fontSize: 9)),
                    ],
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 15),

            // Statistik Ringkasan (Kartu Statistik)
            pw.Row(
              children: [
                _pwStatCard("Total Record", "${data.length}", PdfColor.fromInt(0xFFE3F2FD), PdfColor.fromInt(0xFF1565C0)),
                pw.SizedBox(width: 8),
                _pwStatCard("Janjang Matang", "$totalMatang", PdfColor.fromInt(0xFFE3F2FD), PdfColor.fromInt(0xFF1565C0)),
                pw.SizedBox(width: 8),
                _pwStatCard("Janjang Mentah", "$totalMentah", PdfColor.fromInt(0xFFFFEBEE), PdfColor.fromInt(0xFFC62828)),
                pw.SizedBox(width: 8),
                _pwStatCard("Brondolan", "${totalBron.toStringAsFixed(1)} Kg", PdfColor.fromInt(0xFFFFF3E0), PdfColor.fromInt(0xFFE65100)),
              ],
            ),
            pw.SizedBox(height: 15),

            // Tabel Data Detail
            pw.TableHelper.fromTextArray(
              headers: ["Tanggal", "Pemanen", "Blok", "Afd", "Matang", "Mentah", "Bron", "Catatan"],
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8, color: PdfColors.white),
              cellStyle: const pw.TextStyle(fontSize: 7.5),
              headerDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFF1976D2)),
              cellAlignment: pw.Alignment.centerLeft,
              headerAlignment: pw.Alignment.center,
              data: data.map((e) => [
                e['tanggal']?.toString().split(" ")[0] ?? "-",
                e['pemanen'] ?? "-",
                e['blok'] ?? "-",
                e['afdeling'] ?? "-",
                e['matang']?.toString() ?? "0",
                e['mentah']?.toString() ?? "0",
                e['brondolan']?.toString() ?? "0",
                e['catatan'] ?? "-",
              ]).toList(),
            ),
          ],
        ),
      );

      // Gunakan Printing.layoutPdf untuk web agar muncul dialog download/print standar browser
      if (kIsWeb) {
        await Printing.layoutPdf(
          onLayout: (PdfPageFormat format) async => pdf.save(),
          name: "Laporan_Panen_Admin_${DateTime.now().millisecondsSinceEpoch}.pdf",
        );
      } else {
        await Printing.sharePdf(
          bytes: await pdf.save(),
          filename: "Laporan_Panen_Admin_${DateTime.now().millisecondsSinceEpoch}.pdf",
        );
      }
    } catch (e) {
      debugPrint("❌ PDF Export Error: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Gagal export PDF: $e"),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          )
        );
      }
    }
  }

  pw.Widget _pwStatCard(String label, String value, PdfColor bg, PdfColor textColor) {
    return pw.Expanded(
      child: pw.Container(
        padding: const pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(
          color: bg,
          borderRadius: pw.BorderRadius.circular(6),
          border: pw.Border.all(color: PdfColors.grey200, width: 0.5),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(label, style: pw.TextStyle(fontSize: 8, color: textColor)),
            pw.SizedBox(height: 2),
            pw.Text(value, style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: textColor)),
          ],
        ),
      ),
    );
  }


  // ================= SIDEBAR HELPERS =================
  Future<void> _deleteData(String collection, String? docId) async {
    if (docId == null || docId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("ID Data tidak valid, tidak bisa menghapus."))
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Konfirmasi Hapus"),
        content: Text("Apakah Anda yakin ingin menghapus data ini dari $collection?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("BATAL")),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text("HAPUS", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await FirebaseFirestore.instance.collection(collection).doc(docId).delete();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Data berhasil dihapus dari $collection"))
          );
          // Refresh data setelah penghapusan
          loadFromFirebase();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Gagal menghapus data: $e"), backgroundColor: Colors.red)
          );
        }
      }
    }
  }

  Widget _buildThumbnail(Map<String, dynamic> item) {
    final path = (item['foto'] ?? "").toString();
    
    // 1. Prioritaskan Bytes Cache (Sangat Cepat - Tanpa Decode saat Scroll)
    if (item['foto_bytes'] != null) {
      return Image(
        image: ResizeImage(
          MemoryImage(item['foto_bytes']),
          width: 120, // Thumbnail resolution
        ),
        width: 60,
        height: 60,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.low,
        errorBuilder: (c, e, s) => _buildPlaceholder(icon: Icons.broken_image),
      );
    }

    if (path.isEmpty) return _buildPlaceholder();

    // 2. Handle Base64 Fallback (Jika cache belum siap)
    if (path.startsWith('data:image') || (path.length > 500 && !path.startsWith('http'))) {
      try {
        final base64Data = path.contains(',') ? path.split(',').last : path;
        final cleanBase64 = base64Data.replaceAll(RegExp(r'\s+'), '');
        final bytes = base64Decode(cleanBase64);
        
        return Image(
          image: ResizeImage(
            MemoryImage(bytes),
            width: 120,
          ),
          width: 60,
          height: 60,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.low,
          errorBuilder: (c, e, s) => _buildPlaceholder(icon: Icons.broken_image),
        );
      } catch (e) {
        return _buildPlaceholder(icon: Icons.broken_image);
      }
    }

    // 3. Handle URL
    if (path.startsWith('http')) {
      return Image.network(
        path,
        width: 60,
        height: 60,
        fit: BoxFit.cover,
        errorBuilder: (c, e, s) => _buildPlaceholder(icon: Icons.broken_image),
      );
    }

    // 4. Fallback Web (Laravel Storage)
    if (kIsWeb) {
      String fileName = path.split(RegExp(r'[/\\]')).last;
      String baseUrl = ApiService.baseUrl.replaceAll('/api', '');
      return Image.network(
        "$baseUrl/storage/panen/$fileName",
        width: 60,
        height: 60,
        fit: BoxFit.cover,
        errorBuilder: (c, e, s) => _buildPlaceholder(),
      );
    }

    // 5. Mobile Local File
    return Image.file(
      File(path),
      width: 60,
      height: 60,
      cacheWidth: 120,
      fit: BoxFit.cover,
      errorBuilder: (c, e, s) => _buildPlaceholder(icon: Icons.broken_image),
    );
  }

  Widget _buildPlaceholder({IconData icon = Icons.image_not_supported}) {
    return Container(
      width: 60,
      height: 60,
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(icon, color: Colors.grey[400], size: 24),
    );
  }


  Widget _webViewResetSistem() {
    return Center(
      child: Container(
        width: 600,
        padding: const EdgeInsets.all(40),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 20)],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.warning_amber_rounded, size: 80, color: Colors.red),
            const SizedBox(height: 20),
            const Text(
              "Reset Seluruh Sistem",
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.red),
            ),
            const SizedBox(height: 10),
            const Text(
              "Tindakan ini akan menghapus SELURUH data di database pusat (Firestore) secara permanen, termasuk data panen, trip, PKS, dan daftar pemanen.",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, fontSize: 16),
            ),
            const SizedBox(height: 30),
            if (isLoading)
              const CircularProgressIndicator()
            else
              Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () => _confirmFullReset(),
                      icon: const Icon(Icons.delete_forever),
                      label: const Text("HAPUS SEMUA DATA SEKARANG"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 20),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 15),
                  TextButton(
                    onPressed: () => setState(() => _activeView = "dashboard"),
                    child: const Text("Batal, Kembali ke Dashboard"),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmFullReset() async {
    bool? confirm = await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Konfirmasi Terakhir"),
        content: const Text("Apakah Anda yakin? Semua data akan hilang dan tidak bisa dikembalikan."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("BATAL")),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text("YA, HAPUS SEMUA"),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _executeFullReset();
    }
  }

  Widget _webViewRegistrasiBlok() {
    return ListView(
      padding: const EdgeInsets.all(25),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: modernCard(
              title: "Pendaftaran Blok Baru",
              subtitle: "Tambahkan data blok ke dalam database pusat",
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _webFormItem("Nama/Kode Blok", _blokC, Icons.grid_on_rounded),
                  const SizedBox(height: 25),
                  const Text("KCS Pengelola", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.blueGrey)),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                    decoration: BoxDecoration(
                      color: bgGrey,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.withValues(alpha: 0.1)),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _selectedKcsBlok,
                        isExpanded: true,
                        hint: const Text("Pilih KCS"),
                        items: kcsList.map((kcs) => DropdownMenuItem(
                          value: kcs, 
                          child: Text(kcs, style: const TextStyle(fontSize: 14))
                        )).toList(),
                        onChanged: (v) => setState(() => _selectedKcsBlok = v),
                      ),
                    ),
                  ),
                  const SizedBox(height: 40),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _simpanBlok,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryBlue,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add_location_alt_rounded),
                          SizedBox(width: 12),
                          Text("DAFTARKAN BLOK", style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.1)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 15),
                  Center(
                    child: TextButton(
                      onPressed: () => setState(() => _activeView = "daftar_blok"),
                      child: Text("Lihat Daftar Blok Terdaftar", style: TextStyle(color: accentBlue)),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Center(
                    child: TextButton.icon(
                      onPressed: _importDataBlokDefault,
                      icon: const Icon(Icons.download_rounded, size: 18),
                      label: const Text("IMPORT BLOK DEFAULT"),
                      style: TextButton.styleFrom(foregroundColor: Colors.grey),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _simpanBlok() async {
    if (_blokC.text.isEmpty || _selectedKcsBlok == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Nama Blok dan KCS harus diisi"), backgroundColor: Colors.orange)
      );
      return;
    }

    try {
      await FirebaseFirestore.instance.collection('blocks').add({
        'blok': _blokC.text.trim().toUpperCase(),
        'kcs': _selectedKcsBlok,
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        _blokC.clear();
        setState(() => _selectedKcsBlok = null);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Blok berhasil didaftarkan ke sistem"),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          )
        );
      }
    } catch (e) {
      debugPrint("Gagal daftar blok: $e");
    }
  }

  Future<void> _importDataBlokDefault() async {
    final Map<String, List<String>> defaultData = {
      "KCS1": ["B01", "B02", "B03", "B04", "B05", "B06", "B07", "B08", "B09", "B10"],
      "KCS2": ["C01", "C02", "C03", "C04", "C05", "C06", "C07", "C08", "C09", "C10"],
      "KCS3": ["D01", "D02", "D03", "D04", "D05", "D06", "D07", "D08", "D09", "D10"],
    };

    setState(() => isLoading = true);
    try {
      final batch = FirebaseFirestore.instance.batch();
      final collection = FirebaseFirestore.instance.collection('blocks');

      defaultData.forEach((kcs, bloks) {
        for (var blok in bloks) {
          var docRef = collection.doc();
          batch.set(docRef, {
            'blok': blok,
            'kcs': kcs,
            'createdAt': FieldValue.serverTimestamp(),
          });
        }
      });

      await batch.commit();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Berhasil mengimpor daftar blok default"), backgroundColor: Colors.green)
        );
      }
    } catch (e) {
      debugPrint("Error import blok: $e");
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> _executeFullReset() async {
    setState(() => isLoading = true);
    try {
      // Daftar koleksi yang akan dihapus
      final collections = ['panen', 'trips', 'pks', 'harvesters', 'blocks'];
      
      for (var col in collections) {
        var snapshots = await FirebaseFirestore.instance.collection(col).get();
        var batch = FirebaseFirestore.instance.batch();
        for (var doc in snapshots.docs) {
          batch.delete(doc.reference);
        }
        await batch.commit();
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Sistem Berhasil Direset ke Awal!"), backgroundColor: Colors.green)
        );
        setState(() => _activeView = "dashboard");
      }
    } catch (e) {
      debugPrint("Error reset: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Gagal reset: $e"), backgroundColor: Colors.red)
        );
      }
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Widget _sidebarItem(IconData icon, String title, {bool active = false, VoidCallback? onTap}) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 15, vertical: 4),
      decoration: BoxDecoration(
        color: active ? Colors.white.withValues(alpha: 0.15) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
      ),
      child: ListTile(
        visualDensity: VisualDensity.compact,
        leading: Icon(icon, color: active ? Colors.white : Colors.white60, size: 22),
        title: Text(title, style: TextStyle(color: active ? Colors.white : Colors.white60, fontSize: 14, fontWeight: active ? FontWeight.bold : FontWeight.normal)),
        onTap: onTap,
      ),
    );
  }

  void _navigate(Widget page) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => page));
  }

  Future<void> _pickDate() async {
    DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDateRange: filterTanggalStart != null && filterTanggalEnd != null
          ? DateTimeRange(start: filterTanggalStart!, end: filterTanggalEnd!)
          : null,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: primaryBlue,
              onPrimary: Colors.white,
              onSurface: Colors.black,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        filterTanggalStart = picked.start;
        filterTanggalEnd = picked.end;
        selectedYear = null;
        selectedMonth = null;
      });
      applyFilter();
    }
  }

  void _clearFilter() {
    setState(() {
      filterTanggalStart = null;
      filterTanggalEnd = null;
      selectedYear = null;
      selectedMonth = null;
      selectedAfdeling = null;
    });
    applyFilter();
  }

  Widget _filterDropdown<T>({
    required T? value,
    required String hint,
    required List<DropdownMenuItem<T?>> items,
    required ValueChanged<T?> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: bgGrey,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T?>(
          value: value,
          isExpanded: false,
          hint: Text(hint, style: const TextStyle(fontSize: 12)),
          style: const TextStyle(fontSize: 12, color: Colors.black),
          items: items,
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget mobileLayout() {
    return Scaffold(
      appBar: AppBar(
        title: const Text("HARVESTTRACK"), 
        backgroundColor: primaryBlue, 
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => loadData(),
          )
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => loadData(),
        child: ListView(
          controller: _scrollController,
          padding: const EdgeInsets.all(15),
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("Dashboard Admin", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                if (filterTanggalStart != null)
                  IconButton(
                    icon: const Icon(Icons.filter_alt_off, color: Colors.red),
                    onPressed: _clearFilter,
                  )
              ],
            ),
            const SizedBox(height: 10),
            // Filter Bar Mobile
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _filterDropdown<String?>(
                    value: selectedAfdeling,
                    hint: "Afdeling",
                    items: [
                      const DropdownMenuItem(value: null, child: Text("Semua AFD")),
                      ...afdelings.map((a) => DropdownMenuItem(value: a, child: Text(a))),
                    ],
                    onChanged: (v) {
                      setState(() => selectedAfdeling = v);
                      applyFilter();
                    },
                  ),
                  const SizedBox(width: 8),
                  ActionChip(
                    avatar: Icon(Icons.calendar_today, size: 14, color: primaryBlue),
                    label: Text(
                      filterTanggalStart == null 
                        ? "Pilih Tanggal" 
                        : "${filterTanggalStart!.day}/${filterTanggalStart!.month} - ${filterTanggalEnd!.day}/${filterTanggalEnd!.month}",
                      style: const TextStyle(fontSize: 12),
                    ),
                    onPressed: _pickDate,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 1.2,
              children: [
                _mobileKpi("Jumlah Laporan", "${data.length}", Icons.assignment_rounded, accentBlue,
                    onTap: () => _navigate(MonitoringDataPage(initialData: data))),
                _mobileKpi("Total Janjang", "$totalPanen", Icons.eco, primaryBlue,
                    onTap: () => _navigate(const AnalisisProduksiPage())),
                _mobileKpi("Data PKS", totalTon.toStringAsFixed(1), Icons.factory_rounded, Colors.blue,
                    onTap: () => _navigate(RiwayatPksPage(
                      initialDate: filterTanggalStart,
                      initialMonth: selectedMonth,
                      initialYear: selectedYear,
                      initialAfdeling: selectedAfdeling,
                    ))),
                _mobileKpi("Trip Mobil", "$totalTrip", Icons.local_shipping_rounded, Colors.orange,
                    onTap: () => _navigate(RiwayatTripPage(
                      isGlobal: true,
                      initialDate: filterTanggalStart,
                      initialMonth: selectedMonth,
                      initialYear: selectedYear,
                      initialAfdeling: selectedAfdeling,
                    ))),
                _mobileKpi("Jumlah Pemanen", "$jumlahPemanen", Icons.people, Colors.purple,
                    onTap: () => _showPemanenDialog()),
              ],
            ),
            const SizedBox(height: 25),
            modernCard(
              title: "Aktivitas Hari Ini",
              child: dailySummaryWidget(),
            ),
            const SizedBox(height: 25),
            modernCard(
              title: "🏆 Ranking Pemanen",
              action: _filterDropdown<String?>(
                value: selectedAfdeling,
                hint: "AFD",
                items: [
                  const DropdownMenuItem(value: null, child: Text("Semua")),
                  ...afdelings.map((a) => DropdownMenuItem(value: a, child: Text(a))),
                ],
                onChanged: (v) {
                  setState(() => selectedAfdeling = v);
                  applyFilter();
                },
              ),
              child: rankingWidget(),
            ),
            const SizedBox(height: 25),
            modernCard(
              key: _monitoringKey,
              title: "Monitoring Panen",
              action: IconButton(icon: const Icon(Icons.filter_list), onPressed: _pickDate),
              child: dataTableWidget(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _mobileKpi(String title, String value, IconData icon, Color color, {VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15), boxShadow: [BoxShadow(color: cardShadow, blurRadius: 5)]),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 8),
            Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            Text(title, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
          ],
        ),
      ),
    );
  }
}
