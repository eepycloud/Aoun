import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../api_service.dart';
import '../widgets/risk_badge.dart';

class DashboardScreen extends StatefulWidget {
  final int patientId;
  const DashboardScreen({super.key, required this.patientId});
  @override State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  List<dynamic> _history = [];
  String _period = 'week';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _history = await ApiService.getSymptomHistory(widget.patientId, _period);
    } catch (e) {
      // handle error
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard'),
        actions: [
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'week', label: Text('Week')),
              ButtonSegment(value: 'month', label: Text('Month')),
            ],
            selected: {_period},
            onSelectionChanged: (s) {
              setState(() => _period = s.first);
              _load();
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _history.isEmpty
          ? const Center(child: Text('No symptom data yet.\nLog your first entry!',
          textAlign: TextAlign.center))
          : ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildLatestRiskCard(),
          const SizedBox(height: 16),
          _buildFatigueChart(),
          const SizedBox(height: 16),
          _buildChestPainChart(),
        ],
      ),
    );
  }

  Widget _buildLatestRiskCard() {
    final latest = _history.isNotEmpty ? _history.first : null;
    final risk = latest?['predicted_risk'] as String? ?? 'Unknown';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          const Icon(Icons.monitor_heart, size: 40, color: Color(0xFF1D9E75)),
          const SizedBox(width: 16),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Latest Risk Level', style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 4),
            RiskBadge(riskLevel: risk),
          ]),
          const Spacer(),
          Text(latest?['date'] ?? '', style: const TextStyle(color: Colors.grey, fontSize: 12)),
        ]),
      ),
    );
  }

  Widget _buildFatigueChart() {
    return _buildLineCard('Fatigue Trend', _history, 'fatigue', const Color(0xFF7F77DD));
  }

  Widget _buildChestPainChart() {
    return _buildLineCard('Chest Pain Trend', _history, 'chest_pain', const Color(0xFFE24B4A));
  }

  Widget _buildLineCard(String title, List data, String field, Color color) {
    final spots = data.asMap().entries
        .where((e) => e.value[field] != null)
        .map((e) => FlSpot(e.key.toDouble(), (e.value[field] as num).toDouble()))
        .toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          SizedBox(
            height: 150,
            child: spots.isEmpty
                ? const Center(child: Text('No data'))
                : LineChart(LineChartData(
              minY: 0, maxY: 10,
              lineBarsData: [LineChartBarData(
                spots: spots, color: color,
                isCurved: true, dotData: const FlDotData(show: false),
                belowBarData: BarAreaData(show: true, color: color.withOpacity(0.1)),
              )],
              gridData: const FlGridData(show: true),
              titlesData: const FlTitlesData(
                leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 28)),
                bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
              ),
            )),
          ),
        ]),
      ),
    );
  }
}