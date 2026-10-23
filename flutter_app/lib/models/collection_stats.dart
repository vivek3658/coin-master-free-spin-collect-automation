import 'screen_recognition_state.dart';

class CollectionStats {
  int totalEligible;
  int processedCount;
  int claimedCount;
  int expiredCount;
  int alreadyClaimedCount;
  int awaitingUserActionCount;
  int failedOrUncertainCount;
  int consecutiveExpiredCount;
  int consecutiveAlreadyClaimedCount;
  DateTime? startTime;
  int elapsedSeconds;
  String currentAction;
  int currentRewardIndex;
  bool isForceStopped;
  bool isPaused;
  ScreenRecognitionState? currentScreenState;

  CollectionStats({
    this.totalEligible = 0,
    this.processedCount = 0,
    this.claimedCount = 0,
    this.expiredCount = 0,
    this.alreadyClaimedCount = 0,
    this.awaitingUserActionCount = 0,
    this.failedOrUncertainCount = 0,
    this.consecutiveExpiredCount = 0,
    this.consecutiveAlreadyClaimedCount = 0,
    this.startTime,
    this.elapsedSeconds = 0,
    this.currentAction = 'Idle',
    this.currentRewardIndex = 0,
    this.isForceStopped = false,
    this.isPaused = false,
    this.currentScreenState,
  });

  void reset({int total = 0}) {
    totalEligible = total;
    processedCount = 0;
    claimedCount = 0;
    expiredCount = 0;
    alreadyClaimedCount = 0;
    awaitingUserActionCount = 0;
    failedOrUncertainCount = 0;
    consecutiveExpiredCount = 0;
    consecutiveAlreadyClaimedCount = 0;
    startTime = DateTime.now();
    elapsedSeconds = 0;
    currentAction = 'Starting...';
    currentRewardIndex = 0;
    isForceStopped = false;
    isPaused = false;
    currentScreenState = null;
  }

  CollectionStats copy() {
    return CollectionStats(
      totalEligible: totalEligible,
      processedCount: processedCount,
      claimedCount: claimedCount,
      expiredCount: expiredCount,
      alreadyClaimedCount: alreadyClaimedCount,
      awaitingUserActionCount: awaitingUserActionCount,
      failedOrUncertainCount: failedOrUncertainCount,
      consecutiveExpiredCount: consecutiveExpiredCount,
      consecutiveAlreadyClaimedCount: consecutiveAlreadyClaimedCount,
      startTime: startTime,
      elapsedSeconds: elapsedSeconds,
      currentAction: currentAction,
      currentRewardIndex: currentRewardIndex,
      isForceStopped: isForceStopped,
      isPaused: isPaused,
      currentScreenState: currentScreenState,
    );
  }
}
