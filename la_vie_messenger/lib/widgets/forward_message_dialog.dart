import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../theme/app_theme.dart';
import '../services/chat_service.dart';
import '../services/media_storage_service.dart';

class ForwardMessageDialog extends StatefulWidget {
  final Map<String, dynamic> messageData;

  const ForwardMessageDialog({
    super.key,
    required this.messageData,
  });

  static Future<void> show(BuildContext context, Map<String, dynamic> messageData) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ForwardMessageDialog(messageData: messageData),
    );
  }

  @override
  State<ForwardMessageDialog> createState() => _ForwardMessageDialogState();
}

class _ForwardMessageDialogState extends State<ForwardMessageDialog> {
  final String? _myUid = FirebaseAuth.instance.currentUser?.uid;
  final String? _myName = FirebaseAuth.instance.currentUser?.displayName;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  final Set<String> _forwardingChatIds = {};

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _forwardToChat({
    required String chatId,
    required String targetName,
    required bool isGroup,
    List<String>? groupParticipants,
    String? peerUid,
  }) async {
    if (_myUid == null || _forwardingChatIds.contains(chatId)) return;
    setState(() => _forwardingChatIds.add(chatId));
    HapticFeedback.mediumImpact();

    try {
      final msg = widget.messageData;
      final text = msg['text'] as String? ?? '';
      final type = msg['type'] as String? ?? 'text';
      final mediaUrl = msg['mediaUrl'] as String?;
      final fileName = msg['fileName'] as String?;
      final fileSize = msg['fileSize'] as int?;
      final duration = msg['duration'] as int?;
      final localPath = msg['localPath'] as String?;

      await ChatService.sendMessage(
        chatId: chatId,
        senderId: _myUid,
        senderName: _myName ?? 'User',
        receiverId: isGroup ? chatId : (peerUid ?? ''),
        text: text,
        type: type,
        mediaUrl: mediaUrl,
        fileName: fileName,
        fileSize: fileSize,
        duration: duration,
        localPath: localPath,
        isGroup: isGroup,
        groupParticipants: groupParticipants,
      );

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppTheme.surfaceElevatedColor(context),
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: AppTheme.mint, size: 20),
                const SizedBox(width: 10),
                Text('Forwarded to $targetName', style: const TextStyle(color: Colors.white)),
              ],
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Forward failed: $e'), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _forwardingChatIds.remove(chatId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final bg = AppTheme.surfaceColor(context);
    final surfaceElevated = AppTheme.surfaceElevatedColor(context);
    final textPrim = AppTheme.text(context);
    final textSec = AppTheme.textSec(context);
    final textMuted = AppTheme.textMut(context);
    final border = AppTheme.borderColor(context);
    final mint = AppTheme.mintColor(context);

    return Container(
      height: MediaQuery.of(context).size.height * 0.72,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(color: border),
      ),
      child: Column(
        children: [
          // Drag handle
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: textMuted.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Forward Message',
                  style: TextStyle(color: textPrim, fontSize: 18, fontWeight: FontWeight.bold),
                ),
                IconButton(
                  icon: Icon(Icons.close_rounded, color: textMuted),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),

          // Search Bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Container(
              height: 42,
              decoration: BoxDecoration(
                color: surfaceElevated,
                borderRadius: BorderRadius.circular(21),
                border: Border.all(color: border),
              ),
              child: TextField(
                controller: _searchController,
                style: TextStyle(color: textPrim, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Search chats or contacts...',
                  hintStyle: TextStyle(color: textMuted, fontSize: 13.5),
                  prefixIcon: Icon(Icons.search_rounded, color: mint, size: 20),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 9),
                ),
                onChanged: (val) => setState(() => _searchQuery = val.trim().toLowerCase()),
              ),
            ),
          ),

          const SizedBox(height: 8),

          // Chat & Contacts List
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('chats')
                  .where('participants', arrayContains: _myUid)
                  .orderBy('lastMessageTime', descending: true)
                  .limit(30)
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return Center(child: CircularProgressIndicator(color: mint));
                }

                final docs = snapshot.data!.docs;
                final filteredDocs = docs.where((d) {
                  final data = d.data();
                  final isGroup = data['isGroup'] == true;
                  final name = (isGroup
                          ? (data['name'] ?? data['groupName'] ?? 'Group')
                          : (data['participants'] as List?)?.firstWhere((id) => id != _myUid, orElse: () => ''))
                      .toString()
                      .toLowerCase();

                  if (_searchQuery.isEmpty) return true;
                  return name.contains(_searchQuery);
                }).toList();

                if (filteredDocs.isEmpty) {
                  return Center(
                    child: Text('No conversations found', style: TextStyle(color: textMuted, fontSize: 14)),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  itemCount: filteredDocs.length,
                  itemBuilder: (context, index) {
                    final doc = filteredDocs[index];
                    final data = doc.data();
                    final chatId = doc.id;
                    final isGroup = data['isGroup'] == true;
                    final participants = List<String>.from(data['participants'] ?? []);
                    final peerUid = participants.firstWhere((id) => id != _myUid, orElse: () => '');

                    final displayName = isGroup
                        ? (data['name'] ?? data['groupName'] ?? 'Group') as String
                        : (data['peerNames']?[peerUid] ?? 'User') as String;
                    final avatar = isGroup ? data['avatar'] as String? : null;

                    final isForwarding = _forwardingChatIds.contains(chatId);

                    return ListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      leading: CircleAvatar(
                        radius: 20,
                        backgroundColor: surfaceElevated,
                        backgroundImage: MediaStorageService.getAvatarProvider(avatar),
                        child: (avatar == null || avatar.isEmpty)
                            ? Icon(isGroup ? Icons.groups_rounded : Icons.person_rounded, color: mint, size: 20)
                            : null,
                      ),
                      title: Text(
                        displayName,
                        style: TextStyle(color: textPrim, fontWeight: FontWeight.w600, fontSize: 14.5),
                      ),
                      subtitle: Text(
                        isGroup ? '${participants.length} members' : 'Direct Chat',
                        style: TextStyle(color: textSec, fontSize: 12),
                      ),
                      trailing: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: mint,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          elevation: 0,
                        ),
                        onPressed: isForwarding
                            ? null
                            : () => _forwardToChat(
                                  chatId: chatId,
                                  targetName: displayName,
                                  isGroup: isGroup,
                                  groupParticipants: participants,
                                  peerUid: peerUid,
                                ),
                        child: isForwarding
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                            : const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.send_rounded, size: 14),
                                  SizedBox(width: 4),
                                  Text('Send', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold)),
                                ],
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
