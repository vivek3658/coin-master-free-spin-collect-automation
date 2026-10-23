import 'package:flutter/material.dart';
import '../../services/native_automation_service.dart';

class AccessibilityGuideSheet extends StatelessWidget {
  final NativeAutomationService automationService;
  final VoidCallback onPermissionChecked;

  const AccessibilityGuideSheet({
    super.key,
    required this.automationService,
    required this.onPermissionChecked,
  });

  static Future<void> show(
    BuildContext context, {
    required NativeAutomationService automationService,
    required VoidCallback onPermissionChecked,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => AccessibilityGuideSheet(
        automationService: automationService,
        onPermissionChecked: onPermissionChecked,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF1E2230),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 48,
              height: 5,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.indigo.withAlpha(50),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(Icons.accessibility_new, color: Colors.indigoAccent, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Accessibility Permission',
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Required for Autonomous Collection',
                      style: TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _buildInfoRow(
            icon: Icons.search,
            color: Colors.tealAccent,
            title: 'What it inspects',
            description:
                'Detects in-game Coin Master reward popups, such as "Collect Spins", "Gift Expired", or "Already Collected".',
          ),
          const SizedBox(height: 14),
          _buildInfoRow(
            icon: Icons.touch_app,
            color: Colors.amberAccent,
            title: 'What it interacts with',
            description:
                'Clicks the visible "Collect" button on valid rewards, and presses "OK" to dismiss dialogs when links are expired or already claimed.',
          ),
          const SizedBox(height: 14),
          _buildInfoRow(
            icon: Icons.lock_outline,
            color: Colors.greenAccent,
            title: 'Your privacy is protected',
            description:
                '100% on-device processing. No credentials, keystrokes, personal messages, or unrelated screens are ever captured or sent off-device.',
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6366F1),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 4,
              ),
              onPressed: () async {
                await automationService.openAccessibilitySettings();
                if (context.mounted) {
                  Navigator.pop(context);
                }
                onPermissionChecked();
              },
              icon: const Icon(Icons.settings, size: 20),
              label: const Text(
                'Open Android Settings',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.white70),
              onPressed: () => Navigator.pop(context),
              child: const Text('Continue in Manual Mode'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow({
    required IconData icon,
    required Color color,
    required String title,
    required String description,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
              const SizedBox(height: 2),
              Text(description, style: const TextStyle(color: Colors.white60, fontSize: 13, height: 1.3)),
            ],
          ),
        ),
      ],
    );
  }
}
