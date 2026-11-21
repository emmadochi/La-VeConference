import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:share_plus/share_plus.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../theme/app_theme.dart';
import '../services/chat_service.dart';
import '../services/media_storage_service.dart';
import '../services/contact_service.dart';

/// Full Group Info, Admin Controls & Invite Link screen.
class GroupInfoScreen extends StatefulWidget {
  final String chatId;
  final String groupName;
  final String? groupAvatar;
  final bool isCurrentUserAdmin;

  const GroupInfoScreen({
    super.key,
    required this.chatId,
    required this.groupName,
    this.groupAvatar,
    required this.isCurrentUserAdmin,
  });

  @override
  State<GroupInfoScreen> createState() => _GroupInfoScreenState();
}

class _GroupInfoScreenState extends State<GroupInfoScreen>
    with SingleTickerProviderStateMixin {
  final String _myUid = FirebaseAuth.instance.currentUser?.uid ?? '';
  final String _myName = FirebaseAuth.instance.currentUser?.displayName ?? 'User';
  late final TabController _tabController;
  final TextEditingController _memberSearchCtrl = TextEditingController();
  String _memberSearchQuery = '';
  bool _isGeneratingLink = false;
  bool _isRevokingLink = false;
  bool _showQr = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _memberSearchCtrl.addListener(() {
      setState(() {
        _memberSearchQuery = _memberSearchCtrl.text.trim().toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _memberSearchCtrl.dispose();
    super.dispose();
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────

  bool _isAdmin(List<String> admins) => admins.contains(_myUid);

  Future<String> _ensureInviteLink(String chatId) async {
    setState(() => _isGeneratingLink = true);
    final link = await ChatService.generateInviteLink(chatId);
    if (mounted) setState(() => _isGeneratingLink = false);
    return link;
  }

  void _copyLink(String link) {
    Clipboard.setData(ClipboardData(text: link));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(children: [
          Icon(Icons.check_circle_rounded, color: AppTheme.primaryAccent(context), size: 16),
          const SizedBox(width: 8),
          const Text('Invite link copied!', style: TextStyle(color: Colors.white)),
        ]),
        backgroundColor: AppTheme.surfaceElevatedColor(context),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _revokeLink(String chatId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceElevatedColor(context),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text('Revoke Invite Link?',
            style: TextStyle(color: AppTheme.text(context), fontWeight: FontWeight.bold)),
        content: Text(
          'This link will stop working immediately. All existing links will be invalid.',
          style: TextStyle(color: AppTheme.textSec(context)),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Cancel', style: TextStyle(color: AppTheme.textSec(context)))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.callRed,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Revoke', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      setState(() => _isRevokingLink = true);
      await ChatService.revokeInviteLink(chatId);
      if (mounted) setState(() => _isRevokingLink = false);
    }
  }

  void _showAddGroupMembersSheet(List<String> currentParticipants) {
    if (_myUid.isEmpty) return;
    final Set<String> newlySelectedUids = {};
    final Map<String, String> newlySelectedNames = {};
    final existingUids = Set<String>.from(currentParticipants);

    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surfaceColor(context),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              child: Container(
                height: MediaQuery.of(context).size.height * 0.75,
                padding: const EdgeInsets.only(top: 12),
                child: Column(
                  children: [
                    Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: AppTheme.borderColor(context),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                      child: Row(
                        children: [
                          Icon(Icons.group_add_rounded, color: AppTheme.primaryAccent(context), size: 22),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Add Members to Group',
                              style: TextStyle(
                                color: AppTheme.text(context),
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          if (newlySelectedUids.isNotEmpty)
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.primaryAccent(context),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              ),
                              onPressed: () async {
                                final uids = newlySelectedUids.toList();
                                final names = uids.map((id) => newlySelectedNames[id] ?? 'Contact').toList();
                                Navigator.pop(sheetCtx);

                                try {
                                  await ChatService.addParticipantsToGroup(
                                    chatId: widget.chatId,
                                    newMemberUids: uids,
                                    newMemberNames: names,
                                    adderUid: _myUid,
                                    adderName: _myName,
                                  );

                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('Added ${names.join(", ")} to the group!'),
                                        backgroundColor: AppTheme.primaryAccent(context),
                                      ),
                                    );
                                  }
                                } catch (e) {
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('Failed to add members: $e'),
                                        backgroundColor: AppTheme.callRed,
                                      ),
                                    );
                                  }
                                }
                              },
                              child: Text(
                                'Add (${newlySelectedUids.length})',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: StreamBuilder<List<Map<String, dynamic>>>(
                        stream: _myUid.isNotEmpty ? ContactService.streamContacts(_myUid) : const Stream.empty(),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState == ConnectionState.waiting) {
                            return const Center(child: CircularProgressIndicator());
                          }
                          final contacts = snapshot.data ?? [];
                          final eligibleContacts = contacts.where((c) {
                            final contactUid = c['uid'] as String?;
                            return contactUid != null && !existingUids.contains(contactUid);
                          }).toList();

                          if (eligibleContacts.isEmpty) {
                            return Center(
                              child: Text(
                                'No more contacts to add.',
                                style: TextStyle(color: AppTheme.textSec(context)),
                              ),
                            );
                          }

                          return ListView.builder(
                            itemCount: eligibleContacts.length,
                            itemBuilder: (context, index) {
                              final contactData = eligibleContacts[index];
                              final contactUid = contactData['uid'] as String? ?? '';
                              final contactName = contactData['name'] as String? ?? 'Contact';
                              final contactAvatar = contactData['avatar'] as String?;
                              final isSelected = newlySelectedUids.contains(contactUid);

                              return ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: AppTheme.primaryAccent(context).withValues(alpha: 0.15),
                                  backgroundImage: MediaStorageService.getAvatarProvider(contactAvatar),
                                  child: (contactAvatar == null || contactAvatar.isEmpty)
                                      ? Text(
                                          contactName.isNotEmpty ? contactName[0].toUpperCase() : 'C',
                                          style: TextStyle(
                                            color: AppTheme.primaryAccent(context),
                                            fontWeight: FontWeight.bold,
                                          ),
                                        )
                                      : null,
                                ),
                                title: Text(
                                  contactName,
                                  style: TextStyle(
                                    color: AppTheme.text(context),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                trailing: Checkbox(
                                  value: isSelected,
                                  activeColor: AppTheme.primaryAccent(context),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                                  onChanged: (val) {
                                    setSheetState(() {
                                      if (val == true) {
                                        newlySelectedUids.add(contactUid);
                                        newlySelectedNames[contactUid] = contactName;
                                      } else {
                                        newlySelectedUids.remove(contactUid);
                                        newlySelectedNames.remove(contactUid);
                                      }
                                    });
                                  },
                                ),
                                onTap: () {
                                  setSheetState(() {
                                    if (isSelected) {
                                      newlySelectedUids.remove(contactUid);
                                      newlySelectedNames.remove(contactUid);
                                    } else {
                                      newlySelectedUids.add(contactUid);
                                      newlySelectedNames[contactUid] = contactName;
                                    }
                                  });
                                },
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showMemberOptions(BuildContext ctx, Map<String, dynamic> groupData, String memberUid, String memberName) {
    final admins = List<String>.from(groupData['admins'] ?? []);
    final creatorId = groupData['creatorId'] as String? ?? '';
    final isMemberAdmin = admins.contains(memberUid);
    final isMemberCreator = memberUid == creatorId;
    final canManage = widget.isCurrentUserAdmin && !isMemberCreator && memberUid != _myUid;

    if (!canManage) return;

    showModalBottomSheet(
      context: ctx,
      backgroundColor: AppTheme.surfaceElevatedColor(context),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 8, bottom: 12),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                  color: AppTheme.textMut(context).withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(2)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(memberName,
                  style: TextStyle(color: AppTheme.text(context), fontWeight: FontWeight.bold, fontSize: 16)),
            ),
            if (!isMemberAdmin)
              ListTile(
                leading: Icon(Icons.shield_rounded, color: AppTheme.primaryAccent(context)),
                title: Text('Make Admin', style: TextStyle(color: AppTheme.text(context))),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  ChatService.promoteMemberToAdmin(
                      chatId: widget.chatId,
                      targetUid: memberUid,
                      promoterName: _myName);
                },
              )
            else
              ListTile(
                leading: Icon(Icons.shield_outlined, color: AppTheme.textSec(context)),
                title: Text('Dismiss as Admin', style: TextStyle(color: AppTheme.textSec(context))),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  ChatService.demoteAdminToMember(chatId: widget.chatId, targetUid: memberUid);
                },
              ),
            ListTile(
              leading: const Icon(Icons.person_remove_rounded, color: Colors.redAccent),
              title: const Text('Remove from Group', style: TextStyle(color: Colors.redAccent)),
              onTap: () {
                Navigator.pop(sheetCtx);
                ChatService.removeMemberFromGroup(
                    chatId: widget.chatId,
                    targetUid: memberUid,
                    targetName: memberName,
                    removerName: _myName);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // ─── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: ChatService.streamGroupInfo(widget.chatId),
      builder: (context, snap) {
        final data = snap.data?.data() ?? {};
        final admins = List<String>.from(data['admins'] ?? []);
        final participants = List<String>.from(data['participants'] ?? []);
        final isAdmin = _isAdmin(admins) || widget.isCurrentUserAdmin;
        final onlyAdminsCanPost = data['onlyAdminsCanPost'] == true;
        final onlyAdminsCanEditInfo = data['onlyAdminsCanEditInfo'] == true;
        final onlyAdminsCanAddMembers = data['onlyAdminsCanAddMembers'] == true;
        final inviteToken = data['inviteToken'] as String?;
        final inviteLink = inviteToken != null ? 'https://lichat.app/join/$inviteToken' : null;

        return Scaffold(
          backgroundColor: AppTheme.bg(context),
          body: NestedScrollView(
            headerSliverBuilder: (_, __) => [
              _buildSliverAppBar(context, data, admins),
            ],
            body: Column(
              children: [
                // Tabs
                Container(
                  color: AppTheme.surfaceColor(context),
                  child: TabBar(
                    controller: _tabController,
                    indicatorColor: AppTheme.primaryAccent(context),
                    indicatorWeight: 3,
                    labelColor: AppTheme.primaryAccent(context),
                    unselectedLabelColor: AppTheme.textMut(context),
                    labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                    unselectedLabelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    tabs: const [
                      Tab(text: 'MEMBERS'),
                      Tab(text: 'PERMISSIONS'),
                      Tab(text: 'INVITE'),
                    ],
                  ),
                ),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildMembersTab(participants, admins, data, onlyAdminsCanAddMembers),
                      _buildPermissionsTab(
                          context, isAdmin, onlyAdminsCanPost, onlyAdminsCanEditInfo, onlyAdminsCanAddMembers),
                      _buildInviteTab(context, isAdmin, inviteLink),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ─── SliverAppBar ─────────────────────────────────────────────────────────

  SliverAppBar _buildSliverAppBar(BuildContext context, Map<String, dynamic> data, List<String> admins) {
    final groupName = (data['name'] ?? data['groupName'] ?? widget.groupName) as String;
    final avatar = (data['groupAvatar'] ?? data['avatar'] ?? widget.groupAvatar) as String?;
    final isAdmin = _isAdmin(admins) || widget.isCurrentUserAdmin;
    final isDark = AppTheme.isDark(context);

    return SliverAppBar(
      pinned: true,
      expandedHeight: 220,
      backgroundColor: isDark ? const Color(0xFF151226) : const Color(0xFF1E1A36),
      iconTheme: const IconThemeData(color: Colors.white),
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
        onPressed: () => Navigator.pop(context),
      ),
      actions: [
        if (isAdmin)
          IconButton(
            icon: const Icon(Icons.edit_rounded, color: AppTheme.lilacLight),
            tooltip: 'Edit Group',
            onPressed: () => _showEditGroupSheet(context, groupName),
          ),
      ],
      flexibleSpace: FlexibleSpaceBar(
        background: Stack(
          fit: StackFit.expand,
          children: [
            // Gradient background
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF1E1A36),
                    Color(0xFF28214A),
                    Color(0xFF151226),
                  ],
                ),
              ),
            ),
            // Avatar + Name
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(height: 36),
                Hero(
                  tag: 'group_avatar_${widget.chatId}',
                  child: CircleAvatar(
                    radius: 44,
                    backgroundColor: AppTheme.lilacDark.withValues(alpha: 0.35),
                    backgroundImage: MediaStorageService.getAvatarProvider(avatar),
                    child: (avatar == null || avatar.isEmpty)
                        ? Text(
                            groupName.isNotEmpty ? groupName[0].toUpperCase() : 'G',
                            style: const TextStyle(
                                color: Colors.white, fontWeight: FontWeight.bold, fontSize: 34))
                        : null,
                  ),
                ),
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    groupName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white, fontSize: 19, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${(data['participants'] as List?)?.length ?? 0} members',
                  style: const TextStyle(color: AppTheme.lilacLight, fontSize: 13, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ─── Members Tab ──────────────────────────────────────────────────────────

  Widget _buildMembersTab(
      List<String> participants, List<String> admins, Map<String, dynamic> groupData, bool onlyAdminsCanAddMembers) {
    final creatorId = groupData['creatorId'] as String? ?? '';
    final isAdmin = _isAdmin(admins) || widget.isCurrentUserAdmin;
    final canAddMembers = isAdmin || !onlyAdminsCanAddMembers;

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        // 1. Search Bar
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Container(
            decoration: BoxDecoration(
              color: AppTheme.surfaceElevatedColor(context),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.borderColor(context)),
            ),
            child: TextField(
              controller: _memberSearchCtrl,
              style: TextStyle(color: AppTheme.text(context), fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Search members...',
                hintStyle: TextStyle(color: AppTheme.textMut(context), fontSize: 13),
                prefixIcon: Icon(Icons.search_rounded, color: AppTheme.primaryAccent(context), size: 20),
                suffixIcon: _memberSearchQuery.isNotEmpty
                    ? IconButton(
                        icon: Icon(Icons.close_rounded, color: AppTheme.textMut(context), size: 18),
                        onPressed: () => _memberSearchCtrl.clear(),
                      )
                    : null,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ),

        // 2. Add Participants Action Tile (If permitted)
        if (canAddMembers)
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
            leading: CircleAvatar(
              radius: 22,
              backgroundColor: AppTheme.primaryAccent(context),
              child: const Icon(Icons.person_add_alt_1_rounded, color: Colors.white, size: 20),
            ),
            title: Text(
              'Add Members',
              style: TextStyle(
                color: AppTheme.primaryAccent(context),
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
            subtitle: Text(
              'Invite contacts to this group',
              style: TextStyle(color: AppTheme.textSec(context), fontSize: 12),
            ),
            onTap: () => _showAddGroupMembersSheet(participants),
          ),

        if (canAddMembers)
          Divider(height: 16, thickness: 1, indent: 20, endIndent: 20, color: AppTheme.borderColor(context)),

        // 3. Members List
        ...participants.map((uid) {
          final isMemberAdmin = admins.contains(uid);
          final isMemberCreator = uid == creatorId;
          final isMe = uid == _myUid;

          return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            future: FirebaseFirestore.instance.collection('users').doc(uid).get(),
            builder: (ctx2, userSnap) {
              final userData = userSnap.data?.data() ?? {};
              final name = (userData['name'] ?? userData['displayName'] ?? 'User') as String;
              final avatar = userData['photoUrl'] as String?;
              final statusText = (userData['status'] as String?) ?? (userData['phone'] as String?) ?? 'Hey there! I am using LiChat';

              if (_memberSearchQuery.isNotEmpty && !name.toLowerCase().contains(_memberSearchQuery)) {
                return const SizedBox.shrink();
              }

              return ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                leading: CircleAvatar(
                  radius: 22,
                  backgroundColor: AppTheme.primaryAccent(context).withValues(alpha: 0.15),
                  backgroundImage: MediaStorageService.getAvatarProvider(avatar),
                  child: (avatar == null || avatar.isEmpty)
                      ? Text(name.isNotEmpty ? name[0].toUpperCase() : 'U',
                          style: TextStyle(
                              color: AppTheme.primaryAccent(context), fontWeight: FontWeight.bold))
                      : null,
                ),
                title: Row(children: [
                  Flexible(
                    child: Text(
                      isMe ? 'You' : name,
                      style: TextStyle(
                        color: AppTheme.text(context),
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  if (isMemberCreator) ...[
                    const SizedBox(width: 8),
                    _badge('Creator', const Color(0xFFF59E0B)),
                  ] else if (isMemberAdmin) ...[
                    const SizedBox(width: 8),
                    _badge('Admin', AppTheme.primaryAccent(context)),
                  ],
                ]),
                subtitle: Text(
                  statusText,
                  style: TextStyle(color: AppTheme.textSec(context), fontSize: 12),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: isAdmin && !isMemberCreator && !isMe
                    ? Icon(Icons.more_vert_rounded, color: AppTheme.textSec(context), size: 20)
                    : null,
                onLongPress: isAdmin && !isMemberCreator && !isMe
                    ? () => _showMemberOptions(ctx2, groupData, uid, name)
                    : null,
                onTap: isAdmin && !isMemberCreator && !isMe
                    ? () => _showMemberOptions(ctx2, groupData, uid, name)
                    : null,
              );
            },
          );
        }),
      ],
    );
  }

  Widget _badge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold),
      ),
    );
  }

  // ─── Permissions Tab ──────────────────────────────────────────────────────

  Widget _buildPermissionsTab(BuildContext context, bool isAdmin, bool onlyAdminsCanPost,
      bool onlyAdminsCanEditInfo, bool onlyAdminsCanAddMembers) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _sectionHeader('Message Permissions'),
        const SizedBox(height: 8),
        _permissionCard(
          icon: Icons.chat_bubble_outline_rounded,
          title: 'Send Messages',
          subtitle: 'Choose who can send messages to this group',
          value: !onlyAdminsCanPost,
          trueLabel: 'All Members',
          falseLabel: 'Admins Only',
          isAdmin: isAdmin,
          onChanged: isAdmin
              ? (val) => ChatService.updateGroupPermissions(
                    chatId: widget.chatId,
                    onlyAdminsCanPost: !val,
                  )
              : null,
        ),
        const SizedBox(height: 14),
        _sectionHeader('Group Info Permissions'),
        const SizedBox(height: 8),
        _permissionCard(
          icon: Icons.edit_note_rounded,
          title: 'Edit Group Info',
          subtitle: 'Who can change group name, icon, and description',
          value: !onlyAdminsCanEditInfo,
          trueLabel: 'All Members',
          falseLabel: 'Admins Only',
          isAdmin: isAdmin,
          onChanged: isAdmin
              ? (val) => ChatService.updateGroupPermissions(
                    chatId: widget.chatId,
                    onlyAdminsCanEditInfo: !val,
                  )
              : null,
        ),
        const SizedBox(height: 14),
        _sectionHeader('Members Permissions'),
        const SizedBox(height: 8),
        _permissionCard(
          icon: Icons.person_add_alt_1_rounded,
          title: 'Add Members',
          subtitle: 'Who can add new participants to this group',
          value: !onlyAdminsCanAddMembers,
          trueLabel: 'All Members',
          falseLabel: 'Admins Only',
          isAdmin: isAdmin,
          onChanged: isAdmin
              ? (val) => ChatService.updateGroupPermissions(
                    chatId: widget.chatId,
                    onlyAdminsCanAddMembers: !val,
                  )
              : null,
        ),
        if (!isAdmin) ...[
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.surfaceElevatedColor(context),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppTheme.borderColor(context)),
            ),
            child: Row(children: [
              Icon(Icons.info_outline_rounded, color: AppTheme.primaryAccent(context), size: 20),
              const SizedBox(width: 12),
              Flexible(
                child: Text(
                  'Only group admins have permission to change these settings.',
                  style: TextStyle(color: AppTheme.textSec(context), fontSize: 13),
                ),
              ),
            ]),
          ),
        ],
      ],
    );
  }

  Widget _permissionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required String trueLabel,
    required String falseLabel,
    required bool isAdmin,
    ValueChanged<bool>? onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surfaceElevatedColor(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.borderColor(context)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppTheme.primaryAccent(context).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: AppTheme.primaryAccent(context), size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                title,
                style: TextStyle(
                  color: AppTheme.text(context),
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: TextStyle(color: AppTheme.textSec(context), fontSize: 12),
              ),
              const SizedBox(height: 10),
              _pillSelector(
                selected: value,
                trueLabel: trueLabel,
                falseLabel: falseLabel,
                onChanged: onChanged,
              ),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _pillSelector({
    required bool selected,
    required String trueLabel,
    required String falseLabel,
    ValueChanged<bool>? onChanged,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _pill(label: trueLabel, active: selected, onTap: onChanged != null ? () => onChanged(true) : null),
        const SizedBox(width: 8),
        _pill(label: falseLabel, active: !selected, onTap: onChanged != null ? () => onChanged(false) : null),
      ],
    );
  }

  Widget _pill({required String label, required bool active, VoidCallback? onTap}) {
    final activeBg = AppTheme.primaryAccent(context);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: active ? activeBg : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: active ? activeBg : AppTheme.borderColor(context),
            width: active ? 1.5 : 1.0,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? Colors.white : AppTheme.textSec(context),
            fontSize: 12,
            fontWeight: active ? FontWeight.bold : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  // ─── Invite Tab ───────────────────────────────────────────────────────────

  Widget _buildInviteTab(BuildContext context, bool isAdmin, String? inviteLink) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // Info header
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.primaryAccent(context).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.primaryAccent(context).withValues(alpha: 0.25)),
          ),
          child: Row(children: [
            Icon(Icons.link_rounded, color: AppTheme.primaryAccent(context), size: 28),
            const SizedBox(width: 14),
            Flexible(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Group Invite Link',
                    style: TextStyle(
                      color: AppTheme.text(context),
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    )),
                const SizedBox(height: 3),
                Text('Share this link to let people join this group directly.',
                    style: TextStyle(color: AppTheme.textSec(context), fontSize: 12)),
              ]),
            ),
          ]),
        ),

        const SizedBox(height: 20),

        if (inviteLink != null) ...[
          // Link display box
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: AppTheme.surfaceElevatedColor(context),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppTheme.borderColor(context)),
            ),
            child: Row(children: [
              Expanded(
                child: Text(
                  inviteLink,
                  style: TextStyle(
                    color: AppTheme.primaryAccent(context),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 10),
              GestureDetector(
                onTap: () => _copyLink(inviteLink),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryAccent(context).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.copy_rounded, color: AppTheme.primaryAccent(context), size: 18),
                ),
              ),
            ]),
          ),

          const SizedBox(height: 16),

          // Action buttons
          Row(children: [
            Expanded(
              child: _actionButton(
                icon: Icons.share_rounded,
                label: 'Share Link',
                color: AppTheme.primaryAccent(context),
                onTap: () => SharePlus.instance.share(ShareParams(
                  text: 'Join my group on LiChat: $inviteLink',
                )),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _actionButton(
                icon: _showQr ? Icons.qr_code_2_rounded : Icons.qr_code_rounded,
                label: _showQr ? 'Hide QR Code' : 'Show QR Code',
                color: AppTheme.lilacDark,
                onTap: () => setState(() => _showQr = !_showQr),
              ),
            ),
          ]),

          // QR Code display
          if (_showQr) ...[
            const SizedBox(height: 24),
            Center(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.primaryAccent(context).withValues(alpha: 0.25),
                      blurRadius: 20,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: QrImageView(
                  data: inviteLink,
                  version: QrVersions.auto,
                  size: 200,
                  backgroundColor: Colors.white,
                  eyeStyle: const QrEyeStyle(
                    eyeShape: QrEyeShape.square,
                    color: Color(0xFF1E1A36),
                  ),
                  dataModuleStyle: const QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.circle,
                    color: Color(0xFF1E1A36),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Center(
              child: Text(
                'Scan using any camera to join group',
                style: TextStyle(color: AppTheme.textSec(context), fontSize: 12),
              ),
            ),
          ],

          if (isAdmin) ...[
            const SizedBox(height: 28),
            GestureDetector(
              onTap: _isRevokingLink ? null : () => _revokeLink(widget.chatId),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.redAccent.withValues(alpha: 0.35)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (_isRevokingLink)
                      const SizedBox(
                          width: 16, height: 16,
                          child: CircularProgressIndicator(
                              color: Colors.redAccent, strokeWidth: 2))
                    else
                      const Icon(Icons.link_off_rounded, color: Colors.redAccent, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      _isRevokingLink ? 'Revoking...' : 'Revoke Invite Link',
                      style: const TextStyle(
                          color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ] else ...[
          // No link generated yet
          Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const SizedBox(height: 36),
              Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: AppTheme.primaryAccent(context).withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.add_link_rounded,
                    color: AppTheme.primaryAccent(context), size: 48),
              ),
              const SizedBox(height: 18),
              Text(
                'No invite link yet',
                style: TextStyle(
                  color: AppTheme.text(context),
                  fontWeight: FontWeight.bold,
                  fontSize: 17,
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  'Generate an invite link so anyone can join without needing manual addition.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppTheme.textSec(context), fontSize: 13, height: 1.4),
                ),
              ),
              if (isAdmin) ...[
                const SizedBox(height: 24),
                GestureDetector(
                  onTap: _isGeneratingLink
                      ? null
                      : () async {
                          await _ensureInviteLink(widget.chatId);
                        },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF7C3AED), Color(0xFFA855F7)],
                      ),
                      borderRadius: BorderRadius.circular(30),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF7C3AED).withValues(alpha: 0.35),
                          blurRadius: 14,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_isGeneratingLink)
                          const SizedBox(
                              width: 18, height: 18,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2))
                        else
                          const Icon(Icons.add_link_rounded, color: Colors.white, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          _isGeneratingLink ? 'Generating...' : 'Generate Invite Link',
                          style: const TextStyle(
                              color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ]),
          ),
        ],
      ],
    );
  }

  Widget _actionButton(
      {required IconData icon, required String label, required Color color, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 5),
          Text(label,
              style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold)),
        ]),
      ),
    );
  }

  Widget _sectionHeader(String label) {
    return Text(
      label.toUpperCase(),
      style: TextStyle(
        color: AppTheme.primaryAccent(context),
        fontSize: 11.5,
        fontWeight: FontWeight.bold,
        letterSpacing: 1.1,
      ),
    );
  }

  // ─── Edit Group Sheet ─────────────────────────────────────────────────────

  void _showEditGroupSheet(BuildContext context, String currentName) {
    final ctrl = TextEditingController(text: currentName);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surfaceElevatedColor(context),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 24,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Edit Group Name',
                style: TextStyle(
                    color: AppTheme.text(context), fontWeight: FontWeight.bold, fontSize: 17)),
            const SizedBox(height: 16),
            TextField(
              controller: ctrl,
              autofocus: true,
              style: TextStyle(color: AppTheme.text(context)),
              decoration: InputDecoration(
                hintText: 'Group name...',
                hintStyle: TextStyle(color: AppTheme.textMut(context)),
                filled: true,
                fillColor: AppTheme.bg(context),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: AppTheme.borderColor(context))),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: AppTheme.primaryAccent(context), width: 1.5)),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryAccent(context),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: () {
                  Navigator.pop(ctx);
                  final newName = ctrl.text.trim();
                  if (newName.isNotEmpty && newName != currentName) {
                    ChatService.updateGroupName(
                        chatId: widget.chatId,
                        newName: newName,
                        updaterUid: _myUid,
                        updaterName: _myName);
                  }
                },
                child: const Text('Save', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
