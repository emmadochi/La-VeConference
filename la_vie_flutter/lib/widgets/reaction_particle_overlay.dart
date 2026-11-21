import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class ReactionParticle {
  final Key key;
  final String emoji;
  final Offset startOffset;
  final double driftX;
  final double scale;
  final double rotation;
  final Duration duration;

  ReactionParticle({
    required this.key,
    required this.emoji,
    required this.startOffset,
    required this.driftX,
    required this.scale,
    required this.rotation,
    required this.duration,
  });
}

class ReactionParticleOverlay extends StatefulWidget {
  final Widget child;

  const ReactionParticleOverlay({
    super.key,
    required this.child,
  });

  static ReactionParticleOverlayState? of(BuildContext context) {
    return context.findAncestorStateOfType<ReactionParticleOverlayState>();
  }

  @override
  State<ReactionParticleOverlay> createState() => ReactionParticleOverlayState();
}

class ReactionParticleOverlayState extends State<ReactionParticleOverlay> {
  final List<ReactionParticle> _particles = [];
  final math.Random _random = math.Random();

  int _comboCount = 0;
  DateTime? _lastTapTime;
  String? _lastEmoji;
  Offset? _comboBadgePosition;

  void spawnReaction(String emoji, {Offset? origin}) {
    final now = DateTime.now();
    if (_lastTapTime != null && now.difference(_lastTapTime!).inMilliseconds < 800 && _lastEmoji == emoji) {
      _comboCount++;
    } else {
      _comboCount = 1;
    }
    _lastTapTime = now;
    _lastEmoji = emoji;

    // Haptic feedback with escalating intensity
    try {
      if (_comboCount >= 10) {
        HapticFeedback.heavyImpact();
      } else if (_comboCount >= 4) {
        HapticFeedback.mediumImpact();
      } else {
        HapticFeedback.lightImpact();
      }
    } catch (_) {}

    final screenSize = MediaQuery.of(context).size;
    final defaultOrigin = origin ?? Offset(screenSize.width * 0.75, screenSize.height - 120);
    _comboBadgePosition = defaultOrigin;

    // Determine number of particles to spawn (spam combo produces mass effect)
    final count = _comboCount >= 15
        ? 4
        : _comboCount >= 7
            ? 3
            : _comboCount >= 3
                ? 2
                : 1;

    for (int i = 0; i < count; i++) {
      final drift = (_random.nextDouble() - 0.5) * 160;
      final scaleBonus = math.min((_comboCount - 1) * 0.04, 0.6);
      final scale = (0.9 + _random.nextDouble() * 0.4) + scaleBonus;
      final rotation = (_random.nextDouble() - 0.5) * 0.5;
      final durationMs = 1500 + _random.nextInt(800);

      final particle = ReactionParticle(
        key: UniqueKey(),
        emoji: (i > 0 && _random.nextBool() && _comboCount >= 8) ? '✨' : emoji,
        startOffset: defaultOrigin + Offset((_random.nextDouble() - 0.5) * 40, (_random.nextDouble() - 0.5) * 20),
        driftX: drift,
        scale: scale,
        rotation: rotation,
        duration: Duration(milliseconds: durationMs),
      );

      setState(() {
        _particles.add(particle);
      });
    }

    // Auto-reset combo after pause
    Future.delayed(const Duration(milliseconds: 1000), () {
      if (mounted && _lastTapTime != null && DateTime.now().difference(_lastTapTime!).inMilliseconds >= 950) {
        setState(() {
          _comboCount = 0;
        });
      }
    });
  }

  void _removeParticle(Key key) {
    if (mounted) {
      setState(() {
        _particles.removeWhere((p) => p.key == key);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        // Particle layer
        IgnorePointer(
          child: Stack(
            children: [
              ..._particles.map((p) => _AnimatedParticleWidget(
                    key: p.key,
                    particle: p,
                    onComplete: () => _removeParticle(p.key),
                  )),
              // Combo badge
              if (_comboCount >= 2 && _comboBadgePosition != null)
                Positioned(
                  left: math.max(16.0, math.min(_comboBadgePosition!.dx - 40, MediaQuery.of(context).size.width - 100)),
                  top: math.max(60.0, _comboBadgePosition!.dy - 70),
                  child: TweenAnimationBuilder<double>(
                    key: ValueKey(_comboCount),
                    tween: Tween(begin: 1.4, end: 1.0),
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.elasticOut,
                    builder: (context, scale, child) {
                      return Transform.scale(
                        scale: scale,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: _comboCount >= 10
                                  ? [const Color(0xFFFF0055), const Color(0xFFFF9900)]
                                  : [const Color(0xFF00E5FF), const Color(0xFF5C00FF)],
                            ),
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: (_comboCount >= 10 ? const Color(0xFFFF0055) : const Color(0xFF00E5FF))
                                    .withOpacity(0.5),
                                blurRadius: 10,
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _lastEmoji ?? '🔥',
                                style: const TextStyle(fontSize: 16),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'x$_comboCount',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AnimatedParticleWidget extends StatefulWidget {
  final ReactionParticle particle;
  final VoidCallback onComplete;

  const _AnimatedParticleWidget({
    super.key,
    required this.particle,
    required this.onComplete,
  });

  @override
  State<_AnimatedParticleWidget> createState() => _AnimatedParticleWidgetState();
}

class _AnimatedParticleWidgetState extends State<_AnimatedParticleWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _progress;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.particle.duration,
    );
    _progress = CurvedAnimation(parent: _controller, curve: Curves.easeOutQuad);

    _controller.forward().then((_) {
      if (mounted) {
        widget.onComplete();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _progress,
      builder: (context, child) {
        final t = _progress.value;
        // Travel upwards: from startOffset.dy to startOffset.dy - 350px
        final currentY = widget.particle.startOffset.dy - (380 * t);
        // Horizontal wave sway: driftX * t + math.sin(t * 3 * pi) * 20
        final currentX = widget.particle.startOffset.dx +
            (widget.particle.driftX * t) +
            (math.sin(t * 3 * math.pi) * 18);

        // Opacity: fade in quickly (0 to 0.15), hold, then fade out (0.6 to 1.0)
        double opacity = 1.0;
        if (t < 0.15) {
          opacity = t / 0.15;
        } else if (t > 0.6) {
          opacity = 1.0 - ((t - 0.6) / 0.4);
        }
        opacity = opacity.clamp(0.0, 1.0);

        // Scale: slight pop in
        final scale = widget.particle.scale * (0.8 + 0.3 * (1.0 - (t - 0.5).abs() * 2).clamp(0.0, 1.0));

        return Positioned(
          left: currentX,
          top: currentY,
          child: Transform.rotate(
            angle: widget.particle.rotation * (1 - t),
            child: Transform.scale(
              scale: scale,
              child: Opacity(
                opacity: opacity,
                child: Text(
                  widget.particle.emoji,
                  style: TextStyle(
                    fontSize: 34,
                    shadows: [
                      Shadow(
                        color: Colors.black.withOpacity(0.4),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

