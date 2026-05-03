import 'package:flutter/material.dart';
import '../api_service.dart';
import '../widgets/risk_badge.dart';

class AlertsScreen extends StatefulWidget {
  final int patientId;
  const AlertsScreen({super.key, required this.patientId});
  @override State<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends State<AlertsScreen> {
  List<dynamic> _alerts = [];
  bool _loading = true;

  // Shown when no real alerts exist — gives the screen content for demo
  static const _wellnessTips = [
    {
      'risk': 'Low',
      'message': 'Remember to log your symptoms daily for accurate risk tracking.',
      'type': 'Reminder',
      'created_at': 'General reminder',
    },
    {
      'risk': 'Low',
      'message': 'Stay hydrated — aim for 2 litres of water today.',
      'type': 'Wellness',
      'created_at': 'General reminder',
    },
    {
      'risk': 'Low',
      'message': 'Your next symptom log is due today. Tap the Symptoms tab.',
      'type': 'Reminder',
      'created_at': 'General reminder',
    },
  ];

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _alerts = await ApiService.getAlerts(widget.patientId);
    } catch (e) {
      _alerts = [];
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final displayList = _alerts.isEmpty
        ? List<Map<String, dynamic>>.from(_wellnessTips)
        : _alerts;
    final isShowingTips = _alerts.isEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Alerts'),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  if (isShowingTips)
                    Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.green.shade200),
                      ),
                      child: const Row(children: [
                        Icon(Icons.check_circle, color: Colors.green, size: 18),
                        SizedBox(width: 8),
                        Expanded(child: Text(
                          'No risk alerts — you\'re doing well! Here are some wellness reminders.',
                          style: TextStyle(color: Colors.green, fontSize: 13),
                        )),
                      ]),
                    ),
                  ...displayList.map((a) {
                    final risk   = (a['risk'] as String?) ?? 'Low';
                    final isHigh = risk == 'High';
                    final type   = (a['type'] as String?) ?? '';
                    return Card(
                      color: isHigh ? Colors.red.shade50 : null,
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: Icon(
                          isHigh
                              ? Icons.warning
                              : type == 'Reminder'
                                  ? Icons.notifications_active
                                  : Icons.favorite,
                          color: isHigh
                              ? Colors.red
                              : type == 'Reminder'
                                  ? Colors.orange
                                  : Colors.green,
                        ),
                        title: Text(
                          (a['message'] as String?) ?? '',
                          style: TextStyle(
                            fontWeight: isHigh ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                        subtitle: Text(
                          (a['created_at'] as String?) ?? '',
                          style: const TextStyle(fontSize: 11, color: Colors.grey),
                        ),
                        trailing: RiskBadge(riskLevel: risk),
                      ),
                    );
                  }),
                ],
              ),
            ),
    );
  }
}
