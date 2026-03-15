import 'package:flutter/material.dart';
import 'package:LinkUp/navigation/MainNavigation.dart';
import 'package:LinkUp/page/AuthWrapperPage.dart';
import 'package:LinkUp/utils/SystemSettingsUtil.dart';

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  // 初始化系统设置（后台保活等）
  await SystemSettingsUtil.init();
  
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LinkUp',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1565C0),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        cardTheme: CardThemeData(
          elevation: 3,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
      ),
      home: const AuthWrapperPage(
        child: MainNavigator(), // 配置完成后进入主页面
      ),
    );
  }
}
