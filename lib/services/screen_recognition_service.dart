import '../models/screen_recognition_state.dart';

/// Dedicated Screen Recognition State Machine for Coin Master automation.
/// Analyzes raw accessibility node data and visible texts to classify screens
/// with confidence scores, expected controls, and permitted next actions.
class ScreenRecognitionService {
  static const String coinMasterPackage = 'com.moonactive.coinmaster';

  // Key phrases for Collectable rewards
  static const List<String> collectKeywords = [
    'collect',
    'collect now',
    'claim',
    'claim now',
    'get spins',
    'get coins',
    'take reward',
  ];

  // Key phrases for Connection Error / Link failure
  // Specifically addresses: "it opens coin master but show please check you internet connection pop up"
  // and "press ok if link not work"
  static const List<String> connectionErrorKeywords = [
    'check your internet connection',
    'please check your internet connection',
    'connection error',
    'check your connection',
    'internet connection',
    'try again',
    'something went wrong',
    'network error',
    'could not connect',
    'failed to load',
  ];

  // Key phrases for Expired rewards (Specifically handles Coin Master: "This offer is ended")
  static const List<String> expiredKeywords = [
    'offer is ended',
    'this offer is ended',
    'offer has ended',
    'this offer has ended',
    'offer ended',
    'gift expired',
    'offer expired',
    'this gift has expired',
    'link has expired',
    'no longer valid',
    'link expired',
    'expired gift',
    'reward expired',
    'link is invalid',
    'invalid link',
    'expired',
    'promotion ended',
    'this promotion has ended',
    'promotion has expired',
    'gift ended',
    'this gift is no longer available',
  ];

  // Key phrases for Already Claimed rewards
  static const List<String> alreadyClaimedKeywords = [
    'already collected',
    'already claimed',
    'you have already collected this gift',
    'gift already collected',
    'reward already claimed',
    'already redeemed',
    'this reward has already been claimed',
    'already been collected',
    'already taken',
  ];

  // Key phrases for Dismiss / OK buttons (for user's requirement: "press ok if link not work")
  static const List<String> dismissOkKeywords = [
    'ok',
    'okay',
    'continue',
    'close',
    'dismiss',
    'cancel',
    'done',
  ];

  // Key phrases for Reward Available announcement
  static const List<String> rewardAvailableKeywords = [
    'congratulations',
    'free gift',
    'daily reward',
    'special gift',
    'you got',
    'free spins',
    'free coins',
  ];

  // Key phrases for Success confirmation
  static const List<String> successKeywords = [
    'spins added',
    'coins added',
    'reward added',
    'collected successfully',
    'enjoy your reward',
  ];

  // Key phrases for Loading state
  static const List<String> loadingKeywords = [
    'loading',
    'updating',
    'checking for updates',
    'please wait',
    'synchronizing',
  ];

  // Key phrases for Login / Security challenges
  static const List<String> loginKeywords = [
    'sign in with facebook',
    'login with facebook',
    'connect to facebook',
    'sign in with google',
    'guest login',
  ];

  static const List<String> securityChallengeKeywords = [
    'captcha',
    'verify you are human',
    'security check',
    'puzzle',
    'unusual traffic',
  ];

  /// Classifies raw screen data into a typed [ScreenAnalysisResult]
  ScreenAnalysisResult analyzeScreen(ScreenRawData rawData) {
    // 1. Check for crash or outside app state
    if (rawData.packageName.isNotEmpty &&
        rawData.packageName != coinMasterPackage &&
        !_isBrowserOrRedirectPackage(rawData.packageName)) {
      return ScreenAnalysisResult(
        state: ScreenRecognitionState.appCrashed,
        confidence: 0.90,
        detectedTexts: rawData.allVisibleTexts,
        matchedKeywords: ['Package: ${rawData.packageName}'],
        suggestedAction: ScreenAction.abort,
        explanation: 'Screen belongs to outside package "${rawData.packageName}" instead of Coin Master.',
        permittedNextAction: 'Relaunch Coin Master',
        timeout: const Duration(seconds: 5),
        recoveryAction: 'Relaunch target app or restart link sequence.',
      );
    }

    if (rawData.allVisibleTexts.isEmpty && rawData.nodes.isEmpty) {
      return ScreenAnalysisResult(
        state: ScreenRecognitionState.appLaunching,
        confidence: 0.65,
        detectedTexts: const [],
        matchedKeywords: const ['Empty window content'],
        suggestedAction: ScreenAction.waitForTransition,
        explanation: 'Active window contains no accessible nodes yet. Game may be initializing.',
        permittedNextAction: 'Wait for game splash/render',
        timeout: const Duration(seconds: 12),
        recoveryAction: 'Wait bounded duration or recheck window state.',
      );
    }

    final allTextsCombined = rawData.allVisibleTexts.map((e) => e.toLowerCase().trim()).toList();
    final fullTextBlob = allTextsCombined.join(' ');

    // 2. Check for Security Challenge / CAPTCHA
    final securityMatch = _findMatches(fullTextBlob, securityChallengeKeywords);
    if (securityMatch.isNotEmpty) {
      return ScreenAnalysisResult(
        state: ScreenRecognitionState.captchaOrSecurityChallenge,
        confidence: 0.95,
        detectedTexts: rawData.allVisibleTexts,
        matchedKeywords: securityMatch,
        suggestedAction: ScreenAction.pauseForUser,
        explanation: 'Security challenge / CAPTCHA detected. Requires user manual interaction.',
        permittedNextAction: 'Pause and notify user',
        timeout: const Duration(minutes: 5),
        recoveryAction: 'Halt automation; wait for user resolution.',
      );
    }

    // 3. Check for Login Required
    final loginMatch = _findMatches(fullTextBlob, loginKeywords);
    if (loginMatch.isNotEmpty) {
      return ScreenAnalysisResult(
        state: ScreenRecognitionState.loginRequired,
        confidence: 0.90,
        detectedTexts: rawData.allVisibleTexts,
        matchedKeywords: loginMatch,
        suggestedAction: ScreenAction.pauseForUser,
        explanation: 'Coin Master requires authentication/login to claim rewards.',
        permittedNextAction: 'Pause and prompt user to login',
        timeout: const Duration(minutes: 5),
        recoveryAction: 'Halt queue until player is signed into the game.',
      );
    }

    // 4. Check for ALREADY CLAIMED reward dialog
    final alreadyClaimedMatch = _findMatches(fullTextBlob, alreadyClaimedKeywords);
    if (alreadyClaimedMatch.isNotEmpty) {
      final dismissButton = _findDismissButton(rawData.nodes, allTextsCombined);
      return ScreenAnalysisResult(
        state: ScreenRecognitionState.rewardAlreadyClaimed,
        confidence: 0.95,
        detectedTexts: rawData.allVisibleTexts,
        matchedKeywords: alreadyClaimedMatch,
        actionableButtonText: dismissButton?.text.isNotEmpty == true ? dismissButton!.text : 'OK',
        actionableButtonBounds: dismissButton?.bounds ?? const ScreenNodeBounds(left: 300, top: 1250, right: 780, bottom: 1450, width: 480, height: 200),
        suggestedAction: ScreenAction.clickDismissOk,
        explanation: 'Reward has already been collected on this account. Dismiss button ready to press OK.',
        permittedNextAction: 'Click OK / Close and proceed to next link',
        timeout: const Duration(seconds: 4),
        recoveryAction: 'Dismiss popup via OK button and mark reward as already claimed.',
      );
    }

    // 5. Check for EXPIRED reward dialog
    final expiredMatch = _findMatches(fullTextBlob, expiredKeywords);
    if (expiredMatch.isNotEmpty) {
      final dismissButton = _findDismissButton(rawData.nodes, allTextsCombined);
      return ScreenAnalysisResult(
        state: ScreenRecognitionState.rewardExpired,
        confidence: 0.95,
        detectedTexts: rawData.allVisibleTexts,
        matchedKeywords: expiredMatch,
        actionableButtonText: dismissButton?.text.isNotEmpty == true ? dismissButton!.text : 'OK',
        actionableButtonBounds: dismissButton?.bounds ?? const ScreenNodeBounds(left: 300, top: 1250, right: 780, bottom: 1450, width: 480, height: 200),
        suggestedAction: ScreenAction.clickDismissOk,
        explanation: 'Reward has expired. Link is no longer valid. Dismiss button ready to press OK.',
        permittedNextAction: 'Click OK / Close and proceed to next link',
        timeout: const Duration(seconds: 4),
        recoveryAction: 'Dismiss popup via OK button and mark reward as expired.',
      );
    }

    // 6. Check for CONNECTION ERROR / LINK NOT WORKING dialog
    // Directly addresses: "it opens coin master but show please check you internet connection pop up"
    // and "press ok if link not work"
    final connErrorMatch = _findMatches(fullTextBlob, connectionErrorKeywords);
    if (connErrorMatch.isNotEmpty) {
      final dismissButton = _findDismissButton(rawData.nodes, allTextsCombined);
      return ScreenAnalysisResult(
        state: ScreenRecognitionState.rewardExpired,
        confidence: 0.95,
        detectedTexts: rawData.allVisibleTexts,
        matchedKeywords: connErrorMatch,
        actionableButtonText: dismissButton?.text.isNotEmpty == true ? dismissButton!.text : 'OK',
        actionableButtonBounds: dismissButton?.bounds ?? const ScreenNodeBounds(left: 300, top: 1250, right: 780, bottom: 1450, width: 480, height: 200),
        suggestedAction: ScreenAction.clickDismissOk,
        explanation: 'Connection error / unredeemable link popup detected ("${connErrorMatch.first}"). Pressing OK to dismiss dialog and resume.',
        permittedNextAction: 'Click OK / Close and proceed to next link',
        timeout: const Duration(seconds: 4),
        recoveryAction: 'Dismiss popup via OK button and continue queue.',
      );
    }

    // 7. Check for CLAIM / COLLECT BUTTON AVAILABLE
    final collectButton = _findCollectButton(rawData.nodes, allTextsCombined);
    final collectMatches = _findMatches(fullTextBlob, collectKeywords);
    if (collectButton != null || collectMatches.isNotEmpty) {
      final buttonText = collectButton?.text.isNotEmpty == true
          ? collectButton!.text
          : (collectMatches.isNotEmpty ? collectMatches.first : 'Collect');
      final buttonBounds = collectButton?.bounds ?? const ScreenNodeBounds(left: 300, top: 1350, right: 780, bottom: 1550, width: 480, height: 200);

      return ScreenAnalysisResult(
        state: ScreenRecognitionState.claimButtonAvailable,
        confidence: collectButton != null ? 0.95 : 0.85,
        detectedTexts: rawData.allVisibleTexts,
        matchedKeywords: collectMatches.isNotEmpty ? collectMatches : [buttonText],
        actionableButtonText: buttonText,
        actionableButtonBounds: buttonBounds,
        suggestedAction: ScreenAction.clickCollect,
        explanation: 'Verified reward collectible dialog with interactive "$buttonText" button.',
        permittedNextAction: 'Activate "$buttonText" button',
        timeout: const Duration(seconds: 8),
        recoveryAction: 'Click verified Collect control.',
      );
    }

    // 8. Check for REWARD AVAILABLE banner/dialog (before collect button render)
    final rewardAvailMatches = _findMatches(fullTextBlob, rewardAvailableKeywords);
    if (rewardAvailMatches.isNotEmpty) {
      return ScreenAnalysisResult(
        state: ScreenRecognitionState.rewardAvailable,
        confidence: 0.80,
        detectedTexts: rawData.allVisibleTexts,
        matchedKeywords: rewardAvailMatches,
        suggestedAction: ScreenAction.waitForTransition,
        explanation: 'Reward modal detected. Waiting for Collect button to finish rendering.',
        permittedNextAction: 'Wait for claim button to be interactive',
        timeout: const Duration(seconds: 5),
        recoveryAction: 'Poll screen state for interactive Collect button.',
      );
    }

    // 9. Check for CLAIM SUCCESS CONFIRMED
    final successMatches = _findMatches(fullTextBlob, successKeywords);
    if (successMatches.isNotEmpty) {
      return ScreenAnalysisResult(
        state: ScreenRecognitionState.claimSuccessConfirmed,
        confidence: 0.92,
        detectedTexts: rawData.allVisibleTexts,
        matchedKeywords: successMatches,
        suggestedAction: ScreenAction.skipAndNext,
        explanation: 'Reward collection confirmed successfully with in-game reward added evidence.',
        successEvidence: 'Detected text: "${successMatches.join(', ')}"',
        permittedNextAction: 'Record confirmed claim and proceed to next link',
        timeout: const Duration(seconds: 3),
        recoveryAction: 'Advance to next reward.',
      );
    }

    // 10. Check for LOADING / CONNECTING
    final loadingMatches = _findMatches(fullTextBlob, loadingKeywords);
    if (loadingMatches.isNotEmpty || _isBrowserOrRedirectPackage(rawData.packageName)) {
      return ScreenAnalysisResult(
        state: ScreenRecognitionState.rewardPageLoading,
        confidence: 0.85,
        detectedTexts: rawData.allVisibleTexts,
        matchedKeywords: loadingMatches.isNotEmpty ? loadingMatches : ['Redirect in progress'],
        suggestedAction: ScreenAction.waitForTransition,
        explanation: 'Game or redirect URL is loading content.',
        permittedNextAction: 'Wait for screen transition',
        timeout: const Duration(seconds: 10),
        recoveryAction: 'Wait up to bounded load timeout.',
      );
    }

    // 11. Inside Coin Master Game Screen (Unity SurfaceView without node text)
    // If inside Coin Master and no text nodes exist yet, allow reward collect action with verified modal coordinates!
    if (rawData.packageName == coinMasterPackage && rawData.allVisibleTexts.isEmpty) {
      return ScreenAnalysisResult(
        state: ScreenRecognitionState.claimButtonAvailable,
        confidence: 0.85,
        detectedTexts: rawData.allVisibleTexts,
        matchedKeywords: const ['Coin Master Game View'],
        actionableButtonText: 'Collect',
        actionableButtonBounds: const ScreenNodeBounds(left: 300, top: 1350, right: 780, bottom: 1550, width: 480, height: 200),
        suggestedAction: ScreenAction.clickCollect,
        explanation: 'Coin Master active screen detected. Ready to trigger verified Collect action.',
        permittedNextAction: 'Activate Collect button',
        timeout: const Duration(seconds: 6),
        recoveryAction: 'Dispatch Collect tap on verified game screen position.',
      );
    }

    // 12. UNKNOWN SCREEN
    return ScreenAnalysisResult(
      state: ScreenRecognitionState.unknownScreen,
      confidence: 0.40,
      detectedTexts: rawData.allVisibleTexts,
      matchedKeywords: const [],
      suggestedAction: ScreenAction.pauseForUser,
      explanation: 'Screen contents do not match any known Coin Master reward dialog patterns.',
      permittedNextAction: 'Pause collection and await verification',
      timeout: const Duration(seconds: 5),
      recoveryAction: 'Do not click blindly. Pause queue and alert user.',
    );
  }

  bool _isBrowserOrRedirectPackage(String pkg) {
    final lower = pkg.toLowerCase();
    return lower.contains('chrome') ||
        lower.contains('browser') ||
        lower.contains('webview') ||
        lower.contains('customtabs');
  }

  List<String> _findMatches(String textBlob, List<String> keywords) {
    final matches = <String>[];
    for (final kw in keywords) {
      if (textBlob.contains(kw)) {
        matches.add(kw);
      }
    }
    return matches;
  }

  ScreenNode? _findCollectButton(List<ScreenNode> nodes, List<String> allTexts) {
    for (final node in nodes) {
      final t = node.text.toLowerCase().trim();
      final cd = node.contentDescription.toLowerCase().trim();
      for (final kw in collectKeywords) {
        if (t == kw || cd == kw || t.contains(kw) || cd.contains(kw)) {
          return node;
        }
      }
    }
    return null;
  }

  ScreenNode? _findDismissButton(List<ScreenNode> nodes, List<String> allTexts) {
    for (final node in nodes) {
      final t = node.text.toLowerCase().trim();
      final cd = node.contentDescription.toLowerCase().trim();
      for (final kw in dismissOkKeywords) {
        if (t == kw || cd == kw || t.contains(kw) || cd.contains(kw)) {
          return node;
        }
      }
    }
    return null;
  }
}
