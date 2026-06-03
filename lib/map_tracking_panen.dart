import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

class MapTrackingPanenPage extends StatefulWidget {
  const MapTrackingPanenPage({super.key});

  @override
  State<MapTrackingPanenPage> createState() => _MapTrackingPanenPageState();
}

class _MapTrackingPanenPageState extends State<MapTrackingPanenPage> {

  // 🔥 MAP CONTROLLER
  final MapController mapController = MapController();

  // 🔥 LIST TITIK TRACKING
  List<LatLng> trackingPoints = [];

  // 🔥 STATUS TRACKING
  bool tracking = false;

  // 🔥 START TRACKING
  void startTracking() async {

    LocationPermission permission = await Geolocator.requestPermission();

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return;
    }

    setState(() {
      tracking = true;
    });

    Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 3,
      ),
    ).listen((Position pos) {

      if (!tracking) return;

      final newPoint = LatLng(pos.latitude, pos.longitude);

      setState(() {
        trackingPoints.add(newPoint);
      });

      // 🔥 AUTO MOVE MAP
      mapController.move(newPoint, 17);

      print("📍 ${pos.latitude}, ${pos.longitude}");
    });
  }

  // 🔥 STOP TRACKING
  void stopTracking() {
    setState(() {
      tracking = false;
    });
  }

  // 🔥 CLEAR TRACKING
  void clearTracking() {
    setState(() {
      trackingPoints.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Tracking Panen", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF0D47A1),
        foregroundColor: Colors.white,
      ),

      body: Column(
        children: [

          // 🔥 MAP
          Expanded(
            child: FlutterMap(
              mapController: mapController,
              options: const MapOptions(
                initialCenter: LatLng(-0.5, 101.4), // default Riau
                initialZoom: 13,
              ),
              children: <Widget>[

                // 🔥 MAP TILE
                TileLayer(
                  urlTemplate:
                  "https://tile.openstreetmap.org/{z}/{x}/{y}.png",
                  userAgentPackageName: 'com.example.app',
                ),

                // 🔥 GARIS TRACKING (Hanya muncul jika ada titik)
                if (trackingPoints.isNotEmpty)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: trackingPoints,
                        strokeWidth: 4,
                        color: const Color(0xFF1976D2),
                      ),
                    ],
                  ),

                // 🔥 MARKER TERAKHIR
                MarkerLayer(
                  markers: trackingPoints.isNotEmpty
                      ? [
                    Marker(
                      point: trackingPoints.last,
                      width: 40,
                      height: 40,
                      child: const Icon(
                        Icons.location_on,
                        color: Color(0xFF0D47A1),
                        size: 40,
                      ),
                    ),
                  ]
                      : [],
                ),
              ],
            ),
          ),

          // 🔥 BUTTON CONTROL
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.white,
            child: Row(
              children: [

                Expanded(
                  child: ElevatedButton(
                    onPressed: tracking ? null : startTracking,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0D47A1),
                      foregroundColor: Colors.white,
                    ),
                    child: const Text("START"),
                  ),
                ),

                const SizedBox(width: 10),

                Expanded(
                  child: ElevatedButton(
                    onPressed: tracking ? stopTracking : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                    ),
                    child: const Text("STOP"),
                  ),
                ),

                const SizedBox(width: 10),

                Expanded(
                  child: ElevatedButton(
                    onPressed: clearTracking,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.grey,
                    ),
                    child: const Text("CLEAR"),
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