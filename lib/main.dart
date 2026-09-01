import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'core/database/database_service.dart';
import 'ui/sos_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Eagerly initialize SQLite database
  await DatabaseService.instance.database;

  // Set system UI overlay style for a clean emergency light theme
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: Colors.white,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Crisis Mesh',
      debugShowCheckedModeBanner: false,

      // Clean, high-contrast light theme for emergency readability
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        scaffoldBackgroundColor: const Color(0xFFF8FAFC), // Slate 50
        colorScheme: const ColorScheme.light(
          primary: Color(0xFFDC2626), // Crimson/Red 600 for emergency
          secondary: Color(0xFF2563EB), // Blue 600
          surface: Colors.white,
          onPrimary: Colors.white,
          onSecondary: Colors.white,
          onSurface: Color(0xFF0F172A), // Slate 900
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Color(0xFF0F172A),
          elevation: 0,
          scrolledUnderElevation: 1,
          surfaceTintColor: Colors.transparent,
          iconTheme: IconThemeData(color: Color(0xFF475569)),
        ),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: Color(0xFFE2E8F0)),
          ),
          margin: EdgeInsets.zero,
        ),
        dividerTheme: const DividerThemeData(
          color: Color(0xFFE2E8F0),
          thickness: 1,
          space: 1,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFFF8FAFC),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFFDC2626), width: 1.5),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          labelStyle: const TextStyle(color: Color(0xFF475569), fontSize: 14),
          hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
        ),
        textTheme: const TextTheme(
          titleLarge: TextStyle(
            color: Color(0xFF0F172A),
            fontWeight: FontWeight.w800,
            fontSize: 18,
            letterSpacing: -0.2,
          ),
          titleMedium: TextStyle(
            color: Color(0xFF0F172A),
            fontWeight: FontWeight.w700,
            fontSize: 15,
          ),
          bodyLarge: TextStyle(
            color: Color(0xFF334155),
            fontSize: 14,
            height: 1.4,
          ),
          bodyMedium: TextStyle(
            color: Color(0xFF475569),
            fontSize: 13,
            height: 1.4,
          ),
          bodySmall: TextStyle(
            color: Color(0xFF64748B),
            fontSize: 11,
          ),
        ),
      ),
      home: const SosScreen(),
    );
  }
}
