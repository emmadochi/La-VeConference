import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../theme/app_theme.dart';
import '../services/chat_service.dart';
import '../services/contact_service.dart';
import '../services/media_storage_service.dart';
import '../screens/chat_conversation_screen.dart';
import '../screens/create_media_status_screen.dart';
import '../screens/create_text_status_screen.dart';

class IncomingShareDialog extends StatefulWidget {
  final String mimeType;
  final String text;
  final List<String> files;

  const IncomingShareDialog({
    super.key,
    required this.mimeType,
    required this.text,
    required this.files,
  });

  static Future<void> show(
    BuildContext context, {
    required String mimeType,
    required String text,
    required List<String> files,
  }) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      builder: (ctx) => IncomingShareDialog(
        mimeType: mimeType,
        text: text,
        files: files,
      ),
    );
  }

  @override
  State<IncomingShareDialog> createState() => _IncomingShareDialogState();
}

class _IncomingShareDialogState extends State<IncomingShareDialog> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String? _myUid;

  @override
  void initState() {
    super.initState();
    final user = FirebaseAuth.instance.currentUser;
    _myUid = user?.uid;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _shareToStatus() {
    Navigator.pop(context);
    final files = widget.files;
    final text = widget.text;

    if (files.isNotEmpty) {
      final firstPath = files.first;
      final file = File(firstPath);
      final pathLower = firstPath.toLowerCase();
      final isVideo = pathLower.endsWith('.mp4') || pathLower.endsWith('.mkv') || pathLower.endsWith('.mov') || pathLower.endsWith('.3gp');

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => CreateMediaStatusScreen(
            file: file,
            type: isVideo ? 'video' : 'image',
          ),
        ),
      );
    } else if (text.isNotEmpty) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => CreateTextStatusScreen(
            initialText: text,
          ),
        ),
      );
    }
  }

  bool _isSending = false;
  String? _sendingToId;

  Future<void> _directSendTo({
    required String peerUid,
    required String peerName,
    String? peerAvatar,
    bool isGroup = false,
    String? chatIdOverride,
    List<String>? groupParticipants,
  }) async {
    if (_isSending || _myUid == null) return;
    setState(() {
      _isSending = true;
      _sendingToId = peerUid;
    });

    try {
      final chatId = chatIdOverride ??
          (isGroup ? peerUid : ChatService.getConversationId(_myUid!, peerUid));
      final user = FirebaseAuth.instance.currentUser;
      final myName = user?.displayName ?? 'User';

      final files = widget.files;
      final text = widget.text.trim();

      if (files.isNotEmpty) {
        for (int i = 0; i < files.length; i++) {
          final filePath = files[i];
          final file = File(filePath);
          if (!await file.exists()) continue;

          final pathLower = filePath.toLowerCase();
          final fileName = file.uri.pathSegments.isNotEmpty
              ? file.uri.pathSegments.last
              : 'file_${DateTime.now().millisecondsSinceEpoch}';
          final fileSize = await file.length();
          final isLast = i == files.length - 1;

          String type = 'file';
          String category = 'Documents';
          String mime = 'application/octet-stream';

          if (pathLower.endsWith('.jpg') ||
              pathLower.endsWith('.jpeg') ||
              pathLower.endsWith('.png') ||
              pathLower.endsWith('.webp') ||
              pathLower.endsWith('.gif')) {
            type = 'image';
            category = 'Images';
            mime = 'image/jpeg';
          } else if (pathLower.endsWith('.mp4') ||
              pathLower.endsWith('.mkv') ||
              pathLower.endsWith('.mov') ||
              pathLower.endsWith('.3gp')) {
            type = 'video';
            category = 'Videos';
            mime = 'video/mp4';
          } else if (pathLower.endsWith('.mp3') ||
              pathLower.endsWith('.m4a') ||
              pathLower.endsWith('.wav') ||
              pathLower.endsWith('.aac') ||
              pathLower.endsWith('.ogg')) {
            type = 'audio';
            category = 'VoiceNotes';
            mime = 'audio/m4a';
          }

          final localFile = await MediaStorageService.saveOutgoingFile(
            sourceFile: file,
            category: category,
            targetFileName: fileName,
          );

          final remoteUrl = await MediaStorageService.uploadEphemeralMedia(
            file: localFile,
            chatId: chatId,
            fileName: fileName,
            contentType: mime,
          );

          await ChatService.sendMessage(
            chatId: chatId,
            senderId: _myUid!,
            senderName: myName,
            receiverId: peerUid,
            text: (isLast && text.isNotEmpty)
                ? text
                : (type == 'image'
                    ? 'Photo'
                    : type == 'video'
                        ? 'Video'
                        : fileName),
            type: type,
            mediaUrl: remoteUrl,
            fileName: fileName,
            fileSize: fileSize,
            localPath: localFile.path,
            isGroup: isGroup,
            groupParticipants: groupParticipants,
          );
        }
      } else if (text.isNotEmpty) {
        await ChatService.sendMessage(
          chatId: chatId,
          senderId: _myUid!,
          senderName: myName,
          receiverId: peerUid,
          text: text,
          type: 'text',
          isGroup: isGroup,
          groupParticipants: groupParticipants,
        );
      }

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: AppTheme.mint, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Sent to $peerName',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            backgroundColor: AppTheme.surfaceElevated,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error direct sending to contact: $e');
      if (mounted) {
        setState(() {
          _isSending = false;
          _sendingToId = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  void _shareToChat({
    required String peerUid,
    required String peerName,
    String? peerAvatar,
    bool isGroup = false,
    String? chatIdOverride,
    List<String>? groupParticipants,
  }) {
    Navigator.pop(context);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatConversationScreen(
          peerUid: peerUid,
          peerName: peerName,
          peerAvatar: peerAvatar,
          isGroup: isGroup,
          chatIdOverride: chatIdOverride,
          groupParticipants: groupParticipants,
          initialText: widget.text.isNotEmpty ? widget.text : null,
          initialFiles: widget.files.isNotEmpty ? widget.files : null,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bg = AppTheme.surfaceColor(context);
    final surfaceElevated = AppTheme.surfaceElevatedColor(context);
    final border = AppTheme.borderColor(context);
    final mint = AppTheme.mint;
    final textPrim = AppTheme.text(context);
    final textSec = AppTheme.textSec(context);
    final textMuted = AppTheme.textMut(context);
    final user = FirebaseAuth.instance.currentUser;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.88,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(color: border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 20,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 10, bottom: 6),
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: textMuted.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
            child: Row(
              children: [
                Icon(Icons.send_to_mobile_rounded, color: mint, size: 24),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Share to LiChat',
                        style: TextStyle(
                          color: textPrim,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        widget.files.isNotEmpty
                            ? '${widget.files.length} item${widget.files.length == 1 ? '' : 's'} to share'
                            : 'Text message to share',
                        style: TextStyle(color: textMuted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.close_rounded, color: textMuted),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),

          // Preview Card
          _buildPreviewCard(surfaceElevated, border, mint, textPrim, textMuted),

          const SizedBox(height: 8),

          // Search Field
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
                onChanged: (v) => setState(() => _searchQuery = v.trim().toLowerCase()),
                style: TextStyle(color: textPrim, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Search chats & contacts...',
                  hintStyle: TextStyle(color: textMuted, fontSize: 13.5),
                  prefixIcon: Icon(Icons.search_rounded, color: textMuted, size: 20),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: Icon(Icons.close_rounded, color: textMuted, size: 16),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 9),
                ),
              ),
            ),
          ),

          const SizedBox(height: 6),

          // Content List
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              children: [
                // "My Status" Option
                if (_searchQuery.isEmpty) ...[
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    onTap: _shareToStatus,
                    leading: Stack(
                      children: [
                        CircleAvatar(
                          radius: 24,
                          backgroundColor: surfaceElevated,
                          backgroundImage: MediaStorageService.getAvatarProvider(user?.photoURL),
                          child: user?.photoURL == null
                              ? Icon(Icons.person_rounded, color: textMuted, size: 26)
                              : null,
                        ),
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: Container(
                            width: 18,
                            height: 18,
                            decoration: BoxDecoration(
                              color: mint,
                              shape: BoxShape.circle,
                              border: Border.all(color: bg, width: 2),
                            ),
                            child: const Icon(Icons.add, size: 12, color: Colors.black),
                          ),
                        ),
                      ],
                    ),
                    title: Text(
                      'My Status',
                      style: TextStyle(
                        color: textPrim,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    subtitle: Text(
                      'Share to your 24h status',
                      style: TextStyle(color: textMuted, fontSize: 12.5),
                    ),
                    trailing: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: mint.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.arrow_forward_ios_rounded, color: mint, size: 14),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
                    child: Text(
                      'CHATS & CONTACTS',
                      style: TextStyle(
                        color: textMuted,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                ],

                // 2. Stream Recent Conversations & Paired Contacts
                if (_myUid != null)
                  StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: ChatService.streamConversations(_myUid!),
                    builder: (context, snapshot) {
                      final rawDocs = snapshot.data?.docs ?? [];
                      final recentPeerUids = <String>{};

                      for (final doc in rawDocs) {
                        final data = doc.data();
                        final isGroup = data['isGroup'] == true;
                        if (!isGroup) {
                          final participants = List<String>.from(data['participants'] ?? []);
                          final peerUid = participants.firstWhere(
                            (id) => id != _myUid,
                            orElse: () {
                              final parts = doc.id.split('_');
                              return parts.firstWhere((p) => p != _myUid, orElse: () => '');
                            },
                          );
                          if (peerUid.isNotEmpty) {
                            recentPeerUids.add(peerUid);
                          }
                        }
                      }

                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ...rawDocs.map((doc) {
                            final data = doc.data();
                            final isGroup = data['isGroup'] == true;
                            final participants = List<String>.from(data['participants'] ?? []);
                            final peerUid = isGroup
                                ? doc.id
                                : participants.firstWhere(
                                    (id) => id != _myUid,
                                    orElse: () {
                                      final parts = doc.id.split('_');
                                      return parts.firstWhere((p) => p != _myUid, orElse: () => '');
                                    },
                                  );
                            final initialName = (data['name'] ?? data['groupName'] ?? (data['lastSenderId'] == peerUid ? data['lastSenderName'] : '') ?? '') as String;
                            final initialAvatar = data['avatar'] as String?;
                            final subtitle = data['lastMessage'] ?? (isGroup ? 'Group chat' : 'Direct message');

                            return _ShareTargetTile(
                              myUid: _myUid!,
                              peerUid: peerUid,
                              initialName: initialName,
                              initialAvatar: initialAvatar,
                              subtitle: subtitle,
                              isGroup: isGroup,
                              chatIdOverride: isGroup ? doc.id : null,
                              groupParticipants: isGroup ? participants : null,
                              searchQuery: _searchQuery,
                              isSending: _isSending && _sendingToId == peerUid,
                              mint: mint,
                              textPrim: textPrim,
                              textSec: textSec,
                              textMuted: textMuted,
                              surfaceElevated: surfaceElevated,
                              onTap: (resolvedName, resolvedAvatar) {
                                _shareToChat(
                                  peerUid: peerUid,
                                  peerName: resolvedName,
                                  peerAvatar: resolvedAvatar,
                                  isGroup: isGroup,
                                  chatIdOverride: isGroup ? doc.id : null,
                                  groupParticipants: isGroup ? participants : null,
                                );
                              },
                              onSendDirect: (resolvedName, resolvedAvatar) {
                                _directSendTo(
                                  peerUid: peerUid,
                                  peerName: resolvedName,
                                  peerAvatar: resolvedAvatar,
                                  isGroup: isGroup,
                                  chatIdOverride: isGroup ? doc.id : null,
                                  groupParticipants: isGroup ? participants : null,
                                );
                              },
                            );
                          }),

                          // Also stream paired contacts so any contact not yet chatted with is visible
                          StreamBuilder<List<Map<String, dynamic>>>(
                            stream: ContactService.streamContacts(_myUid!),
                            builder: (context, contactSnap) {
                              final contacts = (contactSnap.data ?? []).where((c) {
                                final uid = c['uid'] as String? ?? '';
                                return uid.isNotEmpty && !recentPeerUids.contains(uid);
                              }).toList();

                              if (contacts.isEmpty) return const SizedBox.shrink();

                              return Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                                    child: Text(
                                      'OTHER CONTACTS',
                                      style: TextStyle(
                                        color: textMuted,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 0.8,
                                      ),
                                    ),
                                  ),
                                  ...contacts.map((c) {
                                    final uid = c['uid'] as String? ?? '';
                                    final name = c['name'] as String? ?? 'Contact';
                                    final avatar = c['avatar'] as String?;

                                    return _ShareTargetTile(
                                      myUid: _myUid!,
                                      peerUid: uid,
                                      initialName: name,
                                      initialAvatar: avatar,
                                      subtitle: 'Paired contact',
                                      isGroup: false,
                                      searchQuery: _searchQuery,
                                      isSending: _isSending && _sendingToId == uid,
                                      mint: mint,
                                      textPrim: textPrim,
                                      textSec: textSec,
                                      textMuted: textMuted,
                                      surfaceElevated: surfaceElevated,
                                      onTap: (resolvedName, resolvedAvatar) {
                                        _shareToChat(
                                          peerUid: uid,
                                          peerName: resolvedName,
                                          peerAvatar: resolvedAvatar,
                                        );
                                      },
                                      onSendDirect: (resolvedName, resolvedAvatar) {
                                        _directSendTo(
                                          peerUid: uid,
                                          peerName: resolvedName,
                                          peerAvatar: resolvedAvatar,
                                        );
                                      },
                                    );
                                  }),
                                ],
                              );
                            },
                          ),
                        ],
                      );
                    },
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewCard(
    Color surfaceElevated,
    Color border,
    Color mint,
    Color textPrim,
    Color textMuted,
  ) {
    if (widget.files.isNotEmpty) {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: surfaceElevated,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 72,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: widget.files.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, idx) {
                  final path = widget.files[idx];
                  final file = File(path);
                  final pathLower = path.toLowerCase();
                  final isImg = pathLower.endsWith('.jpg') ||
                      pathLower.endsWith('.jpeg') ||
                      pathLower.endsWith('.png') ||
                      pathLower.endsWith('.webp') ||
                      pathLower.endsWith('.gif');
                  final isVid = pathLower.endsWith('.mp4') ||
                      pathLower.endsWith('.mkv') ||
                      pathLower.endsWith('.mov') ||
                      pathLower.endsWith('.3gp');
                  final isAud = pathLower.endsWith('.mp3') ||
                      pathLower.endsWith('.m4a') ||
                      pathLower.endsWith('.wav');

                  return Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: Colors.black26,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: mint.withValues(alpha: 0.3)),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: isImg
                        ? Image.file(file, fit: BoxFit.cover)
                        : Center(
                            child: Icon(
                              isVid
                                  ? Icons.videocam_rounded
                                  : isAud
                                      ? Icons.audiotrack_rounded
                                      : Icons.insert_drive_file_rounded,
                              color: mint,
                              size: 30,
                            ),
                          ),
                  );
                },
              ),
            ),
            if (widget.text.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                widget.text,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: textPrim, fontSize: 13),
              ),
            ],
          ],
        ),
      );
    }

    if (widget.text.isNotEmpty) {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: surfaceElevated,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: border),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.format_quote_rounded, color: mint, size: 22),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                widget.text,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: textPrim,
                  fontSize: 13.5,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return const SizedBox.shrink();
  }
}

class _ShareTargetTile extends StatelessWidget {
  final String myUid;
  final String peerUid;
  final String initialName;
  final String? initialAvatar;
  final String subtitle;
  final bool isGroup;
  final String? chatIdOverride;
  final List<String>? groupParticipants;
  final String searchQuery;
  final bool isSending;
  final Color mint;
  final Color textPrim;
  final Color textSec;
  final Color textMuted;
  final Color surfaceElevated;
  final void Function(String resolvedName, String? resolvedAvatar) onTap;
  final void Function(String resolvedName, String? resolvedAvatar) onSendDirect;

  const _ShareTargetTile({
    required this.myUid,
    required this.peerUid,
    required this.initialName,
    this.initialAvatar,
    required this.subtitle,
    required this.isGroup,
    this.chatIdOverride,
    this.groupParticipants,
    required this.searchQuery,
    required this.isSending,
    required this.mint,
    required this.textPrim,
    required this.textSec,
    required this.textMuted,
    required this.surfaceElevated,
    required this.onTap,
    required this.onSendDirect,
  });

  @override
  Widget build(BuildContext context) {
    if (isGroup) {
      final name = initialName.isNotEmpty ? initialName : 'Group Chat';
      if (searchQuery.isNotEmpty &&
          !name.toLowerCase().contains(searchQuery) &&
          !subtitle.toLowerCase().contains(searchQuery)) {
        return const SizedBox.shrink();
      }
      return _buildTile(context, name: name, avatar: initialAvatar, isGroup: true);
    }

    // Direct 1-on-1 chat: Resolve real contact profile or name
    return FutureBuilder<Map<String, dynamic>?>(
      future: ContactService.fetchContactOrProfile(myUid, peerUid),
      builder: (context, snap) {
        final profile = snap.data;
        final name = (profile?['name'] as String?)?.isNotEmpty == true
            ? profile!['name'] as String
            : ((profile?['displayName'] as String?)?.isNotEmpty == true
                ? profile!['displayName'] as String
                : (initialName.isNotEmpty && initialName != 'Contact'
                    ? initialName
                    : 'Contact'));
        final avatar = profile?['avatar'] as String? ??
            profile?['photoURL'] as String? ??
            profile?['photoUrl'] as String? ??
            initialAvatar;

        if (searchQuery.isNotEmpty &&
            !name.toLowerCase().contains(searchQuery) &&
            !subtitle.toLowerCase().contains(searchQuery)) {
          return const SizedBox.shrink();
        }

        return _buildTile(context, name: name, avatar: avatar, isGroup: false);
      },
    );
  }

  Widget _buildTile(
    BuildContext context, {
    required String name,
    required String? avatar,
    required bool isGroup,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      onTap: () => onTap(name, avatar),
      leading: CircleAvatar(
        radius: 22,
        backgroundColor: surfaceElevated,
        backgroundImage: MediaStorageService.getAvatarProvider(avatar),
        child: (avatar == null || avatar.isEmpty)
            ? (isGroup
                ? Icon(Icons.group_rounded, color: mint, size: 20)
                : Text(
                    name.isNotEmpty ? name[0].toUpperCase() : 'U',
                    style: TextStyle(color: mint, fontWeight: FontWeight.bold, fontSize: 16),
                  ))
            : null,
      ),
      title: Text(
        name,
        style: TextStyle(
          color: textPrim,
          fontWeight: FontWeight.w600,
          fontSize: 14.5,
        ),
      ),
      subtitle: Text(
        subtitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: textMuted, fontSize: 12),
      ),
      trailing: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: isSending ? mint.withValues(alpha: 0.15) : mint.withValues(alpha: 0.12),
          shape: BoxShape.circle,
        ),
        child: isSending
            ? Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: mint),
                ),
              )
            : IconButton(
                padding: EdgeInsets.zero,
                icon: Icon(Icons.send_rounded, color: mint, size: 18),
                tooltip: 'Send to $name',
                onPressed: () => onSendDirect(name, avatar),
              ),
      ),
    );
  }
}

