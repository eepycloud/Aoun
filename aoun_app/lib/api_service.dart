import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiService {
  // Base URL — update to your local IP when running on a physical device
  static const String baseUrl = 'http://192.168.68.57:8002';

  // ── CHATBOT ───────────────────────────────────────────────

  static Future<Map<String, dynamic>> chatSend(
      int patientId, String message) async {
    final res = await http.post(
      Uri.parse('$baseUrl/patient/$patientId/chat'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'message': message}),
    );
    if (res.statusCode == 200) return jsonDecode(res.body);
    throw Exception(
        jsonDecode(res.body)['detail'] ?? 'Chat request failed');
  }

  static Future<Map<String, dynamic>> chatWelcome(int patientId) async {
    final res = await http.get(
        Uri.parse('$baseUrl/patient/$patientId/chat/welcome'));
    if (res.statusCode == 200) return jsonDecode(res.body);
    throw Exception('Failed to load chat welcome');
  }

  // ── AUTH ──────────────────────────────────────────────────

  static Future<Map<String, dynamic>> login(
      String email, String password) async {
    final res = await http.post(
      Uri.parse('$baseUrl/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email, 'password': password}),
    );
    if (res.statusCode == 200) return jsonDecode(res.body);
    throw Exception(
        jsonDecode(res.body)['detail'] ?? 'Login failed');
  }

  static Future<Map<String, dynamic>> registerFull({
    required String fullName,
    required String email,
    required String password,
    required String gender,
    DateTime? dateOfBirth,
    String? cancerType,
    String? cancerStage,
    DateTime? treatmentStart,
  }) async {
    final body = <String, dynamic>{
      'full_name': fullName,
      'email':     email,
      'password':  password,
      'gender':    gender,
    };
    if (dateOfBirth    != null)
      body['date_of_birth']  = dateOfBirth.toIso8601String().split('T').first;
    if (cancerType     != null && cancerType.isNotEmpty)
      body['cancer_type']    = cancerType;
    if (cancerStage    != null && cancerStage != 'Unknown')
      body['cancer_stage']   = cancerStage;
    if (treatmentStart != null)
      body['treatment_start'] = treatmentStart.toIso8601String().split('T').first;

    final res = await http.post(
      Uri.parse('$baseUrl/auth/register'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    if (res.statusCode == 201) return jsonDecode(res.body);
    throw Exception(
        jsonDecode(res.body)['detail'] ?? 'Registration failed');
  }

  // ── PROFILE ───────────────────────────────────────────────

  static Future<Map<String, dynamic>> getProfile(int patientId) async {
    final res = await http.get(
        Uri.parse('$baseUrl/patient/$patientId/profile'));
    if (res.statusCode == 200) return jsonDecode(res.body);
    throw Exception('Failed to load profile');
  }

  // ── SYMPTOMS ──────────────────────────────────────────────

  static Future<Map<String, dynamic>> logSymptoms(
      int patientId, Map<String, dynamic> data) async {
    final res = await http.post(
      Uri.parse('$baseUrl/patient/$patientId/symptoms'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(data),
    );
    if (res.statusCode == 201) return jsonDecode(res.body);
    throw Exception(
        jsonDecode(res.body)['detail'] ?? 'Failed to log symptoms');
  }

  static Future<List<dynamic>> getSymptomHistory(
      int patientId, String period) async {
    final res = await http.get(Uri.parse(
        '$baseUrl/patient/$patientId/symptoms?period=$period'));
    if (res.statusCode == 200) return jsonDecode(res.body);
    throw Exception('Failed to load symptom history');
  }

  // ── LIFESTYLE ─────────────────────────────────────────────

  static Future<void> logLifestyle(
      int patientId, Map<String, dynamic> data) async {
    final res = await http.post(
      Uri.parse('$baseUrl/patient/$patientId/lifestyle'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(data),
    );
    if (res.statusCode != 201)
      throw Exception('Failed to save lifestyle data');
  }

  static Future<List<dynamic>> getLifestyleHistory(
      int patientId, String period) async {
    final res = await http.get(Uri.parse(
        '$baseUrl/patient/$patientId/lifestyle?period=$period'));
    if (res.statusCode == 200) return jsonDecode(res.body);
    throw Exception('Failed to load lifestyle history');
  }

  // ── RECOMMENDATIONS ───────────────────────────────────────

  static Future<Map<String, dynamic>> getRecommendations(
      int patientId) async {
    final res = await http.get(
        Uri.parse('$baseUrl/patient/$patientId/recommendations'));
    if (res.statusCode == 200) return jsonDecode(res.body);
    throw Exception('Failed to load recommendations');
  }

  // ── ALERTS ────────────────────────────────────────────────

  static Future<List<dynamic>> getAlerts(int patientId) async {
    final res = await http.get(
        Uri.parse('$baseUrl/patient/$patientId/alerts'));
    if (res.statusCode == 200) return jsonDecode(res.body);
    throw Exception('Failed to load alerts');
  }

  static Future<void> acknowledgeAlert(int alertId) async {
    await http.put(
        Uri.parse('$baseUrl/alerts/$alertId/acknowledge'));
  }

  // ── ML FEEDBACK ───────────────────────────────────────────

  static Future<void> submitMlFeedback(
      int alertId, bool isCorrect) async {
    await http.put(
      Uri.parse('$baseUrl/alerts/$alertId/feedback'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'is_correct': isCorrect}),
    );
  }

  // ── DOCTOR ────────────────────────────────────────────────

  static Future<List<dynamic>> getDoctorPatients(int doctorId) async {
    final res = await http.get(
        Uri.parse('$baseUrl/doctor/$doctorId/patients'));
    if (res.statusCode == 200) return jsonDecode(res.body);
    throw Exception('Failed to load patients');
  }

  static Future<Map<String, dynamic>> getChatFeedbackAnalytics(
      int doctorId) async {
    final res = await http.get(Uri.parse(
        '$baseUrl/doctor/$doctorId/chat-feedback-analytics'));
    if (res.statusCode == 200)
      return jsonDecode(res.body) as Map<String, dynamic>;
    throw Exception('Failed to load chat feedback analytics');
  }

  // ── ADMIN ─────────────────────────────────────────────────

  static Future<List<dynamic>> adminGetAllPatients() async {
    final res =
        await http.get(Uri.parse('$baseUrl/admin/patients'));
    if (res.statusCode == 200) return jsonDecode(res.body);
    throw Exception('Failed to load patients');
  }

  static Future<void> approvePatient(int patientId) async {
    await http.post(
        Uri.parse('$baseUrl/admin/approve/$patientId'));
  }

  static Future<void> deactivatePatient(int patientId) async {
    await http.put(
        Uri.parse('$baseUrl/admin/deactivate/$patientId'));
  }

  // ── REPORT ────────────────────────────────────────────────

  static Future<Map<String, dynamic>> getReport(int patientId) async {
    final res = await http.get(
        Uri.parse('$baseUrl/patient/$patientId/report?days=30'));
    if (res.statusCode == 200) return jsonDecode(res.body);
    throw Exception('Failed to generate report');
  }
}
