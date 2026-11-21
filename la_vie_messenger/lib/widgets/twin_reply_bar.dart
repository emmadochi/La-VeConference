import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';

/// Animated sliding reply bar shown above the message input box
/// when the AI Twin has suggestion candidates ready.
///
/// Layout:
///  ┌────────────────────────────────────────────────────────────────┐
///  │  🤖 AI Twin  ·  "1 of 3"       [◀]  [▶]       [✗ Dismiss]    │
///  │  ┌──────────────────────────────────────────────────────────┐  │
///  │  │  "Sure, that works for me! Let me know the time 👍"      │  │
///  │  └──────────────────────────────────────────────────────────┘  │
///  │        [✏ Edit & Send]              [✈ Send Now]               │
///  └────────────────────────────────────────────────────────────────┘
class TwinReplyBar extends StatefulWidget {
  final List<String> candidates;
  final VoidCallback onDismiss;

  /// Called with the chosen reply text; parent decides to prefill or send
  final void Function(String reply, bool autoSend) onReplyChosen;

  const TwinReplyBar({
    super.key,
    required this.candidates,
    required this.onDismiss,
    required this.onReplyChosen,
  });

  @override
  State<TwinReplyBar> createState() => _TwinReplyBarState();
}

class _TwinReplyBarState extends State<TwinReplyBar>
    with SingleTickerProviderStateMixin {
  int _index = 0;
  late final AnimationController _slideCtrl;
  late final Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _slideCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _slideCtrl, curve: Curves.easeOutCubic));
    _slideCtrl.forward();
  }

  @override
  void dispose() {
    _slideCtrl.dispose();
    super.dispose();
  }

  void _prev() {
    HapticFeedback.selectionClick();
    setState(() => _index = (_index - 1 + widget.candidates.length) % widget.candidates.length);
  }

  void _next() {
    HapticFeedback.selectionClick();
    setState(() => _index = (_index + 1) % widget.candidates.length);
  }

  String get _current => widget.candidates[_index];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lilac = AppTheme.lilac;
    final surface = theme.colorScheme.surface;
    final isDark = theme.brightness == Brightness.dark;
    final cardBg = isDark
        ? const Color(0xFF1E1A2E)
        : const Color(0xFFF3F0FF);
    final borderColor = lilac.withValues(alpha: 0.35);
    final textPrim = theme.colorScheme.onSurface;
    final textMuted = theme.colorScheme.onSurface.withValues(alpha: 0.5);

    return SlideTransition(
      position: _slideAnim,
      child: Container(
        margin: const EdgeInsets.fromLTRB(8, 0, 8, 4),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: borderColor, width: 1.4),
          boxShadow: [
            BoxShadow(
              color: lilac.withValues(alpha: 0.12),
              blurRadius: 16,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Header row ───────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 10, 0),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: lilac.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('🤖', style: const TextStyle(fontSize: 13)),
                        const SizedBox(width: 5),
                        Text(
                          'AI Twin',
                          style: TextStyle(
                            color: lilac,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (widget.candidates.length > 1) ...[
                    // Navigation arrows
                    _NavBtn(onTap: _prev, icon: Icons.chevron_left_rounded, color: lilac),
                    Text(
                      '${_index + 1} / ${widget.candidates.length}',
                      style: TextStyle(color: textMuted, fontSize: 12),
                    ),
                    _NavBtn(onTap: _next, icon: Icons.chevron_right_rounded, color: lilac),
                  ],
                  const Spacer(),
                  // Dismiss
                  GestureDetector(
                    onTap: widget.onDismiss,
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: Icon(Icons.close_rounded, size: 18, color: textMuted),
                    ),
                  ),
                ],
              ),
            ),

            // ── Candidate text bubble ─────────────────────────────────────
            GestureDetector(
              onHorizontalDragEnd: (details) {
                if (details.primaryVelocity != null) {
                  if (details.primaryVelocity! < -200) _next();
                  if (details.primaryVelocity! > 200) _prev();
                }
              },
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: Container(
                  key: ValueKey(_index),
                  margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: cardBg,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    _current,
                    style: TextStyle(
                      color: textPrim,
                      fontSize: 14,
                      height: 1.4,
                    ),
                  ),
                ),
              ),
            ),

            // ── Action buttons ────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: lilac,
                        side: BorderSide(color: lilac.withValues(alpha: 0.5)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                      icon: const Icon(Icons.edit_rounded, size: 16),
                      label: const Text('Edit & Send', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                      onPressed: () {
                        HapticFeedback.lightImpact();
                        widget.onReplyChosen(_current, false);
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: lilac,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        elevation: 0,
                      ),
                      icon: const Icon(Icons.send_rounded, size: 16),
                      label: const Text('Send Now', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                      onPressed: () {
                        HapticFeedback.mediumImpact();
                        widget.onReplyChosen(_current, true);
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavBtn extends StatelessWidget {
  final VoidCallback onTap;
  final IconData icon;
  final Color color;
  const _NavBtn({required this.onTap, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Icon(icon, size: 20, color: color),
      ),
    );
  }
}
