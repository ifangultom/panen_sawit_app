import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

class MapTrackingViewPage extends StatelessWidget {
  final String tracking;

  const MapTrackingViewPage({super.key, required this.tracking});

  List<LatLng> parseTracking() {
    List<LatLng> points = [];

    if (tracking.isEmpty) return points;

    var list = tracking.replaceAll("[", "").replaceAll("]", "").split(",");

    for (int i = 0; i < list.length; i += 2) {
      try {
        double lat = double.parse(list[i]);
        double lng = double.parse(list[i + 1]);
        points.add(LatLng(lat, lng));
      } catch (_) {}
    }

    return points;
  }

  @override
  Widget build(BuildContext context) {
    final points = parseTracking();

    return Scaffold(
      appBar: AppBar(
        title: const Text("Tracking Panen", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF0D47A1),
        foregroundColor: Colors.white,
      ),

      body: FlutterMap(
        options: MapOptions(
          initialCenter: points.isNotEmpty ? points.first : const LatLng(0, 0),
          initialZoom: 15,
        ),
        children: <Widget>[

          TileLayer(
            urlTemplate: "https://tile.openstreetmap.org/{z}/{x}/{y}.png",
            userAgentPackageName: 'app',
          ),

          if (points.isNotEmpty)
            PolylineLayer(
              polylines: [
                Polyline(
                  points: points,
                  strokeWidth: 4,
                  color: const Color(0xFF1976D2),
                )
              ],
            ),
        ],
      ),
    );
  }
}