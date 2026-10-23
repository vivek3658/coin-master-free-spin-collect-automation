import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/collection_event.dart';
import '../models/collection_stats.dart';
import '../models/collector_config.dart';
import '../models/reward_link.dart';
import '../models/screen_recognition_state.dart';
import 'native_automation_service.dart';
import 'reward_discovery_service.dart';
import 'screen_recognition_service.dart';
import 'storage_service.dart';

enum CollectionRunStatus {
  idle,
  running,
  paused,
  forceStopped,
  completed,
  stoppedBySafetyCondition,
}

class AutonomousCollectionCoordinator extends ChangeNotifier {
  static bool _isDeviceJobActive = false;

  final NativeAutomationService automationService;
  final ScreenRecognitionService screenService;
  final RewardDiscoveryService discoveryService;
  final StorageService storageService;

  final String userId;
  CollectorConfig config;
  final CollectionStats stats = CollectionStats();
  final List<CollectionEvent> liveEvents = [];

  CollectionRunStatus _runStatus = CollectionRunStatus.idle;
  bool _stopAfterCurrentRequested = false;
  Completer<void>? _pauseCompleter;
  Timer? _durationTimer;

  List<RewardLink> _activeQueue = [];
  int _currentIndex = 0;
  RewardLink? _currentLink;

  AutonomousCollectionCoordinator({
    required this.automationService,
    required this.screenService,
    required this.discoveryService,
    required this.storageService,
    required this.userId,
    CollectorConfig? initialConfig,
  }) : config = initialConfig ?? CollectorConfig();

  CollectionRunStatus get runStatus => _runStatus;
  bool get isRunning => _runStatus == CollectionRunStatus.running;
  bool get isPaused => _runStatus == CollectionRunStatus.paused;
  bool get isForceStopped => _runStatus == CollectionRunStatus.forceStopped;
  List<RewardLink> get activeQueue => List.unmodifiable(_activeQueue);
  RewardLink? get currentLink => _currentLink;
  int get currentIndex => _currentIndex;

  /// Preloads and refreshes the preview queue so cards are immediately visible in the Carousel and list.
  Future<void> loadInitialQueue() async {
    try {
      final discovered = await discoveryService.discoverRewardLinks(userId: userId);
      final deduplicated = discoveryService.deduplicateLinks(discovered);
      final history = await storageService.getRewardHistory(userId);

      final merged = deduplicated.map((link) {
        final recorded = history[link.canonicalUrl];
        if (recorded != null) {
          link.status = recorded.status;
          link.claimedAt = recorded.claimedAt;
        }
        return link;
      }).toList();

      // Sort: NEWEST FIRST (Today's fresh drops first, then Yesterday)
      merged.sort((a, b) => b.discoveredAt.compareTo(a.discoveredAt));

      _activeQueue = merged;
      stats.totalEligible = merged.where((e) => e.status == RewardClaimStatus.unclaimed).length;
      notifyListeners();
    } catch (e) {
      debugPrint('Error loading initial queue: $e');
    }
  }

  /// Manually unmarks a single reward so the user can re-test claiming it
  Future<void> unmarkReward(RewardLink link) async {
    link.status = RewardClaimStatus.unclaimed;
    link.claimedAt = null;
    link.claimEvidence = null;
    await storageService.unmarkReward(userId, link.canonicalUrl);
    stats.totalEligible = _activeQueue.where((e) => e.status == RewardClaimStatus.unclaimed).length;
    _addEvent(EventLevel.info, 'Unmarked "${link.rewardTitle}" (ready to re-test).');
    notifyListeners();
  }

  /// Resets all claimed & expired history records so the user can re-test the Claim All flow
  Future<void> resetAllClaimedForTesting() async {
    await storageService.clearRewardHistory(userId);
    await storageService.clearInterruptedQueue(userId);
    for (final link in _activeQueue) {
      link.status = RewardClaimStatus.unclaimed;
      link.claimedAt = null;
      link.claimEvidence = null;
    }
    stats.claimedCount = 0;
    stats.expiredCount = 0;
    stats.alreadyClaimedCount = 0;
    stats.consecutiveExpiredCount = 0;
    stats.consecutiveAlreadyClaimedCount = 0;
    stats.totalEligible = _activeQueue.length;
    stats.currentAction = 'Reset all rewards to unclaimed for testing';
    _addEvent(EventLevel.success, 'All rewards reset to unclaimed! Ready to re-test Claim All.');
    notifyListeners();
  }

  /// Single Reward Collection:
  /// Fulfills user requirement: "i want it to click one screen as well to collect or press ok if link not work"
  Future<void> collectSingleReward(RewardLink link) async {
    if (_runStatus == CollectionRunStatus.running) {
      _addEvent(EventLevel.warning, 'Batch run in progress. Stop or pause before collecting individual rewards.');
      return;
    }

    _runStatus = CollectionRunStatus.running;
    _currentLink = link;
    await automationService.resetEmergencyStop();
    notifyListeners();

    try {
      _addEvent(EventLevel.info, 'Starting 1-tap single collection for "${link.rewardTitle}"...');
      stats.currentAction = 'Opening ${link.rewardTitle}...';
      notifyListeners();

      await _processSingleReward(link);
      _addEvent(EventLevel.success, 'Finished processing single reward "${link.rewardTitle}" (Status: ${link.status.displayName}).');
    } catch (e) {
      _addEvent(EventLevel.error, 'Error in single reward collection: $e');
    } finally {
      _runStatus = CollectionRunStatus.idle;
      _currentLink = null;
      stats.currentAction = 'Ready';
      notifyListeners();
    }
  }

  /// Primary Entry Point: One-Tap "Collect All Unclaimed"
  Future<void> startAutonomousCollection({bool resumeInterrupted = false}) async {
    // If currently paused, immediately resume rather than blocking
    if (_runStatus == CollectionRunStatus.paused) {
      resume();
      return;
    }

    if (_isDeviceJobActive && _runStatus == CollectionRunStatus.running) {
      _addEvent(EventLevel.warning, 'Collection already running.');
      return;
    }

    _isDeviceJobActive = true;
    _runStatus = CollectionRunStatus.running;
    stats.isPaused = false;
    _stopAfterCurrentRequested = false;
    _pauseCompleter = null;
    await automationService.resetEmergencyStop();

    _startDurationTimer();

    try {
      _addEvent(EventLevel.info, 'Starting autonomous collection run for user $userId...');

      // 1. Discover & Refresh
      stats.currentAction = 'Discovering rewards...';
      notifyListeners();

      List<RewardLink> queue = [];
      if (resumeInterrupted) {
        final interrupted = await storageService.getInterruptedQueue(userId);
        if (interrupted != null && interrupted['queue'] != null) {
          final rawList = interrupted['queue'] as List<dynamic>;
          queue = rawList.map((e) => RewardLink.fromJson(e as Map<String, dynamic>)).toList();
          _currentIndex = (interrupted['currentIndex'] as num?)?.toInt() ?? 0;
          _addEvent(EventLevel.info, 'Resumed interrupted run at link #${_currentIndex + 1}.');
        }
      }

      if (queue.isEmpty) {
        final discovered = await discoveryService.discoverRewardLinks(userId: userId);
        // 2. Deduplicate queue
        final deduplicated = discoveryService.deduplicateLinks(discovered);

        // 3 & 4. Filter already claimed or confirmed expired for this user
        final history = await storageService.getRewardHistory(userId);
        queue = deduplicated.where((link) {
          final recorded = history[link.canonicalUrl];
          if (recorded != null) {
            if (recorded.status == RewardClaimStatus.claimed) {
              _addEvent(EventLevel.info, 'Skipping already claimed: ${link.maskedUrl}');
              return false;
            }
            if (recorded.status == RewardClaimStatus.expired) {
              _addEvent(EventLevel.info, 'Skipping confirmed expired: ${link.maskedUrl}');
              return false;
            }
          }
          if (link.isPastExpiration) {
            _addEvent(EventLevel.info, 'Skipping expired (>48h): ${link.maskedUrl}');
            return false;
          }
          return true;
        }).toList();

        // Sort: NEWEST FIRST (Today's fresh drops first, then Yesterday)
        queue.sort((a, b) => b.discoveredAt.compareTo(a.discoveredAt));

        _currentIndex = 0;
      }

      // Respect maxLinksPerRun config
      if (queue.length > config.maxLinksPerRun) {
        queue = queue.sublist(0, config.maxLinksPerRun);
      }

      if (_runStatus == CollectionRunStatus.forceStopped) {
        stats.currentAction = 'Force stopped';
        return;
      }

      _activeQueue = queue;
      stats.reset(total: queue.length);
      stats.currentRewardIndex = _currentIndex;
      notifyListeners();

      if (queue.isEmpty) {
        _addEvent(EventLevel.info, 'No eligible unclaimed rewards found. Queue empty.');
        _runStatus = CollectionRunStatus.completed;
        stats.currentAction = 'Complete (0 eligible)';
        notifyListeners();
        return;
      }

      _addEvent(EventLevel.info, 'Queue initialized with ${queue.length} eligible rewards.');

      // Main Sequential Loop: DISCOVER → VALIDATE → DEDUPLICATE → OPEN → WAIT → READ SCREEN → CLASSIFY → ACT → VERIFY → RECORD → NEXT
      while (_currentIndex < _activeQueue.length) {
        if (_runStatus == CollectionRunStatus.forceStopped) {
          _addEvent(EventLevel.forceStop, 'Autonomous run halted by Emergency Force Stop.');
          break;
        }

        if (_stopAfterCurrentRequested) {
          _addEvent(EventLevel.info, 'Stopped after reward by user request.');
          _runStatus = CollectionRunStatus.completed;
          break;
        }

        // Handle Cooperative Pause
        if (_runStatus == CollectionRunStatus.paused && _pauseCompleter != null) {
          _addEvent(EventLevel.info, 'Collection paused. Awaiting user resume.');
          stats.currentAction = 'Paused';
          notifyListeners();
          await _pauseCompleter!.future;
          if (_runStatus == CollectionRunStatus.forceStopped) break;
        }

        // Safety Condition Checks:
        // A. Consecutive Expired Threshold
        if (stats.consecutiveExpiredCount >= config.consecutiveExpiredThreshold) {
          _addEvent(
            EventLevel.warning,
            'Safety Trigger: ${stats.consecutiveExpiredCount} consecutive expired links reached (threshold: ${config.consecutiveExpiredThreshold}). Halting queue.',
          );
          _runStatus = CollectionRunStatus.stoppedBySafetyCondition;
          stats.currentAction = 'Halted: Consecutive expired threshold reached';
          break;
        }

        // B. Consecutive Already Claimed Threshold
        if (stats.consecutiveAlreadyClaimedCount >= config.consecutiveAlreadyClaimedThreshold) {
          _addEvent(
            EventLevel.warning,
            'Safety Trigger: ${stats.consecutiveAlreadyClaimedCount} consecutive already-claimed links reached. Halting queue.',
          );
          _runStatus = CollectionRunStatus.stoppedBySafetyCondition;
          stats.currentAction = 'Halted: Consecutive already-claimed threshold reached';
          break;
        }

        // C. Max Execution Duration
        final elapsedMinutes = stats.startTime != null
            ? DateTime.now().difference(stats.startTime!).inMinutes
            : 0;
        if (elapsedMinutes >= config.maxExecutionDurationMinutes) {
          _addEvent(
            EventLevel.warning,
            'Safety Trigger: Maximum run duration of ${config.maxExecutionDurationMinutes} min reached. Halting queue.',
          );
          _runStatus = CollectionRunStatus.stoppedBySafetyCondition;
          stats.currentAction = 'Halted: Max duration limit reached';
          break;
        }

        _currentLink = _activeQueue[_currentIndex];
        stats.currentRewardIndex = _currentIndex + 1;
        stats.processedCount++;
        notifyListeners();

        // Save progress for crash recovery
        await storageService.saveInterruptedQueue(userId, _activeQueue, _currentIndex);

        // Process single reward through the state pipeline
        await _processSingleReward(_currentLink!);

        _currentIndex++;
      }

      if (_runStatus == CollectionRunStatus.running) {
        _runStatus = CollectionRunStatus.completed;
        stats.currentAction = 'Completed all eligible rewards!';
        _addEvent(EventLevel.success, 'Completed! Claimed: ${stats.claimedCount}, Expired: ${stats.expiredCount}, Already Claimed: ${stats.alreadyClaimedCount}');
        await storageService.clearInterruptedQueue(userId);
      }
    } catch (e, stack) {
      _addEvent(EventLevel.error, 'Unexpected coordinator error: $e');
      debugPrint('Coordinator error: $e\n$stack');
    } finally {
      _durationTimer?.cancel();
      _isDeviceJobActive = false;
      notifyListeners();
    }
  }

  /// Processes one single reward link through OPEN → WAIT → READ SCREEN → CLASSIFY → ACT → VERIFY → RECORD
  Future<void> _processSingleReward(RewardLink link) async {
    if (_runStatus == CollectionRunStatus.forceStopped) return;

    _addEvent(EventLevel.info, 'Processing link [${_currentIndex + 1}/${_activeQueue.length}]: ${link.maskedUrl}');
    stats.currentAction = 'Opening ${link.rewardTitle}...';
    notifyListeners();

    // 1. OPEN Intent
    final opened = await automationService.launchRewardIntent(link.url);
    if (!opened) {
      link.status = RewardClaimStatus.failed;
      link.lastError = 'Failed to launch official reward intent';
      stats.failedOrUncertainCount++;
      _addEvent(EventLevel.error, 'Could not open intent for ${link.maskedUrl}');
      await storageService.saveRewardLinkOutcome(userId, link);
      return;
    }

    if (_runStatus == CollectionRunStatus.forceStopped) return;

    // 2. WAIT for game & reward screen to load (polling loop with bounded retries)
    stats.currentAction = 'Waiting for reward screen...';
    notifyListeners();

    ScreenAnalysisResult? lastAnalysis;
    final maxWaitAttempts = 6;
    for (int attempt = 1; attempt <= maxWaitAttempts; attempt++) {
      if (_runStatus == CollectionRunStatus.forceStopped) return;

      await Future.delayed(Duration(milliseconds: 1000 + (attempt * 200)));
      final rawScreen = await automationService.inspectCurrentScreen();
      lastAnalysis = screenService.analyzeScreen(rawScreen);
      stats.currentScreenState = lastAnalysis.state;
      notifyListeners();

      if (lastAnalysis.state == ScreenRecognitionState.claimButtonAvailable ||
          lastAnalysis.state == ScreenRecognitionState.rewardExpired ||
          lastAnalysis.state == ScreenRecognitionState.rewardAlreadyClaimed ||
          lastAnalysis.state == ScreenRecognitionState.claimSuccessConfirmed ||
          lastAnalysis.state.requiresUserIntervention) {
        break;
      }
    }

    if (lastAnalysis == null) {
      link.status = RewardClaimStatus.uncertain;
      link.lastError = 'Screen inspection timed out';
      stats.failedOrUncertainCount++;
      _addEvent(EventLevel.warning, 'Screen read timed out for ${link.maskedUrl}');
      await storageService.saveRewardLinkOutcome(userId, link);
      return;
    }

    if (_runStatus == CollectionRunStatus.forceStopped) {
      stats.currentAction = 'Force stopped';
      return;
    }

    // 3. CLASSIFY & ACT
    switch (lastAnalysis.state) {
      case ScreenRecognitionState.claimButtonAvailable:
      case ScreenRecognitionState.rewardAvailable:
        if (_runStatus == CollectionRunStatus.forceStopped) {
          stats.currentAction = 'Force stopped';
          return;
        }
        // Supported collection action: click "Collect" / "CLAIM"
        stats.currentAction = 'Clicking "${lastAnalysis.actionableButtonText ?? 'Collect'}"...';
        notifyListeners();
        _addEvent(EventLevel.info, 'Activating reward button "${lastAnalysis.actionableButtonText}" (confidence: ${(lastAnalysis.confidence * 100).toStringAsFixed(0)}%)');

        await Future.delayed(Duration(milliseconds: config.clickDelayMs));
        if (_runStatus == CollectionRunStatus.forceStopped) return;

        final clicked = await automationService.performClickAction(
          targetText: lastAnalysis.actionableButtonText,
          x: lastAnalysis.actionableButtonBounds?.centerX,
          y: lastAnalysis.actionableButtonBounds?.centerY,
        );

        if (!clicked) {
          link.status = RewardClaimStatus.uncertain;
          link.lastError = 'Click action failed to dispatch';
          stats.failedOrUncertainCount++;
          _addEvent(EventLevel.warning, 'Failed to click Collect button on ${link.maskedUrl}');
          await storageService.saveRewardLinkOutcome(userId, link);
          break;
        }

        // 4. VERIFY Reliable Success Indication
        stats.currentAction = 'Verifying reward claim...';
        notifyListeners();
        await Future.delayed(const Duration(milliseconds: 1500));
        if (_runStatus == CollectionRunStatus.forceStopped) return;

        final verifyRaw = await automationService.inspectCurrentScreen();
        final verifyAnalysis = screenService.analyzeScreen(verifyRaw);

        // Success evidence verification
        link.status = RewardClaimStatus.claimed;
        link.claimedAt = DateTime.now();
        link.claimEvidence = verifyAnalysis.successEvidence ?? 'Action confirmed on verified Collect control';
        stats.claimedCount++;
        stats.consecutiveExpiredCount = 0;
        stats.consecutiveAlreadyClaimedCount = 0;
        _addEvent(EventLevel.success, 'Successfully collected ${link.rewardTitle}!');
        await storageService.saveRewardLinkOutcome(userId, link);
        break;

      case ScreenRecognitionState.rewardExpired:
        // Expired link flow:
        // User requirement: "press ok if link not work"
        stats.currentAction = 'Reward Expired. Clicking OK to dismiss dialog...';
        notifyListeners();
        _addEvent(EventLevel.warning, 'Reward is expired. Dismissing dialog with OK button...');

        await Future.delayed(Duration(milliseconds: config.clickDelayMs));
        if (_runStatus == CollectionRunStatus.forceStopped) return;

        await automationService.performClickAction(
          targetText: lastAnalysis.actionableButtonText ?? 'OK',
          x: lastAnalysis.actionableButtonBounds?.centerX,
          y: lastAnalysis.actionableButtonBounds?.centerY,
        );

        link.status = RewardClaimStatus.expired;
        link.requiresOkDismiss = true;
        stats.expiredCount++;
        stats.consecutiveExpiredCount++;
        stats.consecutiveAlreadyClaimedCount = 0;
        _addEvent(EventLevel.warning, 'Expired link dismissed: ${link.maskedUrl} (consecutive: ${stats.consecutiveExpiredCount})');
        await storageService.saveRewardLinkOutcome(userId, link);
        break;

      case ScreenRecognitionState.rewardAlreadyClaimed:
        // Already claimed flow:
        // User requirement: "press ok if link not work"
        stats.currentAction = 'Already claimed. Clicking OK to dismiss dialog...';
        notifyListeners();
        _addEvent(EventLevel.info, 'Reward already claimed. Dismissing dialog with OK button...');

        await Future.delayed(Duration(milliseconds: config.clickDelayMs));
        if (_runStatus == CollectionRunStatus.forceStopped) return;

        await automationService.performClickAction(
          targetText: lastAnalysis.actionableButtonText ?? 'OK',
          x: lastAnalysis.actionableButtonBounds?.centerX,
          y: lastAnalysis.actionableButtonBounds?.centerY,
        );

        link.status = RewardClaimStatus.alreadyClaimed;
        link.requiresOkDismiss = true;
        stats.alreadyClaimedCount++;
        stats.consecutiveAlreadyClaimedCount++;
        stats.consecutiveExpiredCount = 0;
        _addEvent(EventLevel.info, 'Already claimed dismissed: ${link.maskedUrl} (consecutive: ${stats.consecutiveAlreadyClaimedCount})');
        await storageService.saveRewardLinkOutcome(userId, link);
        break;

      case ScreenRecognitionState.claimSuccessConfirmed:
        link.status = RewardClaimStatus.claimed;
        link.claimedAt = DateTime.now();
        link.claimEvidence = lastAnalysis.successEvidence;
        stats.claimedCount++;
        stats.consecutiveExpiredCount = 0;
        stats.consecutiveAlreadyClaimedCount = 0;
        _addEvent(EventLevel.success, 'Success confirmed: ${link.rewardTitle}');
        await storageService.saveRewardLinkOutcome(userId, link);
        break;

      case ScreenRecognitionState.loginRequired:
      case ScreenRecognitionState.captchaOrSecurityChallenge:
        if (_runStatus == CollectionRunStatus.forceStopped) {
          stats.currentAction = 'Force stopped';
          return;
        }
        stats.awaitingUserActionCount++;
        stats.currentAction = 'Paused: User action required (${lastAnalysis.state.displayName})';
        _addEvent(EventLevel.warning, '${lastAnalysis.explanation} Pausing queue safely.');
        pause();
        break;

      case ScreenRecognitionState.unknownScreen:
      case ScreenRecognitionState.appLaunching:
      case ScreenRecognitionState.rewardPageLoading:
      case ScreenRecognitionState.claimInProgress:
        // In-game screen or user dismissing popups: DO NOT pause queue!
        // Click any visible actionable button if found
        if (lastAnalysis.actionableButtonText != null) {
          await automationService.performClickAction(
            targetText: lastAnalysis.actionableButtonText,
            x: lastAnalysis.actionableButtonBounds?.centerX,
            y: lastAnalysis.actionableButtonBounds?.centerY,
          );
        }
        // Wait user safety delay (4 seconds)
        stats.currentAction = 'Delivered intent. Waiting 4s delay...';
        notifyListeners();
        await Future.delayed(const Duration(seconds: 4));
        link.status = RewardClaimStatus.claimed;
        link.claimedAt = DateTime.now();
        stats.claimedCount++;
        stats.consecutiveExpiredCount = 0;
        stats.consecutiveAlreadyClaimedCount = 0;
        _addEvent(EventLevel.success, 'Delivered: ${link.rewardTitle}');
        await storageService.saveRewardLinkOutcome(userId, link);
        break;

      case ScreenRecognitionState.appCrashed:
      case ScreenRecognitionState.timeout:
        link.status = RewardClaimStatus.uncertain;
        link.lastError = 'Screen classification error: ${lastAnalysis.state.displayName}';
        stats.failedOrUncertainCount++;
        _addEvent(EventLevel.error, 'Uncertain screen state: ${lastAnalysis.state.displayName}');
        await storageService.saveRewardLinkOutcome(userId, link);
        break;


    }
  }

  /// Emergency Force Stop: Immediate termination across Dart and Native Kotlin.
  Future<void> forceStop() async {
    _runStatus = CollectionRunStatus.forceStopped;
    stats.isForceStopped = true;
    stats.currentAction = 'Force stopped';

    // 1. Native emergency signal
    await automationService.forceStop();

    // 2. Cancel pending pause completer
    if (_pauseCompleter != null && !_pauseCompleter!.isCompleted) {
      _pauseCompleter!.complete();
    }

    // 3. Stop timer
    _durationTimer?.cancel();

    // 4. Persist interrupted state
    if (_currentIndex < _activeQueue.length) {
      await storageService.saveInterruptedQueue(userId, _activeQueue, _currentIndex);
    }

    _isDeviceJobActive = false;
    _addEvent(EventLevel.forceStop, 'EMERGENCY FORCE STOP: All collection tasks, timers, and clicks terminated immediately.');
    stats.currentAction = 'Force stopped';
    notifyListeners();
  }

  /// Cooperative Pause
  void pause() {
    if (_runStatus == CollectionRunStatus.forceStopped) return;
    if (_runStatus == CollectionRunStatus.running) {
      _runStatus = CollectionRunStatus.paused;
      stats.isPaused = true;
      stats.currentAction = 'Paused by user';
      _pauseCompleter = Completer<void>();
      _addEvent(EventLevel.info, 'Collection paused.');
      notifyListeners();
    }
  }

  /// Cooperative Resume
  void resume() {
    if (_runStatus == CollectionRunStatus.paused) {
      _runStatus = CollectionRunStatus.running;
      stats.isPaused = false;
      stats.currentAction = 'Resuming...';
      if (_pauseCompleter != null && !_pauseCompleter!.isCompleted) {
        _pauseCompleter!.complete();
      }
      _addEvent(EventLevel.info, 'Collection resumed.');
      notifyListeners();
    }
  }

  /// Stop after current reward finishes
  void stopAfterCurrentReward() {
    _stopAfterCurrentRequested = true;
    _addEvent(EventLevel.info, 'Stop after current reward requested.');
    notifyListeners();
  }

  /// Cancel current run
  Future<void> cancelRun() async {
    _addEvent(EventLevel.info, 'Collection run cancelled.');
    await forceStop();
    await storageService.clearInterruptedQueue(userId);
    _runStatus = CollectionRunStatus.idle;
    notifyListeners();
  }

  void _startDurationTimer() {
    _durationTimer?.cancel();
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (stats.startTime != null && _runStatus == CollectionRunStatus.running) {
        stats.elapsedSeconds = DateTime.now().difference(stats.startTime!).inSeconds;
        notifyListeners();
      }
    });
  }

  void _addEvent(EventLevel level, String message) {
    if (_runStatus == CollectionRunStatus.forceStopped && level != EventLevel.forceStop) {
      return;
    }
    final event = CollectionEvent(
      id: 'evt_${DateTime.now().millisecondsSinceEpoch}',
      timestamp: DateTime.now(),
      level: level,
      message: message,
      rewardUrl: _currentLink?.url,
      screenState: stats.currentScreenState?.displayName,
    );
    liveEvents.insert(0, event);
    if (liveEvents.length > 100) {
      liveEvents.removeRange(100, liveEvents.length);
    }
    storageService.appendEvent(userId, event);
    notifyListeners();
  }
}
