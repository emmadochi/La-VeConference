import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../theme/app_theme.dart';
import '../services/chat_service.dart';
import '../services/media_storage_service.dart';

/// Modal bottom sheet showing who has read and received a message.
/// Similar to WhatsApp's "Message Info" screen.
class MessageInfoSheet extends StatelessWidget {
  final String chatId;
  final String messageId;
  final Map<String, dynamic> initialData;
  final bool isGroup;
  final List<String>? groupParticipants;

  const MessageInfoSheet({
    super.key,
    required this.chatId,
    required this.messageId,
    required this.initialData,
    required this.isGroup,
    this.groupParticipants,
  });

  static void show(
    BuildContext context, {
    required String chatId,
    required String messageId,
    required Map<String, dynamic> messageData,
    required bool isGroup,
    List<String>? groupParticipants,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surfaceColor(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => MessageInfoSheet(
        chatId: chatId,
        messageId: messageId,
        initialData: messageData,
        isGroup: isGroup,
        groupParticipants: groupParticipants,
      ),
    );
  }

  String _formatDateTime(dynamic timestampVal) {
    if (timestampVal == null) return 'Pending';
    DateTime? dt;
    if (timestampVal is Timestamp) {
      dt = timestampVal.toDate();
    } else if (timestampVal is String) {
      dt = DateTime.tryParse(timestampVal);
    }
    if (dt == null) return '';

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final msgDate = DateTime(dt.year, dt.month, dt.day);

    final timeStr = DateFormat('h:mm a').format(dt);
    if (msgDate == today) {
      return 'Today, $timeStr';
    } else if (msgDate == today.subtract(const Duration(days: 1))) {
      return 'Yesterday, $timeStr';
    } else {
      return '${DateFormat('MMM d').format(dt)}, $timeStr';
    }
  }

  @override
  Widget build(BuildContext context) {
    final senderId = initialData['senderId'] as String? ?? '';
    final text = initialData['text'] as String? ?? '';
    final type = initialData['type'] as String? ?? 'text';
    final timestamp = initialData['timestamp'];
    final timeStr = _formatDateTime(timestamp);

    return SafeArea(
      child: Container(
        height: MediaQuery.of(context).size.height * 0.82,
        padding: const EdgeInsets.only(top: 10),
        child: Column(
          children: [
            // Handle bar
            Container(
              width: 38,
              height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: AppTheme.borderColor(context),
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // Top Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
              child: Row(
                children: [
                  Icon(Icons.info_outline_rounded, color: AppTheme.primaryAccent(context), size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Message Info',
                      style: TextStyle(
                        color: AppTheme.text(context),
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close_rounded, color: AppTheme.textSec(context), size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            const Divider(height: 1),

            Expanded(
              child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                stream: ChatService.streamMessage(chatId: chatId, messageId: messageId),
                builder: (context, snapshot) {
                  final data = snapshot.data?.data() ?? initialData;
                  final readByMap = Map<String, dynamic>.from(data['readBy'] ?? {});
                  final deliveredToMap = Map<String, dynamic>.from(data['deliveredTo'] ?? {});

                  // Filter out sender from readBy & deliveredTo lists
                  final readUids = readByMap.keys.where((uid) => uid != senderId).toList();
                  final deliveredOnlyUids = deliveredToMap.keys
                      .where((uid) => uid != senderId && !readByMap.containsKey(uid))
                      .toList();

                  final totalPossible = (groupParticipants ?? []).where((uid) => uid != senderId).length;

                  return ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                    children: [
                      // 1. Message Bubble Preview Card
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppTheme.surfaceElevatedColor(context),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppTheme.borderColor(context)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (type == 'image') ...[
                              Row(
                                children: [
                                  Icon(Icons.image_rounded, color: AppTheme.primaryAccent(context), size: 18),
                                  const SizedBox(width: 6),
                                  Text('Photo',
                                      style: TextStyle(
                                          color: AppTheme.primaryAccent(context),
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13)),
                                ],
                              ),
                              const SizedBox(height: 6),
                            ] else if (type == 'audio') ...[
                              Row(
                                children: [
                                  Icon(Icons.mic_rounded, color: AppTheme.primaryAccent(context), size: 18),
                                  const SizedBox(width: 6),
                                  Text('Voice Note',
                                      style: TextStyle(
                                          color: AppTheme.primaryAccent(context),
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13)),
                                ],
                              ),
                              const SizedBox(height: 6),
                            ] else if (type == 'file') ...[
                              Row(
                                children: [
                                  Icon(Icons.insert_drive_file_rounded, color: AppTheme.primaryAccent(context), size: 18),
                                  const SizedBox(width: 6),
                                  Text(data['fileName'] as String? ?? 'Document',
                                      style: TextStyle(
                                          color: AppTheme.primaryAccent(context),
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13)),
                                ],
                              ),
                              const SizedBox(height: 6),
                            ],
                            if (text.isNotEmpty)
                              Text(
                                text,
                                style: TextStyle(
                                  color: AppTheme.text(context),
                                  fontSize: 15,
                                  height: 1.35,
                                ),
                              ),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                Text(
                                  'Sent: $timeStr',
                                  style: TextStyle(color: AppTheme.textMut(context), fontSize: 11.5),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 22),

                      // 2. Read By Section
                      _sectionTitle(
                        context,
                        title: isGroup
                            ? 'Read by (${readUids.length}${totalPossible > 0 ? ' of $totalPossible' : ''})'
                            : 'Read',
                        icon: Icons.done_all_rounded,
                        iconColor: const Color(0xFF38BDF8), // Blue double tick
                      ),
                      const SizedBox(height: 8),

                      if (readUids.isEmpty)
                        _emptyRow(context, 'No one has read this message yet.')
                      else
                        ...readUids.map((uid) {
                          final readAt = readByMap[uid];
                          return _buildMemberTile(context, uid: uid, timestampVal: readAt, isRead: true);
                        }),

                      const SizedBox(height: 22),

                      // 3. Delivered To Section
                      _sectionTitle(
                        context,
                        title: isGroup
                            ? 'Delivered to (${deliveredOnlyUids.length})'
                            : 'Delivered',
                        icon: Icons.done_all_rounded,
                        iconColor: AppTheme.textSec(context), // Grey double tick
                      ),
                      const SizedBox(height: 8),

                      if (deliveredOnlyUids.isEmpty)
                        _emptyRow(context, readUids.isNotEmpty ? 'Delivered to all active readers.' : 'Delivering...')
                      else
                        ...deliveredOnlyUids.map((uid) {
                          final deliveredAt = deliveredToMap[uid];
                          return _buildMemberTile(context, uid: uid, timestampVal: deliveredAt, isRead: false);
                        }),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, {required String title, required IconData icon, required Color iconColor}) {
    return Row(
      children: [
        Icon(icon, color: iconColor, size: 18),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            color: AppTheme.text(context),
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
      ],
    );
  }

  Widget _emptyRow(BuildContext context, String message) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.surfaceElevatedColor(context).withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.borderColor(context)),
      ),
      child: Text(
        message,
        style: TextStyle(color: AppTheme.textMut(context), fontSize: 13, fontStyle: FontStyle.italic),
      ),
    );
  }

  Widget _buildMemberTile(
    BuildContext context, {
    required String uid,
    required dynamic timestampVal,
    required bool isRead,
  }) {
    final formattedTime = _formatDateTime(timestampVal);

    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: FirebaseFirestore.instance.collection('users').doc(uid).get(),
      builder: (context, snapshot) {
        final userData = snapshot.data?.data() ?? {};
        final name = (userData['name'] ?? userData['displayName'] ?? 'Member') as String;
        final avatar = userData['photoUrl'] as String?;

        return Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: AppTheme.surfaceElevatedColor(context),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.borderColor(context)),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: AppTheme.primaryAccent(context).withValues(alpha: 0.15),
                backgroundImage: MediaStorageService.getAvatarProvider(avatar),
                child: (avatar == null || avatar.isEmpty)
                    ? Text(
                        name.isNotEmpty ? name[0].toUpperCase() : 'M',
                        style: TextStyle(
                          color: AppTheme.primaryAccent(context),
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  name,
                  style: TextStyle(
                    color: AppTheme.text(context),
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.done_all_rounded,
                    color: isRead ? const Color(0xFF38BDF8) : AppTheme.textSec(context),
                    size: 16,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    formattedTime,
                    style: TextStyle(
                      color: AppTheme.textSec(context),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
