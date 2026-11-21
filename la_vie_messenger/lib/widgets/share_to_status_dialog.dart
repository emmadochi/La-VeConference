import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/status_service.dart';
import '../services/media_storage_service.dart';
import '../theme/app_theme.dart';

/// Bottom-sheet dialog that lets a user share a chat message / file to their Status.
class ShareToStatusDialog extends StatefulWidget {
  final Map<String, dynamic> messageData;

  const ShareToStatusDialog({super.key, required this.messageData});

  /// Convenience static method — call anywhere you have a BuildContext.
  static Future<void> show(BuildContext context, Map<String, dynamic> data) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => ShareToStatusDialog(messageData: data),
    );
  }

  @override
  State<ShareToStatusDialog> createState() => _ShareToStatusDialogState();
}

class _ShareToStatusDialogState extends State<ShareToStatusDialog> {
  // Gradient / Font pickers (text statuses only)
  final List<List<int>> _gradientPresets = [
    [0xFF7C3AED, 0xFF9333EA],
    [0xFF1E3A8A, 0xFF3B82F6],
    [0xFF9D174D, 0xFFF43F5E],
    [0xFF065F46, 0xFF10B981],
    [0xFFB45309, 0xFFF59E0B],
    [0xFF18181B, 0xFF3F3F46],
  ];
  int _selectedGradient = 0;
  final List<String> _fontFamilies = ['Modern', 'Serif', 'Script', 'Mono'];
  int _selectedFont = 0;
  bool _isPosting = false;

  String get _type => widget.messageData['type'] as String? ?? 'text';
  String get _text => widget.messageData['text'] as String? ?? '';
  String? get _mediaUrl => widget.messageData['mediaUrl'] as String?;
  String? get _localPath => widget.messageData['localPath'] as String?;
  String? get _fileName => widget.messageData['fileName'] as String?;

  bool get _isText => _type == 'text';
  bool get _isImage => _type == 'image';

  TextStyle _getTextStyle() {
    const base = Colors.white;
    const size = 22.0;
    switch (_fontFamilies[_selectedFont]) {
      case 'Serif':
        return GoogleFonts.playfairDisplay(color: base, fontSize: size, fontWeight: FontWeight.w600);
      case 'Script':
        return GoogleFonts.caveat(color: base, fontSize: size + 6, fontWeight: FontWeight.w700);
      case 'Mono':
        return GoogleFonts.spaceMono(color: base, fontSize: size - 4, fontWeight: FontWeight.w500);
      default:
        return GoogleFonts.plusJakartaSans(color: base, fontSize: size, fontWeight: FontWeight.bold);
    }
  }

  Future<void> _post() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    setState(() => _isPosting = true);
    try {
      if (_isText && _text.isNotEmpty) {
        await StatusService.postTextStatus(
          uid: user.uid,
          userName: user.displayName ?? 'Me',
          userAvatar: user.photoURL,
          text: _text,
          gradientColors: _gradientPresets[_selectedGradient],
          fontStyle: _fontFamilies[_selectedFont].toLowerCase(),
        );
      } else if (_isImage) {
        File? imageFile;
        if (_localPath != null && await File(_localPath!).exists()) {
          imageFile = File(_localPath!);
        } else if (_mediaUrl != null && _mediaUrl!.isNotEmpty) {
          imageFile = await MediaStorageService.downloadMediaToLocal(
            remoteUrl: _mediaUrl!,
            category: 'Images',
            targetFileName: _fileName ?? 'shared_status.jpg',
          );
        }
        if (imageFile == null || !await imageFile.exists()) {
          throw Exception('Could not retrieve image file.');
        }
        await StatusService.postMediaStatus(
          uid: user.uid,
          userName: user.displayName ?? 'Me',
          userAvatar: user.photoURL,
          mediaFile: imageFile,
          type: 'image',
          caption: _text.isNotEmpty && !_text.startsWith('\u{1F4F7}') ? _text : null,
        );
      } else {
        // File / audio / fallback -> post as a text status with label
        final label = _type == 'file'
            ? '\u{1F4CE} Shared file: ${_fileName ?? 'Document'}'
            : _text.isNotEmpty
                ? _text
                : '(Shared message)';
        await StatusService.postTextStatus(
          uid: user.uid,
          userName: user.displayName ?? 'Me',
          userAvatar: user.photoURL,
          text: label,
          gradientColors: _gradientPresets[_selectedGradient],
          fontStyle: _fontFamilies[_selectedFont].toLowerCase(),
        );
      }
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Shared to your Status \u2713'),
            backgroundColor: AppTheme.bubbleMe,
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to share: $e'),
            backgroundColor: AppTheme.callRed,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isPosting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final gradColors = _gradientPresets[_selectedGradient].map((c) => Color(c)).toList();
    final showStylePicker = _isText || _type == 'file' || _type == 'audio';

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(
            margin: const EdgeInsets.only(top: 10, bottom: 4),
            width: 40,
            height: 4,
            decoration: BoxDecoration(color: AppTheme.border, borderRadius: BorderRadius.circular(4)),
          ),
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.mint.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.auto_stories_rounded, color: AppTheme.mint, size: 20),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Share to Status', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                      Text('Visible to your contacts for 24 hours', style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: AppTheme.textMuted),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          const Divider(color: AppTheme.border, height: 1),
          // Content Preview
          Padding(
            padding: const EdgeInsets.all(20),
            child: _isImage ? _buildImagePreview() : _buildTextPreview(gradColors),
          ),
          // Style pickers
          if (showStylePicker) ...[
            Padding(
              padding: const EdgeInsets.only(left: 20, right: 20, bottom: 6),
              child: Row(
                children: [
                  const Text('Background', style: TextStyle(color: AppTheme.textMuted, fontSize: 12, fontWeight: FontWeight.w600)),
                  const Spacer(),
                  ...List.generate(_gradientPresets.length, (i) {
                    final c1 = Color(_gradientPresets[i][0]);
                    final c2 = Color(_gradientPresets[i][1]);
                    return GestureDetector(
                      onTap: () => setState(() => _selectedGradient = i),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.only(left: 6),
                        width: i == _selectedGradient ? 28 : 22,
                        height: i == _selectedGradient ? 28 : 22,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(colors: [c1, c2], begin: Alignment.topLeft, end: Alignment.bottomRight),
                          shape: BoxShape.circle,
                          border: i == _selectedGradient
                              ? Border.all(color: Colors.white, width: 2)
                              : Border.all(color: Colors.white24, width: 1),
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 20, right: 20, bottom: 16),
              child: Row(
                children: [
                  const Text('Font', style: TextStyle(color: AppTheme.textMuted, fontSize: 12, fontWeight: FontWeight.w600)),
                  const SizedBox(width: 12),
                  Wrap(
                    spacing: 8,
                    children: List.generate(_fontFamilies.length, (i) {
                      final sel = i == _selectedFont;
                      return GestureDetector(
                        onTap: () => setState(() => _selectedFont = i),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: sel ? AppTheme.mint.withValues(alpha: 0.2) : Colors.transparent,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: sel ? AppTheme.mint : AppTheme.border),
                          ),
                          child: Text(
                            _fontFamilies[i],
                            style: TextStyle(
                              color: sel ? AppTheme.mint : AppTheme.textMuted,
                              fontSize: 12,
                              fontWeight: sel ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                ],
              ),
            ),
          ] else
            const SizedBox(height: 16),
          // Post button
          Padding(
            padding: const EdgeInsets.only(left: 20, right: 20, bottom: 24),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.mint,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                  elevation: 0,
                ),
                onPressed: _isPosting ? null : _post,
                icon: _isPosting
                    ? const SizedBox(
                        width: 18, height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.auto_stories_rounded, size: 18),
                label: Text(
                  _isPosting ? 'Posting\u2026' : 'Post to Status',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextPreview(List<Color> gradColors) {
    String displayText;
    if (_type == 'file') {
      displayText = '\u{1F4CE} ${_fileName ?? 'Document'}';
    } else if (_type == 'audio') {
      displayText = '\u{1F3A4} Voice note';
    } else {
      displayText = _text.isNotEmpty ? _text : '(empty)';
    }
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      height: 130,
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: gradColors, begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(18),
      ),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(20),
      child: Text(
        displayText,
        textAlign: TextAlign.center,
        maxLines: 4,
        overflow: TextOverflow.ellipsis,
        style: _getTextStyle(),
      ),
    );
  }

  Widget _buildImagePreview() {
    Widget imageWidget;
    if (_localPath != null && File(_localPath!).existsSync()) {
      imageWidget = Image.file(File(_localPath!), fit: BoxFit.cover);
    } else if (_mediaUrl != null && _mediaUrl!.isNotEmpty) {
      imageWidget = Image.network(_mediaUrl!, fit: BoxFit.cover);
    } else {
      imageWidget = const Center(child: Icon(Icons.image_not_supported_rounded, color: Colors.white38, size: 48));
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: SizedBox(height: 200, width: double.infinity, child: imageWidget),
    );
  }
}
