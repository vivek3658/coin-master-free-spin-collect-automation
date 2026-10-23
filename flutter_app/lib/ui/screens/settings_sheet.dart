import 'package:flutter/material.dart';
import '../../models/collector_config.dart';

class SettingsSheet extends StatefulWidget {
  final CollectorConfig config;
  final ValueChanged<CollectorConfig> onSave;
  final VoidCallback? onResetHistory;

  const SettingsSheet({
    super.key,
    required this.config,
    required this.onSave,
    this.onResetHistory,
  });

  static Future<void> show(
    BuildContext context, {
    required CollectorConfig config,
    required ValueChanged<CollectorConfig> onSave,
    VoidCallback? onResetHistory,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => SettingsSheet(config: config, onSave: onSave, onResetHistory: onResetHistory),
    );
  }

  @override
  State<SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<SettingsSheet> {
  late int _consecutiveExpiredThreshold;
  late int _consecutiveAlreadyClaimedThreshold;
  late int _maxLinksPerRun;
  late int _maxExecutionDurationMinutes;
  late int _clickDelayMs;
  late bool _enableMockMode;

  @override
  void initState() {
    super.initState();
    _consecutiveExpiredThreshold = widget.config.consecutiveExpiredThreshold;
    _consecutiveAlreadyClaimedThreshold = widget.config.consecutiveAlreadyClaimedThreshold;
    _maxLinksPerRun = widget.config.maxLinksPerRun;
    _maxExecutionDurationMinutes = widget.config.maxExecutionDurationMinutes;
    _clickDelayMs = widget.config.clickDelayMs;
    _enableMockMode = widget.config.enableMockMode;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF1E2230),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      child: SingleChildScrollView(
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
            const SizedBox(height: 16),
            const Text(
              'Safety & Automation Settings',
              style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            const Text(
              'Configure stop conditions, limits, and server connection',
              style: TextStyle(color: Colors.white60, fontSize: 13),
            ),
            const SizedBox(height: 18),

            // Server Host Field
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.bolt, color: Colors.cyanAccent, size: 18),
                      SizedBox(width: 8),
                      Text(
                        'Fastify Server URL',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    initialValue: 'http://localhost:3000',
                    style: const TextStyle(color: Colors.cyanAccent, fontFamily: 'monospace', fontSize: 13),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: Colors.black26,
                      hintText: 'http://localhost:3000',
                      hintStyle: const TextStyle(color: Colors.white30),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Default: http://localhost:3000 (Supports ADB reverse USB, Termux, and Wi-Fi)',
                    style: TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Consecutive Expired Threshold
            _buildSliderTile(
              title: 'Stop after consecutive expired links',
              subtitle: 'Halts the run if links are consecutively confirmed expired',
              value: _consecutiveExpiredThreshold.toDouble(),
              min: 2,
              max: 5,
              divisions: 3,
              displayValue: '$_consecutiveExpiredThreshold links',
              onChanged: (val) => setState(() => _consecutiveExpiredThreshold = val.toInt()),
            ),
            const Divider(color: Colors.white10),

            // Consecutive Already Claimed Threshold
            _buildSliderTile(
              title: 'Stop after consecutive already-claimed',
              subtitle: 'Halts the run if links have already been redeemed',
              value: _consecutiveAlreadyClaimedThreshold.toDouble(),
              min: 2,
              max: 5,
              divisions: 3,
              displayValue: '$_consecutiveAlreadyClaimedThreshold links',
              onChanged: (val) => setState(() => _consecutiveAlreadyClaimedThreshold = val.toInt()),
            ),
            const Divider(color: Colors.white10),

            // Max links per run
            _buildSliderTile(
              title: 'Maximum links per run',
              subtitle: 'Limits queue size to avoid long background execution',
              value: _maxLinksPerRun.toDouble(),
              min: 5,
              max: 50,
              divisions: 9,
              displayValue: '$_maxLinksPerRun links',
              onChanged: (val) => setState(() => _maxLinksPerRun = val.toInt()),
            ),
            const Divider(color: Colors.white10),

            // Click Delay
            _buildSliderTile(
              title: 'Click Delay',
              subtitle: 'Delay between screen recognition and button activation',
              value: _clickDelayMs.toDouble(),
              min: 500,
              max: 3000,
              divisions: 5,
              displayValue: '${(_clickDelayMs / 1000).toStringAsFixed(1)}s',
              onChanged: (val) => setState(() => _clickDelayMs = val.toInt()),
            ),
            const Divider(color: Colors.white10),

            // Mock Mode Toggle
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Test Simulation Mode', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
              subtitle: const Text('Simulates screen flows without launching real Coin Master app', style: TextStyle(color: Colors.white60, fontSize: 12)),
              value: _enableMockMode,
              onChanged: (val) => setState(() => _enableMockMode = val),
            ),
            const Divider(color: Colors.white10),
            const SizedBox(height: 12),

            // Testing / Reset Option
            if (widget.onResetHistory != null) ...[
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.amberAccent,
                  side: const BorderSide(color: Colors.amberAccent),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  minimumSize: const Size(double.infinity, 44),
                ),
                onPressed: () {
                  widget.onResetHistory?.call();
                  Navigator.pop(context);
                },
                icon: const Icon(Icons.restart_alt, size: 18),
                label: const Text(
                  'Reset All Claimed Records (Test Mode)',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ),
              const SizedBox(height: 16),
            ],

            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6366F1),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: () {
                  final updated = widget.config.copyWith(
                    consecutiveExpiredThreshold: _consecutiveExpiredThreshold,
                    consecutiveAlreadyClaimedThreshold: _consecutiveAlreadyClaimedThreshold,
                    maxLinksPerRun: _maxLinksPerRun,
                    maxExecutionDurationMinutes: _maxExecutionDurationMinutes,
                    clickDelayMs: _clickDelayMs,
                    enableMockMode: _enableMockMode,
                  );
                  widget.onSave(updated);
                  Navigator.pop(context);
                },
                child: const Text('Save Settings', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSliderTile({
    required String title,
    required String subtitle,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required String displayValue,
    required ValueChanged<double> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(child: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600))),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.indigo.withAlpha(50),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(displayValue, style: const TextStyle(color: Colors.indigoAccent, fontWeight: FontWeight.bold, fontSize: 12)),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(subtitle, style: const TextStyle(color: Colors.white60, fontSize: 12)),
        Slider(
          value: value,
          min: min,
          max: max,
          divisions: divisions,
          activeColor: Colors.indigoAccent,
          inactiveColor: Colors.white12,
          onChanged: onChanged,
        ),
      ],
    );
  }
}
