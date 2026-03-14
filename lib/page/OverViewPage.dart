import 'package:flutter/material.dart';
import 'package:linkup/components/InformationCart.dart';
import 'package:linkup/components/OnlineDevicesCard.dart';
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
            child: Padding(
              padding: EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Statuscard(),

                  SizedBox(height: 16),

                  Informationcart(
                    icon: Icons.account_circle,
                    title: "账户信息",
                    children: [],
                  ),

                  SizedBox(height: 16),

                  Onlinedevices(),

                  SizedBox(height: 16),

                  Informationcart(
                    icon: Icons.data_usage,
                    title: "流量统计",
                    children: [],
                  ),

                  SizedBox(height: 16),

                  Informationcart(
                    icon: Icons.network_check,
                    title: "网络信息",
                    children: [],
                  ),

                  SizedBox(height: 16),

                  Informationcart(
                    icon: Icons.timer,
                    title: "在线时长",
                    children: [],
                  ),

                  SizedBox(height: 16),

                  Informationcart(
                    icon: Icons.account_balance_wallet,
                    title: "财务信息",
                    children: [],
                  ),

                  SizedBox(height: 16),

                  Informationcart(
                    icon: Icons.system_update,
                    title: "系统版本",
                    children: [],
                  )
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
