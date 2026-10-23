enum EventLevel {
  info,
  success,
  warning,
  error,
  forceStop,
}

class CollectionEvent {
  final String id;
  final DateTime timestamp;
  final EventLevel level;
  final String message;
  final String? rewardUrl;
  final String? screenState;
  final String? actionTaken;

  const CollectionEvent({
    required this.id,
    required this.timestamp,
    required this.level,
    required this.message,
    this.rewardUrl,
    this.screenState,
    this.actionTaken,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'timestamp': timestamp.toIso8601String(),
        'level': level.name,
        'message': message,
        'rewardUrl': rewardUrl,
        'screenState': screenState,
        'actionTaken': actionTaken,
      };

  factory CollectionEvent.fromJson(Map<String, dynamic> json) {
    return CollectionEvent(
      id: json['id'] as String,
      timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ?? DateTime.now(),
      level: EventLevel.values.firstWhere(
        (e) => e.name == json['level'],
        orElse: () => EventLevel.info,
      ),
      message: json['message'] as String? ?? '',
      rewardUrl: json['rewardUrl'] as String?,
      screenState: json['screenState'] as String?,
      actionTaken: json['actionTaken'] as String?,
    );
  }
}
