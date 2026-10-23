import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:rewardpilot/models/collector_config.dart';
import 'package:rewardpilot/models/reward_link.dart';
import 'package:rewardpilot/models/screen_recognition_state.dart';
import 'package:rewardpilot/services/autonomous_collection_coordinator.dart';
import 'package:rewardpilot/services/native_automation_service.dart';
import 'package:rewardpilot/services/reward_discovery_service.dart';
import 'package:rewardpilot/services/screen_recognition_service.dart';
import 'package:rewardpilot/services/storage_service.dart';

void main() {
  late Directory tempDir;
  late StorageService storageService;
  late MockAutomationService mockAutomation;
  late ScreenRecognitionService screenService;
  late RewardDiscoveryService discoveryService;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('rp_test_coord_');
    storageService = StorageService(baseDir: tempDir);
    mockAutomation = MockAutomationService();
    screenService = ScreenRecognitionService();
    discoveryService = RewardDiscoveryService();
  });

  tearDown(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('AutonomousCollectionCoordinator & Safety Rules Tests', () {
    test('1. Deduplication filters identical canonical URLs', () {
      final links = [
        RewardLink(
          id: '1',
          url: 'https://static.moonactive.net/c/v/?c=abc12345',
          canonicalUrl: 'moonactive://campaign/abc12345',
          source: 'Facebook',
          rewardTitle: '25 Spins',
          discoveredAt: DateTime.now(),
          userId: 'u1',
        ),
        RewardLink(
          id: '2',
          url: 'https://static.moonactive.net/c/v/?c=abc12345&utm_source=fb',
          canonicalUrl: 'moonactive://campaign/abc12345',
          source: 'Twitter',
          rewardTitle: '25 Spins',
          discoveredAt: DateTime.now(),
          userId: 'u1',
        ),
      ];

      final deduped = discoveryService.deduplicateLinks(links);
      expect(deduped.length, 1);
      expect(deduped.first.id, '1');
    });

    test('2. Per-User Isolation: User A claimed rewards do not affect User B', () async {
      final userA = 'user_alpha';
      final userB = 'user_beta';

      final link = RewardLink(
        id: 'cm_01',
        url: 'https://static.moonactive.net/c/v/?c=shared_campaign',
        canonicalUrl: 'moonactive://campaign/shared_campaign',
        source: 'Official Feed',
        rewardTitle: '25 Spins',
        discoveredAt: DateTime.now(),
        userId: userA,
        status: RewardClaimStatus.claimed,
        claimedAt: DateTime.now(),
      );

      await storageService.saveRewardLinkOutcome(userA, link);

      // Verify User A has it recorded
      final histA = await storageService.getRewardHistory(userA);
      expect(histA[link.canonicalUrl]?.status, RewardClaimStatus.claimed);

      // Verify User B is isolated and has NO record of it
      final histB = await storageService.getRewardHistory(userB);
      expect(histB.containsKey(link.canonicalUrl), isFalse);
    });

    test('3. Collects eligible reward and activates Collect button', () async {
      mockAutomation.nextScreenData = const ScreenRawData(
        packageName: 'com.moonactive.coinmaster',
        allVisibleTexts: ['Congratulations!', 'Collect 25 Free Spins', 'Collect'],
        nodes: [
          ScreenNode(
            text: 'Collect',
            contentDescription: 'Collect Reward',
            viewId: 'com.moonactive.coinmaster:id/btn_collect',
            className: 'android.widget.Button',
            isClickable: true,
            isEnabled: true,
            bounds: ScreenNodeBounds(left: 300, top: 1200, right: 780, bottom: 1350, width: 480, height: 150),
          ),
        ],
        timestamp: 1000,
        isCoinMaster: true,
      );

      final coordinator = AutonomousCollectionCoordinator(
        automationService: mockAutomation,
        screenService: screenService,
        discoveryService: discoveryService,
        storageService: storageService,
        userId: 'test_user',
        initialConfig: CollectorConfig(clickDelayMs: 10, maxLinksPerRun: 1),
      );

      await coordinator.startAutonomousCollection();
      await Future.delayed(const Duration(milliseconds: 50));

      expect(coordinator.stats.claimedCount, 1);
      expect(mockAutomation.actionHistory.any((a) => a.contains('click: targetText=Collect')), isTrue);
    });

    test('4. Clicks OK on expired link to clear dialog (User requirement verification)', () async {
      // Mock expired screen
      mockAutomation.nextScreenData = const ScreenRawData(
        packageName: 'com.moonactive.coinmaster',
        allVisibleTexts: ['Oops!', 'This gift has expired.', 'OK'],
        nodes: [
          ScreenNode(
            text: 'OK',
            contentDescription: 'Dismiss popup',
            viewId: 'com.moonactive.coinmaster:id/btn_ok',
            className: 'android.widget.Button',
            isClickable: true,
            isEnabled: true,
            bounds: ScreenNodeBounds(left: 400, top: 1100, right: 680, bottom: 1220, width: 280, height: 120),
          ),
        ],
        timestamp: 1000,
        isCoinMaster: true,
      );

      final coordinator = AutonomousCollectionCoordinator(
        automationService: mockAutomation,
        screenService: screenService,
        discoveryService: discoveryService,
        storageService: storageService,
        userId: 'test_user',
        initialConfig: CollectorConfig(clickDelayMs: 10, maxLinksPerRun: 1),
      );

      await coordinator.startAutonomousCollection();

      expect(coordinator.stats.expiredCount, 1);
      // Verify OK button click was dispatched!
      expect(mockAutomation.actionHistory.any((a) => a.contains('click: targetText=OK')), isTrue);
    });

    test('5. Safety Rule: Consecutive Expired Threshold triggers halt at 3 links', () async {
      // Mock expired screen always
      mockAutomation.nextScreenData = const ScreenRawData(
        packageName: 'com.moonactive.coinmaster',
        allVisibleTexts: ['Oops!', 'This gift has expired.', 'OK'],
        nodes: [
          ScreenNode(
            text: 'OK',
            contentDescription: 'Dismiss popup',
            viewId: 'com.moonactive.coinmaster:id/btn_ok',
            className: 'android.widget.Button',
            isClickable: true,
            isEnabled: true,
            bounds: ScreenNodeBounds(left: 400, top: 1100, right: 680, bottom: 1220, width: 280, height: 120),
          ),
        ],
        timestamp: 1000,
        isCoinMaster: true,
      );

      final coordinator = AutonomousCollectionCoordinator(
        automationService: mockAutomation,
        screenService: screenService,
        discoveryService: discoveryService,
        storageService: storageService,
        userId: 'test_user',
        initialConfig: CollectorConfig(
          consecutiveExpiredThreshold: 3,
          clickDelayMs: 5,
          maxLinksPerRun: 10,
        ),
      );

      await coordinator.startAutonomousCollection();

      expect(coordinator.stats.expiredCount, 3);
      expect(coordinator.stats.consecutiveExpiredCount, 3);
      expect(coordinator.runStatus, CollectionRunStatus.stoppedBySafetyCondition);
    });

    test('6. Emergency Force Stop immediately halts execution and prevents further actions', () async {
      mockAutomation.nextScreenData = const ScreenRawData(
        packageName: 'com.moonactive.coinmaster',
        allVisibleTexts: ['Congratulations!', 'Collect 25 Free Spins', 'Collect'],
        nodes: [
          ScreenNode(
            text: 'Collect',
            contentDescription: 'Collect Reward',
            viewId: 'com.moonactive.coinmaster:id/btn_collect',
            className: 'android.widget.Button',
            isClickable: true,
            isEnabled: true,
            bounds: ScreenNodeBounds(left: 300, top: 1200, right: 780, bottom: 1350, width: 480, height: 150),
          ),
        ],
        timestamp: 1000,
        isCoinMaster: true,
      );

      final coordinator = AutonomousCollectionCoordinator(
        automationService: mockAutomation,
        screenService: screenService,
        discoveryService: discoveryService,
        storageService: storageService,
        userId: 'test_user',
        initialConfig: CollectorConfig(clickDelayMs: 500),
      );

      // Start run asynchronously
      final runFuture = coordinator.startAutonomousCollection();

      // Trigger immediate emergency Force Stop
      await Future.delayed(const Duration(milliseconds: 30));
      await coordinator.forceStop();

      await runFuture;

      expect(coordinator.isForceStopped, isTrue);
      expect(mockAutomation.isForceStopped, isTrue);
      expect(mockAutomation.actionHistory.contains('force_stop'), isTrue);
      expect(coordinator.stats.currentAction, 'Force stopped');
    });

    test('7. Interrupted queue is saved and can be safely resumed', () async {
      final queue = [
        RewardLink(
          id: 'int_01',
          url: 'https://static.moonactive.net/c/v/?c=int_01',
          canonicalUrl: 'moonactive://campaign/int_01',
          source: 'Feed',
          rewardTitle: '25 Spins',
          discoveredAt: DateTime.now(),
          userId: 'test_user',
        ),
        RewardLink(
          id: 'int_02',
          url: 'https://static.moonactive.net/c/v/?c=int_02',
          canonicalUrl: 'moonactive://campaign/int_02',
          source: 'Feed',
          rewardTitle: '25 Spins',
          discoveredAt: DateTime.now(),
          userId: 'test_user',
        ),
      ];

      await storageService.saveInterruptedQueue('test_user', queue, 1);

      final saved = await storageService.getInterruptedQueue('test_user');
      expect(saved, isNotNull);
      expect(saved!['currentIndex'], 1);

      await storageService.clearInterruptedQueue('test_user');
      final cleared = await storageService.getInterruptedQueue('test_user');
      expect(cleared, isNull);
    });
  });
}
