import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';

class FotoPanenPage extends StatefulWidget {
  const FotoPanenPage({super.key});

  @override
  State<FotoPanenPage> createState() => _FotoPanenPageState();
}

class _FotoPanenPageState extends State<FotoPanenPage> {
  File? image;

  Future ambilFoto() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.camera);

    if (picked != null) {
      setState(() {
        image = File(picked.path);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Foto Panen")),
      body: Column(
        children: [
          if (image != null)
            Image.file(image!, height: 200),

          ElevatedButton(
            onPressed: ambilFoto,
            child: const Text("Ambil Foto"),
          )
        ],
      ),
    );
  }
}