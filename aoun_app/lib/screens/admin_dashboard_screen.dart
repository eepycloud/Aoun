import 'package:flutter/material.dart';
import '../api_service.dart';

/// Lists all registered patients with approve/deactivate controls.
///
/// the empty-state Center was not scrollable, which crashes
/// RefreshIndicator's gesture tree. The whole body now uses a
/// ListView with AlwaysScrollableScrollPhysics so pull-to-refresh
/// works in both populated and empty states.
class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});
  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  List<dynamic> _patients = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await ApiService.adminGetAllPatients();
      _patients = data;
    } catch (e) {
      _error = e.toString();
      debugPrint(_error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _approve(int id) async {
    try {
      await ApiService.approvePatient(id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Patient approved')),
        );
      }
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<void> _deactivate(int id) async {
    try {
      await ApiService.deactivatePatient(id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Patient deactivated')),
        );
      }
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  String _initial(String? name) {
    if (name == null || name.trim().isEmpty) return '?';
    return name.trim()[0].toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final activeCount = _patients
        .where((p) => (p['is_active'] as bool? ?? false) == true)
        .length;
    final pendingCount = _patients.length - activeCount;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
                            // RefreshIndicator to render correctly.
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(12),
                children: [
                  // ── Summary card ──────────────────────────
                  Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _stat('${_patients.length}', 'Total',
                              Icons.people, Colors.blue),
                          _stat('$activeCount', 'Active',
                              Icons.check_circle, Colors.green),
                          _stat('$pendingCount', 'Pending',
                              Icons.pending_actions, Colors.orange),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // ── Error state ───────────────────────────
                  if (_error != null)
                    Card(
                      color: Colors.red.shade50,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            const Icon(Icons.error_outline,
                                color: Colors.red),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Failed to load patients:\n$_error',
                                style: TextStyle(
                                    color: Colors.red.shade800,
                                    fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                  // ── Empty state ───────────────────────────
                  if (_patients.isEmpty && _error == null)
                    Padding(
                      padding: const EdgeInsets.only(top: 80),
                      child: Column(
                        children: [
                          Icon(Icons.people_outline,
                              size: 64, color: Colors.grey.shade300),
                          const SizedBox(height: 12),
                          const Text(
                            'No patients registered yet.',
                            style: TextStyle(
                                fontSize: 16, color: Colors.grey),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Pull down to refresh',
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),

                  // ── Patients list ─────────────────────────
                  ..._patients.map((raw) {
                    final p = raw as Map<String, dynamic>;
                    final isActive = p['is_active'] as bool? ?? false;
                    final id = p['id'] as int? ?? -1;
                    final name = p['full_name'] as String? ?? 'Unknown';
                    final email = p['email'] as String? ?? '';
                    final cancer = p['cancer_type'] as String? ??
                        'No diagnosis yet';
                    return Card(
                      elevation: 1,
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        leading: CircleAvatar(
                          radius: 22,
                          backgroundColor: isActive
                              ? Colors.green.shade100
                              : Colors.orange.shade100,
                          child: Text(
                            _initial(name),
                            style: TextStyle(
                              color: isActive
                                  ? Colors.green.shade800
                                  : Colors.orange.shade800,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        title: Text(
                          name,
                          style: const TextStyle(
                              fontWeight: FontWeight.w600),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(email,
                                style: const TextStyle(fontSize: 12)),
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                Icon(Icons.local_hospital,
                                    size: 12,
                                    color: Colors.grey.shade600),
                                const SizedBox(width: 4),
                                Text(cancer,
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey.shade700)),
                              ],
                            ),
                          ],
                        ),
                        isThreeLine: true,
                        trailing: isActive
                            ? TextButton(
                                style: TextButton.styleFrom(
                                    foregroundColor: Colors.red),
                                onPressed: id > 0
                                    ? () => _deactivate(id)
                                    : null,
                                child: const Text('Deactivate'),
                              )
                            : ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green,
                                  foregroundColor: Colors.white,
                                  minimumSize: const Size(100, 36),
                                ),
                                onPressed: id > 0
                                    ? () => _approve(id)
                                    : null,
                                child: const Text('Approve'),
                              ),
                      ),
                    );
                  }).toList(),
                ],
              ),
            ),
    );
  }

  Widget _stat(String value, String label, IconData icon, Color color) {
    return Column(
      children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(height: 4),
        Text(value,
            style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: color)),
        Text(label,
            style: const TextStyle(fontSize: 11, color: Colors.grey)),
      ],
    );
  }
}
