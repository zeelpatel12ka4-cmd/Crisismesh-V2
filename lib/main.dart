import 'package:flutter/material.dart';
import 'core/database/database_service.dart';
import 'ui/sos_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Eagerly initialize SQLite database
  await DatabaseService.instance.database;

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
        scaffoldBackgroundColor: const Color(0xFFF9FAFB),
        colorScheme: const ColorScheme.light(
          primary: Color(0xFFEF4444), // Crimson/Red for emergency
          secondary: Color(0xFF3B82F6), // Blue
          surface: Color(0xFFF9FAFB),
          onPrimary: Colors.white,
          onSecondary: Colors.white,
          onSurface: Color(0xFF111827),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Color(0xFF111827),
          elevation: 1,
          iconTheme: IconThemeData(color: Color(0xFF4B5563)),
        ),
        textTheme: const TextTheme(
          titleLarge: TextStyle(
            color: Color(0xFF111827),
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
          bodyLarge: TextStyle(
            color: Color(0xFF374151),
            fontSize: 16,
          ),
          bodyMedium: TextStyle(
            color: Color(0xFF4B5563),
            fontSize: 14,
          ),
        ),
      ),
      home: const SosScreen(),
    );
  }
}
