import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/animation_settings.dart';

class FadeInUp extends StatefulWidget {
  final Widget child;
  final Duration duration;
  final Duration delay;
  final double offsetY;
  final Curve curve;

  const FadeInUp({super.key, required this.child, this.duration = const Duration(milliseconds: 420), this.delay = Duration.zero, this.offsetY = 0.28, this.curve = Curves.easeOutCubic});

  @override
  State<FadeInUp> createState() => _FadeInUpState();
}

class _FadeInUpState extends State<FadeInUp> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _opacity;
  late final Animation<Offset> _offset;
  Timer? _starter;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    // controller is created in build only when animations are enabled (to avoid accessing
    // providers from initState). We'll still set up fields here but defer starting until build.
    _ctrl = AnimationController(vsync: this, duration: widget.duration);
    _opacity = CurvedAnimation(parent: _ctrl, curve: Interval(0.0, 0.6, curve: widget.curve));
    _offset = Tween(begin: Offset(0, widget.offsetY), end: Offset.zero).animate(CurvedAnimation(parent: _ctrl, curve: widget.curve));
    // actual forward will be triggered in build when animations are enabled
  }

  @override
  void dispose() {
    _starter?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final animSettings = Provider.of<AnimationSettings>(context, listen: false);
    if (!animSettings.enabled) return widget.child;
    // ensure controller is started once when animations are enabled
    if (!_started) {
      _started = true;
      if (widget.delay > Duration.zero) {
        _starter = Timer(widget.delay, () {
          if (mounted) _ctrl.forward();
        });
      } else {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _ctrl.forward();
        });
      }
    }
    return FadeTransition(
      opacity: _opacity,
      child: SlideTransition(
        position: _offset,
        child: widget.child,
      ),
    );
  }
}

/// Simple press scale wrapper that gives a pronounced press feedback.
class PressableScale extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double pressedScale;
  final Duration duration;

  const PressableScale({super.key, required this.child, this.onTap, this.pressedScale = 0.92, this.duration = const Duration(milliseconds: 110)});

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale> {
  bool _pressed = false;

  void _onTapDown(_) {
    setState(() => _pressed = true);
  }

  void _onTapUp(_) {
    setState(() => _pressed = false);
  }

  void _onTapCancel() {
    setState(() => _pressed = false);
  }

  @override
  Widget build(BuildContext context) {
    final animSettings = Provider.of<AnimationSettings>(context, listen: false);
    final scale = _pressed ? widget.pressedScale : 1.0;
    if (!animSettings.enabled) {
      return GestureDetector(onTap: widget.onTap, child: widget.child);
    }
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTapDown: widget.onTap != null ? _onTapDown : null,
      onTapUp: widget.onTap != null ? (details) { _onTapUp(details); widget.onTap?.call(); } : null,
      onTapCancel: widget.onTap != null ? _onTapCancel : null,
      child: AnimatedScale(
        scale: scale,
        duration: widget.duration,
        curve: Curves.easeOutCubic,
        child: widget.child,
      ),
    );
  }
}

/// Wrap any child with an index-based staggered delay for entrance animations.
class StaggeredFadeIn extends StatelessWidget {
  final Widget child;
  final int index;
  final Duration baseDelay;
  final Duration stepDelay;
  final Duration duration;
  final double offsetY;

  const StaggeredFadeIn({super.key, required this.child, required this.index, this.baseDelay = const Duration(milliseconds: 20), this.stepDelay = const Duration(milliseconds: 40), this.duration = const Duration(milliseconds: 420), this.offsetY = 0.24});

  @override
  Widget build(BuildContext context) {
    final delay = baseDelay + Duration(milliseconds: stepDelay.inMilliseconds * index);
    final animSettings = Provider.of<AnimationSettings>(context, listen: false);
    if (!animSettings.enabled) return child;
    return FadeInUp(child: child, delay: delay, duration: duration, offsetY: offsetY);
  }
}
