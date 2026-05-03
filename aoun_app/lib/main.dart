import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs   = await SharedPreferences.getInstance();
  final savedId = prefs.getInt('patient_id');
  runApp(AounApp(loggedInPatientId: savedId));
}

class AounApp extends StatelessWidget {
  final int? loggedInPatientId;
  const AounApp({super.key, this.loggedInPatientId});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Aoun عون',
      debugShowCheckedModeBanner: false,

      // Global theme — brand green seed colour
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1D9E75),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF1D9E75),
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF1D9E75),
            foregroundColor: Colors.white,
            minimumSize: const Size(double.infinity, 52),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12)),
          contentPadding: const EdgeInsets.symmetric(
              horizontal: 16, vertical: 14),
        ),
      ),

      // Route to home if session exists, otherwise show login
      home: loggedInPatientId != null
          ? HomeScreen(patientId: loggedInPatientId!)
          : const LoginScreen(),
    );
  }
}
