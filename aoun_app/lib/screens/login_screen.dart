import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../api_service.dart';
import 'home_screen.dart';
import 'signup_screen.dart';
import 'doctor_dashboard_screen.dart';
import 'admin_dashboard_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailCtrl    = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _loading  = false;
  bool _showPass = false;
  String? _error;

  // Demo credentials for doctor and admin roles
  static const _doctorEmail    = 'doctor@aoun.health';
  static const _doctorPassword = 'Doctor@123';
  static const _adminEmail     = 'admin@aoun.health';
  static const _adminPassword  = 'Admin@123';

  Future<void> _login() async {
    final email = _emailCtrl.text.trim();
    final pass  = _passwordCtrl.text;
    setState(() { _loading = true; _error = null; });

    // Doctor role routing
    if (email == _doctorEmail && pass == _doctorPassword) {
      await Future.delayed(const Duration(milliseconds: 400));
      if (!mounted) return;
      setState(() => _loading = false);
      Navigator.pushReplacement(context,
          MaterialPageRoute(builder: (_) =>
              DoctorDashboardScreen(doctorId: 1)));
      return;
    }

    // Admin role routing
    if (email == _adminEmail && pass == _adminPassword) {
      await Future.delayed(const Duration(milliseconds: 400));
      if (!mounted) return;
      setState(() => _loading = false);
      Navigator.pushReplacement(context,
          MaterialPageRoute(builder: (_) =>
              const AdminDashboardScreen()));
      return;
    }

    // Patient login via backend API
    try {
      final result = await ApiService.login(email, pass);
      final prefs  = await SharedPreferences.getInstance();
      await prefs.setInt('patient_id', result['patient_id']);
      await prefs.setString('patient_name', result['name']);
      if (!mounted) return;
      Navigator.pushReplacement(context,
          MaterialPageRoute(builder: (_) =>
              HomeScreen(patientId: result['patient_id'])));
    } catch (e) {
      setState(() {
        _error = e.toString().replaceAll('Exception: ', '');
      });
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFE8F5EE), Color(0xFFFFFFFF)],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const SizedBox(height: 32),

                // App logo
                Center(
                  child: Image.asset('logo/image.png', height: 100,
                      errorBuilder: (_, __, ___) => Container(
                        width: 100, height: 100,
                        decoration: BoxDecoration(
                          color: const Color(0xFF1D9E75),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Icon(Icons.favorite,
                            color: Colors.white, size: 50),
                      )),
                ),
                const SizedBox(height: 20),
                const Text('Aoun عون',
                    style: TextStyle(fontSize: 30,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1D9E75))),
                const Text('Intelligent Cancer Monitoring',
                    style: TextStyle(color: Colors.grey, fontSize: 13)),
                const SizedBox(height: 40),

                // Login card
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20)),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Welcome back',
                            style: TextStyle(fontSize: 20,
                                fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        const Text('Sign in to continue',
                            style: TextStyle(
                                color: Colors.grey, fontSize: 13)),
                        const SizedBox(height: 24),

                        // Email field
                        TextField(
                          controller: _emailCtrl,
                          decoration: InputDecoration(
                            labelText: 'Email',
                            prefixIcon: const Icon(
                                Icons.email_outlined,
                                color: Color(0xFF1D9E75)),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                          keyboardType: TextInputType.emailAddress,
                        ),
                        const SizedBox(height: 16),

                        // Password field
                        TextField(
                          controller: _passwordCtrl,
                          obscureText: !_showPass,
                          decoration: InputDecoration(
                            labelText: 'Password',
                            prefixIcon: const Icon(
                                Icons.lock_outlined,
                                color: Color(0xFF1D9E75)),
                            suffixIcon: IconButton(
                              icon: Icon(_showPass
                                  ? Icons.visibility_off
                                  : Icons.visibility),
                              onPressed: () =>
                                  setState(() => _showPass = !_showPass),
                            ),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                        ),

                        // Error banner
                        if (_error != null) ...[
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.red.shade50,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(children: [
                              const Icon(Icons.error_outline,
                                  color: Colors.red, size: 16),
                              const SizedBox(width: 8),
                              Expanded(child: Text(_error!,
                                  style: const TextStyle(
                                      color: Colors.red, fontSize: 13))),
                            ]),
                          ),
                        ],

                        const SizedBox(height: 24),

                        // Submit button
                        _loading
                            ? const Center(
                                child: CircularProgressIndicator())
                            : SizedBox(
                                width: double.infinity,
                                height: 52,
                                child: ElevatedButton(
                                  onPressed: _login,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor:
                                        const Color(0xFF1D9E75),
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(12)),
                                  ),
                                  child: const Text('Sign In',
                                      style: TextStyle(
                                          fontSize: 16,
                                          color: Colors.white)),
                                ),
                              ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                // Sign up link
                Row(mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                  const Text("Don't have an account?",
                      style: TextStyle(color: Colors.grey)),
                  TextButton(
                    onPressed: () => Navigator.push(context,
                        MaterialPageRoute(
                            builder: (_) => const SignupScreen())),
                    child: const Text('Sign up',
                        style: TextStyle(
                            color: Color(0xFF1D9E75),
                            fontWeight: FontWeight.bold)),
                  ),
                ]),

                // Demo credentials hint
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.blue.shade100),
                  ),
                  child: const Column(children: [
                    Text('Demo accounts',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            color: Colors.blue)),
                    SizedBox(height: 4),
                    Text('Doctor:  doctor@aoun.health / Doctor@123',
                        style: TextStyle(
                            fontSize: 11, color: Colors.blueGrey)),
                    Text('Admin:   admin@aoun.health / Admin@123',
                        style: TextStyle(
                            fontSize: 11, color: Colors.blueGrey)),
                  ]),
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
