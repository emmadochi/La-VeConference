import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../theme/app_theme.dart';
import '../services/chat_service.dart';
import '../services/contact_service.dart';
import '../services/presence_service.dart';
import 'chat_conversation_screen.dart';
import 'create_group_screen.dart';
import 'qr_connect_screen.dart';
import 'starred_messages_screen.dart';
import '../services/media_storage_service.dart';
import '../services/local_db_service.dart';

typedef OnChatSelectedCallback = void Function({
  required String peerUid,
  required String peerName,
  String? peerAvatar,
  required bool isGroup,
  String? chatId,
  List<String>? participants,
});

class ChatListScreen extends StatefulWidget {
  final OnChatSelectedCallback? onChatSelected;
  final String? selectedChatId;
  final bool isDesktop;

  const ChatListScreen({
    super.key,
    this.onChatSelected,
    this.selectedChatId,
    this.isDesktop = false,
  });

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  String? _myUid;
  String? _myName;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _selectedFilter = 'All'; // 'All', 'Unread', 'Groups'
  List<String> _pinnedChats = [];
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _pinnedSubscription;
  StreamSubscription<List<Map<String, dynamic>>>? _contactsSubscription;
  final Map<String, Map<String, dynamic>> _contactsMap = {};
  final Set<String> _pendingProfileFetches = {};
  StreamSubscription<User?>? _authSubscription;
  List<Map<String, dynamic>> _cachedConversations = [];
  bool _hasStreamTimedOut = false;

  void _openConversation({
    required String peerUid,
    required String peerName,
    String? peerAvatar,
    bool isGroup = false,
    String? chatIdOverride,
    List<String>? groupParticipants,
  }) {
    if (widget.onChatSelected != null) {
      widget.onChatSelected!(
        peerUid: peerUid,
        peerName: peerName,
        peerAvatar: peerAvatar,
        isGroup: isGroup,
        chatId: chatIdOverride,
        participants: groupParticipants,
      );
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ChatConversationScreen(
            peerUid: peerUid,
            peerName: peerName,
            peerAvatar: peerAvatar,
            isGroup: isGroup,
            chatIdOverride: chatIdOverride,
            groupParticipants: groupParticipants,
          ),
        ),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    _initUser(FirebaseAuth.instance.currentUser);
    _authSubscription = FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user != null && user.uid != _myUid) {
        _initUser(user);
      }
    });

    // Safety timeout: never hang indefinitely on connection spinners
    Timer(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() => _hasStreamTimedOut = true);
      }
    });

    // 0ms instant display: load local SQLite cached conversations
    LocalDbService.loadConversations().then((cached) {
      if (mounted && cached.isNotEmpty && _cachedConversations.isEmpty) {
        setState(() {
          _cachedConversations = cached;
        });
      }
    });
  }

  void _initUser(User? user) {
    if (user == null) return;
    _myUid = user.uid;
    _myName = user.displayName ?? 'User';

    _contactsSubscription?.cancel();
    _contactsSubscription = ContactService.streamContacts(_myUid!).listen((contacts) {
      if (mounted) {
        setState(() {
          _contactsMap.clear();
          for (final c in contacts) {
            final uid = (c['uid'] as String?) ?? '';
            if (uid.isNotEmpty) {
              _contactsMap[uid] = c;
            }
          }
        });
      }
    });

    _pinnedSubscription?.cancel();
    _pinnedSubscription = FirebaseFirestore.instance
        .collection('users')
        .doc(_myUid)
        .snapshots()
        .listen((doc) {
      if (mounted && doc.exists) {
        final data = doc.data();
        setState(() {
          _pinnedChats = List<String>.from(data?['pinnedChats'] ?? []);
        });
      }
    });

    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _pinnedSubscription?.cancel();
    _contactsSubscription?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  int _extractTimestamp(Map<String, dynamic> data) {
    final raw = data['lastMessageTime'] ?? data['lastTimestamp'] ?? data['timestamp'];
    if (raw is Timestamp) return raw.millisecondsSinceEpoch;
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    if (raw is String) {
      final parsed = DateTime.tryParse(raw);
      if (parsed != null) return parsed.millisecondsSinceEpoch;
    }
    return 0;
  }

  String _formatChatTimestamp(dynamic rawTime) {
    if (rawTime == null) return '';
    DateTime? dateTime;
    if (rawTime is Timestamp) {
      dateTime = rawTime.toDate();
    } else if (rawTime is int) {
      dateTime = DateTime.fromMillisecondsSinceEpoch(rawTime);
    } else if (rawTime is num) {
      dateTime = DateTime.fromMillisecondsSinceEpoch(rawTime.toInt());
    } else if (rawTime is String) {
      dateTime = DateTime.tryParse(rawTime);
    }
    if (dateTime == null) return '';

    final local = dateTime.toLocal();
    final now = DateTime.now();

    final today = DateTime(now.year, now.month, now.day);
    final messageDay = DateTime(local.year, local.month, local.day);
    final diff = today.difference(messageDay).inDays;

    if (diff == 0) {
      return DateFormat('h:mm a').format(local);
    } else if (diff == 1) {
      return 'Yesterday';
    } else if (diff > 1 && diff < 7) {
      return DateFormat('EEEE').format(local);
    } else {
      return DateFormat('M/d/yy').format(local);
    }
  }

  void _showChatOptions({
    required String chatId,
    required String chatName,
    String? chatAvatar,
    required bool isGroup,
    List<String>? participants,
    int unreadCount = 0,
    String? peerUid,
  }) {
    HapticFeedback.mediumImpact();
    final surface = AppTheme.surfaceColor(context);
    final surfaceElevated = AppTheme.surfaceElevatedColor(context);
    final textPrim = AppTheme.text(context);
    final textMuted = AppTheme.textMut(context);
    final border = AppTheme.borderColor(context);
    final mint = AppTheme.mintColor(context);

    final isPinned = _pinnedChats.contains(chatId);

    showModalBottomSheet(
      context: context,
      backgroundColor: surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (modalCtx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Top drag handle
                Container(
                  width: 38,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    color: border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),

                // Chat Summary Header
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 20,
                        backgroundColor: surfaceElevated,
                        backgroundImage: MediaStorageService.getAvatarProvider(chatAvatar),
                        child: (chatAvatar == null || chatAvatar.isEmpty)
                            ? (isGroup
                                ? Icon(Icons.groups_rounded, color: mint, size: 20)
                                : Text(
                                    chatName.isNotEmpty ? chatName[0].toUpperCase() : 'U',
                                    style: TextStyle(color: mint, fontWeight: FontWeight.bold, fontSize: 16),
                                  ))
                            : null,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              chatName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: textPrim, fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                            Text(
                              isGroup ? '${participants?.length ?? 0} members' : 'Direct Conversation',
                              style: TextStyle(color: textMuted, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 10),
                Divider(color: border, height: 1),
                const SizedBox(height: 6),

                // 0. Pin / Unpin to Top
                ListTile(
                  leading: Icon(
                    isPinned ? Icons.push_pin_outlined : Icons.push_pin_rounded,
                    color: mint,
                  ),
                  title: Text(
                    isPinned ? 'Unpin from Top' : 'Pin to Top',
                    style: TextStyle(color: textPrim, fontWeight: FontWeight.w600, fontSize: 14.5),
                  ),
                  onTap: () {
                    Navigator.pop(modalCtx);
                    if (_myUid != null) {
                      ChatService.togglePinChat(
                        myUid: _myUid!,
                        chatId: chatId,
                        isCurrentlyPinned: isPinned,
                      );
                    }
                  },
                ),

                // 1. Mark as Read / Unread
                ListTile(
                  leading: Icon(
                    unreadCount > 0 ? Icons.mark_chat_read_rounded : Icons.mark_chat_unread_rounded,
                    color: mint,
                  ),
                  title: Text(
                    unreadCount > 0 ? 'Mark as Read' : 'Mark as Unread',
                    style: TextStyle(color: textPrim, fontWeight: FontWeight.w600, fontSize: 14.5),
                  ),
                  onTap: () {
                    Navigator.pop(modalCtx);
                    if (_myUid != null) {
                      if (unreadCount > 0) {
                        ChatService.markAsRead(chatId, _myUid!);
                      } else {
                        ChatService.markAsUnread(chatId, _myUid!);
                      }
                    }
                  },
                ),

                // 2. Clear Chat History
                ListTile(
                  leading: const Icon(Icons.cleaning_services_rounded, color: Colors.orangeAccent),
                  title: Text(
                    'Clear Chat Messages',
                    style: TextStyle(color: textPrim, fontWeight: FontWeight.w600, fontSize: 14.5),
                  ),
                  subtitle: Text(
                    'Delete all messages inside this conversation',
                    style: TextStyle(color: textMuted, fontSize: 12),
                  ),
                  onTap: () {
                    Navigator.pop(modalCtx);
                    _confirmClearChat(chatId, chatName);
                  },
                ),

                // 3. Delete Chat / Leave Group
                if (isGroup) ...[
                  ListTile(
                    leading: const Icon(Icons.exit_to_app_rounded, color: Colors.redAccent),
                    title: const Text(
                      'Leave Group',
                      style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w600, fontSize: 14.5),
                    ),
                    subtitle: Text(
                      'Exit group and remove from your chat list',
                      style: TextStyle(color: textMuted, fontSize: 12),
                    ),
                    onTap: () {
                      Navigator.pop(modalCtx);
                      _confirmLeaveGroup(chatId, chatName);
                    },
                  ),
                ] else ...[
                  ListTile(
                    leading: const Icon(Icons.delete_forever_rounded, color: Colors.redAccent),
                    title: const Text(
                      'Delete Conversation',
                      style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w600, fontSize: 14.5),
                    ),
                    subtitle: Text(
                      'Permanently remove this chat and its history',
                      style: TextStyle(color: textMuted, fontSize: 12),
                    ),
                    onTap: () {
                      Navigator.pop(modalCtx);
                      _confirmDeleteChat(chatId, chatName);
                    },
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _confirmDeleteChat(String chatId, String chatName) async {
    final surface = AppTheme.surfaceColor(context);
    final border = AppTheme.borderColor(context);
    final textPrim = AppTheme.text(context);
    final textMuted = AppTheme.textMut(context);

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: border),
        ),
        title: Text('Delete Conversation?', style: TextStyle(color: textPrim, fontWeight: FontWeight.bold)),
        content: Text(
          'Are you sure you want to delete the chat with "$chatName"? All messages will be permanently deleted.',
          style: TextStyle(color: textMuted, fontSize: 13.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: TextStyle(color: textMuted)),
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
      await ChatService.deleteConversation(chatId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Chat with "$chatName" deleted'),
            backgroundColor: AppTheme.surfaceElevatedColor(context),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Future<void> _confirmClearChat(String chatId, String chatName) async {
    final surface = AppTheme.surfaceColor(context);
    final border = AppTheme.borderColor(context);
    final textPrim = AppTheme.text(context);
    final textMuted = AppTheme.textMut(context);

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: border),
        ),
        title: Text('Clear Chat Messages?', style: TextStyle(color: textPrim, fontWeight: FontWeight.bold)),
        content: Text(
          'Are you sure you want to clear all messages in "$chatName"? Media and text history will be erased.',
          style: TextStyle(color: textMuted, fontSize: 13.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: TextStyle(color: textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orangeAccent,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear Messages', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await ChatService.clearChatHistory(chatId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Messages in "$chatName" cleared'),
            backgroundColor: AppTheme.surfaceElevatedColor(context),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Future<void> _confirmLeaveGroup(String chatId, String chatName) async {
    final surface = AppTheme.surfaceColor(context);
    final border = AppTheme.borderColor(context);
    final textPrim = AppTheme.text(context);
    final textMuted = AppTheme.textMut(context);

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: border),
        ),
        title: Text('Leave Group?', style: TextStyle(color: textPrim, fontWeight: FontWeight.bold)),
        content: Text(
          'Are you sure you want to leave "$chatName"? You will not receive future messages from this group.',
          style: TextStyle(color: textMuted, fontSize: 13.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: TextStyle(color: textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Leave', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm == true && _myUid != null) {
      await ChatService.leaveGroup(
        chatId: chatId,
        uid: _myUid!,
        userName: _myName ?? 'User',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('You left "$chatName"'),
            backgroundColor: AppTheme.surfaceElevatedColor(context),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Widget _buildFilterChips(BuildContext context) {
    final isDark = AppTheme.isDarkMode(context);
    final mint = AppTheme.mintColor(context);
    final textPrim = AppTheme.text(context);
    final surfaceElevated = AppTheme.surfaceElevatedColor(context);
    final border = AppTheme.borderColor(context);

    final filters = ['All', 'Unread', 'Groups'];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: filters.map((filter) {
          final isSelected = _selectedFilter == filter;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() => _selectedFilter = filter);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: isSelected
                      ? mint
                      : (isDark ? surfaceElevated : const Color(0xFFF1EEF9)),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isSelected ? mint : border.withValues(alpha: 0.6),
                    width: 1,
                  ),
                ),
                child: Text(
                  filter,
                  style: TextStyle(
                    color: isSelected
                        ? (isDark ? Colors.black : Colors.white)
                        : textPrim,
                    fontSize: 12.5,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bg = AppTheme.bg(context);
    final surface = AppTheme.surfaceColor(context);
    final surfaceElevated = AppTheme.surfaceElevatedColor(context);
    final textPrim = AppTheme.text(context);
    final textMuted = AppTheme.textMut(context);
    final textSec = AppTheme.textSec(context);
    final border = AppTheme.borderColor(context);
    final mint = AppTheme.mintColor(context);
    final isDark = AppTheme.isDarkMode(context);

    if (_myUid == null) {
      return Scaffold(
        backgroundColor: bg,
        body: Center(child: Text('Please log in to view chats', style: TextStyle(color: textPrim))),
      );
    }

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        title: Row(
          children: [
            if (!widget.isDesktop) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.asset(
                  'assets/images/lichat_logo.png',
                  width: 38,
                  height: 38,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(width: 10),
            ],
            Text(
              widget.isDesktop ? 'Chats' : 'LiChat',
              style: TextStyle(
                color: textPrim,
                fontWeight: FontWeight.bold,
                fontSize: widget.isDesktop ? 22 : 20,
                letterSpacing: -0.3,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.group_add_rounded, color: isDark ? mint : textPrim),
            tooltip: 'New Group',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const CreateGroupScreen()),
              );
            },
          ),
          IconButton(
            icon: Icon(Icons.qr_code_scanner_rounded, color: isDark ? mint : textPrim),
            tooltip: 'Scan QR',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const QrConnectScreen()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.star_rounded, color: Color(0xFFF59E0B)),
            tooltip: 'Starred Messages',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const StarredMessagesScreen()),
              );
            },
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          // Sleek Search Bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Container(
              height: 44,
              decoration: BoxDecoration(
                color: surfaceElevated,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: _searchQuery.isNotEmpty ? mint.withValues(alpha: 0.5) : border,
                ),
              ),
              child: TextField(
                controller: _searchController,
                onChanged: (val) {
                  setState(() => _searchQuery = val.trim());
                },
                style: TextStyle(color: textPrim, fontSize: 14.5),
                decoration: InputDecoration(
                  hintText: 'Search chats & contacts...',
                  hintStyle: TextStyle(color: textMuted, fontSize: 14),
                  prefixIcon: Icon(Icons.search_rounded, color: _searchQuery.isNotEmpty ? mint : (isDark ? textMuted : textSec), size: 20),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: Icon(Icons.close_rounded, color: textMuted, size: 18),
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

          // Filter Chips (All / Unread / Groups - only shown when not searching)
          if (_searchQuery.isEmpty) ...[
            const SizedBox(height: 6),
            _buildFilterChips(context),
            const SizedBox(height: 6),
            Divider(color: border, height: 1),
          ],

          // Conversation / Search Results List
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: ChatService.streamConversations(_myUid ?? FirebaseAuth.instance.currentUser?.uid ?? ''),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  debugPrint("Conversations stream error: ${snapshot.error}");
                }

                // INSTANT 0ms cold-start: render SQLite cache immediately
                // If Firestore is still connecting AND we have cached rows, show them now
                if (!snapshot.hasData && _cachedConversations.isNotEmpty) {
                  return _buildCachedConversationsList(context);
                }

                // If Firestore is still connecting AND cache is also empty, show skeleton
                if (!snapshot.hasData && _cachedConversations.isEmpty && !_hasStreamTimedOut) {
                  return _buildSkeletonLoadingList(context);
                }

                final rawDocs = (snapshot.data?.docs ?? []).toList();

                // Cache loaded conversations to SQLite in background for 0ms next cold-start
                if (rawDocs.isNotEmpty) {
                  unawaited(() async {
                    for (final d in rawDocs) {
                      final data = d.data();
                      final isGroup = data['isGroup'] == true;
                      final lastMsgTime = data['lastMessageTime'];
                      int? lastTs;
                      if (lastMsgTime is Timestamp) {
                        lastTs = lastMsgTime.millisecondsSinceEpoch;
                      } else if (lastMsgTime is int) {
                        lastTs = lastMsgTime;
                      }
                      final unreadCounts = Map<String, dynamic>.from(data['unreadCounts'] ?? {});
                      final myUnread = (unreadCounts[_myUid] as num?)?.toInt() ?? 0;
                      await LocalDbService.upsertConversation({
                        'chatId': d.id,
                        'peerUid': isGroup ? null : (data['participants'] as List?)?.firstWhere((id) => id != _myUid, orElse: () => null),
                        'peerName': data['name'] ?? data['groupName'] ?? data['lastSenderName'],
                        'peerAvatar': data['avatar'] ?? data['groupAvatar'],
                        'lastMessage': data['lastMessage'],
                        'lastMessageType': data['lastMessageType'] ?? 'text',
                        'lastTimestamp': lastTs,
                        'unreadCount': myUnread,
                        'isGroup': isGroup,
                      });
                    }
                  }());
                }

                // Automatically mark incoming messages as delivered if app is active
                if (_myUid != null) {
                  for (final d in rawDocs) {
                    final data = d.data();
                    if (data['lastSenderId'] != null &&
                        data['lastSenderId'] != _myUid &&
                        data['lastMessageStatus'] == 'sent') {
                      ChatService.markAsDelivered(d.id, _myUid!);
                    }
                  }
                }

                rawDocs.sort((a, b) {
                  final isAPinned = _pinnedChats.contains(a.id);
                  final isBPinned = _pinnedChats.contains(b.id);
                  if (isAPinned && !isBPinned) return -1;
                  if (!isAPinned && isBPinned) return 1;

                  final tA = _extractTimestamp(a.data());
                  final tB = _extractTimestamp(b.data());
                  return tB.compareTo(tA);
                });

                // Filter docs if search query or tab filter is active
                final docs = rawDocs.where((doc) {
                  final data = doc.data();
                  if (_searchQuery.isNotEmpty) {
                    final name = (data['name'] ?? data['groupName'] ?? data['lastSenderName'] ?? '').toString().toLowerCase();
                    final lastMsg = (data['lastMessage'] ?? '').toString().toLowerCase();
                    final q = _searchQuery.toLowerCase();
                    if (!name.contains(q) && !lastMsg.contains(q)) return false;
                  }

                  if (_selectedFilter == 'Unread') {
                    final unreadCounts = Map<String, dynamic>.from(data['unreadCounts'] ?? {});
                    final myUnread = (unreadCounts[_myUid] as num?)?.toInt() ?? 0;
                    if (myUnread <= 0) return false;
                  } else if (_selectedFilter == 'Groups') {
                    if (data['isGroup'] != true) return false;
                  }

                  return true;
                }).toList();

                // Firestore data arrived - clear stale SQLite cache display
                if (rawDocs.isNotEmpty && _cachedConversations.isNotEmpty) {
                  _cachedConversations = [];
                }

                if (docs.isEmpty) {
                  if (_selectedFilter != 'All') {
                    final isUnreadFilter = _selectedFilter == 'Unread';
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              isUnreadFilter ? Icons.mark_chat_read_rounded : Icons.groups_rounded,
                              size: 54,
                              color: mint.withValues(alpha: 0.6),
                            ),
                            const SizedBox(height: 14),
                            Text(
                              isUnreadFilter ? 'No Unread Chats' : 'No Group Chats',
                              style: TextStyle(color: textPrim, fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              isUnreadFilter
                                  ? 'You are all caught up on your conversations!'
                                  : 'Tap the group icon above to start a new group chat.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: textMuted, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  // Only show contacts/empty state AFTER Firestore has definitively
                  // confirmed there are no conversations. If not yet resolved, show skeleton.
                  if (!snapshot.hasData) {
                    return _buildSkeletonLoadingList(context);
                  }

                  // Fallback to Paired Contacts Stream
                  return StreamBuilder<List<Map<String, dynamic>>>(
                    stream: ContactService.streamContacts(_myUid!),
                    builder: (context, contactSnap) {
                      final rawContacts = contactSnap.data ?? [];
                      final contacts = _searchQuery.isEmpty
                          ? rawContacts
                          : rawContacts.where((c) {
                              final name = (c['name'] ?? '').toString().toLowerCase();
                              final code = (c['lichatCode'] ?? '').toString().toLowerCase();
                              final q = _searchQuery.toLowerCase();
                              return name.contains(q) || code.contains(q);
                            }).toList();

                      if (contacts.isNotEmpty) {
                        return ListView(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(left: 4, bottom: 12, top: 4),
                              child: Row(
                                children: [
                                  Icon(Icons.people_alt_rounded, color: mint, size: 18),
                                  const SizedBox(width: 8),
                                  Text(
                                    _searchQuery.isEmpty
                                        ? 'Paired Contacts (${contacts.length})'
                                        : 'Matching Contacts (${contacts.length})',
                                    style: TextStyle(
                                      color: textPrim,
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            ...contacts.map((contact) {
                              final name = contact['name'] ?? 'User';
                              final peerUid = contact['uid'] ?? '';
                              final avatar = contact['avatar'] as String?;
                              return Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                decoration: BoxDecoration(
                                  color: surface,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: border.withValues(alpha: 0.6)),
                                ),
                                child: ListTile(
                                  dense: true,
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                                  leading: CircleAvatar(
                                    radius: 20,
                                    backgroundColor: surfaceElevated,
                                    backgroundImage: MediaStorageService.getAvatarProvider(avatar),
                                    child: (avatar == null || avatar.isEmpty)
                                        ? Text(
                                            name.isNotEmpty ? name[0].toUpperCase() : 'U',
                                            style: TextStyle(color: mint, fontWeight: FontWeight.bold, fontSize: 15),
                                          )
                                        : null,
                                  ),
                                  title: Text(
                                    name,
                                    style: TextStyle(color: textPrim, fontWeight: FontWeight.w600, fontSize: 14.5),
                                  ),
                                  subtitle: Text(
                                    'Connected • Tap to chat',
                                    style: TextStyle(color: mint, fontSize: 11.5),
                                  ),
                                  trailing: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                    decoration: BoxDecoration(
                                      color: mint.withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(color: mint.withValues(alpha: 0.25)),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.chat_bubble_rounded, color: mint, size: 14),
                                        const SizedBox(width: 5),
                                        Text('Chat', style: TextStyle(color: mint, fontWeight: FontWeight.bold, fontSize: 12)),
                                      ],
                                    ),
                                  ),
                                  onTap: () {
                                    _openConversation(
                                      peerUid: peerUid,
                                      peerName: name,
                                      peerAvatar: avatar,
                                    );
                                  },
                                ),
                              );
                            }),
                          ],
                        );
                      }

                      if (_searchQuery.isNotEmpty) {
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.all(32.0),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.search_off_rounded, size: 64, color: textMuted.withValues(alpha: 0.5)),
                                const SizedBox(height: 16),
                                Text(
                                  'No results for "$_searchQuery"',
                                  style: TextStyle(color: textPrim, fontSize: 16, fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Try searching by contact name, group title, or message keyword.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: textSec, fontSize: 13),
                                ),
                              ],
                            ),
                          ),
                        );
                      }

                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32.0),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.qr_code_2_rounded, size: 70, color: mint.withValues(alpha: 0.5)),
                              const SizedBox(height: 16),
                              Text(
                                'No Paired Contacts Yet',
                                style: TextStyle(color: textPrim, fontSize: 18, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'To protect your privacy, contacts only appear when you connect via barcode, invite link, or LiChat code.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: textSec, fontSize: 13),
                              ),
                              const SizedBox(height: 24),
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: mint,
                                  foregroundColor: isDark ? Colors.black : Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                ),
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(builder: (context) => const QrConnectScreen()),
                                  );
                                },
                                icon: const Icon(Icons.qr_code_scanner_rounded, size: 20),
                                label: const Text('Scan to Add Contact', style: TextStyle(fontWeight: FontWeight.bold)),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(0, 6, 0, 100),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final data = docs[index].data();
                    final isGroup = data['isGroup'] == true;
                    final participants = List<String>.from(data['participants'] ?? []);
                    final lastMessage = data['lastMessage'] ?? '';
                    final unreadCounts = Map<String, dynamic>.from(data['unreadCounts'] ?? {});
                    final myUnread = unreadCounts[_myUid] ?? 0;
                    final timeString = _formatChatTimestamp(data['lastMessageTime'] ?? data['lastTimestamp'] ?? data['timestamp']);
                    final lastSenderId = data['lastSenderId'] as String?;
                    final isLastFromMe = lastSenderId == _myUid;
                    final lastMsgStatus = data['lastMessageStatus'] as String? ?? 'sent';

                    if (isGroup) {
                      final groupName = (data['name'] as String?)?.isNotEmpty == true
                          ? data['name'] as String
                          : ((data['groupName'] as String?)?.isNotEmpty == true
                              ? data['groupName'] as String
                              : 'Group');
                      final groupAvatar = (data['avatar'] as String?)?.isNotEmpty == true
                          ? data['avatar'] as String
                          : data['groupAvatar'] as String?;
                      final lastSender = (data['lastSenderName'] as String?)?.isNotEmpty == true
                          ? "${data['lastSenderName']}: "
                          : '';

                      final isSelected = widget.selectedChatId == docs[index].id;
                      return Container(
                        key: ValueKey(docs[index].id),
                        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: isSelected ? mint.withValues(alpha: isDark ? 0.18 : 0.10) : Colors.transparent,
                          borderRadius: BorderRadius.circular(14),
                          border: isSelected ? Border.all(color: mint.withValues(alpha: 0.35)) : null,
                        ),
                        child: ListTile(
                          dense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                          onTap: () {
                            _openConversation(
                              peerUid: docs[index].id,
                              peerName: groupName,
                              peerAvatar: groupAvatar,
                              isGroup: true,
                              chatIdOverride: docs[index].id,
                              groupParticipants: participants,
                            );
                          },
                          onLongPress: () {
                          _showChatOptions(
                            chatId: docs[index].id,
                            chatName: groupName,
                            chatAvatar: groupAvatar,
                            isGroup: true,
                            participants: participants,
                            unreadCount: myUnread,
                          );
                        },
                        leading: CircleAvatar(
                          radius: 22,
                          backgroundColor: surfaceElevated,
                          backgroundImage: MediaStorageService.getAvatarProvider(groupAvatar),
                          child: (groupAvatar == null || groupAvatar.isEmpty)
                              ? Icon(Icons.groups_rounded, color: isDark ? mint : textPrim, size: 24)
                              : null,
                        ),
                        title: Text(
                          groupName,
                          style: TextStyle(color: textPrim, fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                        subtitle: Row(
                          children: [
                            if (isLastFromMe) ...[
                              _buildListTick(lastMsgStatus),
                              const SizedBox(width: 4),
                            ],
                            Expanded(
                              child: Text(
                                '$lastSender$lastMessage',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: myUnread > 0 ? textPrim : textSec,
                                  fontSize: 13,
                                  fontWeight: myUnread > 0 ? FontWeight.bold : FontWeight.w400,
                                ),
                              ),
                            ),
                          ],
                        ),
                        trailing: Column(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (_pinnedChats.contains(docs[index].id)) ...[
                                  Icon(Icons.push_pin_rounded, size: 13, color: isDark ? mint : textPrim),
                                  const SizedBox(width: 3),
                                ],
                                Text(
                                  timeString,
                                  style: TextStyle(
                                    color: myUnread > 0 ? mint : textSec,
                                    fontSize: 11.5,
                                    fontWeight: myUnread > 0 ? FontWeight.bold : FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                            if (myUnread > 0) ...[
                              const SizedBox(height: 4),
                              Container(
                                constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                                padding: EdgeInsets.symmetric(horizontal: myUnread > 9 ? 6 : 4, vertical: 2),
                                decoration: BoxDecoration(
                                  color: mint,
                                  borderRadius: BorderRadius.circular(10),
                                  boxShadow: [
                                    BoxShadow(
                                      color: mint.withValues(alpha: 0.35),
                                      blurRadius: 6,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Text(
                                  myUnread > 99 ? '99+' : '$myUnread',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: isDark ? Colors.black : Colors.white,
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  }

                    final peerUid = participants.firstWhere((id) => id != _myUid, orElse: () => '');
                    final contact = _contactsMap[peerUid];
                    final cached = contact ?? ContactService.getCachedProfile(peerUid, myUid: _myUid);
                    final participantNames = data['participantNames'] is Map ? data['participantNames'] as Map : null;
                    final participantAvatars = data['participantAvatars'] is Map ? data['participantAvatars'] as Map : null;

                    final String? peerName = (contact?['name'] as String?)?.isNotEmpty == true
                        ? contact!['name'] as String
                        : ((cached?['name'] as String?)?.isNotEmpty == true
                            ? cached!['name'] as String
                            : ((cached?['displayName'] as String?)?.isNotEmpty == true
                                ? cached!['displayName'] as String
                                : ((data['participantNames.$peerUid'] as String?)?.isNotEmpty == true
                                    ? data['participantNames.$peerUid'] as String
                                    : ((participantNames?[peerUid] as String?)?.isNotEmpty == true
                                        ? participantNames![peerUid] as String
                                        : (data['lastSenderId'] == peerUid && (data['lastSenderName'] as String?)?.isNotEmpty == true
                                            ? data['lastSenderName'] as String
                                            : ((data['peerName'] as String?)?.isNotEmpty == true
                                                ? data['peerName'] as String
                                                : null))))));

                    final String? peerAvatar = (contact?['avatar'] as String?)?.isNotEmpty == true
                        ? contact!['avatar'] as String
                        : (cached?['avatar'] as String?
                            ?? cached?['photoURL'] as String?
                            ?? cached?['photoUrl'] as String?
                            ?? (data['participantAvatars.$peerUid'] as String?)
                            ?? (participantAvatars?[peerUid] as String?)
                            ?? (data['peerAvatar'] as String?));

                    if (peerUid.isNotEmpty && _myUid != null && !_contactsMap.containsKey(peerUid) && !_pendingProfileFetches.contains(peerUid)) {
                      _pendingProfileFetches.add(peerUid);
                      ContactService.fetchContactOrProfile(_myUid!, peerUid).then((prof) {
                        if (prof != null && mounted) {
                          setState(() {
                            _contactsMap[peerUid] = prof;
                          });
                        }
                      });
                    }

                    final isSelected = widget.selectedChatId == peerUid || widget.selectedChatId == docs[index].id;
                    return Container(
                      key: ValueKey(docs[index].id),
                      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: isSelected ? mint.withValues(alpha: isDark ? 0.18 : 0.10) : Colors.transparent,
                        borderRadius: BorderRadius.circular(14),
                        border: isSelected ? Border.all(color: mint.withValues(alpha: 0.35)) : null,
                      ),
                          child: ListTile(
                            dense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                            onTap: () {
                              _openConversation(
                                peerUid: peerUid,
                                peerName: peerName ?? 'Contact',
                                peerAvatar: peerAvatar,
                              );
                            },
                            onLongPress: () {
                            _showChatOptions(
                              chatId: docs[index].id,
                              chatName: peerName ?? 'Contact',
                              chatAvatar: peerAvatar,
                              isGroup: false,
                              participants: participants,
                              unreadCount: myUnread,
                              peerUid: peerUid,
                            );
                          },
                          leading: StreamBuilder<UserPresence>(
                            stream: PresenceService.streamUserPresence(peerUid),
                            builder: (context, presenceSnap) {
                              final isOnline = presenceSnap.data?.isOnline == true;

                              return Stack(
                                children: [
                                  CircleAvatar(
                                    radius: 22,
                                    backgroundColor: surfaceElevated,
                                    backgroundImage: MediaStorageService.getAvatarProvider(peerAvatar),
                                    child: (peerAvatar == null || peerAvatar.isEmpty)
                                        ? (peerName != null && peerName.isNotEmpty
                                            ? Text(
                                                peerName[0].toUpperCase(),
                                                style: TextStyle(
                                                  color: isDark ? (isOnline ? mint : textMuted) : textPrim,
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              )
                                            : Icon(Icons.person_rounded, color: isDark ? textMuted : textSec, size: 20))
                                        : null,
                                  ),
                                  if (isOnline)
                                    Positioned(
                                      right: 0,
                                      bottom: 0,
                                      child: Container(
                                        width: 10,
                                        height: 10,
                                        decoration: BoxDecoration(
                                          color: mint,
                                          shape: BoxShape.circle,
                                          border: Border.all(color: bg, width: 1.5),
                                        ),
                                      ),
                                    ),
                                ],
                              );
                            },
                          ),
                          title: peerName != null
                              ? Text(
                                  peerName,
                                  style: TextStyle(color: textPrim, fontWeight: FontWeight.bold, fontSize: 15),
                                )
                              : Container(
                                  width: 110,
                                  height: 14,
                                  margin: const EdgeInsets.symmetric(vertical: 3),
                                  decoration: BoxDecoration(
                                    color: surfaceElevated,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                          subtitle: Row(
                            children: [
                              if (isLastFromMe) ...[
                                _buildListTick(lastMsgStatus),
                                const SizedBox(width: 4),
                              ],
                              Expanded(
                                child: Text(
                                  lastMessage,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: myUnread > 0 ? textPrim : textSec,
                                    fontSize: 13,
                                    fontWeight: myUnread > 0 ? FontWeight.bold : FontWeight.w400,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          trailing: Column(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (_pinnedChats.contains(docs[index].id)) ...[
                                    Icon(Icons.push_pin_rounded, size: 13, color: isDark ? mint : textPrim),
                                    const SizedBox(width: 3),
                                  ],
                                  Text(
                                    timeString,
                                    style: TextStyle(
                                      color: myUnread > 0 ? mint : textSec,
                                      fontSize: 11.5,
                                      fontWeight: myUnread > 0 ? FontWeight.bold : FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                              if (myUnread > 0) ...[
                                const SizedBox(height: 4),
                                Container(
                                  constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                                  padding: EdgeInsets.symmetric(horizontal: myUnread > 9 ? 6 : 4, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: mint,
                                    borderRadius: BorderRadius.circular(10),
                                    boxShadow: [
                                      BoxShadow(
                                        color: mint.withValues(alpha: 0.35),
                                        blurRadius: 6,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: Text(
                                    myUnread > 99 ? '99+' : '$myUnread',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: isDark ? Colors.black : Colors.white,
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
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

  // ─── Skeleton shimmer loader: shown while Firestore is connecting ────────────
  Widget _buildSkeletonLoadingList(BuildContext context) {
    final surfaceElevated = AppTheme.surfaceElevatedColor(context);
    final border = AppTheme.borderColor(context);
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 100),
      itemCount: 8,
      itemBuilder: (_, i) {
        return _SkeletonChatTile(
          surfaceElevated: surfaceElevated,
          border: border,
          delay: i * 60,
        );
      },
    );
  }

  // ─── Render SQLite cached conversations at 0ms (before Firestore resolves) ─
  Widget _buildCachedConversationsList(BuildContext context) {
    final isDark = AppTheme.isDark(context);
    final textPrim = AppTheme.text(context);
    final textSec = AppTheme.textSec(context);
    final mint = AppTheme.mintColor(context);
    final surfaceElevated = AppTheme.surfaceElevatedColor(context);

    final sorted = List<Map<String, dynamic>>.from(_cachedConversations)
      ..sort((a, b) {
        final isPinA = (a['is_pinned'] as int? ?? 0) == 1;
        final isPinB = (b['is_pinned'] as int? ?? 0) == 1;
        if (isPinA && !isPinB) return -1;
        if (!isPinA && isPinB) return 1;
        final tA = (a['last_timestamp'] as int?) ?? 0;
        final tB = (b['last_timestamp'] as int?) ?? 0;
        return tB.compareTo(tA);
      });

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(0, 6, 0, 100),
      itemCount: sorted.length,
      itemBuilder: (context, index) {
        final row = sorted[index];
        final isGroup = (row['is_group'] as int? ?? 0) == 1;
        final name = (row['peer_name'] as String?) ?? (isGroup ? 'Group' : 'Contact');
        final avatar = row['peer_avatar'] as String?;
        final lastMsg = (row['last_message'] as String?) ?? '';
        final unread = (row['unread_count'] as int?) ?? 0;
        final ts = row['last_timestamp'] as int?;
        final timeString = _formatChatTimestamp(ts);
        final peerUid = (row['peer_uid'] as String?) ?? '';
        final chatId = (row['chat_id'] as String?) ?? '';

        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: const BoxDecoration(
            color: Colors.transparent,
            borderRadius: BorderRadius.all(Radius.circular(14)),
          ),
          child: ListTile(
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
            onTap: () {
              _openConversation(
                peerUid: isGroup ? chatId : peerUid,
                peerName: name,
                peerAvatar: avatar,
                isGroup: isGroup,
                chatIdOverride: isGroup ? chatId : null,
              );
            },
            leading: CircleAvatar(
              radius: 22,
              backgroundColor: surfaceElevated,
              backgroundImage: MediaStorageService.getAvatarProvider(avatar),
              child: (avatar == null || avatar.isEmpty)
                  ? (isGroup
                      ? Icon(Icons.groups_rounded,
                          color: isDark ? mint : textPrim, size: 24)
                      : Text(
                          name.isNotEmpty ? name[0].toUpperCase() : 'U',
                          style: TextStyle(
                            color: isDark ? mint : textPrim,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ))
                  : null,
            ),
            title: Text(
              name,
              style: TextStyle(
                color: textPrim,
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
            subtitle: Text(
              lastMsg,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: unread > 0 ? textPrim : textSec,
                fontSize: 13,
                fontWeight: unread > 0 ? FontWeight.bold : FontWeight.w400,
              ),
            ),
            trailing: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  timeString,
                  style: TextStyle(
                    color: unread > 0 ? mint : textSec,
                    fontSize: 11.5,
                    fontWeight: unread > 0 ? FontWeight.bold : FontWeight.w500,
                  ),
                ),
                if (unread > 0) ...[
                  const SizedBox(height: 4),
                  Container(
                    constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                    padding: EdgeInsets.symmetric(horizontal: unread > 9 ? 6 : 4, vertical: 2),
                    decoration: BoxDecoration(
                      color: mint,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      unread > 99 ? '99+' : '$unread',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: isDark ? Colors.black : Colors.white,
                        fontSize: 10.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildListTick(String status) {
    if (status == 'read') {
      return const Icon(Icons.done_all_rounded, size: 15, color: Color(0xFF38BDF8));
    } else if (status == 'delivered') {
      return const Icon(Icons.done_all_rounded, size: 15, color: AppTheme.textMuted);
    } else if (status == 'sent') {
      return const Icon(Icons.done_rounded, size: 15, color: AppTheme.textMuted);
    } else {
      return const Icon(Icons.access_time_rounded, size: 12, color: Colors.white38);
    }
  }
}

// ─── Pulsing skeleton placeholder for a single chat row ───────────────────────
class _SkeletonChatTile extends StatefulWidget {
  final Color surfaceElevated;
  final Color border;
  final int delay;

  const _SkeletonChatTile({
    required this.surfaceElevated,
    required this.border,
    required this.delay,
  });

  @override
  State<_SkeletonChatTile> createState() => _SkeletonChatTileState();
}

class _SkeletonChatTileState extends State<_SkeletonChatTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    _opacity = Tween<double>(begin: 0.35, end: 0.85).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
    Future.delayed(Duration(milliseconds: widget.delay), () {
      if (mounted) _ctrl.repeat(reverse: true);
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.surfaceElevated;
    return AnimatedBuilder(
      animation: _opacity,
      builder: (_, __) => Opacity(
        opacity: _opacity.value,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 7),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: c,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      height: 13,
                      width: 130,
                      decoration: BoxDecoration(
                        color: c,
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      height: 11,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: c,
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Container(
                height: 10,
                width: 36,
                decoration: BoxDecoration(
                  color: c,
                  borderRadius: BorderRadius.circular(5),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
