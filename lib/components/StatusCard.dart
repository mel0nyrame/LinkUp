import 'package:flutter/material.dart';
import 'package:LinkUp/main.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

class Statuscard extends StatefulWidget {
  final bool isOnline;
  final String? statusText;
  final String? detailText;
  final String? errorMsg;

  const Statuscard({
    super.key,
    this.isOnline = false,
    this.statusText,
    this.detailText,
    this.errorMsg,
  });

  @override
  State<Statuscard> createState() => _StatuscardState();
}

class _StatuscardState extends State<Statuscard>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseCtrl;
  late Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat(reverse: true);
    _pulse = Tween(begin: 1.0, end: 1.06).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool online = widget.isOnline;
    final Color statusColor = online ? MyApp.iosGreen : MyApp.iosRed;
    final String title = widget.statusText ?? (online ? '已连接' : '未连接');
    final String? subtitle = widget.detailText ?? widget.errorMsg;

    return RepaintBoundary(
      child: LiquidGlass.withOwnLayer(
        settings: LiquidGlassSettings(
          blur: 14,
          thickness: 10,
          glassColor: const Color(0x1AFFFFFF),
          saturation: 1.05,
        ),
        shape: LiquidRoundedSuperellipse(borderRadius: 20),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Pulsing status circle
              AnimatedBuilder(
                animation: _pulse,
                builder: (context, child) {
                  return Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: statusColor.withOpacity(0.12),
                    ),
                    child: Center(
                      child: Transform.scale(
                        scale: _pulse.value,
                        child: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: statusColor,
                            boxShadow: [
                              BoxShadow(
                                color: statusColor.withOpacity(0.35),
                                blurRadius: 16,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 20),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: Colors.black,
                  letterSpacing: -0.5,
                ),
              ),
              if (subtitle != null && subtitle.isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: statusColor,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
