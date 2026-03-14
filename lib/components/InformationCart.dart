import 'package:flutter/material.dart';

class Informationcart extends StatefulWidget {
  IconData icon;
  String title;
  List<Widget> children;
  
  Informationcart({super.key,required this.icon,required this.title,required this.children});

  @override
  State<Informationcart> createState() => _InformationcartState();
}

class _InformationcartState extends State<Informationcart> {
  
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(widget.icon, color: colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  widget.title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            ...widget.children,
          ],
        ),
      ),
    );
  }
}