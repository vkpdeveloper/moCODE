import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class SessionBusyIndicator extends StatefulWidget {
  final String label;

  const SessionBusyIndicator({super.key, this.label = 'Session busy'});

  @override
  State<SessionBusyIndicator> createState() => _SessionBusyIndicatorState();
}

class _SessionBusyIndicatorState extends State<SessionBusyIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          _BoxyPulse(controller: _controller),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              widget.label,
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 11,
                letterSpacing: 0.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BoxyPulse extends StatelessWidget {
  final AnimationController controller;

  const _BoxyPulse({required this.controller});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 32,
      height: 20,
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, child) {
          final t = controller.value;
          final left = _pulse(t, 0.0);
          final mid = _pulse(t, 0.2);
          final right = _pulse(t, 0.4);
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _BoxyDot(scale: left),
              _BoxyDot(scale: mid),
              _BoxyDot(scale: right),
            ],
          );
        },
      ),
    );
  }

  double _pulse(double t, double delay) {
    final phase = (t + delay) % 1.0;
    final value = (phase < 0.5 ? phase : 1 - phase) * 2;
    return 0.6 + (value * 0.4);
  }
}

class _BoxyDot extends StatelessWidget {
  final double scale;

  const _BoxyDot({required this.scale});

  @override
  Widget build(BuildContext context) {
    return Transform.scale(
      scale: scale,
      child: Container(
        width: 6,
        height: 6,
        decoration: BoxDecoration(
          color: AppTheme.accent,
          border: Border.all(color: AppTheme.border),
        ),
      ),
    );
  }
}
