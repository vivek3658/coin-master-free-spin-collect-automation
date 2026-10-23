enum RewardClaimStatus {
  unclaimed,
  inProgress,
  claimed,
  expired,
  alreadyClaimed,
  failed,
  uncertain,
  skipped,
}

extension RewardClaimStatusExt on RewardClaimStatus {
  String get displayName {
    switch (this) {
      case RewardClaimStatus.unclaimed:
        return 'Unclaimed';
      case RewardClaimStatus.inProgress:
        return 'In Progress';
      case RewardClaimStatus.claimed:
        return 'Claimed';
      case RewardClaimStatus.expired:
        return 'Expired';
      case RewardClaimStatus.alreadyClaimed:
        return 'Already Claimed';
      case RewardClaimStatus.failed:
        return 'Failed';
      case RewardClaimStatus.uncertain:
        return 'Uncertain';
      case RewardClaimStatus.skipped:
        return 'Skipped';
    }
  }

  bool get isFinal =>
      this == RewardClaimStatus.claimed ||
      this == RewardClaimStatus.expired ||
      this == RewardClaimStatus.alreadyClaimed ||
      this == RewardClaimStatus.skipped;
}

class RewardLink {
  final String id;
  final String url;
  final String canonicalUrl;
  final String source;
  final String rewardTitle;
  final String rewardType;
  final int rewardAmount;
  final DateTime discoveredAt;
  RewardClaimStatus status;
  DateTime? claimedAt;
  String? claimEvidence;
  int retryCount;
  String? lastError;
  final String userId;
  bool requiresOkDismiss;

  RewardLink({
    required this.id,
    required this.url,
    required this.canonicalUrl,
    required this.source,
    required this.rewardTitle,
    this.rewardType = 'spins',
    this.rewardAmount = 25,
    required this.discoveredAt,
    this.status = RewardClaimStatus.unclaimed,
    this.claimedAt,
    this.claimEvidence,
    this.retryCount = 0,
    this.lastError,
    required this.userId,
    this.requiresOkDismiss = false,
  });

  /// Sanitized URL for dashboard and logging (masks sensitive campaign parameters)
  String get maskedUrl {
    try {
      final uri = Uri.parse(url);
      final host = uri.host;
      final pathSegments = uri.pathSegments;
      if (pathSegments.isEmpty) return '$host/...';
      final lastPart = pathSegments.last;
      final shortLast = lastPart.length > 8 ? '${lastPart.substring(0, 4)}...${lastPart.substring(lastPart.length - 4)}' : lastPart;
      return '$host/.../$shortLast';
    } catch (_) {
      return url.length > 30 ? '${url.substring(0, 25)}...' : url;
    }
  }

  String get dateCategory {
    final now = DateTime.now();
    final diff = now.difference(discoveredAt);
    if (diff.inHours < 24 && now.day == discoveredAt.day) {
      return 'Today';
    } else if (diff.inDays <= 1 || (now.day - discoveredAt.day == 1)) {
      return 'Yesterday';
    } else if (diff.inDays <= 2) {
      return '2 Days Ago';
    } else {
      return 'Older';
    }
  }

  /// Coin Master official reward links have an active lifetime of ~48 hours.
  DateTime get expiresAt => discoveredAt.add(const Duration(hours: 48));

  /// True if the link is beyond the 48-hour valid lifetime.
  bool get isPastExpiration => DateTime.now().isAfter(expiresAt);

  /// Human-readable expiration countdown (e.g., '28h left', '45m left', 'Offer Ended')
  String get expirationTimeRemaining {
    final now = DateTime.now();
    final remaining = expiresAt.difference(now);
    if (remaining.isNegative) {
      return 'Offer Ended';
    }
    if (remaining.inHours >= 1) {
      return '${remaining.inHours}h left';
    }
    return '${remaining.inMinutes}m left';
  }

  String get rewardBadgeText {
    if (rewardType == 'coins') {
      if (rewardAmount >= 1000000) {
        final m = (rewardAmount / 1000000).toStringAsFixed(1).replaceAll('.0', '');
        return '${m}M Coins';
      }
      return '${rewardAmount ~/ 1000}K Coins';
    } else if (rewardType == 'mixed') {
      return '$rewardAmount Spins + Coins';
    }
    return '$rewardAmount Spins';
  }

  RewardLink copyWith({
    String? id,
    String? url,
    String? canonicalUrl,
    String? source,
    String? rewardTitle,
    String? rewardType,
    int? rewardAmount,
    DateTime? discoveredAt,
    RewardClaimStatus? status,
    DateTime? claimedAt,
    String? claimEvidence,
    int? retryCount,
    String? lastError,
    String? userId,
    bool? requiresOkDismiss,
  }) {
    return RewardLink(
      id: id ?? this.id,
      url: url ?? this.url,
      canonicalUrl: canonicalUrl ?? this.canonicalUrl,
      source: source ?? this.source,
      rewardTitle: rewardTitle ?? this.rewardTitle,
      rewardType: rewardType ?? this.rewardType,
      rewardAmount: rewardAmount ?? this.rewardAmount,
      discoveredAt: discoveredAt ?? this.discoveredAt,
      status: status ?? this.status,
      claimedAt: claimedAt ?? this.claimedAt,
      claimEvidence: claimEvidence ?? this.claimEvidence,
      retryCount: retryCount ?? this.retryCount,
      lastError: lastError ?? this.lastError,
      userId: userId ?? this.userId,
      requiresOkDismiss: requiresOkDismiss ?? this.requiresOkDismiss,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'url': url,
        'canonicalUrl': canonicalUrl,
        'source': source,
        'rewardTitle': rewardTitle,
        'rewardType': rewardType,
        'rewardAmount': rewardAmount,
        'discoveredAt': discoveredAt.toIso8601String(),
        'status': status.name,
        'claimedAt': claimedAt?.toIso8601String(),
        'claimEvidence': claimEvidence,
        'retryCount': retryCount,
        'lastError': lastError,
        'userId': userId,
        'requiresOkDismiss': requiresOkDismiss,
      };

  factory RewardLink.fromJson(Map<String, dynamic> json) {
    return RewardLink(
      id: json['id'] as String,
      url: json['url'] as String,
      canonicalUrl: json['canonicalUrl'] as String? ?? json['url'] as String,
      source: json['source'] as String? ?? 'Social Feed',
      rewardTitle: json['rewardTitle'] as String? ?? 'Reward',
      rewardType: json['rewardType'] as String? ?? 'spins',
      rewardAmount: (json['rewardAmount'] as num?)?.toInt() ?? 25,
      discoveredAt: DateTime.tryParse(json['discoveredAt'] as String? ?? '') ?? DateTime.now(),
      status: RewardClaimStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => RewardClaimStatus.unclaimed,
      ),
      claimedAt: json['claimedAt'] != null ? DateTime.tryParse(json['claimedAt'] as String) : null,
      claimEvidence: json['claimEvidence'] as String?,
      retryCount: (json['retryCount'] as num?)?.toInt() ?? 0,
      lastError: json['lastError'] as String?,
      userId: json['userId'] as String? ?? 'default_user',
      requiresOkDismiss: json['requiresOkDismiss'] as bool? ?? false,
    );
  }
}
