import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'database_helper.dart';

class HeatmapPanenPage extends StatefulWidget {
  const HeatmapPanenPage({super.key});

  @override
  State<HeatmapPanenPage> createState() => _HeatmapPanenPageState();
}

class _HeatmapPanenPageState extends State<HeatmapPanenPage> {

  List data = [];

  @override
  void initState() {
    super.initState();
    loadData();
  }

  void loadData() async {
    final result = await DatabaseHelper.instance.getAllPanen();

    setState(() {
      data = result;
    });
  }

  List<CircleMarker> buildHeatmap() {
    List<CircleMarker> circles = [];

    for (var d in data) {
      if (d['latitude'] != null && d['longitude'] != null) {
        circles.add(
          CircleMarker(
            point: LatLng(
              double.parse(d['latitude']),
              double.parse(d['longitude']),
            ),
            radius: 30,
            color: const Color(0xFF1976D2).withOpacity(0.4),
            borderStrokeWidth: 1,
            borderColor: const Color(0xFF0D47A1),
          ),
        );
      }
    }

    return circles;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Heatmap Panen", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF0D47A1),
        foregroundColor: Colors.white,
      ),

      body: FlutterMap(
        options: const MapOptions(
          initialCenter: LatLng(-0.5, 101.4), // Riau
          initialZoom: 10,
        ),

        children: [
          TileLayer(
            urlTemplate: "https://tile.openstreetmap.org/{z}/{x}/{y}.png",
            userAgentPackageName: 'com.example.app',
          ),

          CircleLayer(
            circles: buildHeatmap(),
          ),
        ],
      ),
    );
  }
}