import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../api_service.dart';
import 'face_wellness_screen.dart';
import 'login_screen.dart';

class PatientHomeTab extends StatefulWidget {
  final int patientId;
  final void Function(int)? onNavigate;
  const PatientHomeTab({super.key, required this.patientId, this.onNavigate});
  @override State<PatientHomeTab> createState() => _PatientHomeTabState();
}

class _PatientHomeTabState extends State<PatientHomeTab> {
  Map<String, dynamic>? _profile;
  List<dynamic> _recentSymptoms = [];
  bool _loading = true;
  int  _daysInTreatment = 0;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _profile        = await ApiService.getProfile(widget.patientId);
      _recentSymptoms = await ApiService.getSymptomHistory(
          widget.patientId, 'week');

      final ts = _profile?['treatment_start'] as String?;
      if (ts != null && ts.isNotEmpty) {
        try {
          final parts = ts.split('-');
          final start = DateTime(int.parse(parts[0]),
              int.parse(parts[1]), int.parse(parts[2]));
          _daysInTreatment =
              DateTime.now().difference(start).inDays;
        } catch (_) {}
      }
    } catch (_) {} finally {
      setState(() => _loading = false);
    }
  }

  String get _greeting {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }

  String get _firstName =>
      (_profile?['full_name'] as String? ?? 'there')
          .split(' ')
          .first;

  String get _genderSymbol =>
      (_profile?['gender'] as String? ?? 'Male') == 'Female'
          ? '♀'
          : '♂';

  Color _riskColor(String risk) {
    switch (risk) {
      case 'High':   return Colors.red;
      case 'Medium': return Colors.orange;
      case 'Low':    return Colors.green;
      default:       return Colors.blueGrey;
    }
  }

  String get _latestRisk => _recentSymptoms.isNotEmpty
      ? (_recentSymptoms.first['predicted_risk'] as String? ??
      'Not assessed')
      : 'Not assessed yet';

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final patientId =
    widget.patientId.toString().padLeft(4, '0');
    final cancer = _profile?['cancer_type'] as String? ?? '';
    final stage  = _profile?['cancer_stage'] as String? ?? '';
    final risk   = _latestRisk;

    return Scaffold(
      backgroundColor: const Color(0xFFF5FBF8),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1D9E75),
        foregroundColor: Colors.white,
        elevation: 0,
        title: Row(children: [
          const Text('Aoun عون',
              style: TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 18)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.25),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text('ID #$patientId',
                style: const TextStyle(
                    fontSize: 12, color: Colors.white)),
          ),
        ]),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white),
            tooltip: 'Sign Out',
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (_) => AlertDialog(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  title: const Text('Sign Out'),
                  content: const Text('Are you sure you want to sign out?'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Cancel')),
                    ElevatedButton(
                        style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red),
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Sign Out',
                            style: TextStyle(color: Colors.white))),
                  ],
                ),
              );
              if (confirm == true && mounted) {
                final prefs = await SharedPreferences.getInstance();
                await prefs.clear();
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                      (_) => false,
                );
              }
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [

            // ── GREETING CARD ────────────────────────────
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF1D9E75), Color(0xFF0F6E56)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(children: [
                Expanded(
                  child: Column(
                      crossAxisAlignment:
                      CrossAxisAlignment.start,
                      children: [
                        Text('$_greeting,',
                            style: TextStyle(
                                color:
                                Colors.white.withOpacity(0.85),
                                fontSize: 14)),
                        Text('$_firstName $_genderSymbol',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.bold)),
                        if (cancer.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                              '$cancer${stage.isNotEmpty ? ' · $stage' : ''}',
                              style: TextStyle(
                                  color: Colors.white.withOpacity(0.8),
                                  fontSize: 12)),
                        ],
                        if (_daysInTreatment > 0) ...[
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 5),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              borderRadius:
                              BorderRadius.circular(20),
                            ),
                            child: Text(
                                'Day $_daysInTreatment of treatment',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500)),
                          ),
                        ],
                      ]),
                ),
                const SizedBox(width: 12),
                CircleAvatar(
                  radius: 30,
                  backgroundColor:
                  Colors.white.withOpacity(0.25),
                  child: Icon(
                    (_profile?['gender'] as String? ??
                        'Male') ==
                        'Female'
                        ? Icons.female
                        : Icons.male,
                    color: Colors.white,
                    size: 36,
                  ),
                ),
              ]),
            ),

            const SizedBox(height: 20),

            // ── RISK STATUS ──────────────────────────────
            _sectionTitle('Current Status'),
            const SizedBox(height: 10),
            Card(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color:
                      _riskColor(risk).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(Icons.monitor_heart,
                        color: _riskColor(risk), size: 30),
                  ),
                  const SizedBox(width: 16),
                  Column(
                      crossAxisAlignment:
                      CrossAxisAlignment.start,
                      children: [
                        const Text('Risk Level',
                            style: TextStyle(
                                color: Colors.grey, fontSize: 12)),
                        const SizedBox(height: 2),
                        Text(risk,
                            style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: _riskColor(risk))),
                      ]),
                  const Spacer(),
                  if (_recentSymptoms.isNotEmpty)
                    Text(
                        _recentSymptoms.first['date'] ?? '',
                        style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 11)),
                ]),
              ),
            ),

            const SizedBox(height: 20),

            // ── QUICK ACTIONS ────────────────────────────
            _sectionTitle('Quick Actions'),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: _quickAction(
                  icon: Icons.favorite,
                  label: 'Log\nSymptoms',
                  color: Colors.red,
                  onTap: () => _navigate(1))),
              const SizedBox(width: 10),
              Expanded(child: _quickAction(
                  icon: Icons.directions_walk,
                  label: 'Log\nLifestyle',
                  color: Colors.orange,
                  onTap: () => _navigate(2))),
              const SizedBox(width: 10),
              Expanded(child: _quickAction(
                  icon: Icons.face_retouching_natural,
                  label: 'Face\nWellness',
                  color: Colors.teal,
                  onTap: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) =>
                          FaceWellnessScreen(patientId: widget.patientId))))),
              const SizedBox(width: 10),
              Expanded(child: _quickAction(
                  icon: Icons.notifications,
                  label: 'View\nAlerts',
                  color: Colors.purple,
                  onTap: () => _navigate(4))),
            ]),

            const SizedBox(height: 20),

            // ── STATS ────────────────────────────────────
            _sectionTitle('This Week'),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: _statCard(
                  '${_recentSymptoms.length}',
                  'Logs this week',
                  Icons.edit_note,
                  Colors.teal)),
              const SizedBox(width: 10),
              Expanded(child: _statCard(
                  _daysInTreatment > 0
                      ? '$_daysInTreatment'
                      : '—',
                  'Days in treatment',
                  Icons.medical_services,
                  Colors.blue)),
              const SizedBox(width: 10),
              Expanded(child: _statCard(
                  '#$patientId',
                  'Patient ID',
                  Icons.badge,
                  Colors.purple)),
            ]),

            const SizedBox(height: 20),

            // ── RECENT LOGS ──────────────────────────────
            if (_recentSymptoms.isNotEmpty) ...[
              _sectionTitle('Recent Symptom Logs'),
              const SizedBox(height: 10),
              ..._recentSymptoms.take(3).map((s) {
                final r =
                    s['predicted_risk'] as String? ?? '—';
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  shape: RoundedRectangleBorder(
                      borderRadius:
                      BorderRadius.circular(12)),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor:
                      _riskColor(r).withOpacity(0.15),
                      child: Icon(Icons.favorite,
                          color: _riskColor(r), size: 18),
                    ),
                    title: Text(s['date'] ?? '',
                        style: const TextStyle(
                            fontWeight: FontWeight.w500)),
                    subtitle: Text(
                        'Fatigue: ${s['fatigue'] ?? '-'} · '
                            'Chest: ${s['chest_pain'] ?? '-'}'),
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color:
                        _riskColor(r).withOpacity(0.1),
                        borderRadius:
                        BorderRadius.circular(20),
                      ),
                      child: Text(r,
                          style: TextStyle(
                              color: _riskColor(r),
                              fontWeight: FontWeight.bold,
                              fontSize: 12)),
                    ),
                  ),
                );
              }),
            ],

            if (_recentSymptoms.isEmpty)
              Card(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(children: [
                    Icon(Icons.add_circle_outline,
                        size: 48, color: Colors.grey.shade300),
                    const SizedBox(height: 12),
                    const Text('No logs yet',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16)),
                    const SizedBox(height: 4),
                    const Text(
                        'Tap "Log Symptoms" to get started',
                        style:
                        TextStyle(color: Colors.grey)),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: () => _navigate(1),
                      icon: const Icon(Icons.favorite,
                          color: Colors.white),
                      label: const Text('Log Symptoms',
                          style: TextStyle(
                              color: Colors.white)),
                      style: ElevatedButton.styleFrom(
                          backgroundColor:
                          const Color(0xFF1D9E75)),
                    ),
                  ]),
                ),
              ),

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  // Navigate by updating HomeScreen's selected tab
  void _navigate(int index) {
    widget.onNavigate?.call(index);
  }

  Widget _sectionTitle(String title) => Text(title,
      style: const TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 15,
          color: Color(0xFF333333)));

  Widget _quickAction(
      {required IconData icon,
        required String label,
        required Color color,
        required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Card(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14)),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Column(children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 6),
            Text(label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500)),
          ]),
        ),
      ),
    );
  }

  Widget _statCard(String value, String label,
      IconData icon, Color color) {
    return Card(
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 6),
          Text(value,
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  color: color)),
          const SizedBox(height: 2),
          Text(label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 10, color: Colors.grey)),
        ]),
      ),
    );
  }
}