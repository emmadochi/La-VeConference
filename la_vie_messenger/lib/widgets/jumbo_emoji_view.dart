import 'package:flutter/material.dart';

/// Helper to detect if a message string consists purely of emojis
/// and counts how many distinct emoji grapheme clusters are present.
class EmojiHelper {
  static final RegExp _singleEmojiPattern = RegExp(
    r'^(\p{Extended_Pictographic}|\p{Emoji_Presentation}|\uFE0F|\u200D|[\u{1F3FB}-\u{1F3FF}]|[\u{1F1E6}-\u{1F1FF}])+$',
    unicode: true,
  );

  /// Returns 0 if text contains regular words/symbols or is empty,
  /// or returns the emoji count (1, 2, 3...) if text is purely emojis.
  static int getEmojiCount(String rawText) {
    final text = rawText.trim();
    if (text.isEmpty) return 0;

    // Fast reject if text contains alphanumeric characters or common punctuation
    if (RegExp(r'[a-zA-Z0-9_]').hasMatch(text)) return 0;

    // Must match unicode emoji sequence
    if (!_singleEmojiPattern.hasMatch(text)) return 0;

    // Split by grapheme clusters (handles ZWJ, skin tones, flags properly)
    final clusters = text.characters.where((c) => c.trim().isNotEmpty).toList();
    if (clusters.isEmpty) return 0;

    // Every cluster must be an emoji
    for (final c in clusters) {
      if (!_singleEmojiPattern.hasMatch(c)) return 0;
    }

    return clusters.length;
  }

  /// Checks if the emoji is a heart that should have a continuous heartbeat pulse
  static bool isHeartEmoji(String text) {
    final t = text.trim();
    const hearts = ['❤️', '💓', '💗', '💖', '💘', '💝', '💞', '💕', '❤️‍🔥'];
    return hearts.contains(t);
  }
}

/// A vibrant, animated display for pure emoji messages (WhatsApp / Telegram style)
class JumboEmojiView extends StatefulWidget {
  final String text;
  final int count;
  final bool isMe;

  const JumboEmojiView({
    super.key,
    required this.text,
    required this.count,
    required this.isMe,
  });

  @override
  State<JumboEmojiView> createState() => _JumboEmojiViewState();
}

class _JumboEmojiViewState extends State<JumboEmojiView> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnimation;
  bool _isHeart = false;

  @override
  void initState() {
    super.initState();
    _isHeart = widget.count == 1 && EmojiHelper.isHeartEmoji(widget.text);

    if (_isHeart) {
      // Continuous heartbeat pulse for single heart emoji
      _controller = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 900),
      )..repeat(reverse: true);

      _scaleAnimation = TweenSequence<double>([
        TweenSequenceItem(
          tween: Tween<double>(begin: 1.0, end: 1.18).chain(CurveTween(curve: Curves.easeInOut)),
          weight: 40,
        ),
        TweenSequenceItem(
          tween: Tween<double>(begin: 1.18, end: 1.05).chain(CurveTween(curve: Curves.easeInOut)),
          weight: 20,
        ),
        TweenSequenceItem(
          tween: Tween<double>(begin: 1.05, end: 1.22).chain(CurveTween(curve: Curves.easeInOut)),
          weight: 40,
        ),
      ]).animate(_controller);
    } else {
      // Playful one-shot spring bounce entrance for other emojis
      _controller = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 550),
      );

      _scaleAnimation = TweenSequence<double>([
        TweenSequenceItem(
          tween: Tween<double>(begin: 0.3, end: 1.25).chain(CurveTween(curve: Curves.easeOutBack)),
          weight: 60,
        ),
        TweenSequenceItem(
          tween: Tween<double>(begin: 1.25, end: 0.94).chain(CurveTween(curve: Curves.easeInOut)),
          weight: 20,
        ),
        TweenSequenceItem(
          tween: Tween<double>(begin: 0.94, end: 1.0).chain(CurveTween(curve: Curves.easeOut)),
          weight: 20,
        ),
      ]).animate(_controller);

      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double fontSize = widget.count == 1
        ? 48.0
        : (widget.count == 2
            ? 34.0
            : (widget.count == 3 ? 29.0 : 22.0));

    return ScaleTransition(
      scale: _scaleAnimation,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
        child: Text(
          widget.text.trim(),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: fontSize,
            height: 1.18,
          ),
        ),
      ),
    );
  }
}
