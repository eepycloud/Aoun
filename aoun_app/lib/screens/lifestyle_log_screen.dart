import 'package:flutter/material.dart';
import '../api_service.dart';

class LifestyleLogScreen extends StatefulWidget {
  final int patientId;
  const LifestyleLogScreen({super.key, required this.patientId});
  @override State<LifestyleLogScreen> createState() => _LifestyleLogScreenState();
}

class _LifestyleLogScreenState extends State<LifestyleLogScreen> {
  double _sleepHours   = 7;
  double _exerciseMins = 30;
  double _dietQuality  = 5;
  double _waterLitres  = 2;
  bool   _loading      = false;
  bool   _saved        = false;

  // History tab
  List<dynamic> _history = [];
  bool _historyLoading = false;
  String _period = 'week';

  @override
  void initState() { super.initState(); _loadHistory(); }

  Future<void> _loadHistory() async {
    setState(() => _historyLoading = true);
    try {
      _history = await ApiService.getLifestyleHistory(widget.patientId, _period);
    } catch (e) {
      debugPrint(e.toString());
    } finally {
      setState(() => _historyLoading = false);
    }
  }

  Future<void> _save() async {
    setState(() { _loading = true; _saved = false; });
    try {
      await ApiService.logLifestyle(widget.patientId, {
        'sleep_hours':    _sleepHours,
        'exercise_mins':  _exerciseMins.toInt(),
        'diet_quality':   _dietQuality.toInt(),
        'water_intake_l': _waterLitres,
      });
      setState(() => _saved = true);
      _loadHistory();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Colors.red));
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Lifestyle'),
          bottom: const TabBar(tabs: [
            Tab(text: 'Log Today'),
            Tab(text: 'History'),
          ]),
        ),
        body: TabBarView(children: [
          _buildLogTab(),
          _buildHistoryTab(),
        ]),
      ),
    );
  }

  Widget _buildLogTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Log your daily habits',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: Colors.grey)),
        const SizedBox(height: 20),

        _buildSlider('Sleep hours', _sleepHours, 0, 12,
            (v) => setState(() => _sleepHours = v), suffix: ' hrs', divisions: 24),
        _buildSlider('Exercise', _exerciseMins, 0, 120,
            (v) => setState(() => _exerciseMins = v), suffix: ' min', divisions: 24),
        _buildSlider('Diet quality (1–10)', _dietQuality, 1, 10,
            (v) => setState(() => _dietQuality = v), divisions: 9),
        _buildSlider('Water intake', _waterLitres, 0, 5,
            (v) => setState(() => _waterLitres = v), suffix: ' L', divisions: 10),

        const SizedBox(height: 24),
        if (_saved)
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.check_circle, color: Colors.green),
              SizedBox(width: 8),
              Text('Saved!', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
            ]),
          ),
        _loading
            ? const Center(child: CircularProgressIndicator())
            : ElevatedButton.icon(
                onPressed: _save,
                icon: const Icon(Icons.save),
                label: const Text('Save Today\'s Log'),
              ),
        const SizedBox(height: 40),
      ],
    );
  }

  Widget _buildHistoryTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'week', label: Text('Week')),
              ButtonSegment(value: 'month', label: Text('Month')),
            ],
            selected: {_period},
            onSelectionChanged: (s) {
              setState(() => _period = s.first);
              _loadHistory();
            },
          ),
        ),
        Expanded(
          child: _historyLoading
              ? const Center(child: CircularProgressIndicator())
              : _history.isEmpty
                  ? const Center(child: Text('No lifestyle data yet.\nLog your first entry!',
                        textAlign: TextAlign.center))
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      itemCount: _history.length,
                      itemBuilder: (_, i) {
                        final l = _history[i];
                        return Card(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(l['date'] ?? '',
                                  style: const TextStyle(fontWeight: FontWeight.bold,
                                      color: Color(0xFF1D9E75))),
                              const SizedBox(height: 8),
                              Row(children: [
                                _statChip('Sleep', '${l['sleep_hours'] ?? '-'} hrs', Icons.bedtime),
                                const SizedBox(width: 8),
                                _statChip('Exercise', '${l['exercise_mins'] ?? '-'} min', Icons.directions_walk),
                                const SizedBox(width: 8),
                                _statChip('Diet', '${l['diet_quality'] ?? '-'}/10', Icons.restaurant),
                              ]),
                            ]),
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }

  Widget _buildSlider(String label, double value, double min, double max,
      ValueChanged<double> onChanged, {int divisions = 10, String suffix = ''}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w500))),
          Text('${value.toStringAsFixed(value < 10 ? 1 : 0)}$suffix',
              style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1D9E75))),
        ]),
        Slider(value: value, min: min, max: max, divisions: divisions, onChanged: onChanged,
            activeColor: const Color(0xFF1D9E75)),
        const Divider(height: 4),
      ],
    );
  }

  Widget _statChip(String label, String value, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: const Color(0xFF1D9E75).withOpacity(0.08),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(children: [
          Icon(icon, size: 18, color: const Color(0xFF1D9E75)),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
          Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
        ]),
      ),
    );
  }
}
