import 'package:flutter/material.dart';
import 'package:linkup/components/StatusCard.dart';

class Overviewpage extends StatefulWidget {
  const Overviewpage({super.key});

  @override
  State<Overviewpage> createState() => _OverviewpageState();
}

class _OverviewpageState extends State<Overviewpage> {
  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async {
        await Future.delayed(const Duration(seconds: 1));
      },
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(padding:  EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Statuscard(),
                
                SizedBox(height: 16),

                
              ],
            ),
            ),
          )
        ],
      )
    );
  }
}