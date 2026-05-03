import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

///
/// "The system shall display an emergency interface and guide patients to
///  contact emergency services when critical risk levels are detected."
///
/// This screen is shown:
///   • Automatically when the ML predicts High risk AND a red-flag symptom
///     is extreme (coughing blood, severe chest pain, etc.)
///   • From the home screen SOS button (always accessible)
///   • From the chatbot's emergency intent
///
/// Design goals:
///   • Dominant red color — unambiguously urgent
///   • Very large, high-contrast call buttons (one tap to dial)
///   • Clear "what to do" bullets — no medical jargon
///   • Works even if patient is panicking (minimal cognitive load)
class EmergencyScreen extends StatelessWidget {
  /// Set this from your backend profile when available.
  /// Null = hide the "Call my doctor" button.
  final String? doctorPhone;

  /// If this screen was opened because of a specific trigger, we show it
  /// at the top so the patient knows why.
  final String? triggerReason;

  const EmergencyScreen({
    super.key,
    this.doctorPhone,
    this.triggerReason,
  });

  // Jordan emergency number (also works: 199 ambulance, 112 European)
  static const String _emergencyNumber = '911';

  Future<void> _callNumber(BuildContext context, String number) async {
    HapticFeedback.heavyImpact();
    final uri = Uri(scheme: 'tel', path: number);
    try {
      final ok = await launchUrl(uri);
      if (!ok && context.mounted) {
        _showFallback(context, number);
      }
    } catch (_) {
      if (context.mounted) _showFallback(context, number);
    }
  }

  void _showFallback(BuildContext context, String number) {
    // If the dialer can't launch, show a copyable number in a dialog
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Call this number'),
        content: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Expanded(
              child: Text(
                number,
                style: const TextStyle(
                    fontSize: 28, fontWeight: FontWeight.bold),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.copy),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: number));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Number copied'),
                    duration: Duration(seconds: 1),
                  ),
                );
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFEF3F3),
      appBar: AppBar(
        backgroundColor: Colors.red.shade700,
        foregroundColor: Colors.white,
        title: const Text('Emergency',
            style: TextStyle(fontWeight: FontWeight.bold)),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            // ── Trigger reason banner ───────────────────────
            if (triggerReason != null) ...[
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.red.shade100,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.red.shade300),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber_rounded,
                        color: Colors.red.shade800, size: 28),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        triggerReason!,
                        style: TextStyle(
                            color: Colors.red.shade900,
                            fontWeight: FontWeight.w600,
                            fontSize: 14),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],

            // ── Primary message ─────────────────────────────
            const Text(
              'Need help right now?',
              style: TextStyle(
                  fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Tap the button below to call emergency services immediately.',
              style: TextStyle(
                  fontSize: 15, color: Colors.grey.shade800, height: 1.4),
            ),
            const SizedBox(height: 24),

            // ── BIG CALL BUTTON ─────────────────────────────
            _EmergencyButton(
              label: 'CALL EMERGENCY',
              number: _emergencyNumber,
              color: Colors.red.shade700,
              icon: Icons.local_hospital,
              onTap: () => _callNumber(context, _emergencyNumber),
            ),
            const SizedBox(height: 14),

            // ── Doctor call button (if number is known) ──────
            if (doctorPhone != null && doctorPhone!.trim().isNotEmpty)
              _EmergencyButton(
                label: 'CALL MY DOCTOR',
                number: doctorPhone!,
                color: const Color(0xFF1D9E75),
                icon: Icons.medical_services,
                onTap: () => _callNumber(context, doctorPhone!),
              ),

            const SizedBox(height: 28),
            const Divider(),
            const SizedBox(height: 16),

            // ── Go to ER immediately if… ────────────────────
            const Text(
              'Go to the ER (or call emergency) immediately if you have:',
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            _RedFlagTile(
              icon: Icons.air,
              text: 'Severe trouble breathing or chest pain',
            ),
            _RedFlagTile(
              icon: Icons.bloodtype,
              text: 'Coughing up blood or vomiting blood',
            ),
            _RedFlagTile(
              icon: Icons.thermostat,
              text: 'Fever over 38°C / 100.4°F (with chemotherapy)',
            ),
            _RedFlagTile(
              icon: Icons.psychology,
              text: 'Sudden confusion, fainting, or loss of consciousness',
            ),
            _RedFlagTile(
              icon: Icons.healing,
              text: 'Uncontrolled bleeding or sudden severe pain',
            ),
            _RedFlagTile(
              icon: Icons.sick,
              text: 'Inability to keep fluids down for 24 hours',
            ),

            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 16),

            // ── While waiting for help ──────────────────────
            const Text(
              'While waiting for help:',
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            _WaitingStep(
              number: '1',
              text: 'Stay calm. Sit or lie down in a safe, comfortable '
                    'position.',
            ),
            _WaitingStep(
              number: '2',
              text: 'If someone is with you, ask them to stay nearby and '
                    'unlock the front door.',
            ),
            _WaitingStep(
              number: '3',
              text: 'Have your medication list and cancer diagnosis ready '
                    'to share with paramedics.',
            ),
            _WaitingStep(
              number: '4',
              text: 'Do not eat or drink unless instructed — in case '
                    'surgery is needed.',
            ),
            _WaitingStep(
              number: '5',
              text: 'If breathing is difficult, sit upright and try slow '
                    'pursed-lip breathing until help arrives.',
            ),

            const SizedBox(height: 30),

            // ── Dismiss ─────────────────────────────────────
            Center(
              child: TextButton.icon(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.arrow_back),
                label: const Text("I'm safe, go back"),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.grey.shade700,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 12),
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// Helpers
// ══════════════════════════════════════════════════════════════

class _EmergencyButton extends StatelessWidget {
  final String label;
  final String number;
  final Color color;
  final IconData icon;
  final VoidCallback onTap;

  const _EmergencyButton({
    required this.label,
    required this.number,
    required this.color,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      elevation: 4,
      shadowColor: color.withOpacity(0.4),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 16),
          child: Row(
            children: [
              Icon(icon, color: Colors.white, size: 40),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      number,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.85),
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.phone_forwarded,
                  color: Colors.white, size: 28),
            ],
          ),
        ),
      ),
    );
  }
}

class _RedFlagTile extends StatelessWidget {
  final IconData icon;
  final String text;
  const _RedFlagTile({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: Colors.red.shade700, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(text, style: const TextStyle(fontSize: 14)),
            ),
          ),
        ],
      ),
    );
  }
}

class _WaitingStep extends StatelessWidget {
  final String number;
  final String text;
  const _WaitingStep({required this.number, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: Colors.red.shade700,
            child: Text(
              number,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(text, style: const TextStyle(fontSize: 14)),
            ),
          ),
        ],
      ),
    );
  }
}
