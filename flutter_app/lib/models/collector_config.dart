class CollectorConfig {
  int consecutiveExpiredThreshold;
  int consecutiveAlreadyClaimedThreshold;
  int maxLinksPerRun;
  int maxExecutionDurationMinutes;
  int launchTimeoutSeconds;
  int screenLoadTimeoutSeconds;
  int verificationTimeoutSeconds;
  int clickDelayMs;
  bool enableMockMode;

  CollectorConfig({
    this.consecutiveExpiredThreshold = 3,
    this.consecutiveAlreadyClaimedThreshold = 3,
    this.maxLinksPerRun = 25,
    this.maxExecutionDurationMinutes = 15,
    this.launchTimeoutSeconds = 12,
    this.screenLoadTimeoutSeconds = 10,
    this.verificationTimeoutSeconds = 8,
    this.clickDelayMs = 1200,
    this.enableMockMode = false,
  });

  CollectorConfig copyWith({
    int? consecutiveExpiredThreshold,
    int? consecutiveAlreadyClaimedThreshold,
    int? maxLinksPerRun,
    int? maxExecutionDurationMinutes,
    int? launchTimeoutSeconds,
    int? screenLoadTimeoutSeconds,
    int? verificationTimeoutSeconds,
    int? clickDelayMs,
    bool? enableMockMode,
  }) {
    return CollectorConfig(
      consecutiveExpiredThreshold: consecutiveExpiredThreshold ?? this.consecutiveExpiredThreshold,
      consecutiveAlreadyClaimedThreshold:
          consecutiveAlreadyClaimedThreshold ?? this.consecutiveAlreadyClaimedThreshold,
      maxLinksPerRun: maxLinksPerRun ?? this.maxLinksPerRun,
      maxExecutionDurationMinutes: maxExecutionDurationMinutes ?? this.maxExecutionDurationMinutes,
      launchTimeoutSeconds: launchTimeoutSeconds ?? this.launchTimeoutSeconds,
      screenLoadTimeoutSeconds: screenLoadTimeoutSeconds ?? this.screenLoadTimeoutSeconds,
      verificationTimeoutSeconds: verificationTimeoutSeconds ?? this.verificationTimeoutSeconds,
      clickDelayMs: clickDelayMs ?? this.clickDelayMs,
      enableMockMode: enableMockMode ?? this.enableMockMode,
    );
  }

  Map<String, dynamic> toJson() => {
        'consecutiveExpiredThreshold': consecutiveExpiredThreshold,
        'consecutiveAlreadyClaimedThreshold': consecutiveAlreadyClaimedThreshold,
        'maxLinksPerRun': maxLinksPerRun,
        'maxExecutionDurationMinutes': maxExecutionDurationMinutes,
        'launchTimeoutSeconds': launchTimeoutSeconds,
        'screenLoadTimeoutSeconds': screenLoadTimeoutSeconds,
        'verificationTimeoutSeconds': verificationTimeoutSeconds,
        'clickDelayMs': clickDelayMs,
        'enableMockMode': enableMockMode,
      };

  factory CollectorConfig.fromJson(Map<String, dynamic> json) {
    return CollectorConfig(
      consecutiveExpiredThreshold: (json['consecutiveExpiredThreshold'] as num?)?.toInt() ?? 3,
      consecutiveAlreadyClaimedThreshold:
          (json['consecutiveAlreadyClaimedThreshold'] as num?)?.toInt() ?? 3,
      maxLinksPerRun: (json['maxLinksPerRun'] as num?)?.toInt() ?? 25,
      maxExecutionDurationMinutes:
          (json['maxExecutionDurationMinutes'] as num?)?.toInt() ?? 15,
      launchTimeoutSeconds: (json['launchTimeoutSeconds'] as num?)?.toInt() ?? 12,
      screenLoadTimeoutSeconds: (json['screenLoadTimeoutSeconds'] as num?)?.toInt() ?? 10,
      verificationTimeoutSeconds: (json['verificationTimeoutSeconds'] as num?)?.toInt() ?? 8,
      clickDelayMs: (json['clickDelayMs'] as num?)?.toInt() ?? 1200,
      enableMockMode: json['enableMockMode'] as bool? ?? false,
    );
  }
}
