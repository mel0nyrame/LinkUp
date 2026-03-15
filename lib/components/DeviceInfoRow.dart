import 'package:flutter/material.dart';

class DeviceInfoRow extends StatelessWidget {
  final String label;
  final String? value;

  const DeviceInfoRow({
    super.key,
    required this.label,
    this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4.0),
      child: Row(
        children: [
          Text(
            '$label: ',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade600,
            ),
          ),
          Expanded(
            child: Text(
              value ?? '-',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade800,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
