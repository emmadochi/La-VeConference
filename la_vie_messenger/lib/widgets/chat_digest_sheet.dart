import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';
import '../services/ai_service.dart';

class ChatDigestSheet extends StatefulWidget {
  final List<Map<String, dynamic>> messages;
  final String targetUserName;
  final String chatTitle;
  final Function(String text)? onShareToChat;

  const ChatDigestSheet({
    super.key,
    required this.messages,
    required this.targetUserName,
    required this.chatTitle,
    this.onShareToChat,
  });

  static Future<void> show(
    BuildContext context, {
    required List<Map<String, dynamic>> messages,
    required String targetUserName,
    required String chatTitle,
    Function(String text)? onShareToChat,
  }) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => ChatDigestSheet(
        messages: messages,
        targetUserName: targetUserName,
        chatTitle: chatTitle,
        onShareToChat: onShareToChat,
      ),
    );
  }

  @override
  State<ChatDigestSheet> createState() => _ChatDigestSheetState();
}

class _ChatDigestSheetState extends State<ChatDigestSheet> {
  bool _isLoading = true;
  AIChatDigestResult? _digest;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadDigest();
  }

  Future<void> _loadDigest() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final res = await AIService.generateChatDigest(
        messages: widget.messages,
        targetUserName: widget.targetUserName,
        chatTitle: widget.chatTitle,
      );
      if (mounted) {
        setState(() {
          _digest = res;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  void _copyToClipboard() {
    if (_digest == null) return;
    final buffer = StringBuffer();
    buffer.writeln("✨ LiChat AI Catch-Up Digest for ${widget.chatTitle}");
    buffer.writeln("\n📌 Summary:\n${_digest!.summary}");
    if (_digest!.decisions.isNotEmpty) {
      buffer.writeln("\n🎯 Decisions Made:");
      for (final d in _digest!.decisions) {
        buffer.writeln("• $d");
      }
    }
    if (_digest!.actionItems.isNotEmpty) {
      buffer.writeln("\n⚡ Action Items:");
      for (final a in _digest!.actionItems) {
        buffer.writeln("• $a");
      }
    }
    Clipboard.setData(ClipboardData(text: buffer.toString()));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Digest copied to clipboard 📋")),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.72,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(
                color: AppTheme.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF7B1FA2), Color(0xFF00ACC1)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Catch Me Up",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      "Executive AI Digest • ${widget.messages.length} messages analyzed",
                      style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                    ),
                  ],
                ),
              ),
              if (_digest != null)
                IconButton(
                  onPressed: _copyToClipboard,
                  icon: const Icon(Icons.copy_rounded, color: Colors.white70, size: 20),
                  tooltip: "Copy digest",
                ),
            ],
          ),
          const SizedBox(height: 16),

          // Content
          Expanded(
            child: _isLoading
                ? _buildLoadingState()
                : _errorMessage != null
                    ? _buildErrorState()
                    : _buildDigestContent(),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const CircularProgressIndicator(
              strokeWidth: 3,
              color: AppTheme.primary,
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            "Analyzing conversation...",
            style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          const Text(
            "Extracting key decisions, tasks, and summary points",
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline_rounded, color: Colors.orangeAccent, size: 40),
          const SizedBox(height: 12),
          const Text(
            "Could not generate AI digest",
            style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          Text(
            _errorMessage ?? "Unknown error",
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _loadDigest,
            icon: const Icon(Icons.refresh_rounded, size: 16),
            label: const Text("Try Again"),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
          ),
        ],
      ),
    );
  }

  Widget _buildDigestContent() {
    final d = _digest!;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Summary Section
          _buildCardSection(
            icon: Icons.notes_rounded,
            title: "Executive Summary",
            color: const Color(0xFF00ACC1),
            child: Text(
              d.summary,
              style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.45),
            ),
          ),
          const SizedBox(height: 14),

          // Decisions Made
          if (d.decisions.isNotEmpty) ...[
            _buildCardSection(
              icon: Icons.check_circle_outline_rounded,
              title: "Decisions & Agreements",
              color: Colors.greenAccent,
              child: Column(
                children: d.decisions
                    .map((item) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.done_all_rounded, color: Colors.greenAccent, size: 16),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(item, style: const TextStyle(color: Colors.white70, fontSize: 13)),
                              ),
                            ],
                          ),
                        ))
                    .toList(),
              ),
            ),
            const SizedBox(height: 14),
          ],

          // Action Items
          if (d.actionItems.isNotEmpty) ...[
            _buildCardSection(
              icon: Icons.bolt_rounded,
              title: "Action Items & Tasks",
              color: Colors.amberAccent,
              child: Column(
                children: d.actionItems
                    .map((item) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.arrow_forward_rounded, color: Colors.amberAccent, size: 16),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(item, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500)),
                              ),
                            ],
                          ),
                        ))
                    .toList(),
              ),
            ),
            const SizedBox(height: 14),
          ],

          // Key Topics Chips
          if (d.keyTopics.isNotEmpty) ...[
            const Text(
              "Topics Explored",
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 12, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: d.keyTopics
                  .map((t) => Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppTheme.background,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppTheme.border),
                        ),
                        child: Text(
                          "#$t",
                          style: const TextStyle(color: AppTheme.primary, fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 20),
          ],

          // Bottom Action: Share to chat
          if (widget.onShareToChat != null)
            SizedBox(
              width: double.infinity,
              height: 44,
              child: ElevatedButton.icon(
                onPressed: () {
                  final text = "✨ *AI Catch-Up Digest:*\n${d.summary}";
                  widget.onShareToChat!(text);
                  Navigator.pop(context);
                },
                icon: const Icon(Icons.share_rounded, size: 16, color: Colors.white),
                label: const Text("Share Summary in Chat", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _buildCardSection({
    required IconData icon,
    required String title,
    required Color color,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.background,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

