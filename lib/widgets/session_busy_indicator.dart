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

/// Compact status indicator for app bars with cool animation when busy
class AppBarStatusIndicator extends StatefulWidget {
  final bool isBusy;

  const AppBarStatusIndicator({super.key, required this.isBusy});

  @override
  State<AppBarStatusIndicator> createState() => _AppBarStatusIndicatorState();
}

class _AppBarStatusIndicatorState extends State<AppBarStatusIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    if (widget.isBusy) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(AppBarStatusIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isBusy && !oldWidget.isBusy) {
      _controller.repeat();
    } else if (!widget.isBusy && oldWidget.isBusy) {
      _controller.stop();
      _controller.reset();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double _pulse(double t, double delay) {
    final phase = (t + delay) % 1.0;
    final value = (phase < 0.5 ? phase : 1 - phase) * 2;
    return 0.6 + (value * 0.4);
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.isBusy ? AppTheme.warning : AppTheme.success;

    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(border: Border.all(color: color)),
      child: widget.isBusy
          ? AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                final t = _controller.value;
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _StatusDot(scale: _pulse(t, 0.0), color: color),
                    const SizedBox(width: 3),
                    _StatusDot(scale: _pulse(t, 0.2), color: color),
                    const SizedBox(width: 3),
                    _StatusDot(scale: _pulse(t, 0.4), color: color),
                  ],
                );
              },
            )
          : Text(
              'IDLE',
              style: TextStyle(
                color: color,
                fontSize: 9,
                fontWeight: FontWeight.bold,
              ),
            ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  final double scale;
  final Color color;

  const _StatusDot({required this.scale, required this.color});

  @override
  Widget build(BuildContext context) {
    return Transform.scale(
      scale: scale,
      child: Container(
        width: 5,
        height: 5,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(1),
        ),
      ),
    );
  }
}

/// Compact busy indicator for session list items with pulsing animation
class SessionItemBusyIndicator extends StatefulWidget {
  const SessionItemBusyIndicator({super.key});

  @override
  State<SessionItemBusyIndicator> createState() =>
      _SessionItemBusyIndicatorState();
}

class _SessionItemBusyIndicatorState extends State<SessionItemBusyIndicator>
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

  double _pulse(double t, double delay) {
    final phase = (t + delay) % 1.0;
    final value = (phase < 0.5 ? phase : 1 - phase) * 2;
    return 0.6 + (value * 0.4);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(border: Border.all(color: AppTheme.warning)),
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final t = _controller.value;
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _StatusDot(scale: _pulse(t, 0.0), color: AppTheme.warning),
              const SizedBox(width: 2),
              _StatusDot(scale: _pulse(t, 0.2), color: AppTheme.warning),
              const SizedBox(width: 2),
              _StatusDot(scale: _pulse(t, 0.4), color: AppTheme.warning),
            ],
          );
        },
      ),
    );
  }
}
