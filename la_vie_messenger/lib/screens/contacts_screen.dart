import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../theme/app_theme.dart';
import '../services/contact_service.dart';
import '../services/call_signaling_service.dart';
import '../services/presence_service.dart';
import 'chat_conversation_screen.dart';
import 'call_screens.dart';
import 'qr_connect_screen.dart';
import 'image_viewer_screen.dart';
import 'contact_profile_screen.dart';
import '../services/media_storage_service.dart';

class ContactsScreen extends StatefulWidget {
  final void Function(String peerUid, String peerName, String? peerAvatar)? onContactChatSelected;

  const ContactsScreen({super.key, this.onContactChatSelected});

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> with SingleTickerProviderStateMixin {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String? _myUid;
  String? _myName;
  String? _myAvatar;
  String _myLichatCode = '';
  late TabController _tabController;
  final Set<String> _selectedContactUids = {};

  bool get _isSelectionMode => _selectedContactUids.isNotEmpty;

  void _toggleContactSelection(String peerUid) {
    setState(() {
      if (_selectedContactUids.contains(peerUid)) {
        _selectedContactUids.remove(peerUid);
      } else {
        _selectedContactUids.add(peerUid);
      }
    });
  }

  void _clearSelection() {
    setState(() {
      _selectedContactUids.clear();
    });
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    final user = FirebaseAuth.instance.currentUser;
    _myUid = user?.uid;
    _myName = user?.displayName ?? 'LiChat User';
    _myAvatar = user?.photoURL;

    if (_myUid != null) {
      ContactService.ensureUserLiChatCode(_myUid!, displayName: _myName).then((code) {
        if (mounted) setState(() => _myLichatCode = code);
      });
    }

    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.trim().toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _startCall({
    required String peerUid,
    required String peerName,
    String? peerAvatar,
    required bool isVideo,
  }) async {
    if (_myUid == null) return;

    final isContact = await ContactService.isContactVerified(_myUid!, peerUid);
    if (!isContact) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Cannot call $peerName. You must be verified contacts.'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
      return;
    }

    final callId = await CallSignalingService.initiateCall(
      callerId: _myUid!,
      callerName: _myName!,
      callerAvatar: _myAvatar,
      receiverId: peerUid,
      receiverName: peerName,
      receiverAvatar: peerAvatar,
      isVideo: isVideo,
    );

    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => OutgoingCallScreen(
            callId: callId,
            peerName: peerName,
            peerAvatar: peerAvatar,
            isVideo: isVideo,
          ),
        ),
      );
    }
  }

  void _openChat({
    required String peerUid,
    required String peerName,
    String? peerAvatar,
  }) {
    if (widget.onContactChatSelected != null) {
      widget.onContactChatSelected!(peerUid, peerName, peerAvatar);
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ChatConversationScreen(
            peerUid: peerUid,
            peerName: peerName,
            peerAvatar: peerAvatar,
          ),
        ),
      );
    }
  }

  void _showRenameDialog(BuildContext context, String peerUid, String currentName) {
    final surface = AppTheme.surfaceColor(context);
    final surfaceElevated = AppTheme.surfaceElevatedColor(context);
    final border = AppTheme.borderColor(context);
    final textPrim = AppTheme.text(context);
    final textMuted = AppTheme.textMut(context);
    final mint = AppTheme.mintColor(context);
    final isDark = AppTheme.isDarkMode(context);

    final controller = TextEditingController(text: currentName);
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: border),
        ),
        title: Text('Edit Contact Nickname', style: TextStyle(color: textPrim, fontSize: 16, fontWeight: FontWeight.bold)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: TextStyle(color: textPrim, fontSize: 14),
          decoration: InputDecoration(
            hintText: 'Enter nickname...',
            hintStyle: TextStyle(color: textMuted, fontSize: 13),
            filled: true,
            fillColor: surfaceElevated,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: mint)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: Text('Cancel', style: TextStyle(color: textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: mint,
              foregroundColor: isDark ? Colors.black : Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () async {
              final newName = controller.text.trim();
              if (newName.isNotEmpty && _myUid != null) {
                await ContactService.updateContactNickname(
                  myUid: _myUid!,
                  peerUid: peerUid,
                  newNickname: newName,
                );
              }
              if (context.mounted) Navigator.pop(dialogCtx);
            },
            child: const Text('Save', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteContact(BuildContext context, String peerUid, String peerName) {
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
        title: Text('Remove Contact?', style: TextStyle(color: textPrim, fontWeight: FontWeight.bold, fontSize: 16)),
        content: Text(
          'Remove $peerName from your verified contacts? You will not be able to exchange messages or see status updates until reconnecting.',
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
              if (_myUid != null) {
                await ContactService.deleteContact(_myUid!, peerUid);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Removed $peerName from contacts.'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              }
            },
            child: const Text('Delete', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _confirmBlockContact(BuildContext context, String peerUid, String peerName) {
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
        title: Text('Block $peerName?', style: TextStyle(color: textPrim, fontWeight: FontWeight.bold, fontSize: 16)),
        content: Text(
          'Blocked contacts will no longer be able to message or call you, and will be removed from your contact list.',
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
              if (_myUid != null) {
                await ContactService.blockContact(_myUid!, peerUid);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Blocked $peerName.'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              }
            },
            child: const Text('Block', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _respondToRequest({
    required String senderUid,
    required String action,
  }) async {
    if (_myUid == null) return;
    final res = await ContactService.respondToContactRequest(
      responderUid:    _myUid!,
      responderName:   _myName ?? 'LiChat User',
      responderAvatar: _myAvatar,
      senderUid:       senderUid,
      action:          action,
    );
    if (mounted) {
      final mint = AppTheme.mintColor(context);
      final surface = AppTheme.surfaceElevatedColor(context);
      if (res['success'] == true) {
        final msg = action == 'accept' ? 'Contact verified & added!' : 'Request declined.';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(action == 'accept' ? Icons.check_circle_rounded : Icons.cancel_rounded, color: mint, size: 16),
                const SizedBox(width: 8),
                Text(msg),
              ],
            ),
            backgroundColor: surface,
            behavior: SnackBarBehavior.floating,
          ),
        );
        if (action == 'accept') {
          _tabController.animateTo(0);
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(res['message'] ?? 'Error'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  Future<void> _batchDeleteSelectedContacts() async {
    if (_selectedContactUids.isEmpty || _myUid == null) return;
    final count = _selectedContactUids.length;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceColor(context),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: AppTheme.borderColor(context)),
        ),
        title: Text(
          'Delete $count Contact${count > 1 ? 's' : ''}?',
          style: TextStyle(color: AppTheme.text(context), fontWeight: FontWeight.bold),
        ),
        content: Text(
          'Are you sure you want to remove the selected $count contact${count > 1 ? 's' : ''} from your contact list?',
          style: TextStyle(color: AppTheme.textSec(context), fontSize: 13.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: TextStyle(color: AppTheme.textSec(context))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final uidsToDelete = _selectedContactUids.toList();
      _clearSelection();

      for (final uid in uidsToDelete) {
        await ContactService.deleteContact(_myUid!, uid);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$count contact${count > 1 ? 's' : ''} deleted.'),
            backgroundColor: AppTheme.surfaceElevatedColor(context),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  void _showVerificationSheet({
    required BuildContext context,
    required String senderUid,
    required String senderName,
    String? senderAvatar,
    String? introNote,
    String? introPhotoUrl,
  }) {
    final textController = TextEditingController();
    final surface = AppTheme.surfaceColor(context);
    final surfaceElevated = AppTheme.surfaceElevatedColor(context);
    final border = AppTheme.borderColor(context);
    final textPrim = AppTheme.text(context);
    final textSec = AppTheme.textSec(context);
    final mint = AppTheme.mintColor(context);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final bottomInset = MediaQuery.of(context).viewInsets.bottom;
            return Container(
              height: MediaQuery.of(context).size.height * 0.85,
              padding: EdgeInsets.only(bottom: bottomInset),
              child: Column(
                children: [
                  // Drag Handle
                  Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(top: 10, bottom: 12),
                    decoration: BoxDecoration(
                      color: border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),

                  // Header with sender info
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 22,
                          backgroundColor: surfaceElevated,
                          backgroundImage: MediaStorageService.getAvatarProvider(senderAvatar),
                          child: (senderAvatar == null || senderAvatar.isEmpty)
                              ? Text(senderName.isNotEmpty ? senderName[0].toUpperCase() : '?',
                                  style: TextStyle(color: mint, fontWeight: FontWeight.bold))
                              : null,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(senderName,
                                  style: TextStyle(color: textPrim, fontWeight: FontWeight.bold, fontSize: 16)),
                              Text('Identity Verification & Inquiry',
                                  style: TextStyle(color: mint, fontSize: 12, fontWeight: FontWeight.w500)),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: Icon(Icons.close_rounded, color: textSec),
                          onPressed: () => Navigator.pop(sheetCtx),
                        ),
                      ],
                    ),
                  ),
                  Divider(color: border, height: 1),

                  // Intro Note & Photo Banner (if attached)
                  if ((introNote != null && introNote.isNotEmpty) || (introPhotoUrl != null && introPhotoUrl.isNotEmpty))
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: surfaceElevated,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: mint.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (introPhotoUrl != null && introPhotoUrl.isNotEmpty) ...[
                            GestureDetector(
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => ImageViewerScreen(
                                      imageUrl: introPhotoUrl,
                                      heroTag: 'intro_photo_$senderUid',
                                    ),
                                  ),
                                );
                              },
                              child: Hero(
                                tag: 'intro_photo_$senderUid',
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: Image.network(
                                    introPhotoUrl,
                                    width: 55,
                                    height: 55,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => Container(
                                      width: 55,
                                      height: 55,
                                      color: Colors.black26,
                                      child: const Icon(Icons.broken_image_rounded, size: 20),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                          ],
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(Icons.badge_rounded, color: mint, size: 14),
                                    const SizedBox(width: 5),
                                    Text('Sender Introduction',
                                        style: TextStyle(color: mint, fontWeight: FontWeight.bold, fontSize: 12)),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  introNote?.isNotEmpty == true ? introNote! : 'Photo attached for identification.',
                                  style: TextStyle(color: textPrim, fontSize: 13, height: 1.3),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Real-time Messages Stream
                  Expanded(
                    child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: ContactService.streamRequestMessages(targetUid: _myUid!, senderUid: senderUid),
                      builder: (context, msgSnap) {
                        final docs = msgSnap.data?.docs ?? [];
                        if (docs.isEmpty) {
                          return Center(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 32),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.chat_outlined, color: textSec.withValues(alpha: 0.5), size: 40),
                                  const SizedBox(height: 10),
                                  Text(
                                    'No messages yet',
                                    style: TextStyle(color: textPrim, fontWeight: FontWeight.bold, fontSize: 14),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Ask who they are or clarify their details before accepting.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(color: textSec, fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }

                        return ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          itemCount: docs.length,
                          itemBuilder: (context, idx) {
                            final m = docs[idx].data();
                            final isMe = m['author_uid'] == _myUid;
                            final text = m['text'] as String? ?? '';
                            final authorName = m['author_name'] as String? ?? 'User';

                            return Align(
                              alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                                decoration: BoxDecoration(
                                  color: isMe ? mint.withValues(alpha: 0.2) : surfaceElevated,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: isMe ? mint.withValues(alpha: 0.4) : border),
                                ),
                                child: Column(
                                  crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      isMe ? 'You' : authorName,
                                      style: TextStyle(
                                        color: isMe ? mint : AppTheme.primaryAccent(context),
                                        fontWeight: FontWeight.bold,
                                        fontSize: 11,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(text, style: TextStyle(color: textPrim, fontSize: 13.5)),
                                  ],
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),

                  // Bottom Action Bar: Send Inquiry & Accept/Decline Buttons
                  Container(
                    padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
                    decoration: BoxDecoration(
                      color: surface,
                      border: Border(top: BorderSide(color: border)),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Message input field
                        Row(
                          children: [
                            Expanded(
                              child: Container(
                                height: 42,
                                decoration: BoxDecoration(
                                  color: surfaceElevated,
                                  borderRadius: BorderRadius.circular(21),
                                  border: Border.all(color: border),
                                ),
                                padding: const EdgeInsets.symmetric(horizontal: 14),
                                child: TextField(
                                  controller: textController,
                                  style: TextStyle(color: textPrim, fontSize: 13.5),
                                  decoration: InputDecoration(
                                    hintText: 'Ask: "Who are you?", "Identify yourself"...',
                                    hintStyle: TextStyle(color: textSec, fontSize: 12.5),
                                    border: InputBorder.none,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              icon: Icon(Icons.send_rounded, color: mint),
                              onPressed: () {
                                final txt = textController.text.trim();
                                if (txt.isNotEmpty && _myUid != null) {
                                  ContactService.sendRequestMessage(
                                    senderUid: senderUid,
                                    targetUid: _myUid!,
                                    authorUid: _myUid!,
                                    authorName: _myName ?? 'User',
                                    text: txt,
                                  );
                                  textController.clear();
                                }
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        // Accept and Decline Buttons
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.redAccent,
                                  side: const BorderSide(color: Colors.redAccent),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                ),
                                icon: const Icon(Icons.close_rounded, size: 16),
                                label: const Text('Decline'),
                                onPressed: () {
                                  Navigator.pop(sheetCtx);
                                  _respondToRequest(senderUid: senderUid, action: 'decline');
                                },
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: mint,
                                  foregroundColor: Colors.black,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                ),
                                icon: const Icon(Icons.check_rounded, size: 16),
                                label: const Text('Accept Contact', style: TextStyle(fontWeight: FontWeight.bold)),
                                onPressed: () {
                                  Navigator.pop(sheetCtx);
                                  _respondToRequest(senderUid: senderUid, action: 'accept');
                                },
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final bg = AppTheme.bg(context);
    final surface = AppTheme.surfaceColor(context);
    final surfaceElevated = AppTheme.surfaceElevatedColor(context);
    final border = AppTheme.borderColor(context);
    final textPrim = AppTheme.text(context);
    final textSec = AppTheme.textSec(context);
    final textMuted = AppTheme.textMut(context);
    final mint = AppTheme.mintColor(context);
    final isDark = AppTheme.isDarkMode(context);

    if (_myUid == null) {
      return Scaffold(
        backgroundColor: bg,
        body: Center(child: CircularProgressIndicator(color: mint)),
      );
    }

    return Scaffold(
      backgroundColor: bg,
      appBar: _isSelectionMode
          ? AppBar(
              backgroundColor: surfaceElevated,
              elevation: 0,
              leading: IconButton(
                icon: const Icon(Icons.close_rounded),
                color: textPrim,
                onPressed: _clearSelection,
              ),
              title: Text(
                '${_selectedContactUids.length} Selected',
                style: TextStyle(color: textPrim, fontWeight: FontWeight.bold, fontSize: 18),
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.delete_sweep_rounded, color: Colors.redAccent),
                  tooltip: 'Delete Selected',
                  onPressed: _batchDeleteSelectedContacts,
                ),
                const SizedBox(width: 8),
              ],
            )
          : AppBar(
              backgroundColor: bg,
              elevation: 0,
              scrolledUnderElevation: 0,
        title: Builder(
          builder: (ctx) {
            final isDesktop = MediaQuery.of(ctx).size.width >= 800;
            return Row(
              children: [
                if (!isDesktop) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.asset('assets/images/lichat_logo.png', width: 28, height: 28),
                  ),
                  const SizedBox(width: 10),
                ],
                Text(
                  'Contacts',
                  style: TextStyle(
                    color: textPrim,
                    fontSize: isDesktop ? 22 : 20,
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.3,
                  ),
                ),
              ],
            );
          },
        ),
        actions: [
          // My LiChat PIN Quick Chip
          if (_myLichatCode.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () {
                  Clipboard.setData(ClipboardData(text: _myLichatCode));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Row(
                        children: [
                          Icon(Icons.check_rounded, color: mint, size: 16),
                          const SizedBox(width: 8),
                          Text('PIN $_myLichatCode copied to clipboard!'),
                        ],
                      ),
                      behavior: SnackBarBehavior.floating,
                      duration: const Duration(seconds: 2),
                    ),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: mint.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: mint.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.fingerprint_rounded, color: mint, size: 14),
                      const SizedBox(width: 4),
                      Text(
                        _myLichatCode,
                        style: TextStyle(color: mint, fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // Scan QR Button
          IconButton(
            icon: Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: surfaceElevated,
                shape: BoxShape.circle,
                border: Border.all(color: border.withValues(alpha: 0.8)),
              ),
              child: Icon(Icons.qr_code_scanner_rounded, color: mint, size: 19),
            ),
            tooltip: 'Scan Barcode',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const QrConnectScreen()),
              );
            },
          ),
          const SizedBox(width: 8),
        ],
        // Sleek, compact pill segmented control (38px height, modern design)
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(46),
          child: StreamBuilder<List<Map<String, dynamic>>>(
            stream: ContactService.streamIncomingRequests(_myUid!),
            builder: (context, reqSnap) {
              final requestCount = (reqSnap.data ?? []).length;
              return Container(
                height: 40,
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: surfaceElevated.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: border.withValues(alpha: 0.8)),
                ),
                child: TabBar(
                  controller: _tabController,
                  indicator: BoxDecoration(
                    color: mint,
                    borderRadius: BorderRadius.circular(19),
                    boxShadow: [
                      BoxShadow(
                        color: mint.withValues(alpha: 0.3),
                        blurRadius: 6,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                  indicatorSize: TabBarIndicatorSize.tab,
                  dividerColor: Colors.transparent,
                  labelColor: isDark ? Colors.black : Colors.white,
                  unselectedLabelColor: textSec,
                  labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  tabs: [
                    const Tab(
                      height: 34,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.people_alt_rounded, size: 16),
                          SizedBox(width: 6),
                          Text('Contacts'),
                        ],
                      ),
                    ),
                    Tab(
                      height: 34,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.person_add_rounded, size: 16),
                          const SizedBox(width: 6),
                          const Text('Requests'),
                          if (requestCount > 0) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: Colors.redAccent,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                '$requestCount',
                                style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // ─── TAB 1: CONTACTS LIST ───────────────────────────────────────────
          Column(
            children: [
              // Search Bar
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
                child: TextField(
                  controller: _searchController,
                  style: TextStyle(color: textPrim, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Search contacts by name...',
                    hintStyle: TextStyle(color: textMuted, fontSize: 13.5),
                    prefixIcon: Icon(Icons.search_rounded, color: mint, size: 20),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: Icon(Icons.clear, color: textMuted, size: 18),
                            onPressed: () => _searchController.clear(),
                          )
                        : null,
                    filled: true,
                    fillColor: surface,
                    contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: border)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: border.withValues(alpha: 0.8))),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: mint, width: 1.5)),
                  ),
                ),
              ),

              // Contacts Stream List
              Expanded(
                child: StreamBuilder<List<Map<String, dynamic>>>(
                  stream: ContactService.streamContacts(_myUid!),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
                      return Center(child: CircularProgressIndicator(color: mint));
                    }

                    final rawContacts = snapshot.data ?? [];
                    final contacts = _searchQuery.isEmpty
                        ? rawContacts
                        : rawContacts.where((c) {
                            final name = (c['name'] as String? ?? '').toLowerCase();
                            return name.contains(_searchQuery);
                          }).toList();

                    if (contacts.isEmpty) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32.0),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(22),
                                decoration: BoxDecoration(
                                  color: surface,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: border),
                                ),
                                child: Icon(
                                  _searchQuery.isNotEmpty ? Icons.search_off_rounded : Icons.people_outline_rounded,
                                  size: 52,
                                  color: mint.withValues(alpha: 0.7),
                                ),
                              ),
                              const SizedBox(height: 18),
                              Text(
                                _searchQuery.isNotEmpty ? 'No Contacts Found' : 'No Verified Contacts Yet',
                                style: TextStyle(color: textPrim, fontSize: 18, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _searchQuery.isNotEmpty
                                    ? 'No contacts match "$_searchQuery".'
                                    : 'Connect with colleagues by scanning their QR code or sharing your LiChat PIN.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: textSec, fontSize: 13, height: 1.4),
                              ),
                              const SizedBox(height: 22),
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: mint,
                                  foregroundColor: isDark ? Colors.black : Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                  elevation: 0,
                                ),
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(builder: (context) => const QrConnectScreen()),
                                  );
                                },
                                icon: const Icon(Icons.qr_code_scanner_rounded, size: 18),
                                label: const Text(
                                  'Scan Barcode or Add PIN',
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }

                    return ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
                      itemCount: contacts.length,
                      itemBuilder: (context, index) {
                        final contact = contacts[index];
                        final peerUid = contact['uid'] as String? ?? '';
                        final peerName = contact['name'] as String? ?? 'User';
                        final peerAvatar = contact['avatar'] as String?;
                        final isSelected = _selectedContactUids.contains(peerUid);

                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? mint.withValues(alpha: isDark ? 0.22 : 0.12)
                                : surface,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: isSelected ? mint : border.withValues(alpha: 0.7),
                              width: isSelected ? 1.5 : 1.0,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: isDark ? 0.12 : 0.03),
                                blurRadius: 4,
                                offset: const Offset(0, 1),
                              ),
                            ],
                          ),
                          child: Material(
                            color: Colors.transparent,
                            borderRadius: BorderRadius.circular(16),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(16),
                              onTap: () {
                                if (_isSelectionMode) {
                                  _toggleContactSelection(peerUid);
                                } else {
                                  _openChat(peerUid: peerUid, peerName: peerName, peerAvatar: peerAvatar);
                                }
                              },
                              onLongPress: () => _toggleContactSelection(peerUid),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                child: StreamBuilder<UserPresence>(
                                  stream: PresenceService.streamUserPresence(peerUid),
                                  builder: (context, presenceSnap) {
                                    final presence = presenceSnap.data;
                                    final isOnline = presence?.isOnline == true;
                                    final statusText = isOnline ? 'Online' : (presence?.statusText ?? 'Offline');

                                    return Row(
                                      children: [
                                        // Avatar with Presence indicator
                                        GestureDetector(
                                          onTap: () {
                                            if (peerAvatar != null && peerAvatar.isNotEmpty) {
                                              Navigator.push(
                                                context,
                                                MaterialPageRoute(
                                                  builder: (context) => ImageViewerScreen(
                                                    imageUrl: peerAvatar,
                                                    title: peerName,
                                                    subtitle: 'Profile Picture',
                                                  ),
                                                ),
                                              );
                                            } else {
                                              Navigator.push(
                                                context,
                                                MaterialPageRoute(
                                                  builder: (context) => ContactProfileScreen(
                                                    peerUid: peerUid,
                                                    peerName: peerName,
                                                    peerAvatar: peerAvatar,
                                                  ),
                                                ),
                                              );
                                            }
                                          },
                                          child: Stack(
                                            children: [
                                              Container(
                                                width: 46,
                                                height: 46,
                                                decoration: BoxDecoration(
                                                  shape: BoxShape.circle,
                                                  border: Border.all(
                                                    color: isOnline ? mint : border.withValues(alpha: 0.6),
                                                    width: 1.8,
                                                  ),
                                                ),
                                                child: CircleAvatar(
                                                  backgroundColor: surfaceElevated,
                                                  backgroundImage: MediaStorageService.getAvatarProvider(peerAvatar),
                                                  child: (peerAvatar == null || peerAvatar.isEmpty)
                                                      ? Text(
                                                          peerName.isNotEmpty ? peerName[0].toUpperCase() : 'U',
                                                          style: TextStyle(color: mint, fontWeight: FontWeight.bold, fontSize: 17),
                                                        )
                                                      : null,
                                                ),
                                              ),
                                              Positioned(
                                                right: 0,
                                                bottom: 0,
                                                child: Container(
                                                  width: 12,
                                                  height: 12,
                                                  decoration: BoxDecoration(
                                                    color: isOnline ? mint : (isDark ? Colors.grey.shade600 : Colors.grey.shade400),
                                                    shape: BoxShape.circle,
                                                    border: Border.all(color: surface, width: 2),
                                                  ),
                                                ),
                                              ),
                                              if (isSelected)
                                                Positioned.fill(
                                                  child: Container(
                                                    decoration: BoxDecoration(
                                                      color: mint,
                                                      shape: BoxShape.circle,
                                                    ),
                                                    child: const Icon(Icons.check_rounded, color: Colors.black, size: 22),
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 12),

                                        // Name and status text
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text(
                                                peerName,
                                                style: TextStyle(
                                                  color: textPrim,
                                                  fontWeight: FontWeight.w700,
                                                  fontSize: 15,
                                                  letterSpacing: 0.1,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                              const SizedBox(height: 3),
                                              Row(
                                                children: [
                                                  if (isOnline) ...[
                                                    Container(
                                                      width: 6,
                                                      height: 6,
                                                      margin: const EdgeInsets.only(right: 5),
                                                      decoration: BoxDecoration(color: mint, shape: BoxShape.circle),
                                                    ),
                                                  ],
                                                  Flexible(
                                                    child: Text(
                                                      statusText,
                                                      style: TextStyle(
                                                        color: isOnline ? mint : textMuted,
                                                        fontSize: 12,
                                                        fontWeight: isOnline ? FontWeight.w600 : FontWeight.normal,
                                                      ),
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),

                                        // Refined action bar: Primary Chat Button + Call Button + More Menu
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            // Primary Chat Button (prominent & clear)
                                            InkWell(
                                              onTap: () => _openChat(peerUid: peerUid, peerName: peerName, peerAvatar: peerAvatar),
                                              borderRadius: BorderRadius.circular(10),
                                              child: Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                                                decoration: BoxDecoration(
                                                  color: mint.withValues(alpha: 0.14),
                                                  borderRadius: BorderRadius.circular(10),
                                                  border: Border.all(color: mint.withValues(alpha: 0.3)),
                                                ),
                                                child: Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    Icon(Icons.chat_bubble_rounded, color: mint, size: 14),
                                                    const SizedBox(width: 4),
                                                    Text(
                                                      'Chat',
                                                      style: TextStyle(color: mint, fontWeight: FontWeight.bold, fontSize: 12),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 6),

                                            // Quick Audio Call
                                            InkWell(
                                              onTap: () => _startCall(peerUid: peerUid, peerName: peerName, peerAvatar: peerAvatar, isVideo: false),
                                              borderRadius: BorderRadius.circular(10),
                                              child: Container(
                                                width: 32,
                                                height: 32,
                                                decoration: BoxDecoration(
                                                  color: surfaceElevated,
                                                  borderRadius: BorderRadius.circular(10),
                                                  border: Border.all(color: border.withValues(alpha: 0.7)),
                                                ),
                                                child: Icon(Icons.phone_rounded, color: mint, size: 15),
                                              ),
                                            ),
                                            const SizedBox(width: 2),

                                            // More Menu (Video call, Edit Nickname, View Profile, Remove)
                                            PopupMenuButton<String>(
                                              icon: Icon(Icons.more_vert_rounded, color: textMuted, size: 18),
                                              shape: RoundedRectangleBorder(
                                                borderRadius: BorderRadius.circular(14),
                                                side: BorderSide(color: border),
                                              ),
                                              color: surfaceElevated,
                                              onSelected: (value) {
                                                if (value == 'video_call') {
                                                  _startCall(peerUid: peerUid, peerName: peerName, peerAvatar: peerAvatar, isVideo: true);
                                                } else if (value == 'edit_nickname') {
                                                  _showRenameDialog(context, peerUid, peerName);
                                                } else if (value == 'profile') {
                                                  Navigator.push(
                                                    context,
                                                    MaterialPageRoute(
                                                      builder: (context) => ContactProfileScreen(
                                                        peerUid: peerUid,
                                                        peerName: peerName,
                                                        peerAvatar: peerAvatar,
                                                      ),
                                                    ),
                                                  );
                                                } else if (value == 'delete') {
                                                  _confirmDeleteContact(context, peerUid, peerName);
                                                } else if (value == 'block') {
                                                  _confirmBlockContact(context, peerUid, peerName);
                                                }
                                              },
                                              itemBuilder: (ctx) => [
                                                PopupMenuItem(
                                                  value: 'video_call',
                                                  child: Row(
                                                    children: [
                                                      Icon(Icons.videocam_rounded, color: mint, size: 18),
                                                      const SizedBox(width: 10),
                                                      Text('Video Call', style: TextStyle(color: textPrim, fontSize: 13)),
                                                    ],
                                                  ),
                                                ),
                                                PopupMenuItem(
                                                  value: 'edit_nickname',
                                                  child: Row(
                                                    children: [
                                                      Icon(Icons.edit_outlined, color: textSec, size: 18),
                                                      const SizedBox(width: 10),
                                                      Text('Edit Nickname', style: TextStyle(color: textPrim, fontSize: 13)),
                                                    ],
                                                  ),
                                                ),
                                                PopupMenuItem(
                                                  value: 'profile',
                                                  child: Row(
                                                    children: [
                                                      Icon(Icons.person_outline_rounded, color: textSec, size: 18),
                                                      const SizedBox(width: 10),
                                                      Text('View Profile', style: TextStyle(color: textPrim, fontSize: 13)),
                                                    ],
                                                  ),
                                                ),
                                                const PopupMenuDivider(),
                                                PopupMenuItem(
                                                  value: 'delete',
                                                  child: const Row(
                                                    children: [
                                                      Icon(Icons.person_remove_rounded, color: Colors.redAccent, size: 18),
                                                      SizedBox(width: 10),
                                                      Text('Delete Contact', style: TextStyle(color: Colors.redAccent, fontSize: 13, fontWeight: FontWeight.w600)),
                                                    ],
                                                  ),
                                                ),
                                                PopupMenuItem(
                                                  value: 'block',
                                                  child: Row(
                                                    children: [
                                                      Icon(Icons.block_rounded, color: Colors.red.shade400, size: 18),
                                                      const SizedBox(width: 10),
                                                      Text('Block Contact', style: TextStyle(color: Colors.red.shade400, fontSize: 13, fontWeight: FontWeight.w600)),
                                                    ],
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ],
                                    );
                                  },
                                ),
                              ),
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

          // ─── TAB 2: CONTACT REQUESTS ────────────────────────────────────────
          StreamBuilder<List<Map<String, dynamic>>>(
            stream: ContactService.streamIncomingRequests(_myUid!),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
                return Center(child: CircularProgressIndicator(color: mint));
              }

              final requests = snapshot.data ?? [];

              if (requests.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(22),
                          decoration: BoxDecoration(
                            color: surface,
                            shape: BoxShape.circle,
                            border: Border.all(color: border),
                          ),
                          child: Icon(Icons.person_add_disabled_rounded, size: 50, color: mint.withValues(alpha: 0.5)),
                        ),
                        const SizedBox(height: 18),
                        Text('No Pending Requests', style: TextStyle(color: textPrim, fontSize: 18, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        Text(
                          'When someone scans your QR code or searches your LiChat PIN, their request will appear here for you to Accept.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: textSec, fontSize: 13, height: 1.4),
                        ),
                      ],
                    ),
                  ),
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                itemCount: requests.length,
                itemBuilder: (context, index) {
                  final req = requests[index];
                  final senderUid    = req['sender_uid']    as String? ?? '';
                  final senderName   = req['sender_name']   as String? ?? 'LiChat User';
                  final senderAvatar = req['sender_avatar'] as String?;
                  final introNote    = req['intro_note']    as String?;
                  final introPhoto   = req['intro_photo_url'] as String?;

                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: mint.withValues(alpha: 0.28)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: isDark ? 0.14 : 0.04),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            // Avatar
                            Container(
                              width: 46,
                              height: 46,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: mint.withValues(alpha: 0.4), width: 1.5),
                              ),
                              child: CircleAvatar(
                                backgroundColor: surfaceElevated,
                                backgroundImage: MediaStorageService.getAvatarProvider(senderAvatar),
                                child: (senderAvatar == null || senderAvatar.isEmpty)
                                    ? Text(
                                        senderName.isNotEmpty ? senderName[0].toUpperCase() : '?',
                                        style: TextStyle(color: mint, fontWeight: FontWeight.bold, fontSize: 17),
                                      )
                                    : null,
                              ),
                            ),
                            const SizedBox(width: 12),

                            // Name and subtitle
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    senderName,
                                    style: TextStyle(color: textPrim, fontWeight: FontWeight.w700, fontSize: 14.5),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 2),
                                  Row(
                                    children: [
                                      Icon(Icons.person_add_rounded, color: mint, size: 12),
                                      const SizedBox(width: 4),
                                      Expanded(
                                        child: Text(
                                          'Wants to connect with you',
                                          style: TextStyle(color: textSec, fontSize: 11.5),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 6),

                            // Verify & Message button
                            _RequestActionButton(
                              label: 'Message',
                              icon: Icons.chat_bubble_outline_rounded,
                              color: AppTheme.primaryAccent(context),
                              onTap: () => _showVerificationSheet(
                                context: context,
                                senderUid: senderUid,
                                senderName: senderName,
                                senderAvatar: senderAvatar,
                                introNote: introNote,
                                introPhotoUrl: introPhoto,
                              ),
                              isDark: isDark,
                              outlined: true,
                            ),
                            const SizedBox(width: 5),

                            // Accept button
                            _RequestActionButton(
                              label: 'Accept',
                              icon: Icons.check_rounded,
                              color: mint,
                              onTap: () => _respondToRequest(senderUid: senderUid, action: 'accept'),
                              isDark: isDark,
                            ),
                            const SizedBox(width: 5),

                            // Decline button
                            _RequestActionButton(
                              label: 'Decline',
                              icon: Icons.close_rounded,
                              color: Colors.redAccent,
                              onTap: () => _respondToRequest(senderUid: senderUid, action: 'decline'),
                              isDark: isDark,
                              outlined: true,
                            ),
                          ],
                        ),
                        if ((introNote != null && introNote.isNotEmpty) || (introPhoto != null && introPhoto.isNotEmpty)) ...[
                          const SizedBox(height: 10),
                          InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () => _showVerificationSheet(
                              context: context,
                              senderUid: senderUid,
                              senderName: senderName,
                              senderAvatar: senderAvatar,
                              introNote: introNote,
                              introPhotoUrl: introPhoto,
                            ),
                            child: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: surfaceElevated,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: mint.withValues(alpha: 0.2)),
                              ),
                              child: Row(
                                children: [
                                  if (introPhoto != null && introPhoto.isNotEmpty) ...[
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: Image.network(
                                        introPhoto,
                                        width: 44,
                                        height: 44,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) => const Icon(Icons.person_rounded, size: 24),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                  ],
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Icon(Icons.badge_rounded, color: mint, size: 13),
                                            const SizedBox(width: 4),
                                            Text(
                                              'Identity Note (Tap to reply)',
                                              style: TextStyle(color: mint, fontWeight: FontWeight.bold, fontSize: 11.5),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          introNote?.isNotEmpty == true ? introNote! : 'Photo attached for identification.',
                                          style: TextStyle(color: textPrim, fontSize: 12.5, fontStyle: FontStyle.italic),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),
                                  Icon(Icons.chevron_right_rounded, color: textSec, size: 18),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Small Accept/Decline action button for request cards.
class _RequestActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final bool isDark;
  final bool outlined;

  const _RequestActionButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
    required this.isDark,
    this.outlined = false,
  });

  @override
  Widget build(BuildContext context) {
    if (outlined) {
      return OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 14),
        label: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
        style: OutlinedButton.styleFrom(
          foregroundColor: color,
          side: BorderSide(color: color.withValues(alpha: 0.6)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      );
    }
    return ElevatedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 14),
      label: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: isDark ? Colors.black : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        elevation: 0,
      ),
    );
  }
}
