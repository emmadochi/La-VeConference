import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class EmojiPickerSheet extends StatefulWidget {
  final ValueChanged<String> onEmojiSelected;
  final VoidCallback onBackspacePressed;
  final VoidCallback? onClose;

  const EmojiPickerSheet({
    super.key,
    required this.onEmojiSelected,
    required this.onBackspacePressed,
    this.onClose,
  });

  @override
  State<EmojiPickerSheet> createState() => _EmojiPickerSheetState();
}

class _EmojiPickerSheetState extends State<EmojiPickerSheet> {
  int _selectedCategoryIndex = 0;
  final PageController _pageController = PageController();

  static const List<Map<String, dynamic>> _categories = [
    {
      'name': 'Smileys',
      'icon': Icons.sentiment_satisfied_alt_rounded,
      'emojis': [
        '😀', '😃', '😄', '😁', '😆', '😅', '😂', '🤣', '🥲', '🥹',
        '☺️', '😊', '😇', '🙂', '🙃', '😉', '😌', '😍', '🥰', '😘',
        '😗', '😙', '😚', '😋', '😛', '😝', '😜', '🤪', '🤨', '🧐',
        '🤓', '😎', '🥸', '🤩', '🥳', '😏', '😒', '😞', '😔', '😟',
        '😕', '🙁', '☹️', '😣', '😖', '😫', '😩', '🥺', '😢', '😭',
        '😮‍💨', '😤', '😠', '😡', '🤬', '🤯', '😳', '🥵', '🥶', '😱',
        '😨', '😰', '😥', '😓', '🤗', '🤔', '🫣', '🤭', '🫢', '🫡',
        '🤫', '🫠', '🤥', '😶', '😐', '😑', '😬', '🫨', '🙄', '😯',
        '😦', '😧', '😮', '😲', '🥱', '😴', '🤤', '😪', '😵', '😵‍💫',
        '🫥', '🤐', '🥴', '🤢', '🤮', '🤧', '😷', '🤒', '🤕', '🤑',
        '🤠', '😈', '👿', '👹', '👺', '🤡', '💩', '👻', '💀', '☠️',
        '👽', '👾', '🤖', '🎃',
      ],
    },
    {
      'name': 'Gestures',
      'icon': Icons.pan_tool_rounded,
      'emojis': [
        '👍', '👎', '👏', '🙌', '🫶', '👐', '🤲', '🤝', '🙏', '✌️',
        '🤞', '🫰', '🤟', '🤘', '🤙', '👈', '👉', '👆', '🖕', '👇',
        '☝️', '🫵', '👋', '🤚', '🖐️', '✋', '🖖', '🫱', '🫲', '🫳',
        '🫴', '👌', '🤌', '🤏', '✊', '👊', '🤛', '🤜', '✍️', '💅',
        '🤳', '💪', '🦾', '🦵', '🦿', '🦶', '👂', '🦻', '👃', '👀',
        '👁️', '👅', '👄', '💋', '🫂', '👶', '👧', '🧒', '👦', '👩',
        '🧑', '👨', '👵', '🧓', '👴', '👮', '👷', '💂', '🕵️', '🧑‍⚕️',
      ],
    },
    {
      'name': 'Hearts & Love',
      'icon': Icons.favorite_rounded,
      'emojis': [
        '❤️', '🧡', '💛', '💚', '💙', '💜', '🖤', '🤍', '🤎', '💔',
        '❤️‍🔥', '❤️‍🩹', '❣️', '💕', '💞', '💓', '💗', '💖', '💘', '💝',
        '💟', '💌', '💋', '💏', '💑', '💐', '🌹', '🥀', '🌺', '🌸',
        '🌷', '✨', '🌟', '💫', '⭐', '🌙', '☀️', '🔥', '💥', '⚡',
      ],
    },
    {
      'name': 'Celebration',
      'icon': Icons.celebration_rounded,
      'emojis': [
        '🎉', '🎊', '🎈', '🎂', '🎁', '🎀', '🪄', '🎆', '🎇', '🧨',
        '🪅', '🥂', '🍻', '🍹', '🍸', '🍷', '🍾', '🏆', '🥇', '🥈',
        '🥉', '🏅', '🎖️', '🎮', '🕹️', '🎲', '🎯', '🎳', '🎪', '🎭',
        '🎨', '🎬', '🎤', '🎧', '🎼', '🎵', '🎶', '🎸', '🎹', '🥁',
      ],
    },
    {
      'name': 'Animals',
      'icon': Icons.pets_rounded,
      'emojis': [
        '🐶', '🐱', '🐭', '🐹', '🐰', '🦊', '🐻', '🐼', '🐨', '🐯',
        '🦁', '🐮', '🐷', '🐸', '🐵', '🙈', '🙉', '🙊', '🐒', '🐔',
        '🐧', '🐦', '🐤', '🐣', '🐥', '🦆', '🦅', '🦉', '🦇', '🐺',
        '🐗', '🐴', '🦄', '🐝', '🐛', '🦋', '🐌', '🐞', '🐜', '🪴',
        '🌲', '🌳', '🌴', '🌵', '🌾', '🌿', '☘️', '🍀', '🍁', '🍂',
      ],
    },
    {
      'name': 'Food & Drink',
      'icon': Icons.fastfood_rounded,
      'emojis': [
        '🍏', '🍎', '🍐', '🍊', '🍋', '🍌', '🍉', '🍇', '🍓', '🫐',
        '🍒', '🍑', '🥭', '🍍', '🥥', '🥝', '🍅', '🥑', '🍔', '🍟',
        '🍕', '🌭', '🥪', '🌮', '🌯', '🥗', '🍝', '🍜', '🍣', '🍱',
        '🥟', '🍦', '🍧', '🍨', '🍩', '🍪', '🎂', '🍰', '🧁', '🍫',
        '🍿', '☕', '🍵', '🧋', '🥤', '🧃', '🥛', '🍷', '🍸', '🍺',
      ],
    },
    {
      'name': 'Objects',
      'icon': Icons.lightbulb_rounded,
      'emojis': [
        '💡', '🔦', '📱', '💻', '⌨️', '🖥️', '📷', '📸', '📹', '🎥',
        '📞', '☎️', '📺', '📻', '🎙️', '🧭', '⏱️', '⏰', '🕰️', '⌛',
        '🔋', '🔌', '💵', '💰', '💳', '💎', '🔑', '🔒', '🔓', '📌',
        '📍', '📎', '✂️', '✉️', '📦', '📝', '📚', '📖', '🚀', '✈️',
        '🚗', '🚲', '🚨', '🛑', '⚠️', '⛔', '🔔', '📢', '💬', '💭',
        '💯', '🟢', '🔴', '🟡', '🔵', '🟣', '🟠', '⚫', '⚪', '🏁',
      ],
    },
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _onTabSelected(int index) {
    setState(() => _selectedCategoryIndex = index);
    _pageController.jumpToPage(index);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 280,
      decoration: BoxDecoration(
        color: AppTheme.surface,
        border: Border(top: BorderSide(color: AppTheme.border.withValues(alpha: 0.8), width: 1)),
      ),
      child: Column(
        children: [
          // Header / Category Tabs Bar
          Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            decoration: BoxDecoration(
              color: AppTheme.surfaceElevated.withValues(alpha: 0.6),
              border: Border(bottom: BorderSide(color: AppTheme.border.withValues(alpha: 0.4))),
            ),
            child: Row(
              children: [
                Expanded(
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: _categories.length,
                    itemBuilder: (context, index) {
                      final cat = _categories[index];
                      final isSelected = _selectedCategoryIndex == index;
                      return InkWell(
                        onTap: () => _onTabSelected(index),
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
                          decoration: isSelected
                              ? BoxDecoration(
                                  color: AppTheme.mint.withValues(alpha: 0.16),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: AppTheme.mint.withValues(alpha: 0.4)),
                                )
                              : null,
                          child: Icon(
                            cat['icon'] as IconData,
                            size: 20,
                            color: isSelected ? AppTheme.mint : AppTheme.textMuted,
                          ),
                        ),
                      );
                    },
                  ),
                ),

                // Backspace Button
                IconButton(
                  icon: const Icon(Icons.backspace_outlined, size: 20, color: AppTheme.textSecondary),
                  tooltip: 'Backspace',
                  onPressed: widget.onBackspacePressed,
                ),

                if (widget.onClose != null)
                  IconButton(
                    icon: const Icon(Icons.keyboard_hide_rounded, size: 20, color: AppTheme.textMuted),
                    tooltip: 'Close Emoji Picker',
                    onPressed: widget.onClose,
                  ),
              ],
            ),
          ),

          // Emoji Grid View Pages
          Expanded(
            child: PageView.builder(
              controller: _pageController,
              itemCount: _categories.length,
              onPageChanged: (idx) {
                setState(() => _selectedCategoryIndex = idx);
              },
              itemBuilder: (context, pageIdx) {
                final emojis = _categories[pageIdx]['emojis'] as List<String>;
                return GridView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  physics: const BouncingScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 8,
                    crossAxisSpacing: 4,
                    mainAxisSpacing: 4,
                  ),
                  itemCount: emojis.length,
                  itemBuilder: (context, emojiIdx) {
                    final emoji = emojis[emojiIdx];
                    return InkWell(
                      onTap: () => widget.onEmojiSelected(emoji),
                      borderRadius: BorderRadius.circular(8),
                      child: Center(
                        child: Text(
                          emoji,
                          style: const TextStyle(fontSize: 24),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
