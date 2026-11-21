import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/chat_service.dart';
import '../theme/app_theme.dart';

class PollMessageBubble extends StatelessWidget {
  final String chatId;
  final String messageId;
  final Map<String, dynamic> pollData;
  final bool isMe;

  const PollMessageBubble({
    super.key,
    required this.chatId,
    required this.messageId,
    required this.pollData,
    required this.isMe,
  });

  @override
  Widget build(BuildContext context) {
    final myUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final question = pollData['question'] as String? ?? 'Poll';
    final allowMultiple = pollData['allowMultiple'] == true;
    final options = List<Map<String, dynamic>>.from(
      (pollData['options'] as List? ?? []).map((o) => Map<String, dynamic>.from(o as Map)),
    );
    final totalVotes = (pollData['totalVotes'] as num?)?.toInt() ?? 0;

    final isDark = AppTheme.isDarkMode(context);
    final mint = AppTheme.mintColor(context);
    final textPrim = isMe ? Colors.white : AppTheme.text(context);
    final textMuted = isMe ? Colors.white70 : AppTheme.textMut(context);
    final surface = isMe ? Colors.black.withValues(alpha: 0.15) : AppTheme.surfaceElevatedColor(context);
    final border = isMe ? Colors.white.withValues(alpha: 0.2) : AppTheme.borderColor(context);

    return Container(
      constraints: const BoxConstraints(minWidth: 240, maxWidth: 320),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Question Header
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: mint.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.poll_rounded, color: mint, size: 16),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  question,
                  style: TextStyle(
                    color: textPrim,
                    fontSize: 15.5,
                    fontWeight: FontWeight.bold,
                    height: 1.3,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            allowMultiple ? 'Select one or more' : 'Select one',
            style: TextStyle(
              color: textMuted,
              fontSize: 11.5,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 12),

          // Options List
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: options.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, idx) {
              final opt = options[idx];
              final optId = opt['id']?.toString() ?? idx.toString();
              final optText = opt['text'] as String? ?? '';
              final voterUids = List<String>.from(opt['voterUids'] ?? []);
              final voteCount = voterUids.length;
              final hasVoted = voterUids.contains(myUid);

              final percentage = totalVotes > 0 ? (voteCount / totalVotes) : 0.0;

              return InkWell(
                onTap: () {
                  HapticFeedback.selectionClick();
                  ChatService.votePoll(
                    chatId: chatId,
                    messageId: messageId,
                    optionId: optId,
                    voterUid: myUid,
                  );
                },
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: hasVoted ? mint : border,
                      width: hasVoted ? 1.6 : 1.0,
                    ),
                  ),
                  child: Stack(
                    children: [
                      // Animated Progress Bar Fill
                      Positioned.fill(
                        child: FractionallySizedBox(
                          alignment: Alignment.centerLeft,
                          widthFactor: percentage.clamp(0.0, 1.0),
                          child: Container(
                            color: mint.withValues(alpha: isDark ? 0.22 : 0.15),
                          ),
                        ),
                      ),

                      // Option Content
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        child: Row(
                          children: [
                            Icon(
                              allowMultiple
                                  ? (hasVoted ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded)
                                  : (hasVoted ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded),
                              color: hasVoted ? mint : textMuted,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                optText,
                                style: TextStyle(
                                  color: textPrim,
                                  fontSize: 14,
                                  fontWeight: hasVoted ? FontWeight.bold : FontWeight.w500,
                                ),
                              ),
                            ),
                            if (totalVotes > 0) ...[
                              const SizedBox(width: 6),
                              Text(
                                '${(percentage * 100).round()}%',
                                style: TextStyle(
                                  color: hasVoted ? mint : textMuted,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),

          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '$totalVotes vote${totalVotes == 1 ? '' : 's'}',
                style: TextStyle(
                  color: textMuted,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Icon(Icons.touch_app_rounded, color: textMuted, size: 14),
            ],
          ),
        ],
      ),
    );
  }
}
