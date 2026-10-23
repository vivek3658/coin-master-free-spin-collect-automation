import 'dart:convert';
import 'dart:io';
import '../models/collector_config.dart';
import '../models/reward_link.dart';
import '../models/user_profile.dart';
import '../models/collection_event.dart';

class StorageService {
  final Directory _baseDir;

  StorageService({Directory? baseDir})
      : _baseDir = baseDir ?? _resolveDefaultDirectory();

  static Directory _resolveDefaultDirectory() {
    try {
      final dir = Directory('.rewardpilot_data');
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
      return dir;
    } catch (_) {
      final fallback = Directory.systemTemp.createTempSync('rewardpilot_');
      return fallback;
    }
  }

  Future<void> _ensureDir() async {
    if (!await _baseDir.exists()) {
      await _baseDir.create(recursive: true);
    }
  }

  File _getUserConfigFile(String userId) =>
      File('${_baseDir.path}/user_${userId}_config.json');

  File _getUserHistoryFile(String userId) =>
      File('${_baseDir.path}/user_${userId}_history.json');

  File _getUserInterruptedQueueFile(String userId) =>
      File('${_baseDir.path}/user_${userId}_interrupted_queue.json');

  File _getUsersListFile() => File('${_baseDir.path}/users.json');

  File _getEventsFile(String userId) =>
      File('${_baseDir.path}/user_${userId}_events.json');

  // User Profile Management (Per-User Isolation)
  Future<List<UserProfile>> getUsers() async {
    await _ensureDir();
    final file = _getUsersListFile();
    if (!await file.exists()) {
      final defaultUsers = [
        UserProfile(
          id: 'user_default',
          name: 'Main Account',
          gamePlayerId: 'CM_PLAYER_01',
          isActive: true,
          createdAt: DateTime.now(),
        ),
        UserProfile(
          id: 'user_alt_02',
          name: 'Secondary Account',
          gamePlayerId: 'CM_PLAYER_02',
          isActive: false,
          createdAt: DateTime.now(),
        ),
      ];
      await saveUsers(defaultUsers);
      return defaultUsers;
    }
    try {
      final text = await file.readAsString();
      final list = jsonDecode(text) as List<dynamic>;
      return list.map((e) => UserProfile.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveUsers(List<UserProfile> users) async {
    await _ensureDir();
    final file = _getUsersListFile();
    final jsonList = users.map((u) => u.toJson()).toList();
    await file.writeAsString(jsonEncode(jsonList));
  }

  // Per-User Reward History (Claimed & Expired)
  Future<Map<String, RewardLink>> getRewardHistory(String userId) async {
    await _ensureDir();
    final file = _getUserHistoryFile(userId);
    if (!await file.exists()) return {};
    try {
      final text = await file.readAsString();
      final map = jsonDecode(text) as Map<String, dynamic>;
      final result = <String, RewardLink>{};
      map.forEach((key, value) {
        result[key] = RewardLink.fromJson(value as Map<String, dynamic>);
      });
      return result;
    } catch (_) {
      return {};
    }
  }

  Future<void> saveRewardLinkOutcome(String userId, RewardLink link) async {
    await _ensureDir();
    final history = await getRewardHistory(userId);
    history[link.canonicalUrl] = link;
    final file = _getUserHistoryFile(userId);
    final map = history.map((key, val) => MapEntry(key, val.toJson()));
    await file.writeAsString(jsonEncode(map));
  }

  /// Manually unmarks a single reward so the user can re-test claiming it
  Future<void> unmarkReward(String userId, String canonicalUrl) async {
    await _ensureDir();
    final history = await getRewardHistory(userId);
    if (history.containsKey(canonicalUrl)) {
      history.remove(canonicalUrl);
      final file = _getUserHistoryFile(userId);
      final map = history.map((key, val) => MapEntry(key, val.toJson()));
      await file.writeAsString(jsonEncode(map));
    }
  }

  /// Clears all claimed & expired history records for testing
  Future<void> clearRewardHistory(String userId) async {
    await _ensureDir();
    final file = _getUserHistoryFile(userId);
    if (await file.exists()) {
      await file.delete();
    }
  }

  // Interrupted Queue Recovery
  Future<void> saveInterruptedQueue(String userId, List<RewardLink> queue, int currentIndex) async {
    await _ensureDir();
    final file = _getUserInterruptedQueueFile(userId);
    final data = {
      'userId': userId,
      'savedAt': DateTime.now().toIso8601String(),
      'currentIndex': currentIndex,
      'queue': queue.map((e) => e.toJson()).toList(),
    };
    await file.writeAsString(jsonEncode(data));
  }

  Future<Map<String, dynamic>?> getInterruptedQueue(String userId) async {
    await _ensureDir();
    final file = _getUserInterruptedQueueFile(userId);
    if (!await file.exists()) return null;
    try {
      final text = await file.readAsString();
      return jsonDecode(text) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  Future<void> clearInterruptedQueue(String userId) async {
    await _ensureDir();
    final file = _getUserInterruptedQueueFile(userId);
    if (await file.exists()) {
      await file.delete();
    }
  }

  // Config Management
  Future<CollectorConfig> getConfig(String userId) async {
    await _ensureDir();
    final file = _getUserConfigFile(userId);
    if (!await file.exists()) return CollectorConfig();
    try {
      final text = await file.readAsString();
      return CollectorConfig.fromJson(jsonDecode(text) as Map<String, dynamic>);
    } catch (_) {
      return CollectorConfig();
    }
  }

  Future<void> saveConfig(String userId, CollectorConfig config) async {
    await _ensureDir();
    final file = _getUserConfigFile(userId);
    await file.writeAsString(jsonEncode(config.toJson()));
  }

  // Audit Events
  Future<void> appendEvent(String userId, CollectionEvent event) async {
    try {
      await _ensureDir();
      final file = _getEventsFile(userId);
      final events = await getEvents(userId);
      events.insert(0, event);
      if (events.length > 150) {
        events.removeRange(150, events.length);
      }
      final jsonList = events.map((e) => e.toJson()).toList();
      await file.writeAsString(jsonEncode(jsonList));
    } catch (_) {
      // Safe drop if directory was cleaned up during test tearDown
    }
  }

  Future<List<CollectionEvent>> getEvents(String userId) async {
    await _ensureDir();
    final file = _getEventsFile(userId);
    if (!await file.exists()) return [];
    try {
      final text = await file.readAsString();
      final list = jsonDecode(text) as List<dynamic>;
      return list.map((e) => CollectionEvent.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }
}

/// In-Memory Storage Service for isolated unit & widget tests
class MemoryStorageService extends StorageService {
  final Map<String, List<UserProfile>> _usersMap = {};
  final Map<String, Map<String, RewardLink>> _historyMap = {};
  final Map<String, Map<String, dynamic>> _interruptedMap = {};
  final Map<String, CollectorConfig> _configMap = {};
  final Map<String, List<CollectionEvent>> _eventsMap = {};

  MemoryStorageService() : super(baseDir: Directory.systemTemp);

  @override
  Future<List<UserProfile>> getUsers() async {
    if (!_usersMap.containsKey('all')) {
      _usersMap['all'] = [
        UserProfile(
          id: 'user_default',
          name: 'Main Account',
          gamePlayerId: 'CM_PLAYER_01',
          isActive: true,
          createdAt: DateTime.now(),
        ),
      ];
    }
    return List.from(_usersMap['all']!);
  }

  @override
  Future<void> saveUsers(List<UserProfile> users) async {
    _usersMap['all'] = List.from(users);
  }

  @override
  Future<Map<String, RewardLink>> getRewardHistory(String userId) async {
    return Map.from(_historyMap[userId] ?? {});
  }

  @override
  Future<void> saveRewardLinkOutcome(String userId, RewardLink link) async {
    _historyMap.putIfAbsent(userId, () => {});
    _historyMap[userId]![link.canonicalUrl] = link;
  }

  @override
  Future<void> saveInterruptedQueue(String userId, List<RewardLink> queue, int currentIndex) async {
    _interruptedMap[userId] = {
      'userId': userId,
      'savedAt': DateTime.now().toIso8601String(),
      'currentIndex': currentIndex,
      'queue': queue.map((e) => e.toJson()).toList(),
    };
  }

  @override
  Future<Map<String, dynamic>?> getInterruptedQueue(String userId) async {
    return _interruptedMap[userId];
  }

  @override
  Future<void> clearInterruptedQueue(String userId) async {
    _interruptedMap.remove(userId);
  }

  @override
  Future<CollectorConfig> getConfig(String userId) async {
    return _configMap[userId] ?? CollectorConfig();
  }

  @override
  Future<void> saveConfig(String userId, CollectorConfig config) async {
    _configMap[userId] = config;
  }

  @override
  Future<void> appendEvent(String userId, CollectionEvent event) async {
    _eventsMap.putIfAbsent(userId, () => []);
    _eventsMap[userId]!.insert(0, event);
  }

  @override
  Future<List<CollectionEvent>> getEvents(String userId) async {
    return List.from(_eventsMap[userId] ?? []);
  }
}
