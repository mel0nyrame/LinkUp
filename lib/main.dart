import 'package:flutter/material.dart';
import 'package:LinkUp/navigation/MainNavigation.dart';
import 'package:LinkUp/page/AuthWrapperPage.dart';
import 'package:LinkUp/utils/LogUtil.dart';
import 'package:LinkUp/utils/SystemSettingsUtil.dart';
void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  await LogUtil.init();
  await SystemSettingsUtil.init();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  static const Color iosBlue = Color(0xFF007AFF);
  static const Color iosGreen = Color(0xFF34C759);
  static const Color iosRed = Color(0xFFFF3B30);
  static const Color iosSecondaryText = Color(0xFF8E8E93);

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: iosBlue,
      brightness: Brightness.light,
      primary: iosBlue,
    );

    return MaterialApp(
      title: 'LinkUp',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: colorScheme,
        useMaterial3: true,
        scaffoldBackgroundColor: Colors.transparent,
        fontFamily: '.SF Pro Text',

        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          surfaceTintColor: Colors.transparent,
          shadowColor: Colors.transparent,
          centerTitle: false,
          titleTextStyle: TextStyle(
            color: Colors.black,
            fontSize: 34,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
            height: 1.1,
          ),
        ),

        cardTheme: CardThemeData(
          color: Colors.white.withOpacity(0.85),
          elevation: 0,
          surfaceTintColor: Colors.transparent,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          margin: EdgeInsets.zero,
        ),

        switchTheme: SwitchThemeData(
          thumbColor: WidgetStateProperty.resolveWith(
              (s) => s.contains(WidgetState.selected) ? Colors.white : Colors.white),
          trackColor: WidgetStateProperty.resolveWith((s) =>
              s.contains(WidgetState.selected) ? iosGreen : Colors.grey.shade300),
          trackOutlineColor: WidgetStateProperty.resolveWith((s) =>
              s.contains(WidgetState.selected) ? iosGreen : Colors.grey.shade300),
        ),

        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: iosBlue,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            minimumSize: const Size(double.infinity, 50),
            textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
          ),
        ),

        dividerTheme: DividerThemeData(
          color: Colors.black.withOpacity(0.06),
          thickness: 0.5,
          space: 0,
        ),

        listTileTheme: const ListTileThemeData(
          contentPadding: EdgeInsets.zero,
          titleTextStyle: TextStyle(fontSize: 17, fontWeight: FontWeight.w400, color: Colors.black),
          subtitleTextStyle: TextStyle(fontSize: 13, color: Color(0xFF8E8E93)),
        ),

        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: iosBlue,
            textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w400),
          ),
        ),
      ),
      home: const LiquidGlassScaffold(child: AuthWrapperPage(child: MainNavigator())),
    );
  }
}

/// Root scaffold that provides the gradient background visible through glass.
class LiquidGlassScaffold extends StatelessWidget {
  final Widget child;
  const LiquidGlassScaffold({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // Gradient background — visible through liquid glass blur
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFFE8F0FE), // light blue tint
                    Color(0xFFF2F2F7), // iOS light gray
                    Color(0xFFFFF5F5), // faint warm pink
                  ],
                ),
              ),
            ),
          ),
          Positioned.fill(child: child),
        ],
      ),
    );
  }
}
