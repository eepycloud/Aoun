import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../api_service.dart';
import '../widgets/risk_badge.dart';

class DoctorDashboardScreen extends StatefulWidget {
  final int doctorId;
  const DoctorDashboardScreen({super.key, required this.doctorId});
  @override
  State<DoctorDashboardScreen> createState() => _DoctorDashboardScreenState();
}

class _DoctorDashboardScreenState extends State<DoctorDashboardScreen> {
  static const Color _brand = Color(0xFF1D9E75);

  List<dynamic> _patients = [];
  Map<String, dynamic>? _chatAnalytics;   // NEW
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
      _patients = await ApiService.getDoctorPatients(widget.doctorId);
      // NEW — load chat feedback analytics in parallel (ignore failure)
      try {
        _chatAnalytics =
            await ApiService.getChatFeedbackAnalytics(widget.doctorId);
      } catch (e) {
        debugPrint('Chat analytics load error: $e');
        _chatAnalytics = null;
      }
    } catch (e) {
      _error = e.toString();
      debugPrint(_error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showPatientDetail(Map<String, dynamic> p) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (_, controller) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: _PatientDetailSheet(
            patient: p,
            scrollController: controller,
          ),
        ),
      ),
    );
  }

  Color _riskColor(String risk) {
    switch (risk) {
      case 'High':
        return Colors.red;
      case 'Medium':
        return Colors.orange;
      case 'Low':
        return Colors.green;
      default:
        return Colors.blueGrey;
    }
  }

  Color _riskBg(String risk) {
    switch (risk) {
      case 'High':
        return Colors.red.shade50;
      case 'Medium':
        return Colors.orange.shade50;
      case 'Low':
        return Colors.green.shade50;
      default:
        return Colors.grey.shade100;
    }
  }

  @override
  Widget build(BuildContext context) {
    final high = _patients.where((p) => p['latest_risk'] == 'High').length;
    final med = _patients.where((p) => p['latest_risk'] == 'Medium').length;
    final low = _patients.where((p) => p['latest_risk'] == 'Low').length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Patient Triage'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(12),
                children: [
                  // ── Triage summary ──────────────────────────────
                  Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _triageStat('$high', 'High', Colors.red),
                          _triageStat('$med', 'Medium', Colors.orange),
                          _triageStat('$low', 'Low', Colors.green),
                          _triageStat('${_patients.length}',
                              'Total', _brand),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // ── Error ──────────────────────────────────────
                  if (_error != null)
                    Card(
                      color: Colors.red.shade50,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          'Failed to load: $_error',
                          style: TextStyle(color: Colors.red.shade800),
                        ),
                      ),
                    ),

                  // ── Empty ──────────────────────────────────────
                  if (_patients.isEmpty && _error == null)
                    Padding(
                      padding: const EdgeInsets.only(top: 80),
                      child: Column(
                        children: [
                          Icon(Icons.medical_services_outlined,
                              size: 64, color: Colors.grey.shade300),
                          const SizedBox(height: 12),
                          const Text('No patients assigned yet.',
                              style: TextStyle(
                                  fontSize: 16, color: Colors.grey)),
                        ],
                      ),
                    ),

                  // ── Patient list ───────────────────────────────
                  ..._patients.map((raw) {
                    final p = raw as Map<String, dynamic>;
                    final risk = p['latest_risk'] as String? ?? 'Unknown';
                    final alerts = p['unread_alerts'] as int? ?? 0;
                    final name = p['name'] as String? ?? '?';
                    return Card(
                      elevation: 1,
                      color: _riskBg(risk),
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      child: ListTile(
                        onTap: () => _showPatientDetail(p),
                        leading: CircleAvatar(
                          backgroundColor: _riskColor(risk).withOpacity(0.2),
                          child: Text(
                            name.isNotEmpty ? name[0].toUpperCase() : '?',
                            style: TextStyle(
                                color: _riskColor(risk),
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                        title: Text(name,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600)),
                        subtitle: Text(
                          '${p['cancer_type'] ?? 'No diagnosis'} · '
                          'Last log: ${p['last_log_date'] ?? 'Never'}',
                          style: const TextStyle(fontSize: 12),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (alerts > 0) ...[
                              Badge(
                                label: Text('$alerts'),
                                child: const Icon(Icons.notifications),
                              ),
                              const SizedBox(width: 8),
                            ],
                            RiskBadge(riskLevel: risk),
                          ],
                        ),
                      ),
                    );
                  }).toList(),

                  // ── NEW: Chat feedback analytics section ─────
                  if (_chatAnalytics != null) ...[
                    const SizedBox(height: 18),
                    _ChatFeedbackPanel(data: _chatAnalytics!),
                  ],

                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }

  Widget _triageStat(String v, String l, Color c) {
    return Column(
      children: [
        Text(v,
            style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: c)),
        Text(l,
            style: const TextStyle(fontSize: 11, color: Colors.grey)),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════
// NEW: Chat feedback analytics panel (FR27)
// ══════════════════════════════════════════════════════════════════

class _ChatFeedbackPanel extends StatelessWidget {
  final Map<String, dynamic> data;
  const _ChatFeedbackPanel({required this.data});

  static const Color _brand = Color(0xFF1D9E75);

  @override
  Widget build(BuildContext context) {
    final total = (data['total_ratings'] as int?) ?? 0;
    final positive = (data['positive'] as int?) ?? 0;
    final negative = (data['negative'] as int?) ?? 0;
    final recent = (data['recent_7_days'] as Map?) ?? {};
    final pos7 = (recent['positive'] as int?) ?? 0;
    final neg7 = (recent['negative'] as int?) ?? 0;
    final blocked = (data['blocked_sources'] as int?) ?? 0;
    final topPos = (data['top_positive'] as List?) ?? [];
    final topNeg = (data['top_negative'] as List?) ?? [];

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: const [
              Icon(Icons.insights, color: _brand, size: 20),
              SizedBox(width: 8),
              Text('Chatbot Knowledge Feedback',
                  style: TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700)),
            ]),
            const SizedBox(height: 4),
            Text(
              total == 0
                  ? 'No patient ratings recorded yet.'
                  : 'Patient thumbs-up / thumbs-down on chat responses.',
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
            const SizedBox(height: 12),

            // Counts row
            Row(children: [
              _statChip(
                icon: Icons.thumb_up,
                label: 'Helpful',
                value: positive,
                color: Colors.green.shade600,
              ),
              const SizedBox(width: 8),
              _statChip(
                icon: Icons.thumb_down,
                label: 'Not helpful',
                value: negative,
                color: Colors.red.shade600,
              ),
              const SizedBox(width: 8),
              _statChip(
                icon: Icons.block,
                label: 'Blocked',
                value: blocked,
                color: Colors.grey.shade700,
              ),
            ]),

            const SizedBox(height: 12),

            // Ratio bar
            if (total > 0)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Overall ratio',
                      style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade700,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: SizedBox(
                      height: 10,
                      child: Row(children: [
                        if (positive > 0)
                          Expanded(
                            flex: positive,
                            child: Container(color: Colors.green.shade400),
                          ),
                        if (negative > 0)
                          Expanded(
                            flex: negative,
                            child: Container(color: Colors.red.shade400),
                          ),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Last 7 days: $pos7 helpful, $neg7 not helpful',
                    style: const TextStyle(
                        fontSize: 11, color: Colors.grey),
                  ),
                ],
              ),

            // Top positive
            if (topPos.isNotEmpty) ...[
              const SizedBox(height: 14),
              _sectionHeader('TOP-RATED SOURCES', Colors.green.shade700),
              ...topPos.map<Widget>((s) =>
                  _sourceRow(s as Map<String, dynamic>, positive: true)),
            ],

            // Top negative
            if (topNeg.isNotEmpty) ...[
              const SizedBox(height: 12),
              _sectionHeader('NEEDS REVIEW', Colors.red.shade700),
              ...topNeg.map<Widget>((s) =>
                  _sourceRow(s as Map<String, dynamic>, positive: false)),
              if (blocked > 0) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(children: [
                    Icon(Icons.block,
                        size: 14, color: Colors.grey.shade700),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '$blocked source${blocked == 1 ? '' : 's'} '
                        'auto-blocked from retrievals (net rating ≤ -3)',
                        style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade800,
                            fontWeight: FontWeight.w500),
                      ),
                    ),
                  ]),
                ),
              ],
            ],

            if (topPos.isEmpty && topNeg.isEmpty && total > 0) ...[
              const SizedBox(height: 10),
              Text(
                'No clear ranking yet — more ratings needed.',
                style: TextStyle(
                    fontSize: 12, color: Colors.grey.shade700),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _statChip({
    required IconData icon,
    required String label,
    required int value,
    required Color color,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 4),
              Text(label,
                  style: TextStyle(
                      fontSize: 10.5,
                      color: color,
                      fontWeight: FontWeight.w600)),
            ]),
            const SizedBox(height: 4),
            Text('$value',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: color)),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(String text, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(text,
          style: TextStyle(
              fontSize: 11,
              letterSpacing: 0.6,
              fontWeight: FontWeight.w700,
              color: color)),
    );
  }

  Widget _sourceRow(Map<String, dynamic> s, {required bool positive}) {
    final title = (s['title'] as String?) ?? 'Knowledge';
    final page = s['page'];
    final type = (s['source_type'] as String?) ?? 'knowledge';
    final net = (s['net_rating'] as int?) ?? 0;
    final votes = (s['votes'] as int?) ?? 0;
    final color = positive ? Colors.green.shade600 : Colors.red.shade600;
    final icon = type == 'pdf'
        ? Icons.picture_as_pdf
        : (type == 'conversation'
            ? Icons.chat_bubble_outline
            : Icons.menu_book_outlined);

    String label = title;
    if (page != null) label += ' · p.$page';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        Icon(icon, size: 14, color: color.withOpacity(0.8)),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12.5),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            '${net > 0 ? '+' : ''}$net',
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: color),
          ),
        ),
        const SizedBox(width: 6),
        Text('$votes vote${votes == 1 ? '' : 's'}',
            style: const TextStyle(fontSize: 10, color: Colors.grey)),
      ]),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
// Patient detail sheet — FR13 trend charts + FR26 ML feedback
// ══════════════════════════════════════════════════════════════════

class _PatientDetailSheet extends StatefulWidget {
  final Map<String, dynamic> patient;
  final ScrollController scrollController;
  const _PatientDetailSheet(
      {required this.patient, required this.scrollController});
  @override
  State<_PatientDetailSheet> createState() => _PatientDetailSheetState();
}

class _PatientDetailSheetState extends State<_PatientDetailSheet> {
  static const Color _brand = Color(0xFF1D9E75);

  List<dynamic> _history = [];
  List<dynamic> _alerts = [];
  bool _loading = true;
  String _period = 'week';

  int get _patientId =>
      (widget.patient['patient_id'] as int?) ??
      (widget.patient['id'] as int? ?? 0);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final hist = await ApiService.getSymptomHistory(_patientId, _period);
      final alerts = await ApiService.getAlerts(_patientId);
      setState(() {
        _history = hist;
        _alerts = alerts;
      });
    } catch (e) {
      debugPrint('Detail load error: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _sendFeedback(int alertId, bool correct) async {
    try {
      await ApiService.submitMlFeedback(alertId, correct);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(correct
              ? 'Confirmed — prediction was correct'
              : 'Noted — prediction was incorrect, will improve model'),
          backgroundColor: correct ? Colors.green : Colors.orange,
        ),
      );
      await _load();
    } catch (e) {
      debugPrint(e.toString());
    }
  }

  Color _riskColor(String r) =>
      r == 'High' ? Colors.red : r == 'Medium' ? Colors.orange : Colors.green;

  @override
  Widget build(BuildContext context) {
    final risk = widget.patient['latest_risk'] as String? ?? 'Unknown';
    final name = widget.patient['name'] as String? ?? '';

    return Column(
      children: [
        Container(
          margin: const EdgeInsets.only(top: 8, bottom: 4),
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: Colors.grey.shade300,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        Expanded(
          child: ListView(
            controller: widget.scrollController,
            padding: const EdgeInsets.all(20),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name,
                            style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        Text(
                          '${widget.patient['cancer_type'] ?? 'Unknown'}'
                          ' · ${widget.patient['cancer_stage'] ?? ''}',
                          style: const TextStyle(color: Colors.grey),
                        ),
                        Text(
                          'Last log: ${widget.patient['last_log_date'] ?? 'Never'}',
                          style: const TextStyle(
                              color: Colors.grey, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  RiskBadge(riskLevel: risk),
                ],
              ),
              const SizedBox(height: 16),

              Row(
                children: [
                  const Text('Trend over:',
                      style: TextStyle(
                          fontWeight: FontWeight.w500, fontSize: 13)),
                  const SizedBox(width: 10),
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
                ],
              ),
              const SizedBox(height: 16),

              if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_history.isEmpty)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.grey),
                      SizedBox(width: 8),
                      Expanded(
                          child: Text(
                              'No symptom logs in this period yet.')),
                    ],
                  ),
                )
              else ...[
                _sectionTitle('Symptom Trends'),
                const SizedBox(height: 8),
                _buildTrendChart('Fatigue', 'fatigue', Colors.orange),
                const SizedBox(height: 16),
                _buildTrendChart('Chest Pain', 'chest_pain', Colors.red),
                const SizedBox(height: 16),
                _buildTrendChart(
                    'Shortness of Breath', 'shortness', Colors.blue),
                const SizedBox(height: 20),

                _sectionTitle('Risk History'),
                const SizedBox(height: 8),
                _buildRiskTimeline(),
                const SizedBox(height: 20),
              ],

              _sectionTitle('Alerts (${_alerts.length})'),
              const SizedBox(height: 8),
              if (_alerts.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text('No alerts for this patient.',
                      style: TextStyle(color: Colors.grey)),
                )
              else
                ..._alerts.take(5).map((raw) {
                  final a = raw as Map<String, dynamic>;
                  final r = a['risk'] as String? ?? 'Medium';
                  return Card(
                    elevation: 0,
                    color: _riskColor(r).withOpacity(0.07),
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    child: ListTile(
                      dense: true,
                      leading: Icon(Icons.warning_amber,
                          color: _riskColor(r)),
                      title: Text(a['message'] ?? '',
                          style: const TextStyle(fontSize: 13)),
                      subtitle: Text(a['created_at'] ?? '',
                          style: const TextStyle(fontSize: 11)),
                      trailing: (a['acknowledged'] as bool? ?? false)
                          ? const Icon(Icons.check,
                              color: Colors.green, size: 18)
                          : null,
                    ),
                  );
                }).toList(),

              const SizedBox(height: 20),

              if (risk == 'High' && _alerts.isNotEmpty) ...[
                const Divider(),
                _sectionTitle('ML Prediction Feedback'),
                const SizedBox(height: 4),
                const Text(
                  'Was the High-risk prediction correct for this patient? '
                  'Your answer helps improve the model.',
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        final firstAlertId = _alerts.first['id'] as int? ??
                            _alerts.first['alert_id'] as int? ??
                            0;
                        if (firstAlertId > 0) {
                          _sendFeedback(firstAlertId, true);
                        }
                      },
                      icon: const Icon(Icons.check, color: Colors.green),
                      label: const Text('Correct',
                          style: TextStyle(color: Colors.green)),
                      style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.green)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        final firstAlertId = _alerts.first['id'] as int? ??
                            _alerts.first['alert_id'] as int? ??
                            0;
                        if (firstAlertId > 0) {
                          _sendFeedback(firstAlertId, false);
                        }
                      },
                      icon: const Icon(Icons.close, color: Colors.red),
                      label: const Text('Incorrect',
                          style: TextStyle(color: Colors.red)),
                      style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.red)),
                    ),
                  ),
                ]),
              ],
              const SizedBox(height: 24),
            ],
          ),
        ),
      ],
    );
  }

  Widget _sectionTitle(String t) => Text(
        t,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      );

  Widget _buildTrendChart(String title, String field, Color color) {
    final sorted = List<Map<String, dynamic>>.from(
        _history.map((e) => e as Map<String, dynamic>))
      ..sort((a, b) =>
          (a['date'] as String).compareTo(b['date'] as String));

    final spots = <FlSpot>[];
    for (int i = 0; i < sorted.length; i++) {
      final v = sorted[i][field];
      if (v == null) continue;
      final d = (v is int) ? v.toDouble() : (v as num).toDouble();
      spots.add(FlSpot(i.toDouble(), d));
    }

    if (spots.isEmpty) {
      return Container(
        height: 60,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(children: [
          Icon(Icons.remove_circle_outline,
              color: Colors.grey.shade400, size: 18),
          const SizedBox(width: 8),
          Text('$title: no data',
              style: TextStyle(
                  color: Colors.grey.shade600, fontSize: 13)),
        ]),
      );
    }

    final lastVal = spots.last.y;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.show_chart, color: color, size: 16),
              const SizedBox(width: 6),
              Text(title,
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: color,
                      fontSize: 13)),
              const Spacer(),
              Text('Latest: ${lastVal.toStringAsFixed(0)}/10',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: color)),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 100,
            child: LineChart(
              LineChartData(
                minY: 0,
                maxY: 10,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: 2,
                  getDrawingHorizontalLine: (v) => FlLine(
                    color: Colors.grey.shade200,
                    strokeWidth: 1,
                  ),
                ),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      interval: 5,
                      reservedSize: 22,
                      getTitlesWidget: (v, _) => Text(
                        v.toInt().toString(),
                        style: TextStyle(
                            fontSize: 9, color: Colors.grey.shade600),
                      ),
                    ),
                  ),
                  rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                ),
                borderData: FlBorderData(show: false),
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: true,
                    color: color,
                    barWidth: 2.5,
                    dotData: FlDotData(
                      show: spots.length <= 12,
                      getDotPainter: (s, _, __, ___) =>
                          FlDotCirclePainter(
                              radius: 3,
                              color: color,
                              strokeWidth: 0),
                    ),
                    belowBarData: BarAreaData(
                      show: true,
                      color: color.withOpacity(0.15),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRiskTimeline() {
    final sorted = List<Map<String, dynamic>>.from(
        _history.map((e) => e as Map<String, dynamic>))
      ..sort((a, b) =>
          (b['date'] as String).compareTo(a['date'] as String));

    if (sorted.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: sorted.take(7).map((r) {
          final date = r['date'] as String? ?? '';
          final risk = r['predicted_risk'] as String? ?? 'Unknown';
          final conf = r['confidence'] as num?;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: _riskColor(risk),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                    child: Text(date,
                        style: const TextStyle(fontSize: 13))),
                Text(risk,
                    style: TextStyle(
                        color: _riskColor(risk),
                        fontWeight: FontWeight.w600,
                        fontSize: 13)),
                if (conf != null) ...[
                  const SizedBox(width: 8),
                  Text('${(conf * 100).toStringAsFixed(0)}%',
                      style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 11)),
                ],
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}
