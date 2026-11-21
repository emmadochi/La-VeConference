import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../theme/app_theme.dart';
import '../services/contact_service.dart';
import '../services/chat_service.dart';
import '../services/media_storage_service.dart';
import 'chat_conversation_screen.dart';

class CreateGroupScreen extends StatefulWidget {
  const CreateGroupScreen({super.key});

  @override
  State<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends State<CreateGroupScreen> {
  final TextEditingController _groupNameController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  final Set<String> _selectedUids = {};
  final Map<String, String> _selectedNames = {};
  final Map<String, String?> _selectedAvatars = {};
  String _searchQuery = '';
  bool _isCreating = false;
  bool _isChannel = false;
  String? _myUid;
  String? _myName;

  @override
  void initState() {
    super.initState();
    final user = FirebaseAuth.instance.currentUser;
    _myUid = user?.uid;
    _myName = user?.displayName ?? 'User';
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.trim().toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _groupNameController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _createGroup() async {
    final groupName = _groupNameController.text.trim();
    if (groupName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a group subject'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    if (_selectedUids.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select at least 1 contact'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    if (_myUid == null) return;

    setState(() => _isCreating = true);

    try {
      final memberUids = _selectedUids.toList();
      final chatId = await ChatService.createGroupChat(
        groupName: groupName,
        memberUids: memberUids,
        myUid: _myUid!,
        myName: _myName!,
        isChannel: _isChannel,
      );

      if (mounted) {
        Navigator.pop(context); // close create group screen
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ChatConversationScreen(
              peerUid: chatId,
              peerName: groupName,
              isGroup: true,
              chatIdOverride: chatId,
              groupParticipants: [_myUid!, ...memberUids],
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isCreating = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to create group: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  Widget _buildGroupDetailsInput(BuildContext context) {
    final surface = AppTheme.surfaceColor(context);
    final surfaceElevated = AppTheme.surfaceElevatedColor(context);
    final border = AppTheme.borderColor(context);
    final textPrim = AppTheme.text(context);
    final textMuted = AppTheme.textMut(context);
    final mint = AppTheme.mintColor(context);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border.withValues(alpha: 0.8)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Group Avatar placeholder with badge
          Stack(
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      mint.withValues(alpha: 0.25),
                      mint.withValues(alpha: 0.08),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  shape: BoxShape.circle,
                  border: Border.all(color: mint.withValues(alpha: 0.5), width: 1.5),
                ),
                child: Icon(Icons.groups_rounded, color: mint, size: 30),
              ),
              Positioned(
                bottom: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: surfaceElevated,
                    shape: BoxShape.circle,
                    border: Border.all(color: border, width: 1),
                  ),
                  child: Icon(Icons.camera_alt_rounded, size: 12, color: mint),
                ),
              ),
            ],
          ),
          const SizedBox(width: 16),

          // Group subject input
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _groupNameController,
                  maxLength: 35,
                  style: TextStyle(
                    color: textPrim,
                    fontSize: 15.5,
                    fontWeight: FontWeight.w600,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Enter group subject...',
                    hintStyle: TextStyle(
                      color: textMuted.withValues(alpha: 0.7),
                      fontSize: 14.5,
                      fontWeight: FontWeight.normal,
                    ),
                    counterText: '',
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                    border: UnderlineInputBorder(
                      borderSide: BorderSide(color: border.withValues(alpha: 0.8)),
                    ),
                    focusedBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: mint, width: 2),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _isChannel
                      ? 'Create an announcement channel where only admins can post'
                      : 'Provide a group subject and optional group icon',
                  style: TextStyle(color: textMuted, fontSize: 11.5),
                ),
                const SizedBox(height: 14),

                // Channel vs Group Selector
                Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: surfaceElevated,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: border),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: () => setState(() => _isChannel = false),
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            decoration: BoxDecoration(
                              color: !_isChannel ? mint.withValues(alpha: 0.25) : Colors.transparent,
                              borderRadius: BorderRadius.circular(10),
                              border: !_isChannel ? Border.all(color: mint.withValues(alpha: 0.5)) : null,
                            ),
                            alignment: Alignment.center,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.groups_rounded, size: 16, color: !_isChannel ? mint : textMuted),
                                const SizedBox(width: 6),
                                Text(
                                  'Group',
                                  style: TextStyle(
                                    color: !_isChannel ? textPrim : textMuted,
                                    fontSize: 12.5,
                                    fontWeight: !_isChannel ? FontWeight.bold : FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: InkWell(
                          onTap: () => setState(() => _isChannel = true),
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            decoration: BoxDecoration(
                              color: _isChannel ? mint.withValues(alpha: 0.25) : Colors.transparent,
                              borderRadius: BorderRadius.circular(10),
                              border: _isChannel ? Border.all(color: mint.withValues(alpha: 0.5)) : null,
                            ),
                            alignment: Alignment.center,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.campaign_rounded, size: 16, color: _isChannel ? mint : textMuted),
                                const SizedBox(width: 6),
                                Text(
                                  'Channel',
                                  style: TextStyle(
                                    color: _isChannel ? textPrim : textMuted,
                                    fontSize: 12.5,
                                    fontWeight: _isChannel ? FontWeight.bold : FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectedMembersPills(BuildContext context) {
    final mint = AppTheme.mintColor(context);
    final border = AppTheme.borderColor(context);
    final surfaceElevated = AppTheme.surfaceElevatedColor(context);

    if (_selectedUids.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: surfaceElevated.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'SELECTED MEMBERS (${_selectedUids.length})',
                style: TextStyle(
                  color: mint,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                ),
              ),
              InkWell(
                onTap: () {
                  setState(() {
                    _selectedUids.clear();
                    _selectedNames.clear();
                    _selectedAvatars.clear();
                  });
                },
                child: Text(
                  'Clear All',
                  style: TextStyle(
                    color: AppTheme.textMut(context),
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 42,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: _selectedUids.map((uid) {
                final name = _selectedNames[uid] ?? 'User';
                final avatar = _selectedAvatars[uid];

                return Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: mint.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: mint.withValues(alpha: 0.35)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircleAvatar(
                        radius: 12,
                        backgroundColor: mint.withValues(alpha: 0.25),
                        backgroundImage: MediaStorageService.getAvatarProvider(avatar),
                        child: (avatar == null || avatar.isEmpty)
                            ? Text(
                                name.isNotEmpty ? name[0].toUpperCase() : 'U',
                                style: TextStyle(
                                  color: mint,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              )
                            : null,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        name,
                        style: TextStyle(
                          color: mint,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 4),
                      InkWell(
                        onTap: () {
                          setState(() {
                            _selectedUids.remove(uid);
                            _selectedNames.remove(uid);
                            _selectedAvatars.remove(uid);
                          });
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(2),
                          child: Icon(Icons.close_rounded, color: mint, size: 14),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchField(BuildContext context) {
    final surfaceElevated = AppTheme.surfaceElevatedColor(context);
    final border = AppTheme.borderColor(context);
    final textPrim = AppTheme.text(context);
    final textMuted = AppTheme.textMut(context);

    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: surfaceElevated.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border.withValues(alpha: 0.8)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Icon(Icons.search_rounded, color: textMuted, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _searchController,
              style: TextStyle(color: textPrim, fontSize: 13.5),
              decoration: InputDecoration(
                hintText: 'Search contacts to add...',
                hintStyle: TextStyle(color: textMuted, fontSize: 13.5),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
          if (_searchQuery.isNotEmpty)
            GestureDetector(
              onTap: () => _searchController.clear(),
              child: Icon(Icons.clear_rounded, color: textMuted, size: 16),
            ),
        ],
      ),
    );
  }

  Widget _buildContactTile({
    required BuildContext context,
    required String uid,
    required String name,
    String? avatar,
    required bool isSelected,
  }) {
    final surface = AppTheme.surfaceColor(context);
    final surfaceElevated = AppTheme.surfaceElevatedColor(context);
    final border = AppTheme.borderColor(context);
    final textPrim = AppTheme.text(context);
    final textMuted = AppTheme.textMut(context);
    final mint = AppTheme.mintColor(context);
    final isDark = AppTheme.isDarkMode(context);

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: isSelected ? mint.withValues(alpha: isDark ? 0.14 : 0.08) : surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSelected ? mint.withValues(alpha: 0.5) : border.withValues(alpha: 0.6),
          width: isSelected ? 1.5 : 1,
        ),
      ),
      child: ListTile(
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
        onTap: () {
          setState(() {
            if (isSelected) {
              _selectedUids.remove(uid);
              _selectedNames.remove(uid);
              _selectedAvatars.remove(uid);
            } else {
              _selectedUids.add(uid);
              _selectedNames[uid] = name;
              _selectedAvatars[uid] = avatar;
            }
          });
        },
        leading: Stack(
          children: [
            CircleAvatar(
              radius: 19,
              backgroundColor: surfaceElevated,
              backgroundImage: MediaStorageService.getAvatarProvider(avatar),
              child: (avatar == null || avatar.isEmpty)
                  ? Text(
                      name.isNotEmpty ? name[0].toUpperCase() : 'U',
                      style: TextStyle(
                        color: mint,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    )
                  : null,
            ),
          ],
        ),
        title: Text(
          name,
          style: TextStyle(
            color: textPrim,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
            fontSize: 14,
          ),
        ),
        trailing: Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isSelected ? mint : Colors.transparent,
            border: Border.all(
              color: isSelected ? mint : textMuted.withValues(alpha: 0.5),
              width: 1.5,
            ),
          ),
          child: isSelected
              ? Icon(
                  Icons.check_rounded,
                  size: 15,
                  color: isDark ? Colors.black : Colors.white,
                )
              : null,
        ),
      ),
    );
  }

  Widget _buildContentBody(BuildContext context, {required bool isDesktop}) {
    final textSec = AppTheme.textSec(context);
    final textMuted = AppTheme.textMut(context);
    final mint = AppTheme.mintColor(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. Group details (avatar + subject)
        _buildGroupDetailsInput(context),

        // 2. Selected members pills
        _buildSelectedMembersPills(context),
        const SizedBox(height: 14),

        // 3. Search contacts bar
        _buildSearchField(context),
        const SizedBox(height: 12),

        // 4. Section title
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Text(
            'SELECT PARTICIPANTS',
            style: TextStyle(
              color: textSec,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            ),
          ),
        ),
        const SizedBox(height: 6),

        // 5. Contact List Stream
        Expanded(
          child: StreamBuilder<List<Map<String, dynamic>>>(
            stream: ContactService.streamContacts(_myUid!),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return Center(child: CircularProgressIndicator(color: mint));
              }

              final allContacts = snapshot.data!;
              final contacts = _searchQuery.isEmpty
                  ? allContacts
                  : allContacts.where((c) {
                      final n = (c['name'] ?? '').toString().toLowerCase();
                      final code = (c['lichatCode'] ?? '').toString().toLowerCase();
                      return n.contains(_searchQuery) || code.contains(_searchQuery);
                    }).toList();

              if (contacts.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _searchQuery.isEmpty
                              ? Icons.people_outline_rounded
                              : Icons.search_off_rounded,
                          size: 42,
                          color: textMuted.withValues(alpha: 0.6),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          _searchQuery.isEmpty
                              ? 'No contacts found. Pair with contacts to add them to a group.'
                              : 'No contacts match "$_searchQuery"',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: textMuted, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                );
              }

              return ListView.builder(
                itemCount: contacts.length,
                padding: const EdgeInsets.only(bottom: 12),
                itemBuilder: (context, index) {
                  final contact = contacts[index];
                  final uid = contact['uid'] as String? ?? '';
                  final name = contact['name'] as String? ?? 'User';
                  final avatar = contact['avatar'] as String?;
                  final isSelected = _selectedUids.contains(uid);

                  return _buildContactTile(
                    context: context,
                    uid: uid,
                    name: name,
                    avatar: avatar,
                    isSelected: isSelected,
                  );
                },
              );
            },
          ),
        ),

        // 6. Action Footer Bar (Desktop or Mobile embedded)
        if (isDesktop) _buildDesktopFooterBar(context),
      ],
    );
  }

  Widget _buildDesktopFooterBar(BuildContext context) {
    final border = AppTheme.borderColor(context);
    final textMuted = AppTheme.textMut(context);
    final mint = AppTheme.mintColor(context);
    final isDark = AppTheme.isDarkMode(context);

    return Container(
      padding: const EdgeInsets.only(top: 14),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: border.withValues(alpha: 0.8), width: 1)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: textMuted,
              side: BorderSide(color: border),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            ),
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 12),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: mint,
              foregroundColor: isDark ? Colors.black : Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            ),
            onPressed: _isCreating ? null : _createGroup,
            icon: _isCreating
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      color: isDark ? Colors.black : Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : const Icon(Icons.check_rounded, size: 18),
            label: Text(
              _isCreating ? 'Creating Group...' : 'Create Group (${_selectedUids.length})',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bg = AppTheme.bg(context);
    final surface = AppTheme.surfaceColor(context);
    final border = AppTheme.borderColor(context);
    final textPrim = AppTheme.text(context);
    final mint = AppTheme.mintColor(context);
    final isDark = AppTheme.isDarkMode(context);

    if (_myUid == null) {
      return Scaffold(
        backgroundColor: bg,
        body: Center(child: CircularProgressIndicator(color: mint)),
      );
    }

    final isDesktop = MediaQuery.of(context).size.width >= 700;

    if (isDesktop) {
      return Scaffold(
        backgroundColor: bg,
        appBar: AppBar(
          backgroundColor: bg,
          elevation: 0,
          leading: IconButton(
            icon: Icon(Icons.arrow_back_rounded, color: textPrim),
            onPressed: () => Navigator.pop(context),
            tooltip: 'Back',
          ),
          title: Text(
            'New Group',
            style: TextStyle(color: textPrim, fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ),
        body: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 640),
            margin: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: border.withValues(alpha: 0.8)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.06),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: _buildContentBody(context, isDesktop: true),
          ),
        ),
      );
    }

    // Mobile layout
    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        title: Text(
          'New Group',
          style: TextStyle(color: textPrim, fontSize: 18, fontWeight: FontWeight.bold),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: _buildContentBody(context, isDesktop: false),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: mint,
        foregroundColor: isDark ? Colors.black : Colors.white,
        onPressed: _isCreating ? null : _createGroup,
        icon: _isCreating
            ? SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  color: isDark ? Colors.black : Colors.white,
                  strokeWidth: 2,
                ),
              )
            : const Icon(Icons.check_rounded, size: 20),
        label: Text(
          _isCreating ? 'Creating...' : 'Create Group (${_selectedUids.length})',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}
