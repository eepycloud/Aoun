import 'package:flutter/material.dart';
import '../api_service.dart';

class RecommendationsScreen extends StatefulWidget {
  final int patientId;
  const RecommendationsScreen({super.key, required this.patientId});
  @override State<RecommendationsScreen> createState() => _RecommendationsScreenState();
}

class _RecommendationsScreenState extends State<RecommendationsScreen> {
  Map<String, dynamic>? _data;
  bool _loading = true;
  String? _errorMsg;

  // Fallback recommendations shown even if no symptom log exists
  static const _fallback = {
    "current_risk": "Not assessed yet",
    "recommendations": [
      {"category": "general",  "title": "Log your symptoms first",
       "body": "Go to the Symptoms tab and submit your daily symptom log to receive personalised recommendations."},
      {"category": "diet",     "title": "Stay hydrated",
       "body": "Drink at least 2 litres of water daily to support your body during treatment."},
      {"category": "exercise", "title": "Light daily movement",
       "body": "Even a short 10-minute walk can improve mood and energy levels."},
      {"category": "sleep",    "title": "Consistent sleep schedule",
       "body": "Aim for 7-8 hours per night. Good sleep supports immune function."},
    ]
  };

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() { _loading = true; _errorMsg = null; });
    try {
      _data = await ApiService.getRecommendations(widget.patientId);
    } catch (e) {
      // Show fallback instead of error
      _data = Map<String, dynamic>.from(_fallback);
      _errorMsg = 'Showing general recommendations — log symptoms for personalised tips.';
    } finally {
      setState(() => _loading = false);
    }
  }

  IconData _iconFor(String category) {
    switch (category) {
      case 'diet':     return Icons.restaurant;
      case 'exercise': return Icons.directions_walk;
      case 'sleep':    return Icons.bedtime;
      default:         return Icons.lightbulb;
    }
  }

  Color _colorFor(String risk) {
    switch (risk) {
      case 'High':   return Colors.red;
      case 'Medium': return Colors.orange;
      case 'Low':    return const Color(0xFF1D9E75);
      default:       return Colors.blueGrey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Health Recommendations'),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Risk banner
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: _colorFor(_data!['current_risk'] ?? '').withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: _colorFor(_data!['current_risk'] ?? '').withOpacity(0.3)),
                    ),
                    child: Row(children: [
                      Icon(Icons.monitor_heart,
                          color: _colorFor(_data!['current_risk'] ?? ''), size: 32),
                      const SizedBox(width: 12),
                      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text('Current risk level',
                            style: TextStyle(color: Colors.grey, fontSize: 12)),
                        Text(
                          _data!['current_risk'] ?? 'Unknown',
                          style: TextStyle(
                            fontSize: 20, fontWeight: FontWeight.bold,
                            color: _colorFor(_data!['current_risk'] ?? ''),
                          ),
                        ),
                      ]),
                    ]),
                  ),

                  // Info banner if using fallback
                  if (_errorMsg != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.blue.shade200),
                      ),
                      child: Row(children: [
                        const Icon(Icons.info_outline, color: Colors.blue, size: 18),
                        const SizedBox(width: 8),
                        Expanded(child: Text(_errorMsg!,
                            style: const TextStyle(color: Colors.blue, fontSize: 12))),
                      ]),
                    ),
                  ],

                  const SizedBox(height: 20),
                  const Text('Recommendations for you',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 12),

                  ...(_data!['recommendations'] as List? ?? []).map((r) {
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor:
                              _colorFor(_data!['current_risk'] ?? '').withOpacity(0.15),
                          child: Icon(_iconFor(r['category'] ?? ''),
                              color: _colorFor(_data!['current_risk'] ?? '')),
                        ),
                        title: Text(r['title'] ?? '',
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(r['body'] ?? ''),
                        ),
                        isThreeLine: true,
                      ),
                    );
                  }),
                  const SizedBox(height: 8),
                  const Text('Tap refresh after logging symptoms for updated tips.',
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                      textAlign: TextAlign.center),
                  const SizedBox(height: 40),
                ],
              ),
            ),
    );
  }
}
