import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'symptom_log_screen.dart';
import 'dashboard_screen.dart';
import 'alerts_screen.dart';
import 'lifestyle_log_screen.dart';
import 'recommendations_screen.dart';
import 'patient_home_tab.dart';
import 'login_screen.dart';
import 'face_wellness_screen.dart';
import 'chatbot_screen.dart';
import 'emergency_screen.dart';

class HomeScreen extends StatefulWidget {
  final int patientId;
  const HomeScreen({super.key, required this.patientId});
  @override State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;
  String _patientName    = '';
  String _gender         = 'Male';
  String _cancerType     = '';
  String _cancerStage    = '';
  String _treatmentStart = '';
  int    _daysInTreatment = 0;

  @override
  void initState() { super.initState(); _loadInfo(); }

  Future<void> _loadInfo() async {
    final prefs = await SharedPreferences.getInstance();
    _patientName = prefs.getString('patient_name') ?? 'Patient';
    if (mounted) setState(() {});
  }

  late final List<Widget> _screens = [
    PatientHomeTab(patientId: widget.patientId, onNavigate: (i) => setState(() => _selectedIndex = i)),
    SymptomLogScreen(patientId: widget.patientId),
    LifestyleLogScreen(patientId: widget.patientId),
    RecommendationsScreen(patientId: widget.patientId),
    AlertsScreen(patientId: widget.patientId),
  ];

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
            (_) => false);
  }

  Future<bool> _onWillPop() async {
    final exit = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        title: const Text('Exit Aoun?'),
        content: const Text('Are you sure you want to exit?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Exit')),
        ],
      ),
    );
    if (exit == true) SystemNavigator.pop();
    return false;
  }

  String get _genderStr =>
      _gender == 'Female' ? 'Female' : 'Male';
  IconData get _genderIcon =>
      _gender == 'Female' ? Icons.female : Icons.male;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvoked: (_) => _onWillPop(),
      child: Scaffold(
        // ── SIDEBAR DRAWER ──────────────────────────────────
        drawer: Drawer(
          child: SafeArea(
            child: Column(children: [
              // Header
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF1D9E75), Color(0xFF0F6E56)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CircleAvatar(
                        radius: 32,
                        backgroundColor: Colors.white.withOpacity(0.3),
                        child: Icon(_genderIcon,
                            color: Colors.white, size: 36),
                      ),
                      const SizedBox(height: 12),
                      Text(_patientName,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold)),
                      Text(
                        'Patient #${widget.patientId.toString().padLeft(4, '0')}',
                        style: TextStyle(
                            color: Colors.white.withOpacity(0.8),
                            fontSize: 12),
                      ),
                    ]),
              ),

              // Nav items
              Expanded(
                child: ListView(children: [
                  _drawerItem(Icons.home_outlined, 'Home',
                      Colors.teal, 0),
                  _drawerItem(
                      Icons.dashboard_outlined, 'Dashboard',
                      Colors.indigo, -1, onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => DashboardScreen(
                                patientId: widget.patientId)));
                  }),
                  _drawerItem(
                      Icons.face_retouching_natural,
                      'Face Wellness Check',
                      Colors.teal,
                      -1, onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => FaceWellnessScreen(
                                patientId: widget.patientId)));
                  }),
                  _drawerItem(Icons.favorite_outline,
                      'Log Symptoms', Colors.red, 1),
                  _drawerItem(Icons.directions_walk,
                      'Lifestyle', Colors.orange, 2),
                  _drawerItem(Icons.lightbulb_outline,
                      'Health Tips', Colors.amber, 3),
                  _drawerItem(Icons.notifications_outlined,
                      'Alerts', Colors.purple, 4),

                  const Divider(),

                  // ── FR25 — Emergency drawer entry ────────
                  _drawerItem(
                      Icons.emergency,
                      'Emergency',
                      Colors.red.shade700,
                      -1, onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) =>
                                const EmergencyScreen()));
                  }),

                  const Divider(),
                  ListTile(
                    leading: const Icon(Icons.logout,
                        color: Colors.red),
                    title: const Text('Logout',
                        style: TextStyle(
                            color: Colors.red,
                            fontWeight: FontWeight.w500)),
                    onTap: () {
                      Navigator.pop(context);
                      _logout();
                    },
                  ),
                ]),
              ),

              Padding(
                padding: const EdgeInsets.all(16),
                child: Text('Aoun عون v1.0',
                    style: TextStyle(
                        color: Colors.grey.shade400,
                        fontSize: 11)),
              ),
            ]),
          ),
        ),

        body: _screens[_selectedIndex],

        // ── FLOATING BUTTONS (Emergency SOS + Chat) ───────────
        floatingActionButton: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            // FR25 — Emergency SOS (always visible, mini red button)
            FloatingActionButton(
              heroTag: 'sos_fab',
              backgroundColor: Colors.red.shade700,
              tooltip: 'Emergency',
              mini: true,
              elevation: 4,
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const EmergencyScreen(),
                  ),
                );
              },
              child: const Icon(Icons.emergency,
                  color: Colors.white, size: 20),
            ),
            const SizedBox(height: 10),
            // Chat assistant
            FloatingActionButton(
              heroTag: 'chat_fab',
              backgroundColor: const Color(0xFF1D9E75),
              tooltip: 'Ask Aoun',
              elevation: 4,
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ChatbotScreen(
                        patientId: widget.patientId),
                  ),
                );
              },
              child: const Icon(Icons.chat_bubble_outline,
                  color: Colors.white, size: 26),
            ),
          ],
        ),

        // ── BOTTOM NAV ────────────────────────────────────
        bottomNavigationBar: NavigationBar(
          selectedIndex: _selectedIndex,
          onDestinationSelected: (i) =>
              setState(() => _selectedIndex = i),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined, color: Colors.teal),
              selectedIcon:
              Icon(Icons.home, color: Color(0xFF1D9E75)),
              label: 'Home',
            ),
            NavigationDestination(
              icon: Icon(Icons.favorite_outline, color: Colors.red),
              selectedIcon:
              Icon(Icons.favorite, color: Colors.red),
              label: 'Symptoms',
            ),
            NavigationDestination(
              icon: Icon(Icons.directions_walk,
                  color: Colors.orange),
              selectedIcon: Icon(Icons.directions_walk,
                  color: Colors.orange),
              label: 'Lifestyle',
            ),
            NavigationDestination(
              icon: Icon(Icons.lightbulb_outline,
                  color: Colors.amber),
              selectedIcon:
              Icon(Icons.lightbulb, color: Colors.amber),
              label: 'Tips',
            ),
            NavigationDestination(
              icon: Icon(Icons.notifications_outlined,
                  color: Colors.purple),
              selectedIcon: Icon(Icons.notifications,
                  color: Colors.purple),
              label: 'Alerts',
            ),
          ],
        ),
      ),
    );
  }

  Widget _drawerItem(IconData icon, String label, Color color,
      int index, {VoidCallback? onTap}) {
    final selected = _selectedIndex == index;
    return ListTile(
      selected: selected,
      selectedTileColor: color.withOpacity(0.1),
      leading: Icon(icon,
          color: selected ? color : Colors.grey.shade600),
      title: Text(label,
          style: TextStyle(
              fontWeight: selected
                  ? FontWeight.bold
                  : FontWeight.normal,
              color: selected ? color : null)),
      onTap: onTap ??
              () {
            Navigator.pop(context);
            setState(() => _selectedIndex = index);
          },
    );
  }
}
