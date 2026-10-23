import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../models/screen_recognition_state.dart';

abstract class NativeAutomationService {
  bool get isForceStopped;
  Future<bool> isAccessibilityEnabled();
  Future<bool> openAccessibilitySettings();
  Future<bool> isCoinMasterInstalled();
  Future<bool> launchRewardIntent(String url);
  Future<ScreenRawData> inspectCurrentScreen();
  Future<bool> performClickAction({
    String? targetText,
    String? viewId,
    int? x,
    int? y,
  });
  Future<void> forceStop();
  Future<void> resetEmergencyStop();
}

class AndroidNativeAutomationService implements NativeAutomationService {
  static const MethodChannel _channel = MethodChannel('com.rewardpilot/automation');

  bool _isForceStopped = false;

  @override
  bool get isForceStopped => _isForceStopped;

  @override
  Future<bool> isAccessibilityEnabled() async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        final result = await _channel.invokeMethod<bool>('isAccessibilityEnabled');
        return result ?? false;
      } catch (e) {
        debugPrint('Error checking accessibility: $e');
        return false;
      }
    }
    return false;
  }

  @override
  Future<bool> openAccessibilitySettings() async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        final result = await _channel.invokeMethod<bool>('openAccessibilitySettings');
        return result ?? false;
      } catch (e) {
        debugPrint('Error opening accessibility settings: $e');
        return false;
      }
    }
    return false;
  }

  @override
  Future<bool> isCoinMasterInstalled() async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        final result = await _channel.invokeMethod<bool>('isCoinMasterInstalled');
        return result ?? false;
      } catch (e) {
        return false;
      }
    }
    return false;
  }

  @override
  Future<bool> launchRewardIntent(String url) async {
    if (_isForceStopped) {
      debugPrint('Launch intent blocked: Force stop is active.');
      return false;
    }
    if (!kIsWeb && Platform.isAndroid) {
      try {
        final result = await _channel.invokeMethod<bool>('launchRewardIntent', {'url': url});
        return result ?? false;
      } catch (e) {
        debugPrint('Error launching reward intent: $e');
        return false;
      }
    }
    return true;
  }

  @override
  Future<ScreenRawData> inspectCurrentScreen() async {
    if (_isForceStopped) {
      return ScreenRawData(
        packageName: '',
        allVisibleTexts: const ['Force stop active'],
        nodes: const [],
        timestamp: DateTime.now().millisecondsSinceEpoch,
        isCoinMaster: false,
      );
    }

    if (!kIsWeb && Platform.isAndroid) {
      try {
        final map = await _channel.invokeMapMethod<dynamic, dynamic>('inspectCurrentScreen');
        if (map != null) {
          return ScreenRawData.fromMap(map);
        }
      } catch (e) {
        debugPrint('Error inspecting screen via native channel: $e');
      }
    }

    return ScreenRawData(
      packageName: 'com.moonactive.coinmaster',
      allVisibleTexts: const [],
      nodes: const [],
      timestamp: DateTime.now().millisecondsSinceEpoch,
      isCoinMaster: true,
    );
  }

  @override
  Future<bool> performClickAction({
    String? targetText,
    String? viewId,
    int? x,
    int? y,
  }) async {
    if (_isForceStopped) {
      debugPrint('Click action blocked: Force stop is active.');
      return false;
    }

    if (!kIsWeb && Platform.isAndroid) {
      try {
        final result = await _channel.invokeMapMethod<dynamic, dynamic>('performClickAction', {
          'targetText': targetText,
          'viewId': viewId,
          'x': x,
          'y': y,
        });
        return result?['success'] == true;
      } catch (e) {
        debugPrint('Error performing native click: $e');
        return false;
      }
    }
    return true;
  }

  @override
  Future<void> forceStop() async {
    _isForceStopped = true;
    debugPrint('NativeAutomationService: Emergency Force Stop activated.');
    if (!kIsWeb && Platform.isAndroid) {
      try {
        await _channel.invokeMethod<bool>('forceStop');
      } catch (e) {
        debugPrint('Error signaling native force stop: $e');
      }
    }
  }

  @override
  Future<void> resetEmergencyStop() async {
    _isForceStopped = false;
    if (!kIsWeb && Platform.isAndroid) {
      try {
        await _channel.invokeMethod<bool>('resetEmergencyStop');
      } catch (e) {
        debugPrint('Error resetting native force stop: $e');
      }
    }
  }
}

/// Mock Automation Service for testing and desktop verification
class MockAutomationService implements NativeAutomationService {
  bool _isForceStopped = false;
  ScreenRawData? nextScreenData;
  final List<String> actionHistory = [];

  @override
  bool get isForceStopped => _isForceStopped;

  @override
  Future<bool> isAccessibilityEnabled() async => true;

  @override
  Future<bool> openAccessibilitySettings() async => true;

  @override
  Future<bool> isCoinMasterInstalled() async => true;

  @override
  Future<bool> launchRewardIntent(String url) async {
    if (_isForceStopped) return false;
    actionHistory.add('launch: $url');
    return true;
  }

  @override
  Future<ScreenRawData> inspectCurrentScreen() async {
    if (_isForceStopped) {
      return ScreenRawData(
        packageName: '',
        allVisibleTexts: const ['Force stop active'],
        nodes: const [],
        timestamp: DateTime.now().millisecondsSinceEpoch,
        isCoinMaster: false,
      );
    }
    return nextScreenData ??
        ScreenRawData(
          packageName: 'com.moonactive.coinmaster',
          allVisibleTexts: const ['Congratulations!', 'Collect 25 Free Spins', 'Collect'],
          nodes: [
            const ScreenNode(
              text: 'Collect',
              contentDescription: 'Collect Reward',
              viewId: 'com.moonactive.coinmaster:id/btn_collect',
              className: 'android.widget.Button',
              isClickable: true,
              isEnabled: true,
              bounds: ScreenNodeBounds(left: 300, top: 1200, right: 780, bottom: 1350, width: 480, height: 150),
            ),
          ],
          timestamp: DateTime.now().millisecondsSinceEpoch,
          isCoinMaster: true,
        );
  }

  @override
  Future<bool> performClickAction({
    String? targetText,
    String? viewId,
    int? x,
    int? y,
  }) async {
    if (_isForceStopped) return false;
    actionHistory.add('click: targetText=$targetText, viewId=$viewId, coord=($x, $y)');
    return true;
  }

  @override
  Future<void> forceStop() async {
    _isForceStopped = true;
    actionHistory.add('force_stop');
  }

  @override
  Future<void> resetEmergencyStop() async {
    _isForceStopped = false;
    actionHistory.add('reset_force_stop');
  }
}
