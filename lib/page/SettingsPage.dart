import 'package:flutter/material.dart';
import 'package:LinkUp/components/AccountCard.dart';
import 'package:LinkUp/components/NetWorkConfig.dart';
import 'package:LinkUp/components/SystemSettingsCard.dart';
import 'package:LinkUp/components/LogViewerCard.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  Key _refreshKey = UniqueKey();

  void _onConfigChanged() {
    setState(() => _refreshKey = UniqueKey());
  }

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        // Large title header
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(20, 12, 20, 4),
            child: Text(
              '设置',
              style: TextStyle(
                fontSize: 34,
                fontWeight: FontWeight.w700,
                color: Colors.black,
                letterSpacing: -0.5,
                height: 1.1,
              ),
            ),
          ),
        ),
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Text(
              '配置认证参数和系统选项',
              style: TextStyle(fontSize: 15, color: Color(0xFF8E8E93)),
            ),
          ),
        ),

        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              AccountCard(key: _refreshKey, onConfigChanged: _onConfigChanged),
              const SizedBox(height: 16),
              const SystemSettingsCard(),
              const SizedBox(height: 16),
              const NetworkConfigCard(),
              const SizedBox(height: 16),
              const LogViewerCard(),
              const SizedBox(height: 32),
              // Space for floating pill nav
              const SizedBox(height: 80),
            ]),
          ),
        ),
      ],
    );
  }
}
