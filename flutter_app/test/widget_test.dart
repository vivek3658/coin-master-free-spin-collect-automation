import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rewardpilot/main.dart';
import 'package:rewardpilot/services/native_automation_service.dart';
import 'package:rewardpilot/services/storage_service.dart';

void main() {
  testWidgets('RewardPilot Dashboard smoke test', (WidgetTester tester) async {
    // Set a realistic phone screen size (1080x1920) so all dashboard sections are visible
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final storage = MemoryStorageService();
    final mockAutomation = MockAutomationService();

    await tester.pumpWidget(RewardPilotApp(
      storageService: storage,
      automationService: mockAutomation,
    ));

    // Yield for microtasks to resolve _initApp
    await tester.pump();
    await tester.pump();

    // Verify key UI elements are present
    expect(find.text('RewardPilot'), findsOneWidget);
    expect(find.text('Autonomous Collector'), findsOneWidget);
    expect(find.text('⚡ COLLECT ALL SPINS'), findsOneWidget);
    expect(find.text('FORCE STOP'), findsOneWidget);
    expect(find.text('LIVE COLLECTION LOG'), findsOneWidget);
  });
}
