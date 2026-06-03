import 'dart:async';
import 'dart:convert'; // 🔥 TAMBAHAN
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

class MapGeoTaggingPage extends StatefulWidget {
  const MapGeoTaggingPage({super.key});

  @override
  State<MapGeoTaggingPage> createState() => _MapGeoTaggingPageState();
}

class _MapGeoTaggingPageState extends State<MapGeoTaggingPage> {

  final MapController mapController = MapController();

  String latitude = "-";
  String longitude = "-";
  String status = "Menunggu lokasi...";

  List<LatLng> trackingPoints = [];
  bool tracking = false;

  StreamSubscription<Position>? positionStream;

  @override
  void initState() {
    super.initState();
    ambilLokasi();
  }

  // =====================
  // 🔥 AMBIL LOKASI
  // =====================
  Future<void> ambilLokasi() async {
    try {
      setState(() {
        status = "Mengambil lokasi...";
      });

      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() {
          status = "GPS tidak aktif";
        });
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.deniedForever) {
        setState(() {
          status = "Izin ditolak";
        });
        return;
      }

      Position pos = await Geolocator.getCurrentPosition();

      setState(() {
        latitude = pos.latitude.toString();
        longitude = pos.longitude.toString();
        status = "Lokasi berhasil";
      });

      mapController.move(LatLng(pos.latitude, pos.longitude), 16);

    } catch (e) {
      setState(() {
        status = "Error: $e";
      });
    }
  }

  // =====================
  // 🔥 START TRACKING
  // =====================
  void startTracking() async {

    LocationPermission permission = await Geolocator.requestPermission();

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return;
    }

    setState(() {
      tracking = true;
      status = "Tracking berjalan...";
    });

    positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 3,
      ),
    ).listen((Position pos) {

      if (!tracking) return;

      final point = LatLng(pos.latitude, pos.longitude);

      setState(() {
        latitude = pos.latitude.toString();
        longitude = pos.longitude.toString();
        trackingPoints.add(point);
      });

      mapController.move(point, 17);
    });
  }

  // =====================
  // 🔥 STOP TRACKING
  // =====================
  void stopTracking() {
    setState(() {
      tracking = false;
      status = "Tracking dihentikan";
    });

    positionStream?.cancel();
  }

  // =====================
  // 🔥 KIRIM DATA KE INPUT PANEN (FIX FINAL)
  // =====================
  void gunakanLokasi() {

    // 🔥 CONVERT TRACKING KE JSON
    final path = trackingPoints
        .map((p) => {
      "lat": p.latitude,
      "lng": p.longitude,
    })
        .toList();

    Navigator.pop(context, {
      "lat": latitude,
      "lng": longitude,
      "tracking": jsonEncode(path), // 🔥 INI YANG BARU
    });
  }

  @override
  void dispose() {
    positionStream?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F4F7),

      appBar: AppBar(
        backgroundColor: const Color(0xFF0D47A1),
        foregroundColor: Colors.white,
        title: const Text("Geo Tagging (Open Map)", style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),

      body: Column(
        children: [

          // =====================
          // 🔥 MAP
          // =====================
          Expanded(
            child: FlutterMap(
              mapController: mapController,
              options: const MapOptions(
                initialCenter: LatLng(-0.5, 101.4),
                initialZoom: 13,
              ),
              children: <Widget>[

                // 🔥 TILE FIX 403
                TileLayer(
                  urlTemplate: "https://tile.openstreetmap.org/{z}/{x}/{y}.png",
                  userAgentPackageName: 'com.example.panen_sawit_app',
                ),

                // 🔥 MARKER
                if (latitude != "-")
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: LatLng(
                          double.parse(latitude),
                          double.parse(longitude),
                        ),
                        width: 40,
                        height: 40,
                        child: const Icon(
                          Icons.location_on,
                          color: Color(0xFF0D47A1),
                          size: 40,
                        ),
                      ),
                    ],
                  ),

                // 🔥 TRACKING LINE (Hanya muncul jika ada titik)
                if (trackingPoints.isNotEmpty)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: trackingPoints,
                        color: const Color(0xFF1976D2),
                        strokeWidth: 4,
                      ),
                    ],
                  ),
              ],
            ),
          ),

          // =====================
          // 🔥 INFO
          // =====================
          Container(
            padding: const EdgeInsets.all(10),
            child: Column(
              children: [
                Text("Lat: $latitude"),
                Text("Lng: $longitude"),
                Text(status),
              ],
            ),
          ),

          // =====================
          // 🔥 BUTTON
          // =====================
          Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              children: [

                Row(
                  children: [

                    Expanded(
                      child: ElevatedButton(
                        onPressed: ambilLokasi,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0D47A1),
                          foregroundColor: Colors.white,
                        ),
                        child: const Text("Ambil"),
                      ),
                    ),

                    const SizedBox(width: 10),

                    Expanded(
                      child: ElevatedButton(
                        onPressed: tracking ? null : startTracking,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1976D2),
                          foregroundColor: Colors.white,
                        ),
                        child: const Text("Tracking"),
                      ),
                    ),

                    const SizedBox(width: 10),

                    Expanded(
                      child: ElevatedButton(
                        onPressed: tracking ? stopTracking : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text("Stop"),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 10),

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: gunakanLokasi,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text("Gunakan Lokasi"),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}