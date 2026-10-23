import 'package:flutter/material.dart';
import 'services/native_automation_service.dart';
import 'services/storage_service.dart';
import 'ui/screens/dashboard_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final storageService = StorageService();
  runApp(RewardPilotApp(storageService: storageService));
}

class RewardPilotApp extends StatelessWidget {
  final StorageService storageService;
  final NativeAutomationService? automationService;

  const RewardPilotApp({
    super.key,
    required this.storageService,
    this.automationService,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RewardPilot',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0F172A),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF6366F1),
          secondary: Color(0xFF10B981),
          surface: Color(0xFF1E293B),
          error: Color(0xFFEF4444),
        ),
        fontFamily: 'Roboto',
      ),
      home: DashboardScreen(
        storageService: storageService,
        automationService: automationService,
      ),
    );
  }
}

