import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'; // 🔥 DETECT WEB
import 'package:firebase_core/firebase_core.dart';
import 'package:camera/camera.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart'; // 🔥 ADD THIS
import 'database_helper.dart'; // 🔥 ADD THIS

// 🔥 PAGES
import 'login_page.dart';
import 'dashboard_admin.dart';

// 🔥 GLOBAL CAMERA
List<CameraDescription> cameras = [];

// 🔥 GLOBAL THEME NOTIFIER
final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.light);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Load Theme Preference
  try {
    final prefs = await SharedPreferences.getInstance();
    final isDark = prefs.getBool('isDarkMode') ?? false;
    themeNotifier.value = isDark ? ThemeMode.dark : ThemeMode.light;
  } catch (e) {
    debugPrint("Prefs Error: $e");
  }

  // 2. Inisialisasi Firebase & Kamera
  try {
    if (kIsWeb) {
      await Firebase.initializeApp(
        options: const FirebaseOptions(
            apiKey: "AIzaSyDOoCGw10TVqFTxpuWmrq4V0G4akNgGmIY",
            authDomain: "harvesttrack-feb35.firebaseapp.com",
            projectId: "harvesttrack-feb35",
            storageBucket: "harvesttrack-feb35.firebasestorage.app",
            messagingSenderId: "122513543211",
            appId: "1:122513543211:web:e2702f45e1400d738bda6e",
            measurementId: "G-Q9GZ9LX7QV"
        ),
      );
    } else {
      await Firebase.initializeApp();
    }
  } catch (e) {
    debugPrint("Firebase Init Error: $e");
  }

  try {
    if (!kIsWeb) {
      final available = await availableCameras();
      cameras = available;
    }
  } catch (e) {
    debugPrint("Camera Init Error: $e");
  }

  // 3. Setup Auto Sync on Connectivity Change (Mobile Only)
  if (!kIsWeb) {
    Connectivity().onConnectivityChanged.listen((List<ConnectivityResult> results) {
      if (results.any((r) => r != ConnectivityResult.none)) {
        debugPrint("🌐 Koneksi terdeteksi! Menjalankan sinkronisasi otomatis...");
        DatabaseHelper.instance.syncData();
      }
    });
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (_, ThemeMode currentMode, __) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'HarvestTrack Admin',
          themeMode: currentMode,
          theme: ThemeData(
            primaryColor: const Color(0xFF0D47A1),
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF0D47A1),
              brightness: Brightness.light,
            ),
            useMaterial3: true,
            appBarTheme: const AppBarTheme(
              backgroundColor: const Color(0xFF0D47A1),
              foregroundColor: Colors.white,
            ),
          ),
          darkTheme: ThemeData(
            brightness: Brightness.dark,
            primaryColor: const Color(0xFF0D47A1),
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF0D47A1),
              brightness: Brightness.dark,
            ),
            useMaterial3: true,
          ),
          home: const RootPage(),
        );
      },
    );
  }
}

////////////////////////////////////////////////////////////////////////////////
/// 🔥 ROOT PAGE (PINTU MASUK SEMUA PLATFORM)
////////////////////////////////////////////////////////////////////////////////
class RootPage extends StatelessWidget {
  const RootPage({super.key});

  @override
  Widget build(BuildContext context) {
    // Baik Web maupun Android, semuanya diarahkan ke LoginPage dulu.
    // Setelah Login berhasil, logika di login_page.dart akan
    // mengarahkan Admin ke DashboardAdmin secara otomatis.
    return const LoginPage();
  }
}