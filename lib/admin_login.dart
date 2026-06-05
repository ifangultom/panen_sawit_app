import 'package:flutter/material.dart';
import 'dashboard_admin.dart';

class AdminLoginPage extends StatefulWidget {
  @override
  State<AdminLoginPage> createState() => _AdminLoginPageState();
}

class _AdminLoginPageState extends State<AdminLoginPage> {
  final email = TextEditingController();
  final password = TextEditingController();

  void login() {
    // 🔥 login simple (sementara)
    if (email.text == "admin@gmail.com" && password.text == "123456") {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => DashboardAdmin()),
      );
    } else {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("Login gagal")));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Container(
          width: 300,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text("MASUK ADMIN", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              TextField(controller: email, decoration: InputDecoration(labelText: "Email")),
              TextField(controller: password, obscureText: true, decoration: InputDecoration(labelText: "Kata Sandi")),
              SizedBox(height: 20),
              ElevatedButton(onPressed: login, child: Text("Masuk"))
            ],
          ),
        ),
      ),
    );
  }
}