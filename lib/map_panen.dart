import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'database_helper.dart';
import 'detail_panen_page.dart';

class MapPanenPage extends StatefulWidget {
  final DateTime? initialDate;
  final int? initialMonth;
  final int? initialYear;
  final String? initialAfdeling;
  final List<Map<String, dynamic>>? initialData;

  const MapPanenPage({
    super.key,
    this.initialDate,
    this.initialMonth,
    this.initialYear,
    this.initialAfdeling,
    this.initialData,
  });

  @override
  State<MapPanenPage> createState() => _MapPanenPageState();
}

class _MapPanenPageState extends State<MapPanenPage> {
  List<Map<String, dynamic>> allData = [];
  List<Map<String, dynamic>> data = [];
  final MapController _mapController = MapController();
  bool isLoading = true;

  DateTime? filterTanggal;
  int? selectedMonth;
  int? selectedYear;
  String? selectedAfdeling;

  List<String> afdelings = [];
  final List<String> months = [
    "Januari", "Februari", "Maret", "April", "Mei", "Juni",
    "Juli", "Agustus", "September", "Oktober", "November", "Desember"
  ];
  final List<int> years = List.generate(5, (index) => DateTime.now().year - index);

  @override
  void initState() {
    super.initState();
    filterTanggal = widget.initialDate;
    selectedMonth = widget.initialMonth;
    selectedYear = widget.initialYear;
    selectedAfdeling = widget.initialAfdeling;
    loadData();
  }

  Future<void> loadData() async {
    if (!mounted) return;
    setState(() => isLoading = true);
    
    try {
      // 1. Ambil Data Lokal
      List<Map<String, dynamic>> localData = await DatabaseHelper.instance.getAllPanen();
      
      // 2. Ambil Data Cloud
      List<Map<String, dynamic>> cloudData = [];
      try {
        final snapshot = await FirebaseFirestore.instance.collection('panen').get();
        cloudData = snapshot.docs.map((doc) => doc.data()).toList();
      } catch (e) {
        debugPrint("Firebase Fetch Error: $e");
      }

      // 3. Gabungkan Data (Unique)
      Map<String, Map<String, dynamic>> mergedMap = {};
      for (var item in localData) {
        DateTime? dt = _parseDate(item['tanggal'] ?? item['waktu']);
        String tglStr = dt?.toIso8601String().split('T')[0] ?? "no-date";
        String key = "${item['pemanen']}_${tglStr}_${item['blok']}";
        mergedMap[key] = Map<String, dynamic>.from(item);
      }
      for (var item in cloudData) {
        DateTime? dt = _parseDate(item['tanggal'] ?? item['waktu']);
        String tglStr = dt?.toIso8601String().split('T')[0] ?? "no-date";
        String key = "${item['pemanen']}_${tglStr}_${item['blok']}";
        mergedMap[key] = Map<String, dynamic>.from(item);
      }

      if (mounted) {
        setState(() {
          allData = mergedMap.values.toList();
          
          Set<String> afdSet = {};
          for (var item in allData) {
            if (item['afdeling'] != null) afdSet.add(item['afdeling'].toString());
          }
          afdelings = afdSet.toList()..sort();
          
          isLoading = false;
          applyFilter();
        });
      }
    } catch (e) {
      if (mounted) setState(() => isLoading = false);
    }
  }

  void applyFilter() {
    List<Map<String, dynamic>> filtered = allData.where((item) {
      if (selectedAfdeling != null && item['afdeling']?.toString() != selectedAfdeling) return false;
      
      if (selectedYear != null || filterTanggal != null) {
        DateTime? dt = _parseDate(item['tanggal'] ?? item['waktu']);
        if (dt == null) return false;
        
        if (selectedYear != null) {
          if (dt.year != selectedYear) return false;
          if (selectedMonth != null && dt.month != selectedMonth) return false;
        } else if (filterTanggal != null) {
          String fDate = filterTanggal!.toIso8601String().split('T')[0];
          String itemDate = dt.toIso8601String().split('T')[0];
          if (fDate != itemDate) return false;
        }
      }
      return true;
    }).toList();

    setState(() {
      data = filtered;
    });

    _centerMapToData(filtered);
  }

  // Pendeteksian koordinat yang lebih kuat (Support GeoPoint & multiple field names)
  LatLng? _getLatLng(Map<String, dynamic> d) {
    double? lat;
    double? lng;

    // 1. Coba deteksi jika data adalah GeoPoint (Firebase)
    if (d['location'] != null && d['location'] is GeoPoint) {
      lat = (d['location'] as GeoPoint).latitude;
      lng = (d['location'] as GeoPoint).longitude;
    } 
    // 2. Coba deteksi dari berbagai variasi nama field
    else {
      var latVal = d['latitude'] ?? d['lat'] ?? d['Latitude'] ?? d['gps_lat'];
      var lngVal = d['longitude'] ?? d['lng'] ?? d['long'] ?? d['Longitude'] ?? d['gps_lng'];
      
      lat = double.tryParse(latVal?.toString() ?? "");
      lng = double.tryParse(lngVal?.toString() ?? "");
    }
    
    // Validasi: Abaikan jika 0.0 atau null
    if (lat != null && lng != null && lat != 0 && lng != 0) {
      return LatLng(lat, lng);
    }
    return null;
  }

  DateTime? _parseDate(dynamic val) {
    if (val == null) return null;
    if (val is Timestamp) return val.toDate();
    if (val is DateTime) return val;
    return DateTime.tryParse(val.toString());
  }

  void _centerMapToData(List<Map<String, dynamic>> currentData) {
    List<LatLng> points = [];
    for (var d in currentData) {
      LatLng? pos = _getLatLng(d);
      if (pos != null) points.add(pos);
    }

    if (points.isNotEmpty) {
      double avgLat = points.map((p) => p.latitude).reduce((a, b) => a + b) / points.length;
      double avgLng = points.map((p) => p.longitude).reduce((a, b) => a + b) / points.length;
      _mapController.move(LatLng(avgLat, avgLng), 13);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Hitung marker yang valid
    List<Marker> markers = [];
    int dataWithGps = 0;

    for (var d in data) {
      LatLng? pos = _getLatLng(d);
      if (pos != null) {
        dataWithGps++;
        
        int janjang = (int.tryParse(d['matang']?.toString() ?? "0") ?? 0) + 
                      (int.tryParse(d['mentah']?.toString() ?? "0") ?? 0);
        
        // Warna Marker dinamis (Tema Biru)
        Color markerColor = janjang > 50 ? Colors.red : (janjang > 20 ? Colors.orange : const Color(0xFF0D47A1));

        markers.add(
          Marker(
            width: 45,
            height: 45,
            point: pos,
            child: GestureDetector(
              onTap: () => _showDetail(d),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Icon(Icons.location_on, color: markerColor.withValues(alpha: 0.4), size: 42),
                  Icon(Icons.location_on, color: markerColor, size: 35),
                  const Positioned(
                    top: 8,
                    child: Icon(Icons.circle, color: Colors.white, size: 8),
                  ),
                ],
              ),
            ),
          ),
        );
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("Peta Monitoring Panen", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF0D47A1),
        foregroundColor: Colors.white,
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: loadData),
        ],
      ),
      body: Column(
        children: [
          _filterBar(),
          Expanded(
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: const MapOptions(
                    initialCenter: LatLng(-0.5, 101.4),
                    initialZoom: 10,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: "https://tile.openstreetmap.org/{z}/{x}/{y}.png",
                      userAgentPackageName: 'com.harvesttrack.app',
                    ),
                    MarkerLayer(markers: markers),
                  ],
                ),
                if (isLoading)
                  const Center(child: CircularProgressIndicator()),
                
                // Panel Diagnostic (Hanya muncul jika ada data tapi tidak ada titik)
                if (!isLoading && data.isNotEmpty && markers.isEmpty)
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: Container(
                      margin: const EdgeInsets.all(20),
                      padding: const EdgeInsets.all(15),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 10)],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.gps_off, color: Colors.orange, size: 30),
                          const SizedBox(height: 10),
                          Text(
                            "Ditemukan ${data.length} data panen,\ntapi tidak ada koordinat GPS yang valid.",
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 5),
                          const Text(
                            "Pastikan izin lokasi aktif saat memanen.",
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                          TextButton(onPressed: loadData, child: const Text("Refresh Data"))
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showDetail(Map<String, dynamic> d) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(d['blok'] ?? "Detail Panen"),
        content: Text("Pemanen: ${d['pemanen']}\nHasil: ${d['matang']} Matang, ${d['mentah']} Mentah"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Tutup")),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.push(context, MaterialPageRoute(builder: (_) => DetailPanenPage(data: d, isReadOnly: true)));
            },
            child: const Text("Detail Lengkap"),
          )
        ],
      ),
    );
  }

  Widget _filterBar() {
    return Container(
      padding: const EdgeInsets.all(8),
      color: Colors.white,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _drop<String?>(selectedAfdeling, "AFD", [
              const DropdownMenuItem(value: null, child: Text("Semua AFD")),
              ...afdelings.map((a) => DropdownMenuItem(value: a, child: Text(a))),
            ], (v) { setState(() => selectedAfdeling = v); applyFilter(); }),
            const SizedBox(width: 8),
            _drop<int?>(selectedMonth, "Bulan", [
              const DropdownMenuItem(value: null, child: Text("Bulan")),
              ...List.generate(12, (i) => DropdownMenuItem(value: i + 1, child: Text(months[i]))),
            ], (v) { setState(() { selectedMonth = v; filterTanggal = null; }); applyFilter(); }),
            const SizedBox(width: 8),
            _drop<int?>(selectedYear, "Tahun", [
              const DropdownMenuItem(value: null, child: Text("Tahun")),
              ...years.map((y) => DropdownMenuItem(value: y, child: Text(y.toString()))),
            ], (v) { setState(() { selectedYear = v; filterTanggal = null; }); applyFilter(); }),
          ],
        ),
      ),
    );
  }

  Widget _drop<T>(T value, String hint, List<DropdownMenuItem<T>> items, ValueChanged<T> onChanged) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(8)),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          hint: Text(hint, style: const TextStyle(fontSize: 12)),
          items: items,
          onChanged: (v) {
            if (v != null || null is T) {
              onChanged(v as T);
            }
          },
        ),
      ),
    );
  }
}
