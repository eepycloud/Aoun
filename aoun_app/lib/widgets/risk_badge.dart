import 'package:flutter/material.dart';

/// Reusable pill badge that colours itself based on risk level.
class RiskBadge extends StatelessWidget {
  final String riskLevel;
  const RiskBadge({super.key, required this.riskLevel});

  @override
  Widget build(BuildContext context) {
    Color bg, fg;
    switch (riskLevel) {
      case 'High':
        bg = Colors.red.shade100;    fg = Colors.red.shade800;    break;
      case 'Medium':
        bg = Colors.orange.shade100; fg = Colors.orange.shade800; break;
      case 'Low':
        bg = Colors.green.shade100;  fg = Colors.green.shade800;  break;
      default:
        bg = Colors.grey.shade200;   fg = Colors.grey.shade700;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(riskLevel,
          style: TextStyle(
              color: fg, fontWeight: FontWeight.bold, fontSize: 13)),
    );
  }
}
