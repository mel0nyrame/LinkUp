import 'package:flutter/material.dart';
import 'package:LinkUp/components/GlassCard.dart';
import 'package:LinkUp/main.dart';

class InfoCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final List<Widget> children;

  const InfoCard({
    super.key,
    required this.icon,
    required this.title,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: MyApp.iosBlue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: MyApp.iosBlue, size: 18),
              ),
              const SizedBox(width: 10),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: Colors.black,
                ),
              ),
            ],
          ),
          if (children.isNotEmpty) ...[
            const SizedBox(height: 12),
            Divider(color: Colors.black.withOpacity(0.06), height: 1),
            const SizedBox(height: 8),
            ...children,
          ],
        ],
      ),
    );
  }
}
