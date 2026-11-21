import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/status_service.dart';
import '../theme/app_theme.dart';
import '../widgets/status_privacy_dialog.dart';

class CreateTextStatusScreen extends StatefulWidget {
  final String? initialText;

  const CreateTextStatusScreen({super.key, this.initialText});

  @override
  State<CreateTextStatusScreen> createState() => _CreateTextStatusScreenState();
}

class _CreateTextStatusScreenState extends State<CreateTextStatusScreen> {
  late final TextEditingController _textController;
  final FocusNode _focusNode = FocusNode();
  bool _isPosting = false;
  int _charCount = 0;
  int _durationHours = 24;
  StatusPrivacySettings _privacy = const StatusPrivacySettings(privacy: 'all');

  static const int _maxChars = 200;

  final List<List<int>> _gradientPresets = [
    [0xFF7C3AED, 0xFF9333EA], // Lilac / Amethyst (Default LiChat)
    [0xFF1E3A8A, 0xFF3B82F6], // Ocean Blue
    [0xFF9D174D, 0xFFF43F5E], // Rose Crimson
    [0xFF065F46, 0xFF10B981], // Emerald Teal
    [0xFFB45309, 0xFFF59E0B], // Warm Amber
    [0xFF18181B, 0xFF3F3F46], // Deep Carbon
  ];
  int _selectedGradientIndex = 0;

  final List<String> _fontFamilies = ['Modern', 'Serif', 'Script', 'Mono'];
  int _selectedFontIndex = 0;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(text: widget.initialText ?? '');
    _charCount = _textController.text.length;
    _textController.addListener(() {
      setState(() => _charCount = _textController.text.length);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
    StatusPrivacySettings.load().then((p) {
      if (mounted) setState(() => _privacy = p);
    });
  }

  TextStyle _getTextStyle() {
    const baseColor = Colors.white;
    const baseSize = 28.0;

    switch (_fontFamilies[_selectedFontIndex]) {
      case 'Serif':
        return GoogleFonts.playfairDisplay(
          color: baseColor,
          fontSize: baseSize,
          fontWeight: FontWeight.w600,
        );
      case 'Script':
        return GoogleFonts.caveat(
          color: baseColor,
          fontSize: baseSize + 8,
          fontWeight: FontWeight.w700,
        );
      case 'Mono':
        return GoogleFonts.spaceMono(
          color: baseColor,
          fontSize: baseSize - 4,
          fontWeight: FontWeight.w500,
        );
      case 'Modern':
      default:
        return GoogleFonts.plusJakartaSans(
          color: baseColor,
          fontSize: baseSize,
          fontWeight: FontWeight.bold,
        );
    }
  }

  void _cycleGradient() {
    setState(() {
      _selectedGradientIndex = (_selectedGradientIndex + 1) % _gradientPresets.length;
    });
  }

  void _cycleFont() {
    setState(() {
      _selectedFontIndex = (_selectedFontIndex + 1) % _fontFamilies.length;
    });
  }

  Future<void> _openPrivacyPicker() async {
    final updated = await StatusPrivacyDialog.show(context, _privacy);
    if (updated != null && mounted) {
      setState(() => _privacy = updated);
    }
  }

  Future<void> _openDurationPicker() async {
    final selected = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: AppTheme.surfaceColor(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        final textPrim = AppTheme.text(ctx);
        final textSec = AppTheme.textSec(ctx);
        final mint = AppTheme.mintColor(ctx);

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 38,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: AppTheme.borderColor(ctx),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Row(
                  children: [
                    Icon(Icons.hourglass_bottom_rounded, color: mint, size: 22),
                    const SizedBox(width: 8),
                    Text(
                      'Status Longevity',
                      style: TextStyle(color: textPrim, fontSize: 17, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Select how long your status remains visible before disappearing:',
                  style: TextStyle(color: textSec, fontSize: 13),
                ),
                const SizedBox(height: 16),
                for (final hours in [4, 12, 24, 48])
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: _durationHours == hours ? mint.withValues(alpha: 0.15) : Colors.transparent,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        hours == 24 ? Icons.timer_rounded : Icons.schedule_rounded,
                        color: _durationHours == hours ? mint : textSec,
                        size: 20,
                      ),
                    ),
                    title: Text(
                      '$hours Hours${hours == 24 ? ' (Standard 24h)' : ''}',
                      style: TextStyle(
                        color: _durationHours == hours ? mint : textPrim,
                        fontWeight: _durationHours == hours ? FontWeight.bold : FontWeight.w500,
                      ),
                    ),
                    trailing: _durationHours == hours
                        ? Icon(Icons.check_circle_rounded, color: mint, size: 22)
                        : null,
                    onTap: () => Navigator.pop(ctx, hours),
                  ),
              ],
            ),
          ),
        );
      },
    );

    if (selected != null && mounted) {
      setState(() => _durationHours = selected);
    }
  }

  Future<void> _postStatus() async {
    final text = _textController.text.trim();
    if (text.isEmpty || text.length > _maxChars) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _isPosting = true);
    try {
      await StatusService.postTextStatus(
        uid: user.uid,
        userName: user.displayName ?? 'Me',
        userAvatar: user.photoURL,
        text: text,
        gradientColors: _gradientPresets[_selectedGradientIndex],
        fontStyle: _fontFamilies[_selectedFontIndex].toLowerCase(),
        privacy: _privacy.privacy,
        privacyUids: _privacy.selectedUids,
        durationHours: _durationHours,
      );

      if (mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Status update posted!'),
            backgroundColor: AppTheme.bubbleMe,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to post status: $e'), backgroundColor: AppTheme.callRed),
        );
      }
    } finally {
      if (mounted) setState(() => _isPosting = false);
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = _gradientPresets[_selectedGradientIndex]
        .map((c) => Color(c))
        .toList();

    return Scaffold(
      body: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: colors,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Top Action Bar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.white, size: 28),
                      tooltip: 'Discard',
                      onPressed: () => Navigator.pop(context),
                    ),
                    const Spacer(),

                    // Font Switcher Button
                    IconButton(
                      icon: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.4)),
                        ),
                        child: Text(
                          _fontFamilies[_selectedFontIndex],
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      tooltip: 'Change Font',
                      onPressed: _cycleFont,
                    ),

                    const SizedBox(width: 8),

                    // Color Palette Button
                    IconButton(
                      icon: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withValues(alpha: 0.25),
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        child: const Icon(Icons.palette_rounded, color: Colors.white, size: 18),
                      ),
                      tooltip: 'Change Color',
                      onPressed: _cycleGradient,
                    ),
                  ],
                ),
              ),

              // Main Status Center Text Area
              Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: TextField(
                      controller: _textController,
                      focusNode: _focusNode,
                      textAlign: TextAlign.center,
                      maxLines: null,
                      maxLength: _maxChars,
                      cursorColor: Colors.white,
                      style: _getTextStyle(),
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        counterText: '',
                        hintText: 'Type a status update...',
                        hintStyle: _getTextStyle().copyWith(
                          color: Colors.white.withValues(alpha: 0.5),
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              // Bottom Bar: Privacy Pill + Char Counter + Send Action
              Padding(
                padding: const EdgeInsets.only(left: 20, right: 20, bottom: 20),
                child: Row(
                  children: [
                    // Privacy Pill
                    GestureDetector(
                      onTap: _openPrivacyPicker,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.lock_outline_rounded, color: Colors.white70, size: 14),
                            const SizedBox(width: 6),
                            Text(
                              _privacy.label,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: 4),
                            const Icon(Icons.arrow_drop_down_rounded, color: Colors.white70, size: 18),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(width: 8),

                    // Duration Longevity Pill
                    GestureDetector(
                      onTap: _openDurationPicker,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.timer_outlined, color: Colors.white70, size: 14),
                            const SizedBox(width: 4),
                            Text(
                              '${_durationHours}h',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: 2),
                            const Icon(Icons.arrow_drop_down_rounded, color: Colors.white70, size: 16),
                          ],
                        ),
                      ),
                    ),

                    const Spacer(),

                    // Char counter
                    AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 200),
                      style: TextStyle(
                        color: _charCount > _maxChars
                            ? Colors.redAccent
                            : _charCount > (_maxChars * 0.85).toInt()
                                ? Colors.orangeAccent
                                : Colors.white.withValues(alpha: 0.65),
                        fontSize: 13,
                        fontWeight: _charCount > _maxChars ? FontWeight.bold : FontWeight.w500,
                      ),
                      child: Text('$_charCount / $_maxChars'),
                    ),
                    const SizedBox(width: 14),

                    FloatingActionButton(
                      heroTag: 'post_status_fab',
                      onPressed: (_isPosting || _charCount == 0 || _charCount > _maxChars) ? null : _postStatus,
                      backgroundColor: _charCount > _maxChars ? Colors.redAccent.withValues(alpha: 0.5) : Colors.white,
                      elevation: 4,
                      child: _isPosting
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: AppTheme.lilacDeep,
                              ),
                            )
                          : Icon(
                              Icons.send_rounded,
                              color: _charCount > _maxChars ? Colors.white54 : AppTheme.lilacDeep,
                            ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
