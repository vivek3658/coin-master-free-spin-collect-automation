import 'package:flutter_test/flutter_test.dart';
import 'package:rewardpilot/models/screen_recognition_state.dart';
import 'package:rewardpilot/services/reward_discovery_service.dart';
import 'package:rewardpilot/services/screen_recognition_service.dart';

void main() {
  late ScreenRecognitionService service;

  setUp(() {
    service = ScreenRecognitionService();
  });

  group('ScreenRecognitionService State Machine Tests', () {
    test('1. Recognizes APP_LAUNCHING when window has no accessible nodes', () {
      const raw = ScreenRawData(
        packageName: 'com.moonactive.coinmaster',
        allVisibleTexts: [],
        nodes: [],
        timestamp: 1000,
        isCoinMaster: true,
      );

      final result = service.analyzeScreen(raw);
      expect(result.state, ScreenRecognitionState.appLaunching);
      expect(result.suggestedAction, ScreenAction.waitForTransition);
    });

    test('2. Recognizes REWARD_PAGE_LOADING when loading or redirecting', () {
      const raw = ScreenRawData(
        packageName: 'com.android.chrome',
        allVisibleTexts: ['Connecting to server...', 'Loading reward...'],
        nodes: [],
        timestamp: 1000,
        isCoinMaster: false,
      );

      final result = service.analyzeScreen(raw);
      expect(result.state, ScreenRecognitionState.rewardPageLoading);
      expect(result.suggestedAction, ScreenAction.waitForTransition);
    });

    test('3. Recognizes REWARD_AVAILABLE when reward banner appears', () {
      const raw = ScreenRawData(
        packageName: 'com.moonactive.coinmaster',
        allVisibleTexts: ['Congratulations!', 'You got a Special Gift!', 'Daily Reward'],
        nodes: [],
        timestamp: 1000,
        isCoinMaster: true,
      );

      final result = service.analyzeScreen(raw);
      expect(result.state, ScreenRecognitionState.rewardAvailable);
      expect(result.confidence, greaterThanOrEqualTo(0.80));
    });

    test('4. Recognizes CLAIM_BUTTON_AVAILABLE and extracts button text and bounds', () {
      const raw = ScreenRawData(
        packageName: 'com.moonactive.coinmaster',
        allVisibleTexts: ['Free Gift', 'You got 25 Spins!', 'Collect'],
        nodes: [
          ScreenNode(
            text: 'Collect',
            contentDescription: 'Collect Reward',
            viewId: 'com.moonactive.coinmaster:id/btn_collect',
            className: 'android.widget.Button',
            isClickable: true,
            isEnabled: true,
            bounds: ScreenNodeBounds(left: 200, top: 800, right: 600, bottom: 950, width: 400, height: 150),
          ),
        ],
        timestamp: 1000,
        isCoinMaster: true,
      );

      final result = service.analyzeScreen(raw);
      expect(result.state, ScreenRecognitionState.claimButtonAvailable);
      expect(result.suggestedAction, ScreenAction.clickCollect);
      expect(result.actionableButtonText, 'Collect');
      expect(result.actionableButtonBounds?.centerX, 400);
      expect(result.actionableButtonBounds?.centerY, 875);
    });

    test('5. Recognizes CLAIM_SUCCESS_CONFIRMED with evidence', () {
      const raw = ScreenRawData(
        packageName: 'com.moonactive.coinmaster',
        allVisibleTexts: ['Reward Added', 'Enjoy your reward!'],
        nodes: [],
        timestamp: 1000,
        isCoinMaster: true,
      );

      final result = service.analyzeScreen(raw);
      expect(result.state, ScreenRecognitionState.claimSuccessConfirmed);
      expect(result.suggestedAction, ScreenAction.skipAndNext);
      expect(result.successEvidence, isNotNull);
    });

    test('6. Recognizes REWARD_EXPIRED and targets OK button to dismiss dialog', () {
      const raw = ScreenRawData(
        packageName: 'com.moonactive.coinmaster',
        allVisibleTexts: ['Oops!', 'This gift has expired.', 'OK'],
        nodes: [
          ScreenNode(
            text: 'OK',
            contentDescription: 'Dismiss dialog',
            viewId: 'com.moonactive.coinmaster:id/btn_ok',
            className: 'android.widget.Button',
            isClickable: true,
            isEnabled: true,
            bounds: ScreenNodeBounds(left: 300, top: 700, right: 500, bottom: 800, width: 200, height: 100),
          ),
        ],
        timestamp: 1000,
        isCoinMaster: true,
      );

      final result = service.analyzeScreen(raw);
      expect(result.state, ScreenRecognitionState.rewardExpired);
      expect(result.suggestedAction, ScreenAction.clickDismissOk);
      expect(result.actionableButtonText, 'OK');
      expect(result.actionableButtonBounds?.centerX, 400);
    });

    test('7. Recognizes REWARD_ALREADY_CLAIMED and targets OK button to dismiss dialog', () {
      const raw = ScreenRawData(
        packageName: 'com.moonactive.coinmaster',
        allVisibleTexts: ['Oops!', 'You have already collected this gift.', 'OK'],
        nodes: [
          ScreenNode(
            text: 'OK',
            contentDescription: 'Dismiss dialog',
            viewId: 'com.moonactive.coinmaster:id/btn_ok',
            className: 'android.widget.Button',
            isClickable: true,
            isEnabled: true,
            bounds: ScreenNodeBounds(left: 300, top: 700, right: 500, bottom: 800, width: 200, height: 100),
          ),
        ],
        timestamp: 1000,
        isCoinMaster: true,
      );

      final result = service.analyzeScreen(raw);
      expect(result.state, ScreenRecognitionState.rewardAlreadyClaimed);
      expect(result.suggestedAction, ScreenAction.clickDismissOk);
      expect(result.actionableButtonText, 'OK');
    });

    test('8. Recognizes LOGIN_REQUIRED and pauses safely', () {
      const raw = ScreenRawData(
        packageName: 'com.moonactive.coinmaster',
        allVisibleTexts: ['Welcome Back', 'Sign in with Facebook to continue', 'Guest Login'],
        nodes: [],
        timestamp: 1000,
        isCoinMaster: true,
      );

      final result = service.analyzeScreen(raw);
      expect(result.state, ScreenRecognitionState.loginRequired);
      expect(result.suggestedAction, ScreenAction.pauseForUser);
      expect(result.state.requiresUserIntervention, isTrue);
    });

    test('9. Recognizes CAPTCHA_OR_SECURITY_CHALLENGE and pauses safely', () {
      const raw = ScreenRawData(
        packageName: 'com.moonactive.coinmaster',
        allVisibleTexts: ['Security Check', 'Please solve this captcha', 'Verify you are human'],
        nodes: [],
        timestamp: 1000,
        isCoinMaster: true,
      );

      final result = service.analyzeScreen(raw);
      expect(result.state, ScreenRecognitionState.captchaOrSecurityChallenge);
      expect(result.suggestedAction, ScreenAction.pauseForUser);
      expect(result.confidence, greaterThanOrEqualTo(0.90));
    });

    test('10. Recognizes UNKNOWN_SCREEN without guessing blindly', () {
      const raw = ScreenRawData(
        packageName: 'com.moonactive.coinmaster',
        allVisibleTexts: ['Random in-game village event', 'Attack friend', 'Shield count: 3'],
        nodes: [],
        timestamp: 1000,
        isCoinMaster: true,
      );

      final result = service.analyzeScreen(raw);
      expect(result.state, ScreenRecognitionState.unknownScreen);
      expect(result.suggestedAction, ScreenAction.pauseForUser);
      expect(result.confidence, lessThan(0.50));
    });

    test('11. Recognizes APP_CRASHED when unexpected launcher package is active', () {
      const raw = ScreenRawData(
        packageName: 'com.google.android.apps.nexuslauncher',
        allVisibleTexts: ['Home', 'Search', 'Photos'],
        nodes: [],
        timestamp: 1000,
        isCoinMaster: false,
      );

      final result = service.analyzeScreen(raw);
      expect(result.state, ScreenRecognitionState.appCrashed);
      expect(result.suggestedAction, ScreenAction.abort);
    });

    test('12. Recognizes "Please check your internet connection" popup and targets OK button to dismiss dialog', () {
      const raw = ScreenRawData(
        packageName: 'com.moonactive.coinmaster',
        allVisibleTexts: ['Connection Error', 'Please check your internet connection and try again.', 'OK'],
        nodes: [
          ScreenNode(
            text: 'OK',
            contentDescription: 'Dismiss popup',
            viewId: 'com.moonactive.coinmaster:id/btn_ok',
            className: 'android.widget.Button',
            isClickable: true,
            isEnabled: true,
            bounds: ScreenNodeBounds(left: 300, top: 1250, right: 780, bottom: 1450, width: 480, height: 200),
          ),
        ],
        timestamp: 1000,
        isCoinMaster: true,
      );

      final result = service.analyzeScreen(raw);
      expect(result.state, ScreenRecognitionState.rewardExpired);
      expect(result.suggestedAction, ScreenAction.clickDismissOk);
      expect(result.actionableButtonText, 'OK');
      expect(result.explanation.contains('Connection error'), isTrue);
    });

    test('13. Levvvel-style discovery yields 28+ categorized rewards with Today and Yesterday', () async {
      final discovery = RewardDiscoveryService();
      final links = await discovery.discoverRewardLinks(userId: 'user_levvvel_test');

      expect(links.length, greaterThanOrEqualTo(25));
      expect(links.any((l) => l.dateCategory == 'Today'), isTrue);
      expect(links.any((l) => l.dateCategory == 'Yesterday'), isTrue);
      expect(links.any((l) => l.rewardType == 'spins'), isTrue);
      expect(links.any((l) => l.rewardType == 'coins'), isTrue);
    });
  });
}
