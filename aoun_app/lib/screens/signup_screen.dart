import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../api_service.dart';
import 'home_screen.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});
  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _cancerCtrl = TextEditingController();

  String _gender = 'Male';
  String _cancerStage = 'Unknown';
  DateTime? _dateOfBirth;
  bool _loading = false;
  bool _showPass = false;
  String? _error;

  Future<void> _pickDOB() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(1995),
      firstDate: DateTime(1920),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _dateOfBirth = picked);
  }

  String _formatDate(DateTime d) =>
      "${d.day}/${d.month}/${d.year}";

  Future<void> _register() async {
    if (_nameCtrl.text.isEmpty ||
        _emailCtrl.text.isEmpty ||
        _passwordCtrl.text.isEmpty) {
      setState(() => _error = "Fill all required fields");
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await ApiService.registerFull(
        fullName: _nameCtrl.text,
        email: _emailCtrl.text,
        password: _passwordCtrl.text,
        gender: _gender,
        dateOfBirth: _dateOfBirth,
        cancerType:
        _cancerCtrl.text.isEmpty ? null : _cancerCtrl.text,
        cancerStage: _cancerStage,
        treatmentStart: null,
      );

      final login = await ApiService.login(
          _emailCtrl.text, _passwordCtrl.text);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('patient_id', login['patient_id']);

      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) =>
              HomeScreen(patientId: login['patient_id']),
        ),
      );
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FA),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Create Account",
                style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              const Text(
                "Join us and start your health journey",
                style: TextStyle(color: Colors.grey),
              ),

              const SizedBox(height: 25),
              // Name, email, password, gender, DOB, cancer info fields
              _modernField(_nameCtrl, "Full Name"),
              const SizedBox(height: 15),
              _modernField(_emailCtrl, "Email",
                  type: TextInputType.emailAddress),
              const SizedBox(height: 15),
              TextField(
                controller: _passwordCtrl,
                obscureText: !_showPass,
                decoration: _modernInput("Password").copyWith(
                  suffixIcon: IconButton(
                    icon: Icon(_showPass
                        ? Icons.visibility_off
                        : Icons.visibility),
                    onPressed: () =>
                        setState(() => _showPass = !_showPass),
                  ),
                ),
              ),

              const SizedBox(height: 15),
              DropdownButtonFormField<String>(
                isExpanded: true,
                value: _gender,
                decoration: _modernInput("Gender"),
                items: const [
                  DropdownMenuItem(value: "Male", child: Text("Male")),
                  DropdownMenuItem(value: "Female", child: Text("Female")),
                  DropdownMenuItem(value: "Other", child: Text("Other")),
                ],
                onChanged: (v) =>
                    setState(() => _gender = v!),
              ),

              const SizedBox(height: 15),
              GestureDetector(
                onTap: _pickDOB,
                child: AbsorbPointer(
                  child: TextField(
                    decoration: _modernInput(
                        _dateOfBirth == null
                            ? "Date of Birth"
                            : _formatDate(_dateOfBirth!)),
                  ),
                ),
              ),

              const SizedBox(height: 25),
              const Text(
                "Medical Info (Optional)",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),

              _modernField(_cancerCtrl, "Cancer Type"),
              const SizedBox(height: 15),

              DropdownButtonFormField<String>(
                isExpanded: true,
                value: _cancerStage,
                decoration: _modernInput("Cancer Stage"),
                items: const [
                  DropdownMenuItem(value: "Unknown", child: Text("Unknown")),
                  DropdownMenuItem(value: "Stage I", child: Text("Stage I")),
                  DropdownMenuItem(value: "Stage II", child: Text("Stage II")),
                  DropdownMenuItem(value: "Stage III", child: Text("Stage III")),
                  DropdownMenuItem(value: "Stage IV", child: Text("Stage IV")),
                ],
                onChanged: (v) =>
                    setState(() => _cancerStage = v!),
              ),

              const SizedBox(height: 25),
              if (_error != null)
                Text(_error!,
                    style: const TextStyle(color: Colors.red)),

              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: 55,
                child: ElevatedButton(
                  onPressed: _loading ? null : _register,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1D9E75),
                    shape: RoundedRectangleBorder(
                        borderRadius:
                        BorderRadius.circular(14)),
                  ),
                  child: _loading
                      ? const CircularProgressIndicator(
                      color: Colors.white)
                      : const Text(
                    "Create Account",
                    style: TextStyle(fontSize: 16),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _modernField(TextEditingController ctrl, String hint,
      {TextInputType type = TextInputType.text}) {
    return TextField(
      controller: ctrl,
      keyboardType: type,
      decoration: _modernInput(hint),
    );
  }

  InputDecoration _modernInput(String hint) {
    return InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: Colors.white,
      contentPadding:
      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none),
    );
  }
}