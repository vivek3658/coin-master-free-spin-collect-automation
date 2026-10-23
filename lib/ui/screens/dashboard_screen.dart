import 'package:flutter/material.dart';
import '../../models/collection_event.dart';
import '../../models/collection_stats.dart';
import '../../models/collector_config.dart';
import '../../models/reward_link.dart';
import '../../models/screen_recognition_state.dart';
import '../../models/user_profile.dart';
import '../../services/autonomous_collection_coordinator.dart';
import '../../services/native_automation_service.dart';
import '../../services/reward_discovery_service.dart';
import '../../services/screen_recognition_service.dart';
import '../../services/storage_service.dart';
import 'accessibility_guide_sheet.dart';
import 'settings_sheet.dart';

class DashboardScreen extends StatefulWidget {
  final StorageService storageService;
  final NativeAutomationService? automationService;

  const DashboardScreen({
    super.key,
    required this.storageService,
    this.automationService,
  });

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> with WidgetsBindingObserver {
  late NativeAutomationService _automationService;
  late ScreenRecognitionService _screenService;
  late RewardDiscoveryService _discoveryService;
  AutonomousCollectionCoordinator? _coordinator;

  List<UserProfile> _users = [];
  UserProfile? _activeUser;
  bool _isAccessibilityEnabled = false;
  CollectorConfig _config = CollectorConfig();
  bool _isLoading = true;

  // Carousel & Filter State
  final PageController _carouselController = PageController(viewportFraction: 0.88);
  int _currentCarouselPage = 0;
  String _selectedCategoryTab = 'All';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _automationService = widget.automationService ?? AndroidNativeAutomationService();
    _screenService = ScreenRecognitionService();
    _discoveryService = RewardDiscoveryService();
    _initApp();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _carouselController.dispose();
    _coordinator?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Automatically scan and discover new official spin drops whenever app is opened or resumed
      _coordinator?.loadInitialQueue();
      _checkPermission();
    }
  }

  Future<void> _initApp() async {
    final users = await widget.storageService.getUsers();
    final active = users.isNotEmpty ? users.first : null;
    final config = active != null ? await widget.storageService.getConfig(active.id) : CollectorConfig();
    final isAcc = await _automationService.isAccessibilityEnabled();

    setState(() {
      _users = users;
      _activeUser = active;
      _config = config;
      _isAccessibilityEnabled = isAcc;
      _isLoading = false;
    });

    if (active != null) {
      _setupCoordinator(active.id);
    }
  }

  void _setupCoordinator(String userId) {
    _coordinator?.dispose();
    final service = _config.enableMockMode ? MockAutomationService() : _automationService;
    _coordinator = AutonomousCollectionCoordinator(
      automationService: service,
      screenService: _screenService,
      discoveryService: _discoveryService,
      storageService: widget.storageService,
      userId: userId,
      initialConfig: _config,
    );
    _coordinator!.addListener(() {
      if (mounted) setState(() {});
    });

    // Automatically load all rich Levvvel-style daily rewards on start
    _coordinator!.loadInitialQueue();
  }

  Future<void> _checkPermission() async {
    final isAcc = await _automationService.isAccessibilityEnabled();
    setState(() => _isAccessibilityEnabled = isAcc);
  }

  Future<void> _switchUser(UserProfile user) async {
    if (_coordinator?.isRunning == true) {
      await _coordinator?.forceStop();
    }
    setState(() => _activeUser = user);
    _setupCoordinator(user.id);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading || _coordinator == null) {
      return const Scaffold(
        backgroundColor: Color(0xFF0F172A),
        body: Center(child: CircularProgressIndicator(color: Colors.indigoAccent)),
      );
    }

    final stats = _coordinator!.stats;
    final isRunning = _coordinator!.isRunning;
    final isPaused = _coordinator!.isPaused;
    final isForceStopped = _coordinator!.isForceStopped;
    final currentLink = _coordinator!.currentLink;
    final queue = _coordinator!.activeQueue;

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B),
        elevation: 0,
        titleSpacing: 12,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Colors.amber, Colors.orangeAccent]),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.stars, color: Colors.white, size: 18),
            ),
            const SizedBox(width: 8),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'RewardPilot',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                Text(
                  'Autonomous Collector',
                  style: TextStyle(fontSize: 10, color: Colors.white60),
                ),
              ],
            ),
          ],
        ),
        actions: [
          // Refresh Queue Button
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.tealAccent, size: 20),
            visualDensity: VisualDensity.compact,
            tooltip: 'Refresh Spin Links',
            onPressed: () {
              _coordinator?.loadInitialQueue();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Refreshed official Coin Master & Levvvel reward links!'),
                  duration: Duration(seconds: 2),
                  backgroundColor: Color(0xFF1E293B),
                ),
              );
            },
          ),
          // Profile isolation selector
          if (_users.isNotEmpty)
            PopupMenuButton<UserProfile>(
              tooltip: 'Switch User Account',
              padding: EdgeInsets.zero,
              icon: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.indigo.withAlpha(60),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.person, color: Colors.indigoAccent, size: 15),
                    const SizedBox(width: 3),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 80),
                      child: Text(
                        _activeUser?.name ?? 'User',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
              onSelected: _switchUser,
              itemBuilder: (ctx) => _users
                  .map((u) => PopupMenuItem(
                        value: u,
                        child: Text('${u.name} (${u.gamePlayerId})'),
                      ))
                  .toList(),
            ),
          // Settings button
          IconButton(
            icon: const Icon(Icons.tune, color: Colors.white70, size: 20),
            visualDensity: VisualDensity.compact,
            tooltip: 'Safety Settings',
            onPressed: () => SettingsSheet.show(
              context,
              config: _config,
              onSave: (newConfig) {
                setState(() => _config = newConfig);
                if (_activeUser != null) {
                  widget.storageService.saveConfig(_activeUser!.id, newConfig);
                  _setupCoordinator(_activeUser!.id);
                }
              },
              onResetHistory: () async {
                await _coordinator?.resetAllClaimedForTesting();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('✨ All rewards reset to Unclaimed! You can now test "Collect All Spins" again.'),
                      backgroundColor: Color(0xFF047857),
                    ),
                  );
                }
              },
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Permission & Mode Banner
            _buildStatusHeader(),

            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: [
                  // 0. SKEUOMORPHIC EXECUTING NOTIFICATION BANNER (Real-time Ticker)
                  if (isRunning || isPaused)
                    _buildSkeuomorphicExecutingBanner(stats, currentLink, isRunning, isPaused),

                  // 1. HERO CONTROLS: "Collect All Unclaimed" & "FORCE STOP"
                  _buildPrimaryControls(isRunning, isPaused, isForceStopped),

                  const SizedBox(height: 16),

                  // 2. INTERACTIVE CAROUSEL OF SPIN REWARDS (Levvvel-style)
                  // Fulfills: "why only one and 2 links arent many link should show cant you do it like levvel or coin master spin website show spins link open a coin master official website many carousal of spin to click"
                  // and "i want it to click one screen as well to collect or press ok if link not work"
                  _buildSpinsCarousel(queue, isRunning),

                  const SizedBox(height: 16),

                  // 3. LIVE STATE MACHINE & CURRENT TARGET CARD
                  _buildLiveStatusCard(stats, currentLink),

                  const SizedBox(height: 16),

                  // 4. STATS METRICS GRID
                  _buildMetricsGrid(stats),

                  const SizedBox(height: 16),

                  // 5. CATEGORIZED REWARD LINKS DIRECTORY (Levvvel-style Tabs: Today, Yesterday, 2d ago, Older)
                  _buildCategorizedRewardsList(queue, isRunning),

                  const SizedBox(height: 16),

                  // 6. LIVE AUDIT EVENT LOG
                  _buildLiveEventLog(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF1E2536), Color(0xFF131824)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        border: Border(bottom: BorderSide(color: Color(0xFF334155), width: 1.5)),
        boxShadow: [BoxShadow(color: Colors.black45, offset: Offset(0, 3), blurRadius: 6)],
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Glowing Convex Green LED (100% Official Drops Indicator)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF0A0F1D),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF10B981).withAlpha(120), width: 1.2),
                boxShadow: const [BoxShadow(color: Colors.black54, offset: Offset(0, 2), blurRadius: 4)],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [Color(0xFF6EE7B7), Color(0xFF059669)],
                        center: Alignment(-0.3, -0.3),
                      ),
                      boxShadow: [
                        BoxShadow(color: Color(0xFF10B981), blurRadius: 8, spreadRadius: 1.5),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'OFFICIAL MOON ACTIVE DROPS ONLY',
                    style: TextStyle(
                      color: Color(0xFF6EE7B7),
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.6,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),

            // Amber LED: 4s Popup Safe
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF0A0F1D),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.amber.withAlpha(100), width: 1.2),
                boxShadow: const [BoxShadow(color: Colors.black54, offset: Offset(0, 2), blurRadius: 4)],
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.shield_rounded, color: Colors.amberAccent, size: 12),
                  SizedBox(width: 6),
                  Text(
                    '4s POPUP-SAFE DELAY',
                    style: TextStyle(color: Colors.amberAccent, fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),

            // Tactile Accessibility & Persistence Status Pill (Tap to open guide & battery settings)
            GestureDetector(
              onTap: () {
                AccessibilityGuideSheet.show(
                  context,
                  automationService: _automationService,
                  onPermissionChecked: _checkPermission,
                );
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF0A0F1D),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: _isAccessibilityEnabled ? Colors.cyanAccent.withAlpha(120) : Colors.redAccent.withAlpha(160),
                    width: 1.2,
                  ),
                  boxShadow: const [BoxShadow(color: Colors.black54, offset: Offset(0, 2), blurRadius: 4)],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _isAccessibilityEnabled ? Icons.verified_user : Icons.warning_amber_rounded,
                      color: _isAccessibilityEnabled ? Colors.cyanAccent : Colors.redAccent,
                      size: 12,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _isAccessibilityEnabled ? 'PERSISTENT' : 'ENABLE SERVICE',
                      style: TextStyle(
                        color: _isAccessibilityEnabled ? Colors.cyanAccent : Colors.redAccent,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Skeuomorphic Arcade/Console Executing Notification Banner
  Widget _buildSkeuomorphicExecutingBanner(CollectionStats stats, RewardLink? currentLink, bool isRunning, bool isPaused) {
    final stepNum = stats.currentRewardIndex;
    final totalSteps = stats.totalEligible > 0 ? stats.totalEligible : (_coordinator?.activeQueue.length ?? 0);
    final progress = totalSteps > 0 ? (stepNum / totalSteps).clamp(0.0, 1.0) : 0.0;
    final title = currentLink?.rewardTitle ?? 'Connecting to Game...';
    final source = currentLink?.source ?? 'Official Moon Active';

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF222B3D), Color(0xFF101624), Color(0xFF1A2233)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF475569), width: 2),
        boxShadow: const [
          BoxShadow(color: Colors.black87, offset: Offset(0, 6), blurRadius: 14),
          BoxShadow(color: Color(0x3310B981), offset: Offset(0, 0), blurRadius: 18),
        ],
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top Ticker Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  // Convex Glowing Green LED Bulb
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: isPaused
                            ? [Colors.amberAccent, Colors.orange]
                            : [const Color(0xFF34D399), const Color(0xFF059669)],
                        center: const Alignment(-0.3, -0.3),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: isPaused ? Colors.amber.withOpacity(0.8) : const Color(0xFF10B981).withOpacity(0.8),
                          blurRadius: 8,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    isPaused ? 'QUEUE PAUSED' : '⚡ EXECUTING REWARD [$stepNum / $totalSteps]',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      color: isPaused ? Colors.amberAccent : const Color(0xFF34D399),
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.8,
                    ),
                  ),
                ],
              ),
              // Tactile 4s delay pill
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white24),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.timer, color: Colors.amberAccent, size: 12),
                    SizedBox(width: 4),
                    Text('4s delay', style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          // Digital LCD Panel
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF060911),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF1E293B)),
              boxShadow: const [
                BoxShadow(color: Colors.black, blurRadius: 4),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFFF8FAFC),
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Text(
                      source,
                      style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(width: 6),
                    const Text('•', style: TextStyle(color: Colors.white30, fontSize: 11)),
                    const SizedBox(width: 6),
                    const Text(
                      'Dismiss popups safely',
                      style: TextStyle(color: Colors.white54, fontSize: 11),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 10),

          // Tactile Segmented Progress Bar
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: const Color(0xFF060911),
              valueColor: AlwaysStoppedAnimation<Color>(
                isPaused ? Colors.amberAccent : const Color(0xFF10B981),
              ),
            ),
          ),

          const SizedBox(height: 12),

          // Prominent 3D Tactile Action Buttons on the Notification Banner
          Row(
            children: [
              // Emergency STOP Button
              Expanded(
                flex: 3,
                child: GestureDetector(
                  onTap: () => _coordinator?.forceStop(),
                  child: Container(
                    height: 44,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFEF4444), Color(0xFFDC2626), Color(0xFF991B1B)],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFFCA5A5), width: 1.2),
                      boxShadow: const [
                        BoxShadow(color: Color(0xFF7F1D1D), offset: Offset(0, 4), blurRadius: 0),
                        BoxShadow(color: Colors.black45, offset: Offset(0, 6), blurRadius: 6),
                      ],
                    ),
                    child: const Center(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.stop, color: Colors.white, size: 20),
                          SizedBox(width: 6),
                          Text(
                            'STOP IMMEDIATELY',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.5,
                              shadows: [Shadow(color: Colors.black87, offset: Offset(0, 1), blurRadius: 2)],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              const SizedBox(width: 10),

              // Pause / Resume Toggle
              Expanded(
                flex: 2,
                child: GestureDetector(
                  onTap: () {
                    if (isPaused) {
                      _coordinator?.resume();
                    } else {
                      _coordinator?.pause();
                    }
                  },
                  child: Container(
                    height: 44,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF334155), Color(0xFF1E293B)],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white24, width: 1),
                      boxShadow: const [
                        BoxShadow(color: Color(0xFF0F172A), offset: Offset(0, 3), blurRadius: 0),
                      ],
                    ),
                    child: Center(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(isPaused ? Icons.play_arrow : Icons.pause, color: Colors.amberAccent, size: 18),
                          const SizedBox(width: 4),
                          Text(
                            isPaused ? 'RESUME' : 'PAUSE',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPrimaryControls(bool isRunning, bool isPaused, bool isForceStopped) {
    return Column(
      children: [
        Row(
          children: [
            // 1. Skeuomorphic 3D Golden Action Button: "COLLECT ALL SPINS"
            Expanded(
              flex: 3,
              child: GestureDetector(
                onTap: isRunning ? null : () => _coordinator?.startAutonomousCollection(),
                child: Container(
                  height: 58,
                  decoration: BoxDecoration(
                    gradient: isRunning
                        ? const LinearGradient(colors: [Color(0xFF334155), Color(0xFF1E293B)])
                        : const LinearGradient(
                            colors: [Color(0xFFFFDF00), Color(0xFFF59E0B), Color(0xFFB45309)],
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                          ),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: isRunning ? Colors.white24 : const Color(0xFFFFFBEB), width: 1.5),
                    boxShadow: [
                      BoxShadow(
                        color: isRunning ? const Color(0xFF0F172A) : const Color(0xFF78350F),
                        offset: const Offset(0, 5),
                        blurRadius: 0,
                      ),
                      BoxShadow(
                        color: isRunning ? Colors.transparent : Colors.amber.withOpacity(0.35),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isRunning ? Icons.hourglass_top : Icons.bolt,
                          color: isRunning ? Colors.white60 : const Color(0xFF3E1F00),
                          size: 26,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          isRunning ? 'COLLECTING...' : '⚡ COLLECT ALL SPINS',
                          style: TextStyle(
                            color: isRunning ? Colors.white : const Color(0xFF3E1F00),
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.5,
                            shadows: isRunning ? [] : [const Shadow(color: Colors.white54, offset: Offset(0, 1), blurRadius: 1)],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),

            // 2. Skeuomorphic 3D Ruby Red Emergency Force Stop Button
            Expanded(
              flex: 2,
              child: GestureDetector(
                onTap: (isRunning || isPaused) ? () => _coordinator?.forceStop() : null,
                child: Container(
                  height: 58,
                  decoration: BoxDecoration(
                    gradient: (isRunning || isPaused)
                        ? const LinearGradient(
                            colors: [Color(0xFFEF4444), Color(0xFFDC2626), Color(0xFF991B1B)],
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                          )
                        : const LinearGradient(colors: [Color(0xFF291515), Color(0xFF1A0E0E)]),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: (isRunning || isPaused) ? const Color(0xFFFCA5A5) : Colors.white12, width: 1.5),
                    boxShadow: [
                      BoxShadow(
                        color: (isRunning || isPaused) ? const Color(0xFF7F1D1D) : Colors.black45,
                        offset: const Offset(0, 5),
                        blurRadius: 0,
                      ),
                    ],
                  ),
                  child: Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.stop_circle, color: (isRunning || isPaused) ? Colors.white : Colors.white24, size: 22),
                        const SizedBox(width: 6),
                        Text(
                          'FORCE STOP',
                          style: TextStyle(
                            color: (isRunning || isPaused) ? Colors.white : Colors.white24,
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),

        // Secondary Controls (Pause, Resume, Stop after current)
        if (isRunning || isPaused) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.amberAccent,
                    side: const BorderSide(color: Colors.amberAccent),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () {
                    if (isPaused) {
                      _coordinator?.resume();
                    } else {
                      _coordinator?.pause();
                    }
                  },
                  icon: Icon(isPaused ? Icons.play_arrow : Icons.pause, size: 18),
                  label: Text(isPaused ? 'Resume' : 'Pause'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white70,
                    side: const BorderSide(color: Colors.white24),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () => _coordinator?.stopAfterCurrentReward(),
                  icon: const Icon(Icons.hourglass_bottom, size: 18),
                  label: const Text('Stop After Current'),
                ),
              ),
            ],
          ),
        ] else ...[
          const SizedBox(height: 10),
          // Test Mode: Option to manually reset all claimed to re-test Claim All flow
          GestureDetector(
            onTap: () async {
              await _coordinator?.resetAllClaimedForTesting();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('✨ All rewards reset to Unclaimed! You can now test "Collect All Spins" again.'),
                    backgroundColor: Color(0xFF047857),
                    duration: Duration(seconds: 2),
                  ),
                );
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.amberAccent.withAlpha(90), width: 1),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.restart_alt, color: Colors.amberAccent, size: 16),
                  SizedBox(width: 8),
                  Text(
                    'RESET ALL CLAIMED (TEST CLAIM ALL AGAIN)',
                    style: TextStyle(
                      color: Colors.amberAccent,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  /// Interactive Carousel of Free Spin Reward Cards (Levvvel-style)
  Widget _buildSpinsCarousel(List<RewardLink> queue, bool isRunning) {
    if (queue.isEmpty) {
      return Container(
        height: 160,
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(18),
        ),
        child: const Center(
          child: Text('Loading Coin Master spin rewards...', style: TextStyle(color: Colors.white60)),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                const Icon(Icons.view_carousel, color: Colors.amberAccent, size: 18),
                const SizedBox(width: 8),
                const Text(
                  'DAILY SPINS & REWARDS CAROUSEL',
                  style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                ),
              ],
            ),
            Text(
              '${queue.length} Total Rewards',
              style: const TextStyle(color: Colors.tealAccent, fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ],
        ),
        const SizedBox(height: 10),

        SizedBox(
          height: 190,
          child: PageView.builder(
            controller: _carouselController,
            itemCount: queue.length,
            onPageChanged: (idx) => setState(() => _currentCarouselPage = idx),
            itemBuilder: (ctx, idx) {
              final link = queue[idx];
              return _buildCarouselCard(link, isRunning);
            },
          ),
        ),

        const SizedBox(height: 8),

        // Carousel Dot Indicators
        Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(
              queue.length > 10 ? 10 : queue.length,
              (idx) => Container(
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: _currentCarouselPage % 10 == idx ? 16 : 6,
                height: 6,
                decoration: BoxDecoration(
                  color: _currentCarouselPage % 10 == idx ? Colors.amberAccent : Colors.white24,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCarouselCard(RewardLink link, bool isRunning) {
    Color gradientStart;
    Color gradientEnd;
    IconData rewardIcon;

    if (link.rewardType == 'coins') {
      gradientStart = const Color(0xFF047857);
      gradientEnd = const Color(0xFF065F46);
      rewardIcon = Icons.monetization_on;
    } else if (link.rewardType == 'mixed') {
      gradientStart = const Color(0xFF6D28D9);
      gradientEnd = const Color(0xFF4C1D95);
      rewardIcon = Icons.card_giftcard;
    } else {
      gradientStart = const Color(0xFFD97706);
      gradientEnd = const Color(0xFFB45309);
      rewardIcon = Icons.casino;
    }

    final isClaimed = link.status == RewardClaimStatus.claimed;
    final isExpired = link.status == RewardClaimStatus.expired;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [gradientStart, gradientEnd],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: gradientStart.withAlpha(60),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  // Date category badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.black.withAlpha(60),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      link.dateCategory.toUpperCase(),
                      style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(width: 6),
                  // Expiration badge (Identifies active ~48h lifetime)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: link.isPastExpiration ? Colors.red.withAlpha(60) : Colors.black.withAlpha(60),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: link.isPastExpiration ? Colors.redAccent.withAlpha(120) : Colors.amberAccent.withAlpha(90),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.hourglass_bottom,
                          size: 10,
                          color: link.isPastExpiration ? Colors.redAccent : Colors.amberAccent,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          link.expirationTimeRemaining,
                          style: TextStyle(
                            color: link.isPastExpiration ? Colors.redAccent : Colors.amberAccent,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              // Source chip
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(30),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  link.source,
                  style: const TextStyle(color: Colors.white, fontSize: 10),
                ),
              ),
            ],
          ),

          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(40),
                  shape: BoxShape.circle,
                ),
                child: Icon(rewardIcon, color: Colors.white, size: 28),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      link.rewardTitle,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        shadows: [Shadow(color: Colors.black45, blurRadius: 4)],
                      ),
                    ),
                    Text(
                      link.rewardBadgeText,
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),

          // Action Row with Unmark (for testing) and Collect buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isClaimed
                      ? Colors.teal.withAlpha(80)
                      : (isExpired ? Colors.orange.withAlpha(80) : Colors.black.withAlpha(40)),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  link.status.displayName,
                  style: TextStyle(
                    color: isClaimed ? Colors.tealAccent : (isExpired ? Colors.orangeAccent : Colors.white70),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (isClaimed || isExpired)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Manual Unmark Button for Testing
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white54),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        minimumSize: const Size(0, 32),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: () {
                        _coordinator?.unmarkReward(link);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Unmarked "${link.rewardTitle}" (set to Unclaimed for testing)!'),
                            duration: const Duration(seconds: 1),
                          ),
                        );
                      },
                      icon: const Icon(Icons.undo, size: 12, color: Colors.white70),
                      label: const Text('Unmark', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(width: 6),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        minimumSize: const Size(0, 32),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: isRunning ? null : () => _coordinator?.collectSingleReward(link),
                      child: const Text('Retry', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black)),
                    ),
                  ],
                )
              else
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black,
                    elevation: 2,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: isRunning ? null : () => _coordinator?.collectSingleReward(link),
                  icon: const Icon(Icons.touch_app, size: 16, color: Colors.black),
                  label: const Text(
                    'Collect Now',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCategorizedRewardsList(List<RewardLink> queue, bool isRunning) {
    final categories = ['All', 'Today', 'Yesterday', '2 Days Ago', 'Older'];
    final filtered = _selectedCategoryTab == 'All'
        ? queue
        : queue.where((l) => l.dateCategory == _selectedCategoryTab).toList();

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withAlpha(20)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.format_list_bulleted, color: Colors.tealAccent, size: 18),
                  SizedBox(width: 8),
                  Text(
                    'REWARDS DIRECTORY',
                    style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              Text(
                '${filtered.length} Links',
                style: const TextStyle(color: Colors.white38, fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Category Tabs
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: categories.map((cat) {
                final isSel = _selectedCategoryTab == cat;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(cat),
                    selected: isSel,
                    selectedColor: Colors.tealAccent,
                    backgroundColor: const Color(0xFF0F172A),
                    labelStyle: TextStyle(
                      color: isSel ? Colors.black : Colors.white70,
                      fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                      fontSize: 12,
                    ),
                    onSelected: (val) {
                      if (val) setState(() => _selectedCategoryTab = cat);
                    },
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 12),

          // Scrollable Reward Items
          SizedBox(
            height: 220,
            child: filtered.isEmpty
                ? const Center(
                    child: Text('No rewards found in this category.', style: TextStyle(color: Colors.white38)),
                  )
                : ListView.builder(
                    itemCount: filtered.length,
                    itemBuilder: (ctx, idx) {
                      final item = filtered[idx];
                      final isClaimed = item.status == RewardClaimStatus.claimed;
                      final isExpired = item.status == RewardClaimStatus.expired;

                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white.withAlpha(10)),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: item.rewardType == 'coins'
                                    ? Colors.greenAccent.withAlpha(20)
                                    : Colors.amberAccent.withAlpha(20),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                item.rewardType == 'coins' ? Icons.monetization_on : Icons.casino,
                                color: item.rewardType == 'coins' ? Colors.greenAccent : Colors.amberAccent,
                                size: 18,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.rewardTitle,
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                                  ),
                                  Text(
                                    '${item.source} • ${item.dateCategory} • ⏳ ${item.expirationTimeRemaining}',
                                    style: TextStyle(
                                      color: item.isPastExpiration ? Colors.redAccent.withAlpha(180) : Colors.white54,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (isClaimed || isExpired) ...[
                              Icon(
                                isClaimed ? Icons.check_circle : Icons.cancel,
                                color: isClaimed ? Colors.tealAccent : Colors.orangeAccent,
                                size: 18,
                              ),
                              const SizedBox(width: 4),
                              IconButton(
                                icon: const Icon(Icons.undo, color: Colors.amberAccent, size: 16),
                                visualDensity: VisualDensity.compact,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                tooltip: 'Unmark for testing',
                                onPressed: () {
                                  _coordinator?.unmarkReward(item);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('Unmarked "${item.rewardTitle}" (ready to re-test)!'),
                                      duration: const Duration(seconds: 1),
                                    ),
                                  );
                                },
                              ),
                            ] else
                              OutlinedButton(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.tealAccent,
                                  side: const BorderSide(color: Colors.tealAccent),
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  minimumSize: const Size(60, 32),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                                onPressed: isRunning ? null : () => _coordinator?.collectSingleReward(item),
                                child: const Text('Collect', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildLiveStatusCard(CollectionStats stats, RewardLink? currentLink) {
    final state = stats.currentScreenState ?? ScreenRecognitionState.appLaunching;

    Color badgeColor;
    switch (state) {
      case ScreenRecognitionState.claimButtonAvailable:
      case ScreenRecognitionState.rewardAvailable:
      case ScreenRecognitionState.claimSuccessConfirmed:
        badgeColor = Colors.tealAccent;
        break;
      case ScreenRecognitionState.rewardExpired:
      case ScreenRecognitionState.rewardAlreadyClaimed:
        badgeColor = Colors.orangeAccent;
        break;
      case ScreenRecognitionState.loginRequired:
      case ScreenRecognitionState.captchaOrSecurityChallenge:
        badgeColor = Colors.amberAccent;
        break;
      case ScreenRecognitionState.appCrashed:
      case ScreenRecognitionState.timeout:
        badgeColor = Colors.redAccent;
        break;
      default:
        badgeColor = Colors.indigoAccent;
    }

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withAlpha(20)),
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'REWARD QUEUE [${stats.currentRewardIndex} / ${stats.totalEligible}]',
                style: const TextStyle(color: Colors.white60, fontSize: 12, fontWeight: FontWeight.bold),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: badgeColor.withAlpha(30),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: badgeColor.withAlpha(80)),
                ),
                child: Text(
                  state.displayName,
                  style: TextStyle(color: badgeColor, fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: stats.totalEligible > 0 ? stats.processedCount / stats.totalEligible : 0.0,
              backgroundColor: Colors.white12,
              valueColor: AlwaysStoppedAnimation<Color>(badgeColor),
              minHeight: 6,
            ),
          ),
          const SizedBox(height: 14),

          // Current Action Banner (explicitly showing action taken, like clicking OK or Collect)
          Row(
            children: [
              const Icon(Icons.flash_on, color: Colors.amberAccent, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  stats.currentAction,
                  style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),

          if (currentLink != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        currentLink.rewardTitle,
                        style: const TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      Text(
                        currentLink.source,
                        style: const TextStyle(color: Colors.white60, fontSize: 12),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Target: ${currentLink.maskedUrl}',
                    style: const TextStyle(color: Colors.white38, fontSize: 12, fontFamily: 'monospace'),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMetricsGrid(CollectionStats stats) {
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      childAspectRatio: 1.3,
      children: [
        _buildStatCard('Claimed', '${stats.claimedCount}', Colors.tealAccent, Icons.check_circle_outline),
        _buildStatCard('Expired/Dismissed', '${stats.expiredCount}', Colors.orangeAccent, Icons.history_toggle_off),
        _buildStatCard('Already Claimed', '${stats.alreadyClaimedCount}', Colors.blueAccent, Icons.done_all),
        _buildStatCard('Awaiting User', '${stats.awaitingUserActionCount}', Colors.amberAccent, Icons.person_pin),
        _buildStatCard('Uncertain/Failed', '${stats.failedOrUncertainCount}', Colors.redAccent, Icons.error_outline),
        _buildStatCard(
          'Consecutive Exp.',
          '${stats.consecutiveExpiredCount} / ${_config.consecutiveExpiredThreshold}',
          stats.consecutiveExpiredCount > 1 ? Colors.redAccent : Colors.white70,
          Icons.shield,
        ),
      ],
    );
  }

  Widget _buildStatCard(String label, String value, Color color, IconData icon) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withAlpha(15)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 16),
              const SizedBox(width: 4),
              Text(
                value,
                style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white60, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _buildLiveEventLog() {
    final events = _coordinator!.liveEvents;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withAlpha(20)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.terminal, color: Colors.indigoAccent, size: 18),
                  SizedBox(width: 8),
                  Text(
                    'LIVE COLLECTION LOG',
                    style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              Text(
                '${events.length} events',
                style: const TextStyle(color: Colors.white38, fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            height: 180,
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(12),
            ),
            child: events.isEmpty
                ? const Center(
                    child: Text('No events recorded yet. Press Collect to start.',
                        style: TextStyle(color: Colors.white38, fontSize: 12)),
                  )
                : ListView.builder(
                    itemCount: events.length,
                    padding: const EdgeInsets.all(8),
                    itemBuilder: (ctx, idx) {
                      final evt = events[idx];
                      Color tagColor;
                      switch (evt.level) {
                        case EventLevel.success:
                          tagColor = Colors.tealAccent;
                          break;
                        case EventLevel.warning:
                          tagColor = Colors.orangeAccent;
                          break;
                        case EventLevel.error:
                          tagColor = Colors.redAccent;
                          break;
                        case EventLevel.forceStop:
                          tagColor = Colors.red;
                          break;
                        case EventLevel.info:
                          tagColor = Colors.blueAccent;
                          break;
                      }

                      final timeStr =
                          '${evt.timestamp.hour.toString().padLeft(2, '0')}:${evt.timestamp.minute.toString().padLeft(2, '0')}:${evt.timestamp.second.toString().padLeft(2, '0')}';

                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              timeStr,
                              style: const TextStyle(color: Colors.white30, fontSize: 11, fontFamily: 'monospace'),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: tagColor.withAlpha(30),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                evt.level.name.toUpperCase(),
                                style: TextStyle(color: tagColor, fontSize: 9, fontWeight: FontWeight.bold),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                evt.message,
                                style: const TextStyle(color: Colors.white70, fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
