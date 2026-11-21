import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../theme/app_theme.dart';
import '../services/chat_service.dart';
import 'chat_conversation_screen.dart';

class StarredMessagesScreen extends StatefulWidget {
  const StarredMessagesScreen({super.key});

  @override
  State<StarredMessagesScreen> createState() => _StarredMessagesScreenState();
}

class _StarredMessagesScreenState extends State<StarredMessagesScreen> {
  final String? _myUid = FirebaseAuth.instance.currentUser?.uid;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _formatTimestamp(dynamic ts) {
    if (ts == null) return '';
    DateTime dt;
    if (ts is Timestamp) {
      dt = ts.toDate();
    } else {
      return '';
    }
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inDays == 0) return DateFormat('HH:mm').format(dt);
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return DateFormat('EEEE').format(dt);
    return DateFormat('d MMM yyyy').format(dt);
  }

  String _formatDateHeader(dynamic ts) {
    if (ts == null) return '';
    DateTime dt;
    if (ts is Timestamp) {
      dt = ts.toDate();
    } else {
      return '';
    }
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inDays == 0) return 'Today';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return DateFormat('EEEE').format(dt);
    return DateFormat('d MMMM yyyy').format(dt);
  }

  String _normalizeDate(dynamic ts) {
    if (ts == null) return '';
    if (ts is Timestamp) {
      final d = ts.toDate();
      return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    }
    return '';
  }

  Widget _buildMessagePreview(Map<String, dynamic> data) {
    final type = data['type'] as String? ?? 'text';
    final text = data['text'] as String? ?? '';
    final fileName = data['fileName'] as String?;
    final duration = data['duration'] as int?;

    switch (type) {
      case 'image':
        return Row(
          children: [
            const Icon(Icons.image_rounded, size: 14, color: AppTheme.textSecondary),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                text.isNotEmpty ? text : '📷 Photo',
                style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        );
      case 'audio':
        final mins = duration != null ? duration ~/ 60 : 0;
        final secs = duration != null ? (duration % 60).toString().padLeft(2, '0') : '00';
        return Row(
          children: [
            const Icon(Icons.mic_rounded, size: 14, color: AppTheme.textSecondary),
            const SizedBox(width: 4),
            Text('🎤 Voice note ${duration != null ? '($mins:$secs)' : ''}',
                style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
          ],
        );
      case 'file':
        return Row(
          children: [
            const Icon(Icons.insert_drive_file_rounded, size: 14, color: AppTheme.textSecondary),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                '📄 ${fileName ?? 'Document'}',
                style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        );
      default:
        return Text(
          text,
          style: const TextStyle(color: Colors.white, fontSize: 13.5),
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        );
    }
  }

  Widget _buildThumbnail(Map<String, dynamic> data) {
    final type = data['type'] as String? ?? 'text';
    final mediaUrl = data['mediaUrl'] as String?;

    if (type == 'image' && mediaUrl != null && mediaUrl.isNotEmpty) {
      if (mediaUrl.startsWith('data:')) {
        try {
          final bytes = base64Decode(mediaUrl.substring(mediaUrl.indexOf(',') + 1));
          return ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.memory(bytes, width: 56, height: 56, fit: BoxFit.cover),
          );
        } catch (_) {}
      } else {
        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.network(
            mediaUrl,
            width: 56,
            height: 56,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _mediaIcon(Icons.broken_image_rounded),
          ),
        );
      }
    }

    switch (type) {
      case 'audio':
        return _mediaIcon(Icons.mic_rounded, color: AppTheme.lilacDark);
      case 'file':
        return _mediaIcon(Icons.insert_drive_file_rounded, color: AppTheme.lilacDark);
      case 'image':
        return _mediaIcon(Icons.image_rounded, color: AppTheme.lilacDark);
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _mediaIcon(IconData icon, {Color color = AppTheme.mint}) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: AppTheme.surfaceElevated,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.border),
      ),
      child: Icon(icon, color: color, size: 24),
    );
  }

  void _unstarMessage(String messageId) async {
    if (_myUid == null) return;
    await FirebaseFirestore.instance
        .collection('users')
        .doc(_myUid)
        .collection('starredMessages')
        .doc(messageId)
        .delete();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppTheme.surfaceElevated,
          behavior: SnackBarBehavior.floating,
          content: const Row(
            children: [
              Icon(Icons.star_outline_rounded, color: AppTheme.mint, size: 18),
              SizedBox(width: 8),
              Text('Message unstarred', style: TextStyle(color: Colors.white)),
            ],
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _jumpToChat(BuildContext context, Map<String, dynamic> data) async {
    final chatId = data['chatId'] as String?;
    final isGroup = data['isGroup'] as bool? ?? false;
    final senderName = data['senderName'] as String? ?? 'Chat';

    if (chatId == null) return;

    // Fetch the chat document to get peer info
    final chatDoc = await FirebaseFirestore.instance.collection('chats').doc(chatId).get();
    if (!chatDoc.exists) return;

    final chatData = chatDoc.data()!;
    final participants = List<String>.from(chatData['participants'] ?? []);
    final peerUid = isGroup
        ? chatId
        : participants.firstWhere((uid) => uid != _myUid, orElse: () => chatId);
    final peerName = isGroup ? (chatData['groupName'] as String? ?? senderName) : senderName;
    final peerAvatar = chatData['groupAvatar'] as String?;

    if (!context.mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatConversationScreen(
          peerUid: peerUid,
          peerName: peerName,
          peerAvatar: peerAvatar,
          isGroup: isGroup,
          chatIdOverride: chatId,
          groupParticipants: isGroup ? participants : null,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_myUid == null) {
      return const Scaffold(
        backgroundColor: AppTheme.background,
        body: Center(child: Text('Not signed in', style: TextStyle(color: Colors.white54))),
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Starred Messages',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 17,
              ),
            ),
            Text(
              'Your bookmarked messages',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 11.5),
            ),
          ],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Container(
              height: 40,
              decoration: BoxDecoration(
                color: AppTheme.surfaceElevated,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppTheme.border),
              ),
              child: TextField(
                controller: _searchController,
                onChanged: (v) => setState(() => _searchQuery = v.trim().toLowerCase()),
                style: const TextStyle(color: Colors.white, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Search starred messages...',
                  hintStyle: const TextStyle(color: AppTheme.textMuted, fontSize: 13),
                  prefixIcon: Icon(
                    Icons.search_rounded,
                    color: _searchQuery.isNotEmpty ? AppTheme.mint : AppTheme.textMuted,
                    size: 18,
                  ),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.close_rounded, color: AppTheme.textMuted, size: 16),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
          ),
        ),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: ChatService.streamStarredMessages(_myUid),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: AppTheme.mint, strokeWidth: 2),
            );
          }

          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 48),
                  const SizedBox(height: 12),
                  Text('Error loading starred messages', style: TextStyle(color: Colors.white54)),
                ],
              ),
            );
          }

          var docs = snapshot.data?.docs ?? [];

          // Apply search filter
          if (_searchQuery.isNotEmpty) {
            docs = docs.where((doc) {
              final data = doc.data();
              final text = (data['text'] as String? ?? '').toLowerCase();
              final sender = (data['senderName'] as String? ?? '').toLowerCase();
              final fileName = (data['fileName'] as String? ?? '').toLowerCase();
              return text.contains(_searchQuery) ||
                  sender.contains(_searchQuery) ||
                  fileName.contains(_searchQuery);
            }).toList();
          }

          if (docs.isEmpty) {
            return _buildEmptyState();
          }

          // Build grouped list with date headers
          final List<dynamic> items = [];
          String? lastDate;
          for (final doc in docs) {
            final data = doc.data();
            final starredAt = data['starredAt'];
            final dateKey = _normalizeDate(starredAt);
            if (dateKey != lastDate) {
              items.add({'_type': 'header', 'date': starredAt});
              lastDate = dateKey;
            }
            items.add({'_type': 'message', 'doc': doc});
          }

          return ListView.builder(
            padding: const EdgeInsets.only(top: 8, bottom: 24),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index] as Map<String, dynamic>;

              if (item['_type'] == 'header') {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
                  child: Row(
                    children: [
                      Text(
                        _formatDateHeader(item['date']),
                        style: const TextStyle(
                          color: AppTheme.textMuted,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Expanded(child: Divider(color: AppTheme.border, thickness: 1)),
                    ],
                  ),
                );
              }

              final doc = item['doc'] as QueryDocumentSnapshot<Map<String, dynamic>>;
              final data = doc.data();
              final messageId = doc.id;
              final type = data['type'] as String? ?? 'text';
              final senderName = data['senderName'] as String? ?? '';
              final isMe = data['senderId'] == _myUid;
              final starredAt = data['starredAt'];
              final hasThumbnail = type == 'image' || type == 'audio' || type == 'file';

              return Dismissible(
                key: Key(messageId),
                direction: DismissDirection.endToStart,
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 24),
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.star_outline_rounded, color: Colors.redAccent, size: 22),
                      SizedBox(height: 4),
                      Text('Unstar', style: TextStyle(color: Colors.redAccent, fontSize: 11)),
                    ],
                  ),
                ),
                confirmDismiss: (_) async => true,
                onDismissed: (_) => _unstarMessage(messageId),
                child: GestureDetector(
                  onLongPress: () {
                    HapticFeedback.mediumImpact();
                    _showItemOptions(context, messageId, data);
                  },
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppTheme.border),
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => _jumpToChat(context, data),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Row 1: sender + star icon + time
                            Row(
                              children: [
                                Container(
                                  width: 7,
                                  height: 7,
                                  margin: const EdgeInsets.only(right: 8),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: isMe ? AppTheme.lilacDark : AppTheme.mint,
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    isMe ? 'You' : senderName,
                                    style: TextStyle(
                                      color: isMe ? AppTheme.lilacLight : AppTheme.mint,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const Icon(Icons.star_rounded, color: Color(0xFFF59E0B), size: 14),
                                const SizedBox(width: 6),
                                Text(
                                  _formatTimestamp(starredAt),
                                  style: const TextStyle(
                                    color: AppTheme.textMuted,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),

                            // Row 2: thumbnail + message content
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (hasThumbnail) ...[
                                  _buildThumbnail(data),
                                  const SizedBox(width: 10),
                                ],
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      _buildMessagePreview(data),
                                    ],
                                  ),
                                ),
                              ],
                            ),

                            // Jump-to-chat hint
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                const Icon(Icons.open_in_new_rounded, color: AppTheme.textMuted, size: 12),
                                const SizedBox(width: 4),
                                const Text(
                                  'Tap to jump to chat',
                                  style: TextStyle(color: AppTheme.textMuted, fontSize: 11),
                                ),
                                const Spacer(),
                                GestureDetector(
                                  onTap: () => _unstarMessage(messageId),
                                  child: const Row(
                                    children: [
                                      Icon(Icons.star_rounded, color: Color(0xFFF59E0B), size: 14),
                                      SizedBox(width: 3),
                                      Text('Starred', style: TextStyle(color: Color(0xFFF59E0B), fontSize: 11)),
                                    ],
                                  ),
                                ),
                              ],
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
        },
      ),
    );
  }

  void _showItemOptions(
    BuildContext context,
    String messageId,
    Map<String, dynamic> data,
  ) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.open_in_new_rounded, color: AppTheme.mint),
              title: const Text('Jump to Chat', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
              onTap: () {
                Navigator.pop(context);
                _jumpToChat(context, data);
              },
            ),
            if ((data['text'] as String? ?? '').isNotEmpty && data['type'] == 'text')
              ListTile(
                leading: const Icon(Icons.copy_rounded, color: AppTheme.textSecondary),
                title: const Text('Copy Text', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(context);
                  Clipboard.setData(ClipboardData(text: data['text'] as String));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Copied to clipboard'),
                      duration: Duration(seconds: 1),
                    ),
                  );
                },
              ),
            ListTile(
              leading: const Icon(Icons.star_outline_rounded, color: Colors.redAccent),
              title: const Text('Remove Star', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w600)),
              onTap: () {
                Navigator.pop(context);
                _unstarMessage(messageId);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  AppTheme.lilacDark.withValues(alpha: 0.25),
                  Colors.transparent,
                ],
              ),
            ),
            child: const Icon(
              Icons.star_rounded,
              color: Color(0xFFF59E0B),
              size: 44,
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'No Starred Messages',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 48),
            child: Text(
              _searchQuery.isEmpty
                  ? 'Long-press any message in a chat\nand tap ⭐ Star to bookmark it here.'
                  : 'No matches found for your search.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppTheme.textMuted, fontSize: 14, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}
