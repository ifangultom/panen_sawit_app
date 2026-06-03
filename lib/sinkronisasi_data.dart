import 'package:flutter/material.dart';
import 'api_service.dart';

class SinkronisasiDataPage extends StatelessWidget {
  const SinkronisasiDataPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Sinkronisasi Data")),
      body: Center(
        child: ElevatedButton(
          onPressed: () async {
            await ApiService.syncData();

            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("Data berhasil disinkronkan")),
            );
          },
          child: const Text("SYNC DATA"),
        ),
      ),
    );
  }
}