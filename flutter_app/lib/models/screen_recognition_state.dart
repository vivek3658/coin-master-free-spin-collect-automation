import 'package:flutter/foundation.dart';

/// All recognized screen states for Coin Master reward automation.
enum ScreenRecognitionState {
  appLaunching,
  rewardPageLoading,
  rewardAvailable,
  claimButtonAvailable,
  claimInProgress,
  claimSuccessConfirmed,
  rewardExpired,
  rewardAlreadyClaimed,
  loginRequired,
  captchaOrSecurityChallenge,
  unknownScreen,
  appCrashed,
  timeout,
}

extension ScreenRecognitionStateExt on ScreenRecognitionState {
  String get displayName {
    switch (this) {
      case ScreenRecognitionState.appLaunching:
        return 'APP_LAUNCHING';
      case ScreenRecognitionState.rewardPageLoading:
        return 'REWARD_PAGE_LOADING';
      case ScreenRecognitionState.rewardAvailable:
        return 'REWARD_AVAILABLE';
      case ScreenRecognitionState.claimButtonAvailable:
        return 'CLAIM_BUTTON_AVAILABLE';
      case ScreenRecognitionState.claimInProgress:
        return 'CLAIM_IN_PROGRESS';
      case ScreenRecognitionState.claimSuccessConfirmed:
        return 'CLAIM_SUCCESS_CONFIRMED';
      case ScreenRecognitionState.rewardExpired:
        return 'REWARD_EXPIRED';
      case ScreenRecognitionState.rewardAlreadyClaimed:
        return 'REWARD_ALREADY_CLAIMED';
      case ScreenRecognitionState.loginRequired:
        return 'LOGIN_REQUIRED';
      case ScreenRecognitionState.captchaOrSecurityChallenge:
        return 'CAPTCHA_OR_SECURITY_CHALLENGE';
      case ScreenRecognitionState.unknownScreen:
        return 'UNKNOWN_SCREEN';
      case ScreenRecognitionState.appCrashed:
        return 'APP_CRASHED';
      case ScreenRecognitionState.timeout:
        return 'TIMEOUT';
    }
  }

  bool get isTerminalSuccess => this == ScreenRecognitionState.claimSuccessConfirmed;
  bool get isTerminalFailure =>
      this == ScreenRecognitionState.rewardExpired ||
      this == ScreenRecognitionState.rewardAlreadyClaimed ||
      this == ScreenRecognitionState.timeout ||
      this == ScreenRecognitionState.appCrashed;
  bool get requiresUserIntervention =>
      this == ScreenRecognitionState.loginRequired ||
      this == ScreenRecognitionState.captchaOrSecurityChallenge ||
      this == ScreenRecognitionState.unknownScreen;
}

/// Action to perform based on screen state
enum ScreenAction {
  clickCollect,
  clickDismissOk,
  waitForTransition,
  pauseForUser,
  skipAndNext,
  retry,
  abort,
}

class ScreenNodeBounds {
  final int left;
  final int top;
  final int right;
  final int bottom;
  final int width;
  final int height;

  const ScreenNodeBounds({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
    required this.width,
    required this.height,
  });

  int get centerX => left + (width ~/ 2);
  int get centerY => top + (height ~/ 2);

  factory ScreenNodeBounds.fromMap(Map<dynamic, dynamic>? map) {
    if (map == null) {
      return const ScreenNodeBounds(left: 0, top: 0, right: 0, bottom: 0, width: 0, height: 0);
    }
    return ScreenNodeBounds(
      left: (map['left'] as num?)?.toInt() ?? 0,
      top: (map['top'] as num?)?.toInt() ?? 0,
      right: (map['right'] as num?)?.toInt() ?? 0,
      bottom: (map['bottom'] as num?)?.toInt() ?? 0,
      width: (map['width'] as num?)?.toInt() ?? 0,
      height: (map['height'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toMap() => {
        'left': left,
        'top': top,
        'right': right,
        'bottom': bottom,
        'width': width,
        'height': height,
      };

  @override
  String toString() => 'Bounds($left, $top, $right, $bottom)';
}

class ScreenNode {
  final String text;
  final String contentDescription;
  final String viewId;
  final String className;
  final bool isClickable;
  final bool isEnabled;
  final ScreenNodeBounds bounds;
  final List<ScreenNode> children;

  const ScreenNode({
    required this.text,
    required this.contentDescription,
    required this.viewId,
    required this.className,
    required this.isClickable,
    required this.isEnabled,
    required this.bounds,
    this.children = const [],
  });

  factory ScreenNode.fromMap(Map<dynamic, dynamic> map) {
    final rawChildren = map['children'] as List<dynamic>? ?? [];
    return ScreenNode(
      text: map['text'] as String? ?? '',
      contentDescription: map['contentDescription'] as String? ?? '',
      viewId: map['viewId'] as String? ?? '',
      className: map['className'] as String? ?? '',
      isClickable: map['isClickable'] as bool? ?? false,
      isEnabled: map['isEnabled'] as bool? ?? true,
      bounds: ScreenNodeBounds.fromMap(map['bounds'] as Map<dynamic, dynamic>?),
      children: rawChildren.map((c) => ScreenNode.fromMap(c as Map<dynamic, dynamic>)).toList(),
    );
  }
}

class ScreenRawData {
  final String packageName;
  final List<String> allVisibleTexts;
  final List<ScreenNode> nodes;
  final int timestamp;
  final bool isCoinMaster;

  const ScreenRawData({
    required this.packageName,
    required this.allVisibleTexts,
    required this.nodes,
    required this.timestamp,
    required this.isCoinMaster,
  });

  factory ScreenRawData.fromMap(Map<dynamic, dynamic> map) {
    final rawTexts = map['allVisibleTexts'] as List<dynamic>? ?? [];
    final rawNodes = map['nodes'] as List<dynamic>? ?? [];
    return ScreenRawData(
      packageName: map['packageName'] as String? ?? '',
      allVisibleTexts: rawTexts.map((e) => e.toString()).toList(),
      nodes: rawNodes.map((n) => ScreenNode.fromMap(n as Map<dynamic, dynamic>)).toList(),
      timestamp: (map['timestamp'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
      isCoinMaster: map['isCoinMaster'] as bool? ?? false,
    );
  }
}

@immutable
class ScreenAnalysisResult {
  final ScreenRecognitionState state;
  final double confidence; // 0.0 to 1.0
  final List<String> detectedTexts;
  final List<String> matchedKeywords;
  final String? actionableButtonText;
  final ScreenNodeBounds? actionableButtonBounds;
  final ScreenAction suggestedAction;
  final String explanation;
  final String? successEvidence;
  final String permittedNextAction;
  final Duration timeout;
  final String recoveryAction;

  const ScreenAnalysisResult({
    required this.state,
    required this.confidence,
    required this.detectedTexts,
    required this.matchedKeywords,
    this.actionableButtonText,
    this.actionableButtonBounds,
    required this.suggestedAction,
    required this.explanation,
    this.successEvidence,
    required this.permittedNextAction,
    required this.timeout,
    required this.recoveryAction,
  });

  @override
  String toString() {
    return 'ScreenAnalysisResult(${state.displayName}, conf: ${(confidence * 100).toStringAsFixed(0)}%, action: $suggestedAction)';
  }
}
