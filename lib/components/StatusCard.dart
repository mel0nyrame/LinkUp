import 'package:flutter/material.dart';
import 'package:LinkUp/main.dart';
import 'package:lightweight_liquid_glass/lightweight_liquid_glass.dart';

/// 状态卡沿用底部导航的玻璃观感（描边、高光、圆角），但关闭实时背景模糊：
/// 状态卡随概况页滚动，身后只有静态渐变，采样背景没有视觉收益，持续滑动
/// 却要反复读取背景。关闭模糊后由 [GlassStyle.backgroundGradient] 提供
/// 半透明卡面，配套的 `fallbackColor` 必须显式给 `Colors.transparent`，
/// 否则会回退到上游的不透明底色。
const GlassStyle _statusCardStyle = GlassStyle(
  blurEnabled: false,
  borderRadius: BorderRadius.all(Radius.circular(20)),
  shadowOpacity: 0,
  backgroundGradient: LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xE6FFFFFF), Color(0xCCFFFFFF)],
  ),
);

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
    _pulse = Tween(
      begin: 1.0,
      end: 1.06,
    ).animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));
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
      child: GlassSurface(
        style: _statusCardStyle,
        fallbackColor: Colors.transparent,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 脉冲自带一层 RepaintBoundary：圆点每帧重画时，玻璃表面与
              // 文字不必跟着重画。
              RepaintBoundary(
                child: AnimatedBuilder(
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 5,
                  ),
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
