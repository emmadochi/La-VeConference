import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:share_plus/share_plus.dart';
import '../theme/app_theme.dart';
import '../services/presence_service.dart';
import '../services/call_signaling_service.dart';
import '../services/chat_service.dart';
import '../services/contact_service.dart';
import '../services/media_storage_service.dart';
import 'image_viewer_screen.dart';
import 'call_screens.dart';

class ContactProfileScreen extends StatefulWidget {
  final String peerUid;
  final String peerName;
  final String? peerAvatar;

  const ContactProfileScreen({
    super.key,
    required this.peerUid,
    required this.peerName,
    this.peerAvatar,
  });

  @override
  State<ContactProfileScreen> createState() => _ContactProfileScreenState();
}

class _ContactProfileScreenState extends State<ContactProfileScreen> {
  final String? _myUid = FirebaseAuth.instance.currentUser?.uid;
  final String? _myName = FirebaseAuth.instance.currentUser?.displayName;
  final String? _myAvatar = FirebaseAuth.instance.currentUser?.photoURL;
  late String _currentName;
  String? _currentAvatar;
  String? _bio;
  bool _isMuted = false;

  @override
  void initState() {
    super.initState();
    _currentName = widget.peerName;
    _currentAvatar = widget.peerAvatar;
    _fetchContactDetails();
  }

  Future<void> _fetchContactDetails() async {
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(widget.peerUid).get();
      if (doc.exists && mounted) {
        final data = doc.data();
        setState(() {
          _bio = data?['status'] as String? ?? data?['bio'] as String?;
          final freshAvatar = data?['avatar'] as String? ?? data?['photoURL'] as String?;
          if (freshAvatar != null && freshAvatar.isNotEmpty) {
            _currentAvatar = freshAvatar;
          }
          final freshName = data?['name'] as String? ?? data?['displayName'] as String?;
          if (freshName != null && freshName.isNotEmpty) {
            _currentName = freshName;
          }
        });
      }
    } catch (_) {}
  }

  void _openZoomedAvatar() {
    if (_currentAvatar != null && _currentAvatar!.isNotEmpty) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ImageViewerScreen(
            imageUrl: _currentAvatar,
            title: _currentName,
            subtitle: 'Profile Picture',
          ),
        ),
      );
    }
  }

  void _startCall(bool isVideo) async {
    if (_myUid == null) return;
    HapticFeedback.lightImpact();

    final callId = await CallSignalingService.initiateCall(
      callerId: _myUid,
      callerName: _myName ?? 'LiChat User',
      callerAvatar: _myAvatar,
      receiverId: widget.peerUid,
      receiverName: _currentName,
      receiverAvatar: _currentAvatar,
      isVideo: isVideo,
    );

    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => OutgoingCallScreen(
            callId: callId,
            peerName: _currentName,
            peerAvatar: _currentAvatar,
            isVideo: isVideo,
          ),
        ),
      );
    }
  }

  void _shareContact() {
    SharePlus.instance.share(
      ShareParams(
        text: 'Connect with $_currentName on LiChat! LiChat Code: ${widget.peerUid.substring(0, 8).toUpperCase()}',
      ),
    );
  }

  void _showEditNicknameDialog() {
    final controller = TextEditingController(text: _currentName);
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: AppTheme.surfaceColor(context),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: AppTheme.borderColor(context)),
        ),
        title: Text(
          'Edit Nickname',
          style: TextStyle(color: AppTheme.text(context), fontSize: 16, fontWeight: FontWeight.bold),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: TextStyle(color: AppTheme.text(context)),
          decoration: InputDecoration(
            hintText: 'Enter name',
            hintStyle: TextStyle(color: AppTheme.textMut(context)),
            filled: true,
            fillColor: AppTheme.surfaceElevatedColor(context),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: Text('Cancel', style: TextStyle(color: AppTheme.textMut(context))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.mintColor(context),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () {
              final newName = controller.text.trim();
              if (newName.isNotEmpty) {
                setState(() => _currentName = newName);
              }
              Navigator.pop(dialogCtx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteContact() {
    if (_myUid == null) return;
    final surface = AppTheme.surfaceColor(context);
    final border = AppTheme.borderColor(context);
    final textPrim = AppTheme.text(context);
    final textSec = AppTheme.textSec(context);
    final textMuted = AppTheme.textMut(context);

    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: border),
        ),
        title: Text('Delete Contact?', style: TextStyle(color: textPrim, fontWeight: FontWeight.bold, fontSize: 16)),
        content: Text(
          'Remove $_currentName from your verified contacts list? You will no longer see them in your contacts.',
          style: TextStyle(color: textSec, fontSize: 13.5, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: Text('Cancel', style: TextStyle(color: textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 0,
            ),
            onPressed: () async {
              Navigator.pop(dialogCtx);
              await ContactService.deleteContact(_myUid!, widget.peerUid);
              if (mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Removed $_currentName from contacts.'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            },
            child: const Text('Delete', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _confirmBlockContact() {
    if (_myUid == null) return;
    final surface = AppTheme.surfaceColor(context);
    final border = AppTheme.borderColor(context);
    final textPrim = AppTheme.text(context);
    final textSec = AppTheme.textSec(context);
    final textMuted = AppTheme.textMut(context);

    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: border),
        ),
        title: Text('Block $_currentName?', style: TextStyle(color: textPrim, fontWeight: FontWeight.bold, fontSize: 16)),
        content: Text(
          'Blocked contacts cannot send you messages or calls, and are removed from your contacts list.',
          style: TextStyle(color: textSec, fontSize: 13.5, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: Text('Cancel', style: TextStyle(color: textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 0,
            ),
            onPressed: () async {
              Navigator.pop(dialogCtx);
              await ContactService.blockContact(_myUid!, widget.peerUid);
              if (mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Blocked $_currentName.'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            },
            child: const Text('Block', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bg = AppTheme.bg(context);
    final surface = AppTheme.surfaceColor(context);
    final surfaceElevated = AppTheme.surfaceElevatedColor(context);
    final textPrim = AppTheme.text(context);
    final textSec = AppTheme.textSec(context);
    final textMuted = AppTheme.textMut(context);
    final border = AppTheme.borderColor(context);
    final mint = AppTheme.mintColor(context);
    final chatId = _myUid != null ? ChatService.getConversationId(_myUid, widget.peerUid) : null;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: textPrim),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.edit_outlined, color: textMuted),
            tooltip: 'Edit Nickname',
            onPressed: _showEditNicknameDialog,
          ),
          IconButton(
            icon: Icon(Icons.share_rounded, color: textMuted),
            tooltip: 'Share Contact',
            onPressed: _shareContact,
          ),
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert_rounded, color: textMuted),
            color: surfaceElevated,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            onSelected: (val) {
              if (val == 'delete') {
                _confirmDeleteContact();
              } else if (val == 'block') {
                _confirmBlockContact();
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'delete',
                child: const Row(children: [
                  Icon(Icons.person_remove_rounded, color: Colors.redAccent, size: 18),
                  SizedBox(width: 10),
                  Text('Delete Contact', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w600)),
                ]),
              ),
              PopupMenuItem(
                value: 'block',
                child: Row(children: [
                  Icon(Icons.block_rounded, color: Colors.red.shade400, size: 18),
                  const SizedBox(width: 10),
                  Text('Block Contact', style: TextStyle(color: Colors.red.shade400, fontWeight: FontWeight.w600)),
                ]),
              ),
            ],
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // 1. Hero Avatar & Name Card
            Center(
              child: Column(
                children: [
                  GestureDetector(
                    onTap: _openZoomedAvatar,
                    child: Stack(
                      alignment: Alignment.bottomRight,
                      children: [
                        Hero(
                          tag: 'avatar_${widget.peerUid}',
                          child: Container(
                            width: 110,
                            height: 110,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: mint.withValues(alpha: 0.6), width: 2.5),
                              boxShadow: [
                                BoxShadow(
                                  color: mint.withValues(alpha: 0.2),
                                  blurRadius: 16,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                            child: CircleAvatar(
                              backgroundColor: surfaceElevated,
                              backgroundImage: MediaStorageService.getAvatarProvider(_currentAvatar),
                              child: (_currentAvatar == null || _currentAvatar!.isEmpty)
                                  ? Text(
                                      _currentName.isNotEmpty ? _currentName[0].toUpperCase() : 'U',
                                      style: TextStyle(color: mint, fontSize: 42, fontWeight: FontWeight.bold),
                                    )
                                  : null,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.all(5),
                          decoration: BoxDecoration(
                            color: surfaceElevated,
                            shape: BoxShape.circle,
                            border: Border.all(color: border),
                          ),
                          child: Icon(Icons.zoom_in_rounded, color: mint, size: 18),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _currentName,
                    style: TextStyle(color: textPrim, fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  StreamBuilder<UserPresence>(
                    stream: PresenceService.streamUserPresence(widget.peerUid),
                    builder: (context, presenceSnap) {
                      final presence = presenceSnap.data;
                      final isOnline = presence?.isOnline == true;
                      final statusText = presence?.statusText ?? 'Offline';

                      return Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: isOnline ? AppTheme.callGreen : textMuted,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            statusText,
                            style: TextStyle(
                              color: isOnline ? AppTheme.callGreen : textMuted,
                              fontSize: 13,
                              fontWeight: isOnline ? FontWeight.w600 : FontWeight.normal,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // 2. Primary Action Bar (Hick's Law: 4 Core Actions)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildActionButton(
                    icon: Icons.chat_bubble_rounded,
                    label: 'Message',
                    color: mint,
                    onTap: () => Navigator.pop(context),
                  ),
                  _buildActionButton(
                    icon: Icons.phone_rounded,
                    label: 'Audio Call',
                    color: AppTheme.callGreen,
                    onTap: () => _startCall(false),
                  ),
                  _buildActionButton(
                    icon: Icons.videocam_rounded,
                    label: 'Video Call',
                    color: mint,
                    onTap: () => _startCall(true),
                  ),
                  _buildActionButton(
                    icon: Icons.share_rounded,
                    label: 'Share',
                    color: textSec,
                    onTap: _shareContact,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // 3. Info & About Section
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('About & Details', style: TextStyle(color: textSec, fontSize: 12.5, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 12),
                    if (_bio != null && _bio!.isNotEmpty) ...[
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.info_outline_rounded, color: textMuted, size: 20),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(_bio!, style: TextStyle(color: textPrim, fontSize: 14)),
                                const SizedBox(height: 2),
                                Text('Bio', style: TextStyle(color: textMuted, fontSize: 11)),
                              ],
                            ),
                          ),
                        ],
                      ),
                      Divider(color: border, height: 24),
                    ],
                    Row(
                      children: [
                        Icon(Icons.tag_rounded, color: textMuted, size: 20),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.peerUid.substring(0, widget.peerUid.length > 12 ? 12 : widget.peerUid.length).toUpperCase(),
                                style: TextStyle(color: textPrim, fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: 1),
                              ),
                              const SizedBox(height: 2),
                              Text('LiChat ID', style: TextStyle(color: textMuted, fontSize: 11)),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: Icon(Icons.copy_rounded, color: mint, size: 18),
                          tooltip: 'Copy ID',
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: widget.peerUid));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('LiChat ID copied'), duration: Duration(seconds: 1)),
                            );
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // 4. Shared Media Gallery Card
            if (chatId != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Shared Media', style: TextStyle(color: textSec, fontSize: 12.5, fontWeight: FontWeight.w600)),
                          Icon(Icons.photo_library_outlined, color: textMuted, size: 16),
                        ],
                      ),
                      const SizedBox(height: 12),
                      StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                        stream: FirebaseFirestore.instance
                            .collection('chats')
                            .doc(chatId)
                            .collection('messages')
                            .where('type', isEqualTo: 'image')
                            .orderBy('timestamp', descending: true)
                            .limit(6)
                            .snapshots(),
                        builder: (context, mediaSnap) {
                          final docs = mediaSnap.data?.docs ?? [];
                          if (docs.isEmpty) {
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Text('No photos shared yet', style: TextStyle(color: textMuted, fontSize: 13)),
                            );
                          }

                          return GridView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: docs.length,
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              crossAxisSpacing: 8,
                              mainAxisSpacing: 8,
                            ),
                            itemBuilder: (context, index) {
                              final item = docs[index].data();
                              final mediaUrl = item['mediaUrl'] as String?;
                              final localPath = item['localPath'] as String?;

                              return GestureDetector(
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => ImageViewerScreen(
                                        imageUrl: mediaUrl,
                                        localPath: localPath,
                                        title: _currentName,
                                      ),
                                    ),
                                  );
                                },
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: Container(
                                    color: surfaceElevated,
                                    child: (mediaUrl != null && mediaUrl.isNotEmpty)
                                        ? (mediaUrl.startsWith('data:')
                                            ? Builder(builder: (_) {
                                                try {
                                                  final bytes = base64Decode(mediaUrl.substring(mediaUrl.indexOf(',') + 1));
                                                  return Image.memory(bytes, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_rounded, color: Colors.white24));
                                                } catch (_) {
                                                  return const Icon(Icons.broken_image_rounded, color: Colors.white24);
                                                }
                                              })
                                            : Image.network(mediaUrl, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.image, color: Colors.white24)))
                                        : const Icon(Icons.image, color: Colors.white24),
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),

            const SizedBox(height: 16),

            // 5. Settings / Preferences Card
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 6),
                decoration: BoxDecoration(
                  color: surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: border),
                ),
                child: Column(
                  children: [
                    SwitchListTile(
                      value: _isMuted,
                      onChanged: (val) {
                        setState(() => _isMuted = val);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(_isMuted ? 'Notifications muted' : 'Notifications unmuted'),
                            duration: const Duration(seconds: 1),
                          ),
                        );
                      },
                      activeColor: mint,
                      title: Text('Mute Notifications', style: TextStyle(color: textPrim, fontSize: 14)),
                      secondary: Icon(Icons.notifications_off_outlined, color: textMuted),
                    ),
                    Divider(color: border, height: 1),
                    ListTile(
                      leading: const Icon(Icons.person_remove_rounded, color: Colors.redAccent),
                      title: const Text('Delete Contact', style: TextStyle(color: Colors.redAccent, fontSize: 14, fontWeight: FontWeight.w600)),
                      subtitle: Text('Remove from your verified contacts list', style: TextStyle(color: textMuted, fontSize: 12)),
                      onTap: _confirmDeleteContact,
                    ),
                    Divider(color: border, height: 1),
                    ListTile(
                      leading: Icon(Icons.block_rounded, color: Colors.red.shade400),
                      title: Text('Block Contact', style: TextStyle(color: Colors.red.shade400, fontSize: 14, fontWeight: FontWeight.w600)),
                      subtitle: Text('Prevent calls and messages from reaching you', style: TextStyle(color: textMuted, fontSize: 12)),
                      onTap: _confirmBlockContact,
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    final surfaceElevated = AppTheme.surfaceElevatedColor(context);
    final border = AppTheme.borderColor(context);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: surfaceElevated,
                shape: BoxShape.circle,
                border: Border.all(color: border),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(color: AppTheme.text(context), fontSize: 12, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }
}
