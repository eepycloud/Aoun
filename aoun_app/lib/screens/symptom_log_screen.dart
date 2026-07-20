import 'package:flutter/material.dart';
import '../api_service.dart';
import '../widgets/risk_badge.dart';

class SymptomLogScreen extends StatefulWidget {
  final int patientId;
  const SymptomLogScreen({super.key, required this.patientId});
  @override State<SymptomLogScreen> createState() => _SymptomLogScreenState();
}

class _SymptomLogScreenState extends State<SymptomLogScreen> {
  Map<String, double> _values = {
    'air_pollution': 0, 'alcohol_use': 0, 'dust_allergy': 0,
    'occupational_hazards': 0, 'genetic_risk': 0, 'chronic_lung_disease': 0,
    'balanced_diet': 5, 'obesity': 0, 'smoking': 0, 'passive_smoker': 0,
    'chest_pain': 0, 'coughing_of_blood': 0, 'fatigue': 0, 'weight_loss': 0,
    'shortness_of_breath': 0, 'wheezing': 0, 'swallowing_difficulty': 0,
    'clubbing_of_finger_nails': 0, 'frequent_cold': 0, 'dry_cough': 0, 'snoring': 0,
  };

  // Fetched from profile — not editable by user
  double _age    = 30;
  double _gender = 1; // 1=Male, 0=Female

  bool   _loading        = false;
  bool   _profileLoading = true;
  Map<String, dynamic>? _result;

  @override
  void initState() { super.initState(); _loadProfile(); }

  Future<void> _loadProfile() async {
    try {
      final profile = await ApiService.getProfile(widget.patientId);
      // Calculate age from date_of_birth
      final dob = profile['date_of_birth'] as String?;
      if (dob != null && dob.isNotEmpty) {
        final parts = dob.split('-');
        if (parts.length == 3) {
          final birthYear  = int.tryParse(parts[0]) ?? 0;
          final birthMonth = int.tryParse(parts[1]) ?? 1;
          final birthDay   = int.tryParse(parts[2]) ?? 1;
          final now = DateTime.now();
          int age = now.year - birthYear;
          if (now.month < birthMonth ||
              (now.month == birthMonth && now.day < birthDay)) age--;
          _age = age.toDouble().clamp(1, 100);
        }
      }
      // Map gender string to 0/1
      final genderStr = (profile['gender'] as String? ?? 'Male').toLowerCase();
      _gender = genderStr == 'female' ? 0.0 : 1.0;
    } catch (_) {
      // Keep defaults if profile fails — silent fallback
    } finally {
      if (mounted) setState(() => _profileLoading = false);
    }
  }

  final Map<String, IconData> _icons = {
    'air_pollution':            Icons.air,
    'alcohol_use':              Icons.local_bar,
    'dust_allergy':             Icons.filter_drama,
    'occupational_hazards':     Icons.engineering,
    'genetic_risk':             Icons.biotech,
    'chronic_lung_disease':     Icons.air,
    'balanced_diet':            Icons.restaurant,
    'obesity':                  Icons.monitor_weight,
    'smoking':                  Icons.smoking_rooms,
    'passive_smoker':           Icons.smoke_free,
    'chest_pain':               Icons.favorite,
    'coughing_of_blood':        Icons.bloodtype,
    'fatigue':                  Icons.battery_0_bar,
    'weight_loss':              Icons.trending_down,
    'shortness_of_breath':      Icons.air_outlined,
    'wheezing':                 Icons.graphic_eq,
    'swallowing_difficulty':    Icons.dining,
    'clubbing_of_finger_nails': Icons.pan_tool,
    'frequent_cold':            Icons.ac_unit,
    'dry_cough':                Icons.sick,
    'snoring':                  Icons.bedtime,
  };

  final Map<String, Color> _colors = {
    'air_pollution':            Colors.blue,
    'alcohol_use':              Colors.purple,
    'dust_allergy':             Colors.brown,
    'occupational_hazards':     Colors.orange,
    'genetic_risk':             Colors.indigo,
    'chronic_lung_disease':     Colors.teal,
    'balanced_diet':            Colors.green,
    'obesity':                  Colors.deepOrange,
    'smoking':                  Colors.grey,
    'passive_smoker':           Colors.blueGrey,
    'chest_pain':               Colors.red,
    'coughing_of_blood':        Colors.red,
    'fatigue':                  Colors.amber,
    'weight_loss':              Colors.cyan,
    'shortness_of_breath':      Colors.lightBlue,
    'wheezing':                 Colors.lime,
    'swallowing_difficulty':    Colors.pink,
    'clubbing_of_finger_nails': Colors.deepPurple,
    'frequent_cold':            Colors.lightBlue,
    'dry_cough':                Colors.orange,
    'snoring':                  Colors.purple,
  };

  final Map<String, String> _labels = {
    'air_pollution':            'Air Pollution Exposure',
    'alcohol_use':              'Alcohol Use',
    'dust_allergy':             'Dust Allergy',
    'occupational_hazards':     'Occupational Hazards',
    'genetic_risk':             'Genetic Risk',
    'chronic_lung_disease':     'Chronic Lung Disease',
    'balanced_diet':            'Balanced Diet',
    'obesity':                  'Obesity Level',
    'smoking':                  'Smoking',
    'passive_smoker':           'Passive Smoker Exposure',
    'chest_pain':               'Chest Pain',
    'coughing_of_blood':        'Coughing of Blood',
    'fatigue':                  'Fatigue',
    'weight_loss':              'Unexpected Weight Loss',
    'shortness_of_breath':      'Shortness of Breath',
    'wheezing':                 'Wheezing',
    'swallowing_difficulty':    'Swallowing Difficulty',
    'clubbing_of_finger_nails': 'Clubbing of Finger Nails',
    'frequent_cold':            'Frequent Colds',
    'dry_cough':                'Dry Cough',
    'snoring':                  'Snoring',
  };

  Future<void> _submit() async {
    setState(() { _loading = true; _result = null; });
    try {
      final data = {
        'age':        _age,
        'gender_val': _gender,
        ..._values.map((k, v) => MapEntry(k, v)),
      };
      final res = await ApiService.logSymptoms(widget.patientId, data);
      setState(() { _result = res; });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Colors.red));
    } finally {
      setState(() { _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_profileLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFFF5FBF8),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF5FBF8),
      appBar: AppBar(
        title: const Text('Log Daily Symptoms'),
        backgroundColor: const Color(0xFF1D9E75),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Info banner
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.teal.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.teal.shade100),
            ),
            child: const Row(children: [
              Icon(Icons.info_outline, color: Colors.teal, size: 18),
              SizedBox(width: 8),
              Expanded(child: Text(
                  'Move sliders to rate each item (0 = none, 10 = severe).',
                  style: TextStyle(color: Colors.teal, fontSize: 13))),
            ]),
          ),
          const SizedBox(height: 16),

          // Profile info chip — shows age & gender pulled from account
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.teal.shade100),
            ),
            child: Row(children: [
              const Icon(Icons.person_outline, color: Colors.teal, size: 18),
              const SizedBox(width: 8),
              Text(
                'Using your profile: Age ${_age.toInt()} · ${_gender == 1 ? 'Male' : 'Female'}',
                style: const TextStyle(color: Colors.teal, fontSize: 13),
              ),
              const Spacer(),
              const Icon(Icons.check_circle, color: Colors.teal, size: 16),
            ]),
          ),
          const SizedBox(height: 20),

          // Symptom sliders
          const Text('Symptoms & Risk Factors',
              style: TextStyle(fontWeight: FontWeight.bold,
                  fontSize: 15, color: Color(0xFF333333))),
          const SizedBox(height: 10),

          Card(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: _values.keys.map((key) => _buildSlider(
                  _labels[key] ?? key,
                  _values[key]!,
                  0, 10,
                      (v) => setState(() => _values[key] = v),
                  icon: _icons[key] ?? Icons.circle,
                  color: _colors[key] ?? Colors.teal,
                  divisions: 10,
                )).toList(),
              ),
            ),
          ),

          const SizedBox(height: 24),
          _loading
              ? const Center(child: CircularProgressIndicator())
              : ElevatedButton.icon(
            onPressed: _submit,
            icon: const Icon(Icons.send, color: Colors.white),
            label: const Text('Submit & Get Risk Assessment',
                style: TextStyle(fontSize: 15, color: Colors.white)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1D9E75),
              minimumSize: const Size(double.infinity, 52),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),

          if (_result != null) ...[
            const SizedBox(height: 20),
            _buildResultCard(_result!),
          ],
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildSlider(String label, double value, double min, double max,
      ValueChanged<double> onChanged,
      {required IconData icon, required Color color,
        int divisions = 10, String suffix = '', bool showInt = true}) {
    final display = showInt
        ? '${value.toInt()}$suffix'
        : suffix.isNotEmpty ? suffix : value.toStringAsFixed(0);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(label,
              style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13))),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(display, style: TextStyle(
                fontWeight: FontWeight.bold, color: color, fontSize: 13)),
          ),
        ]),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: color,
            thumbColor: color,
            inactiveTrackColor: color.withOpacity(0.2),
            overlayColor: color.withOpacity(0.15),
            trackHeight: 4,
          ),
          child: Slider(
            value: value, min: min, max: max,
            divisions: divisions, onChanged: onChanged,
          ),
        ),
        const Divider(height: 2),
        const SizedBox(height: 6),
      ]),
    );
  }

  Widget _buildResultCard(Map<String, dynamic> result) {
    final prediction   = result['prediction'] as Map<String, dynamic>?;
    final risk         = prediction?['risk_level'] as String? ?? 'Unknown';
    final confidence   = prediction?['confidence'] as num?;
    final confText     = confidence != null
        ? '${(confidence * 100).toStringAsFixed(1)}%' : 'N/A';
    final isHigh       = risk == 'High';
    final alertCreated = result['alert_created'] as bool? ?? false;
    final diagWarning  = result['diagnosis_warning'] as String?;
    final repeatedAlert= result['repeated_data_alert'] as String?;

    Color riskColor = risk == 'High'
        ? Colors.red : risk == 'Medium' ? Colors.orange : Colors.green;

    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.assessment, color: riskColor, size: 24),
            const SizedBox(width: 10),
            const Text('Risk Assessment',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const Spacer(),
            RiskBadge(riskLevel: risk),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            const Icon(Icons.percent, color: Colors.grey, size: 16),
            const SizedBox(width: 4),
            Text('Confidence: $confText',
                style: const TextStyle(color: Colors.grey)),
          ]),
          if (diagWarning != null) ...[
            const SizedBox(height: 10),
            _alertBanner(diagWarning, Colors.orange, Icons.info_outline),
          ],
          if (repeatedAlert != null) ...[
            const SizedBox(height: 10),
            _alertBanner(repeatedAlert, Colors.red, Icons.warning_amber),
          ],
          if (isHigh || alertCreated) ...[
            const SizedBox(height: 10),
            _alertBanner(
                'High risk detected! Your doctor has been notified.',
                Colors.red, Icons.warning),
          ],
        ]),
      ),
    );
  }

  Widget _alertBanner(String msg, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 8),
        Expanded(child: Text(msg,
            style: TextStyle(color: color, fontSize: 13))),
      ]),
    );
  }
}