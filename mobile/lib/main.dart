import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'core/theme/app_theme.dart';
import 'presentation/pages/auth/login_page.dart';
import 'presentation/providers/auth_providers.dart';
import 'presentation/providers/greenhouse_providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Inisialisasi format tanggal (bahasa Indonesia)
  try {
    await initializeDateFormatting('id_ID', null);
  } catch (e) {
    debugPrint("Locale formatting init note: $e");
  }

  // Inisialisasi database SQLite sesuai platform
  if (kIsWeb) {
    databaseFactory = databaseFactoryFfiWeb;
  } else if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  try {
    await dotenv.load(fileName: "assets/.env");
  } catch (e) {
    debugPrint("Peringatan: Gagal memuat file assets/.env: $e");
  }

  // Inisialisasi Firebase (Firestore)
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp();
    }
  } catch (e) {
    debugPrint("Firebase default initialize note: $e");
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
          options: const FirebaseOptions(
            apiKey: "AIzaSyDummyKeyForSmartTaniApp",
            appId: "1:100000000000:android:smarttani",
            messagingSenderId: "100000000000",
            projectId: "smart-greenhouse-ad587",
          ),
        );
      }
    } catch (err) {
      debugPrint("Firebase fallback options init: $err");
    }
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => GreenhouseProvider()),
      ],
      child: MaterialApp(
        title: 'TaniGreen',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.darkTheme,
        home: const LoginPage(),
      ),
    );
  }
}
