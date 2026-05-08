import 'package:flutter/material.dart';
import 'package:LinkUp/main.dart';

class InfoDataRow extends StatelessWidget {
  final String label;
  final dynamic value;
  final IconData icon;
  final Color? valueColor;

  const InfoDataRow({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Icon(icon, size: 17, color: MyApp.iosSecondaryText),
          const SizedBox(width: 10),
          Text(
            label,
            style: const TextStyle(
              fontSize: 15,
              color: Color(0xFF8E8E93),
            ),
          ),
          const Spacer(),
          Text(
            value?.toString() ?? '-',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: valueColor ?? Colors.black.withOpacity(0.85),
            ),
          ),
        ],
      ),
    );
  }
}
